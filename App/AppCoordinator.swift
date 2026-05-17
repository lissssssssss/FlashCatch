import Foundation
import UIKit
import Combine

private let appGroupID = "group.com.flashcatch.shared"
private let recordingStateKey = "broadcastRecording"
private let videoFilenameKey = "lastRecordedVideo"

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
    private var bufferClipURL: URL?
    private var wasPreRecording = false

    @Published var isPreRecording = false
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var showToast = false
    @Published var toastMessage = ""
    @Published var showPaywall = false
    @Published var debugLog: [String] = []

    func logError(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        debugLog.append("[\(timestamp)] \(message)")
        if debugLog.count > 50 { debugLog.removeFirst() }
    }

    var isAppUsable: Bool {
        purchaseService.isLifetimePurchased || !trialManager.isTrialExpired
    }

    init() {
        setupNotifications()
        observeBroadcastState()
    }

    // MARK: - Lifecycle

    func onAppear() {
        permissionManager.checkAllPermissions()
        trialManager.updateTrialStatus()
        logError("onAppear: onboarding=\(settings.onboardingCompleted), usable=\(isAppUsable), available=\(clipBufferService.isAvailable)")

        if settings.onboardingCompleted {
            if isAppUsable {
                startBufferingIfNeeded()
            } else {
                showPaywall = true
            }
        }
    }

    func onOnboardingComplete() {
        settings.onboardingCompleted = true
        startBufferingIfNeeded()
    }

    func onPurchaseComplete() {
        showPaywall = false
        startBufferingIfNeeded()
    }

    // MARK: - 预录制控制

    func togglePreRecording() {
        if isPreRecording {
            stopPreRecording()
        } else {
            startPreRecording()
        }
    }

    func startPreRecording() {
        guard !isPreRecording else { return }
        if !isAppUsable {
            showPaywall = true
            return
        }
        logError("开启预录制")
        startBufferingIfNeeded()
    }

    func stopPreRecording() {
        guard isPreRecording else { return }
        logError("关闭预录制")
        Task {
            try? await clipBufferService.stopBuffering()
            isPreRecording = false
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
            "com.flashcatch.broadcast.stateChanged" as CFString,
            nil,
            .deliverImmediately
        )
    }

    private func handleBroadcastStateChanged() {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        let nowRecording = defaults.bool(forKey: recordingStateKey)

        if !isRecording && nowRecording {
            handleBroadcastStarted()
        } else if isRecording && !nowRecording {
            handleBroadcastStopped()
        }
    }

    private func handleBroadcastStarted() {
        logError("Broadcast 录制已启动")
        wasPreRecording = isPreRecording
        isRecording = true

        if isPreRecording {
            Task {
                do {
                    logError("导出缓冲片段...")
                    let clipURL = try await clipBufferService.exportClip(
                        duration: settings.bufferTimeInterval
                    )
                    bufferClipURL = clipURL
                    logError("缓冲导出成功")

                    try await clipBufferService.stopBuffering()
                    isPreRecording = false
                } catch {
                    logError("导出缓冲失败: \(error)")
                    bufferClipURL = nil
                }
            }
        } else {
            bufferClipURL = nil
        }

        if settings.hapticEnabled {
            HapticService.shared.playTap()
        }
    }

    private func handleBroadcastStopped() {
        logError("Broadcast 录制已停止")
        isRecording = false
        isProcessing = true

        Task {
            // 短暂等待 Extension 完成写入
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await performMergeAndSave()
        }
    }

    // MARK: - Private — Merge & Save

    private func performMergeAndSave() async {
        var tempFiles: [URL] = []

        guard let defaults = UserDefaults(suiteName: appGroupID),
              let filename = defaults.string(forKey: videoFilenameKey),
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        else {
            logError("无法获取录制文件信息")
            isProcessing = false
            restorePreRecordingIfNeeded()
            return
        }

        let recordingURL = container.appendingPathComponent(filename)

        guard FileManager.default.fileExists(atPath: recordingURL.path) else {
            logError("录制文件不存在: \(filename)")
            isProcessing = false
            restorePreRecordingIfNeeded()
            return
        }

        logError("录制文件: \(filename)")
        tempFiles.append(recordingURL)

        do {
            var finalURL = recordingURL

            if let bufferURL = bufferClipURL {
                logError("拼接: 缓冲片段 + 录制视频...")
                tempFiles.append(bufferURL)
                let mergedURL = try await videoExportService.mergeClips(
                    bufferClip: bufferURL,
                    continuationClip: recordingURL
                )
                tempFiles.append(mergedURL)
                finalURL = mergedURL
                logError("拼接完成")
            }

            let assetId = try await photoLibraryService.saveVideoToAlbum(url: finalURL)
            let duration = bufferClipURL != nil ? settings.bufferTimeInterval : 0
            historyStore.add(assetIdentifier: assetId, duration: duration)

            if settings.hapticEnabled {
                HapticService.shared.playSuccess()
            }
            showToastMessage("录制已保存到相册")
        } catch {
            if settings.hapticEnabled {
                HapticService.shared.playError()
            }
            logError("保存失败: \(error)")
            showToastMessage("保存失败: \(error.localizedDescription)")
        }

        TempFileManager.shared.cleanup(urls: tempFiles)
        bufferClipURL = nil
        isProcessing = false
        restorePreRecordingIfNeeded()
    }

    private func restorePreRecordingIfNeeded() {
        if wasPreRecording {
            Task {
                await clipBufferService.restartBuffering()
                isPreRecording = clipBufferService.isBuffering
            }
        }
        wasPreRecording = false
    }

    // MARK: - Private — Buffering

    private func startBufferingIfNeeded() {
        guard isAppUsable else {
            logError("startBuffering 跳过: app不可用")
            return
        }
        guard !isRecording else {
            logError("startBuffering 跳过: 正在录制")
            return
        }
        guard !clipBufferService.isBuffering else {
            logError("startBuffering 跳过: 已在缓冲")
            isPreRecording = true
            return
        }
        logError("尝试启动缓冲...")
        Task {
            do {
                try await clipBufferService.startBuffering()
                isPreRecording = true
                logError("缓冲启动成功")
            } catch {
                logError("缓冲启动失败: \(error)")
                showToastMessage("缓冲启动失败，正在重试...")
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                do {
                    try await clipBufferService.startBuffering()
                    isPreRecording = true
                    logError("缓冲重试成功")
                } catch {
                    logError("缓冲重试失败: \(error)")
                }
            }
        }
    }

    // MARK: - Helpers

    private func showToastMessage(_ message: String) {
        toastMessage = message
        showToast = true
    }

    // MARK: - App Lifecycle Notifications

    private func setupNotifications() {
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handleEnterForeground()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handleMemoryWarning()
                }
            }
            .store(in: &cancellables)
    }

    private func handleEnterForeground() {
        trialManager.updateTrialStatus()

        if !isAppUsable {
            showPaywall = true
            return
        }

        if settings.onboardingCompleted && !clipBufferService.isBuffering
            && !isRecording && !isProcessing {
            startBufferingIfNeeded()
        }
    }

    private func handleMemoryWarning() {
        if settings.bufferDuration > 15 {
            settings.bufferDuration = 15
            if !isRecording {
                Task { await clipBufferService.restartBuffering() }
            }
        }
    }
}
