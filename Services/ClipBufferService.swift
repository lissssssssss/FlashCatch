import Combine
import ReplayKit

@MainActor
final class ClipBufferService: ObservableObject {

    enum State: Equatable {
        case idle
        case buffering
        case exporting
        case error(String)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.buffering, .buffering), (.exporting, .exporting):
                return true
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var latestClipURL: URL?

    private let recorder = RPScreenRecorder.shared()
    private var periodicExportTask: Task<Void, Never>?
    private var exportDuration: TimeInterval = 20

    var isAvailable: Bool {
        recorder.isAvailable
    }

    var isBuffering: Bool {
        state == .buffering || state == .exporting
    }

    var isRecorderBusy: Bool {
        recorder.isRecording
    }

    func startBuffering(duration: TimeInterval = 20) async throws {
        guard recorder.isAvailable else {
            state = .error(ClipBufferError.recorderUnavailable.localizedDescription)
            throw ClipBufferError.recorderUnavailable
        }
        guard !recorder.isRecording else {
            throw ClipBufferError.bufferingAlreadyActive
        }
        guard state != .buffering && state != .exporting else {
            return
        }

        exportDuration = duration
        try await recorder.startClipBuffering()
        state = .buffering
        startPeriodicExport()
    }

    func stopBuffering() async throws {
        guard state == .buffering || state == .exporting else { return }
        stopPeriodicExport()
        if recorder.isRecording {
            do {
                try await recorder.stopClipBuffering()
            } catch {
                // 系统可能已经停止了缓冲，忽略错误
            }
        }
        state = .idle
    }

    func exportClip(duration: TimeInterval) async throws -> URL {
        guard state == .buffering else {
            throw ClipBufferError.notBuffering
        }

        state = .exporting
        let tempURL = TempFileManager.shared.createTempURL(prefix: "clip_")

        do {
            try await recorder.exportClip(to: tempURL, duration: duration)
            state = .buffering
            return tempURL
        } catch {
            state = .buffering
            throw ClipBufferError.exportFailed(underlying: error)
        }
    }

    func restartBuffering() async {
        if recorder.isRecording {
            return
        }
        do {
            if state == .buffering || state == .exporting {
                stopPeriodicExport()
                try await recorder.stopClipBuffering()
                state = .idle
            }
            try await Task.sleep(nanoseconds: 300_000_000)
            try await recorder.startClipBuffering()
            state = .buffering
            startPeriodicExport()
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    // MARK: - Periodic Export

    private func startPeriodicExport() {
        stopPeriodicExport()
        periodicExportTask = Task { [weak self] in
            // 等待缓冲积累一段时间再开始导出
            try? await Task.sleep(nanoseconds: 5_000_000_000)

            while !Task.isCancelled {
                guard let self, self.state == .buffering else { break }

                let tempURL = TempFileManager.shared.createTempURL(prefix: "preclip_")
                do {
                    try await self.recorder.exportClip(to: tempURL, duration: self.exportDuration)
                    let oldURL = self.latestClipURL
                    self.latestClipURL = tempURL
                    if let old = oldURL {
                        TempFileManager.shared.cleanup(urls: [old])
                    }
                } catch {
                    try? FileManager.default.removeItem(at: tempURL)
                }

                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private func stopPeriodicExport() {
        periodicExportTask?.cancel()
        periodicExportTask = nil
    }

    func consumeLatestClip() -> URL? {
        let url = latestClipURL
        latestClipURL = nil
        return url
    }

    func clearLatestClip() {
        if let url = latestClipURL {
            TempFileManager.shared.cleanup(urls: [url])
        }
        latestClipURL = nil
    }
}
