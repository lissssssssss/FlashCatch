import Foundation
import UIKit
import Combine
import ReplayKit
import Photos

private let appGroupID = "group.com.flashcatch.shared"
private let recordingStateKey = "broadcastRecording"
private let videoFilenameKey = "lastRecordedVideo"
private let bufferFilenameKey = "lastBufferVideo"
private let bufferDurationKey = "bufferDuration"
private let finishedWritingKey = "broadcastFinishedWriting"
private let startRecordingSignalKey = "startRecordingSignal"
private let stopRecordingSignalKey = "stopRecordingSignal"
private let commandNotificationName = "com.flashcatch.app.command"
private let stateChangedNotificationName = "com.flashcatch.broadcast.stateChanged"

@MainActor
final class AppCoordinator: ObservableObject {

    let settings = SettingsStore()
    let clipBufferService = ClipBufferService()
    let permissionManager = PermissionManager()
    let videoExportService = VideoExportService()
    let photoLibraryService = PhotoLibraryService()
    let purchaseService = PurchaseService()
    let trialManager = TrialManager()
    let historyStore = RecordingHistoryStore()

    private var cancellables = Set<AnyCancellable>()
    private let appGroupAvailable: Bool

    /// 状态：idle → broadcasting(缓冲中) → recording(正式录制) → processing → idle
    @Published var isPreRecording = false   // broadcast 已启动，缓冲中
    @Published var isRecording = false      // 正式录制中
    @Published var isProcessing = false     // 拼接保存中
    @Published var showToast = false
    @Published var toastMessage = ""
    @Published var showPaywall = false
    @Published var debugLog: [String] = []

    func logError(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        debugLog.append("[\(timestamp)] \(message)")
        if debugLog.count > 50 { debugLog.removeFirst() }
        print("[FlashCatch] \(message)")
    }

    var isAppUsable: Bool {
        purchaseService.isLifetimePurchased || !trialManager.isTrialExpired
    }

    init() {
        appGroupAvailable = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil
        setupNotifications()
        if appGroupAvailable {
            observeBroadcastState()
            syncBufferDurationToAppGroup()
        }
        logError("init: appGroupAvailable=\(appGroupAvailable)")
    }

    // MARK: - Lifecycle

    func onAppear() {
        permissionManager.checkAllPermissions()
        trialManager.updateTrialStatus()
        logError("onAppear: onboarding=\(settings.onboardingCompleted), usable=\(isAppUsable), appGroup=\(appGroupAvailable)")

        if settings.onboardingCompleted {
            if isAppUsable {
                checkBroadcastState()
            } else {
                showPaywall = true
            }
        }
    }

    func onOnboardingComplete() {
        settings.onboardingCompleted = true
        logError("onboarding 完成")
    }

    func onPurchaseComplete() {
        showPaywall = false
    }

    // MARK: - 预录制控制（启动/停止 Broadcast）

    func togglePreRecording() {
        logError("togglePreRecording: isPreRecording=\(isPreRecording)")
        if isPreRecording {
            stopPreRecording()
        } else {
            startPreRecording()
        }
    }

    func startPreRecording() {
        guard !isPreRecording, !isRecording else { return }
        if !isAppUsable {
            showPaywall = true
            return
        }
        guard appGroupAvailable else {
            logError("App Group 不可用，无法使用 Broadcast Extension")
            showToastMessage("需要开发者账号才能使用跨App录制")
            return
        }
        logError("开启预录制: 同步设置并等待用户确认 broadcast")
        syncBufferDurationToAppGroup()
        // UI 中的 BroadcastPickerView 会触发系统 broadcast picker
        // broadcast 启动后 Extension 会通知我们
    }

    func stopPreRecording() {
        logError("关闭预录制: 请手动停止 broadcast")
        // 用户需要通过系统 UI 停止 broadcast
        // 或者我们可以强制结束，但 ReplayKit 不提供直接 API
        showToastMessage("请从控制中心停止录屏")
    }

    // MARK: - 录制控制（通过 App Group 通知 Extension）

    func startRecording() {
        guard isPreRecording, !isRecording, !isProcessing else {
            logError("startRecording: 条件不满足 pre=\(isPreRecording) rec=\(isRecording) proc=\(isProcessing)")
            return
        }
        guard appGroupAvailable else { return }

        logError("=== 发送开始录制信号 ===")

        if let defaults = UserDefaults(suiteName: appGroupID) {
            defaults.set(true, forKey: startRecordingSignalKey)
            defaults.synchronize()
        }

        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(commandNotificationName as CFString),
            nil, nil, true
        )

        isRecording = true
        isPreRecording = false
        logError("录制信号已发送, 等待 Extension 处理")

        if settings.hapticEnabled {
            HapticService.shared.playTap()
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        guard appGroupAvailable else { return }

        logError("=== 发送停止录制信号 ===")

        if let defaults = UserDefaults(suiteName: appGroupID) {
            defaults.set(true, forKey: stopRecordingSignalKey)
            defaults.synchronize()
        }

        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(commandNotificationName as CFString),
            nil, nil, true
        )

        isRecording = false
        isProcessing = true
        logError("停止信号已发送, 等待 Extension 完成写入")

