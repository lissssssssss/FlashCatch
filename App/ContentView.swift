import SwiftUI
import UIKit
import ReplayKit

struct ContentView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @EnvironmentObject var settings: SettingsStore
    @State private var selectedRecord: RecordingRecord?

    var body: some View {
        Group {
            if !settings.onboardingCompleted {
                OnboardingView(
                    viewModel: OnboardingViewModel(),
                    onComplete: {
                        coordinator.onOnboardingComplete()
                    }
                )
            } else {
                mainView
            }
        }
        .onAppear {
            coordinator.onAppear()
        }
        .overlay(alignment: .topLeading) {
            if coordinator.isPreRecording || coordinator.isRecording {
                recordingFloatingButton
                    .padding(.top, 50)
                    .padding(.leading, 8)
            }
        }
        .overlay(alignment: .bottom) {
            if coordinator.showToast {
                toastView
            }
        }
        .overlay(alignment: .topTrailing) {
            debugOverlay
                .padding(.top, 50)
        }
        .fullScreenCover(isPresented: $coordinator.showPaywall) {
            PaywallView(
                purchaseService: coordinator.purchaseService,
                trialManager: coordinator.trialManager,
                onDismiss: {
                    coordinator.onPurchaseComplete()
                }
            )
        }
    }

    // MARK: - 左上角浮动录制按钮

    private var recordingFloatingButton: some View {
        Group {
            if coordinator.isRecording {
                // 录制中：透明点击区域（不会被录制捕获）
                Color.clear
                    .frame(width: 70, height: 44)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        coordinator.stopRecording()
                    }
            } else {
                // 未录制：显示可见按钮
                Button(action: {
                    coordinator.startRecording()
                }) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 9, height: 9)

                        Text("录制")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.75))
                    .clipShape(Capsule())
                }
                .disabled(coordinator.isProcessing)
            }
        }
    }

    private var mainView: some View {
        ScrollView {
            VStack(spacing: 28) {
                statusSection
                    .padding(.top, 40)

                preRecordingToggle

                explanationCard

                if !coordinator.historyStore.records.isEmpty {
                    Divider()
                        .padding(.horizontal, 32)

                    historySection
                }

                Divider()
                    .padding(.horizontal, 32)

                settingsSection
            }
            .padding(.bottom, 60)
        }
    }

    // MARK: - 状态区

    private var statusSection: some View {
        VStack(spacing: 16) {
            statusIndicator

            if coordinator.isRecording {
                Text("正在录制")
                    .font(.headline)
                    .foregroundColor(.red)
                Text("点击左上角停止")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if coordinator.isProcessing {
                Text("正在拼接保存...")
                    .font(.headline)
                    .foregroundColor(.orange)
            } else if coordinator.isPreRecording {
                Text("预录制已开启")
                    .font(.headline)
                    .foregroundColor(.green)
                Text("正在缓冲最近 \(settings.bufferDuration) 秒（可切换App）")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("预录制已关闭")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }

            trialBadge
        }
    }

    // MARK: - 操作区

    private var preRecordingToggle: some View {
        VStack(spacing: 12) {
            if coordinator.isProcessing {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("正在拼接并保存...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else if coordinator.isRecording {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text("录制中，点击左上角停止")
                        .font(.subheadline)
                        .foregroundColor(.red)
                }
            } else if coordinator.isPreRecording {
                Text("预录制缓冲中，可切换到其他 App")
                    .font(.subheadline)
                    .foregroundColor(.green)
                Text("点击左上角按钮开始录制")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 8) {
                    Text("点击下方按钮开启预录制")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    BroadcastPickerRepresentable()
                        .frame(width: 240, height: 50)
                }
                .padding(.horizontal, 32)
            }
        }
    }

    // MARK: - 原理说明

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars")
                    .foregroundColor(.red)
                Text("自动回溯，不错过开头")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            HStack(alignment: .top, spacing: 8) {
                Text("1")
                    .font(.caption2).fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(width: 18, height: 18)
                    .background(Color.red)
                    .clipShape(Circle())
                Text("后台缓冲最近 \(settings.bufferDuration) 秒画面")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(alignment: .top, spacing: 8) {
                Text("2")
                    .font(.caption2).fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(width: 18, height: 18)
                    .background(Color.red)
                    .clipShape(Circle())
                Text("看到精彩瞬间后再按「开始录制」")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(alignment: .top, spacing: 8) {
                Text("3")
                    .font(.caption2).fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(width: 18, height: 18)
                    .background(Color.red)
                    .clipShape(Circle())
                Text("停止后自动拼接为完整视频，包含开头")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal, 32)
    }

    // MARK: - 录制记录

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("录制记录")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(coordinator.historyStore.records.count) 个视频")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 32)

            ForEach(coordinator.historyStore.records) { record in
                HistoryRowView(record: record) {
                    selectedRecord = record
                } onDelete: {
                    coordinator.deleteRecording(record)
                }
            }
        }
        .fullScreenCover(item: $selectedRecord) { record in
            VideoPlayerView(assetIdentifier: record.assetIdentifier)
        }
    }

    // MARK: - 设置区

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("预录时长")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Picker("时长", selection: $settings.bufferDuration) {
                    ForEach(SettingsStore.BufferDuration.allCases) { duration in
                        Text(duration.displayName).tag(duration.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("画质")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Picker("画质", selection: $settings.videoQuality) {
                    ForEach(SettingsStore.VideoQuality.allCases) { quality in
                        Text(quality.displayName).tag(quality.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Toggle("保存成功震动提醒", isOn: $settings.hapticEnabled)

            purchaseSection
        }
        .padding(.horizontal, 32)
    }

    private var purchaseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if coordinator.purchaseService.isLifetimePurchased {
                Label("已永久解锁", systemImage: "checkmark.seal.fill")
                    .font(.subheadline)
                    .foregroundColor(.green)
            } else {
                HStack {
                    Text("免费试用")
                        .font(.subheadline)
                    Spacer()
                    Text("剩余 \(coordinator.trialManager.daysRemaining) 天")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                }

                Button(action: { coordinator.showPaywall = true }) {
                    Text("立即解锁永久版")
                        .font(.subheadline)
                        .foregroundColor(.red)
                }
            }

            Button(action: {
                Task { await coordinator.purchaseService.restorePurchases() }
            }) {
                Text("恢复购买")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Status Indicator

    @ViewBuilder
    private var trialBadge: some View {
        if coordinator.purchaseService.isLifetimePurchased {
            Label("已永久解锁", systemImage: "checkmark.seal.fill")
                .font(.caption)
                .foregroundColor(.green)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
        } else {
            Label("免费试用剩余 \(coordinator.trialManager.daysRemaining) 天", systemImage: "clock")
                .font(.caption)
                .foregroundColor(.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
        }
    }

    private var statusIndicator: some View {
        ZStack {
            Circle()
                .fill(statusColor.opacity(0.15))
                .frame(width: 120, height: 120)

            Circle()
                .fill(statusColor.opacity(0.3))
                .frame(width: 80, height: 80)

            Image(systemName: statusIcon)
                .font(.system(size: 36))
                .foregroundColor(statusColor)
        }
    }

    private var statusColor: Color {
        if coordinator.isRecording { return .red }
        if coordinator.isProcessing { return .orange }
        if coordinator.isPreRecording { return .green }
        return .gray
    }

    private var statusIcon: String {
        if coordinator.isRecording { return "record.circle.fill" }
        if coordinator.isProcessing { return "arrow.down.circle" }
        if coordinator.isPreRecording { return "record.circle" }
        return "pause.circle"
    }

    // MARK: - Debug Overlay (临时，最后删掉)

    @State private var showDebugLog = false

    private var debugOverlay: some View {
        VStack {
            Button(action: { showDebugLog.toggle() }) {
                Text("DBG")
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(4)
            }
            .padding(.top, 50)
            .padding(.trailing, 8)

            if showDebugLog {
                VStack(alignment: .leading, spacing: 4) {
                    Text("installDate: \(coordinator.trialManager.installDate.description)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.yellow)
                    Text("daysRemaining: \(coordinator.trialManager.daysRemaining)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.yellow)

                    Button("重置试用期") {
                        coordinator.trialManager.resetTrial()
                        coordinator.showPaywall = false
                        coordinator.logError("试用期已重置")
                    }
                    .font(.system(size: 10))
                    .foregroundColor(.green)

                    Divider().background(Color.gray)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(coordinator.debugLog.indices, id: \.self) { i in
                                Text(coordinator.debugLog[i])
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                }
                .padding(8)
                .frame(maxWidth: 280)
                .background(Color.black.opacity(0.85))
                .cornerRadius(8)
                .padding(.trailing, 8)
            }
        }
    }

    private var toastView: some View {
        Text(coordinator.toastMessage)
            .font(.subheadline)
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.75))
            .cornerRadius(8)
            .padding(.bottom, 32)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation {
                        coordinator.showToast = false
                    }
                }
            }
    }
}

// MARK: - RPSystemBroadcastPickerView Wrapper

struct BroadcastPickerRepresentable: UIViewRepresentable {

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 240, height: 50))
        picker.preferredExtension = "com.flashcatch.FlashCatch.FlashCatchBroadcast"
        picker.showsMicrophoneButton = false

        if let button = picker.subviews.first(where: { $0 is UIButton }) as? UIButton {
            button.setTitle("开启预录制", for: .normal)
            button.setTitleColor(.white, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
            button.backgroundColor = UIColor.systemGreen
            button.layer.cornerRadius = 12
            button.setImage(nil, for: .normal)

            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.leadingAnchor.constraint(equalTo: picker.leadingAnchor),
                button.trailingAnchor.constraint(equalTo: picker.trailingAnchor),
                button.topAnchor.constraint(equalTo: picker.topAnchor),
                button.bottomAnchor.constraint(equalTo: picker.bottomAnchor),
            ])
        }

        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
