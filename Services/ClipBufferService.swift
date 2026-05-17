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

    private let recorder = RPScreenRecorder.shared()

    var isAvailable: Bool {
        recorder.isAvailable
    }

    var isBuffering: Bool {
        state == .buffering || state == .exporting
    }

    var isRecorderBusy: Bool {
        recorder.isRecording
    }

    func startBuffering() async throws {
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

        try await recorder.startClipBuffering()
        state = .buffering
    }

    func stopBuffering() async throws {
        guard state == .buffering || state == .exporting else { return }
        do {
            try await recorder.stopClipBuffering()
        } catch {
            // 系统可能已经停止了缓冲，忽略错误
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
            state = .error(error.localizedDescription)
            throw ClipBufferError.exportFailed(underlying: error)
        }
    }

    func restartBuffering() async {
        // 确保 recorder 空闲
        if recorder.isRecording {
            return
        }
        do {
            if state == .buffering || state == .exporting {
                try await recorder.stopClipBuffering()
                state = .idle
            }
            try await Task.sleep(nanoseconds: 300_000_000)
            try await recorder.startClipBuffering()
            state = .buffering
        } catch {
            state = .error(error.localizedDescription)
        }
    }
}