        Task {
            await waitForExtensionFinishWriting()
            await performMergeAndSave()
        }
    }

    // MARK: - 录制管理

    func deleteRecording(_ record: RecordingRecord) {
        Task {
            do {
                try await photoLibraryService.deleteAsset(assetIdentifier: record.assetIdentifier)
                logError("删除视频成功")
            } catch {
                logError("删除视频失败: \(error)")
            }
            historyStore.remove(id: record.id)
            showToastMessage("已删除")
        }
    }

    // MARK: - 监听 Broadcast Extension 状态

    private func observeBroadcastState() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()

        CFNotificationCenterAddObserver(
            center,
            observer,
            { _, observer, _, _, _ in
                guard let observer = observer else { return }
                let coordinator = Unmanaged<AppCoordinator>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in
                    coordinator.handleBroadcastStateChanged()
                }
            },
            stateChangedNotificationName as CFString,
            nil,
            .deliverImmediately
        )
    }

    private func handleBroadcastStateChanged() {
        guard appGroupAvailable, let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.synchronize()
        let broadcasting = defaults.bool(forKey: recordingStateKey)
        let finished = defaults.bool(forKey: finishedWritingKey)

        logError("broadcast 状态变化: broadcasting=\(broadcasting), finished=\(finished)")

        if broadcasting && !isPreRecording && !isRecording {
            isPreRecording = true
            logError("Broadcast 已启动，进入预录制缓冲状态")
        } else if !broadcasting && (isPreRecording || isRecording) {
            if finished && isProcessing {
                logError("Extension 写入完成")
            } else if !isProcessing {
                isPreRecording = false
                isRecording = false
                logError("Broadcast 已结束")
            }
        }
    }

    private func checkBroadcastState() {
        guard appGroupAvailable, let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.synchronize()
        let broadcasting = defaults.bool(forKey: recordingStateKey)
        if broadcasting {
            isPreRecording = true
            logError("检测到 broadcast 正在运行")
        }
    }

    // MARK: - Wait for Extension

    private func waitForExtensionFinishWriting() async {
        guard appGroupAvailable, let defaults = UserDefaults(suiteName: appGroupID) else { return }

        for i in 0..<30 {
            defaults.synchronize()
            if defaults.bool(forKey: finishedWritingKey) {
                logError("Extension 写入完成信号 (等待了 \(i * 500)ms)")
                return
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        logError("等待 Extension 写入超时 (15s)")
    }

    // MARK: - Merge & Save

    private func performMergeAndSave() async {
        var tempFiles: [URL] = []

        guard let defaults = UserDefaults(suiteName: appGroupID),
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        else {
            logError("无法访问 App Group")
            isProcessing = false
            return
        }

        defaults.synchronize()
        let recordingFilename = defaults.string(forKey: videoFilenameKey)
        let bufferFilename = defaults.string(forKey: bufferFilenameKey)

        logError("录制文件: \(recordingFilename ?? "nil"), 缓冲文件: \(bufferFilename ?? "nil")")

        let recordingURL: URL? = {
            guard let name = recordingFilename else { return nil }
            let url = container.appendingPathComponent(name)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }()

        let bufferURL: URL? = {
            guard let name = bufferFilename else { return nil }
            let url = container.appendingPathComponent(name)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }()

        guard recordingURL != nil || bufferURL != nil else {
            logError("录制文件和缓冲文件都不存在")
            isProcessing = false
            return
        }

        do {
            var finalURL: URL

            if let bufURL = bufferURL, let recURL = recordingURL {
                logError("拼接: 缓冲 + 录制...")
                tempFiles.append(bufURL)
                tempFiles.append(recURL)
                let mergedURL = try await videoExportService.mergeClips(
                    bufferClip: bufURL,
                    continuationClip: recURL
                )
                tempFiles.append(mergedURL)
                finalURL = mergedURL
                logError("拼接完成")
            } else if let bufURL = bufferURL {
                finalURL = bufURL
                tempFiles.append(bufURL)
                logError("仅缓冲文件")
            } else {
                finalURL = recordingURL!
                tempFiles.append(recordingURL!)
                logError("仅录制文件")
            }

            let assetId = try await photoLibraryService.saveVideoToAlbum(url: finalURL)
            let realDuration = photoLibraryService.fetchDuration(assetIdentifier: assetId)
            historyStore.add(assetIdentifier: assetId, duration: realDuration)
            logError("保存成功! duration=\(realDuration)s")

            if settings.hapticEnabled {
                HapticService.shared.playSuccess()
            }
            showToastMessage("已保存（含预录制 \(settings.bufferDuration)s）")
        } catch {
            if settings.hapticEnabled {
                HapticService.shared.playError()
            }
            logError("保存失败: \(error)")
            showToastMessage("保存失败: \(error.localizedDescription)")
        }

        TempFileManager.shared.cleanup(urls: tempFiles)
        isProcessing = false
    }

    // MARK: - Helpers

    private func syncBufferDurationToAppGroup() {
        guard appGroupAvailable, let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.set(settings.bufferDuration, forKey: bufferDurationKey)
        defaults.synchronize()
    }

    private func showToastMessage(_ message: String) {
        toastMessage = message
        showToast = true
    }

    // MARK: - App Lifecycle

    private func setupNotifications() {
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor in self?.handleEnterForeground() }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                Task { @MainActor in self?.logError("内存警告") }
            }
            .store(in: &cancellables)

        settings.$bufferDuration
            .sink { [weak self] _ in
                self?.syncBufferDurationToAppGroup()
            }
            .store(in: &cancellables)
    }

    private func handleEnterForeground() {
        logError("进入前台")
        trialManager.updateTrialStatus()

        if !isAppUsable {
            showPaywall = true
            return
        }

        checkBroadcastState()
    }
}
