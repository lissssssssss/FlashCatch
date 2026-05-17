import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @EnvironmentObject var settings: SettingsStore

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
                Text("点击左上角红条停止")
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
                Text("正在缓冲最近 \(settings.bufferDuration) 秒")
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
                Text("录制中，点击左上角红条停止")
                    .font(.subheadline)
                    .foregroundColor(.red)
            } else {
                Button(action: { coordinator.togglePreRecording() }) {
                    HStack(spacing: 8) {
                        Image(systemName: coordinator.isPreRecording ? "stop.circle.fill" : "play.circle.fill")
                            .font(.title2)
                        Text(coordinator.isPreRecording ? "关闭预录制" : "开启预录制")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(coordinator.isPreRecording ? Color.orange : Color.green)
                    .cornerRadius(12)
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
            Text("录制记录")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 32)

            ForEach(coordinator.historyStore.records) { record in
                historyRow(record)
            }
        }
    }

    private func historyRow(_ record: RecordingRecord) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.systemGray5))
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                        .foregroundColor(.red)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(formatRecordDate(record.date))
                    .font(.subheadline)
                Text("时长 \(formatDuration(record.duration))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: {
                openInPhotos(assetIdentifier: record.assetIdentifier)
            }) {
                Image(systemName: "arrow.up.forward.square")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 32)
    }

    private func formatRecordDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }

    private func openInPhotos(assetIdentifier: String) {
        guard let url = URL(string: "photos-redirect://") else { return }
        UIApplication.shared.open(url)
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
        switch coordinator.clipBufferService.state {
        case .buffering: return .green
        case .exporting: return .orange
        case .error: return .red
        case .idle: return .gray
        }
    }

    private var statusIcon: String {
        if coordinator.isRecording { return "record.circle.fill" }
        if coordinator.isProcessing { return "arrow.down.circle" }
        switch coordinator.clipBufferService.state {
        case .buffering: return "record.circle"
        case .exporting: return "arrow.down.circle"
        case .error: return "exclamationmark.triangle"
        case .idle: return "pause.circle"
        }
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

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
