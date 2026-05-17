import Combine
import ReplayKit

@MainActor
final class RecordingService: NSObject, ObservableObject, RPScreenRecorderDelegate {

    enum State: Equatable {
        case idle
        case recording
        case stopping
        case error(String)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.recording, .recording), (.stopping, .stopping):
                return true
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var recordingDuration: TimeInterval = 0

    private let recorder = RPScreenRecorder.shared()
    private var recordingStartTime: Date?
    private var durationTimer: Timer?
    private var stoppedByUser: ((URL?) -> Void)?

    var isRecording: Bool {
        state == .recording
    }

    override init() {
        super.init()
        recorder.delegate = self
    }

    func startRecording() async throws {
        guard recorder.isAvailable else {
            throw ClipBufferError.recorderUnavailable
        }
        guard state == .idle else { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            recorder.startRecording { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        state = .recording
        recordingStartTime = Date()
        startDurationTimer()
    }

    func stopRecording() async throws -> URL {
        guard state == .recording else {
            throw RecordingError.notRecording
        }

        state = .stopping
        stopDurationTimer()

        let outputURL = TempFileManager.shared.createTempURL(prefix: "record_")
        try await recorder.stopRecording(withOutput: outputURL)

        state = .idle
        recordingDuration = 0
        recordingStartTime = nil

        return outputURL
    }

    // MARK: - RPScreenRecorderDelegate

    nonisolated func screenRecorderDidChangeAvailability(_ screenRecorder: RPScreenRecorder) {}

    nonisolated func screenRecorder(_ screenRecorder: RPScreenRecorder, didStopRecordingWith previewViewController: RPPreviewViewController?, error: (any Error)?) {
        Task { @MainActor in
            if state == .recording {
                state = .idle
                stopDurationTimer()
                recordingDuration = 0
                recordingStartTime = nil
            }
        }
    }

    // MARK: - Private

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let start = self.recordingStartTime else { return }
                self.recordingDuration = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }
}

enum RecordingError: LocalizedError {
    case notRecording
    case startFailed(underlying: Error?)

    var errorDescription: String? {
        switch self {
        case .notRecording:
            return "当前未在录制状态"
        case .startFailed(let underlying):
            return "录制启动失败: \(underlying?.localizedDescription ?? "未知错误")"
        }
    }
}
