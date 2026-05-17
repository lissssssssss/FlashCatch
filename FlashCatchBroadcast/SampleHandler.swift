import ReplayKit
import AVFoundation

private let appGroupID = "group.com.flashcatch.shared"
private let recordingStateKey = "broadcastRecording"
private let videoFilenameKey = "lastRecordedVideo"

class SampleHandler: RPBroadcastSampleHandler {

    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var sessionStarted = false
    private var outputURL: URL?

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        let sharedContainer = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        )
        guard let container = sharedContainer else {
            finishBroadcastWithError(NSError(domain: "FlashCatch", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "无法访问共享容器"
            ]))
            return
        }

        let filename = "broadcast_\(Int(Date().timeIntervalSince1970)).mp4"
        let fileURL = container.appendingPathComponent(filename)
        outputURL = fileURL

        try? FileManager.default.removeItem(at: fileURL)

        do {
            assetWriter = try AVAssetWriter(outputURL: fileURL, fileType: .mp4)
        } catch {
            finishBroadcastWithError(error as NSError)
            return
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1080,
            AVVideoHeightKey: 1920,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 6_000_000
            ]
        ]
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput?.expectsMediaDataInRealTime = true

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000
        ]
        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput?.expectsMediaDataInRealTime = true

        if let videoInput = videoInput {
            assetWriter?.add(videoInput)
        }
        if let audioInput = audioInput {
            assetWriter?.add(audioInput)
        }

        setRecordingState(true, filename: filename)
    }

    override func broadcastPaused() {}

    override func broadcastResumed() {}

    override func broadcastFinished() {
        guard let writer = assetWriter, writer.status == .writing else {
            assetWriter?.cancelWriting()
            setRecordingState(false, filename: nil)
            return
        }

        videoInput?.markAsFinished()
        audioInput?.markAsFinished()

        writer.finishWriting { [weak self] in
            self?.setRecordingState(false, filename: nil)
        }
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard let writer = assetWriter else { return }

        if !sessionStarted {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startWriting()
            writer.startSession(atSourceTime: timestamp)
            sessionStarted = true
        }

        guard writer.status == .writing else { return }

        switch sampleBufferType {
        case .video:
            if let input = videoInput, input.isReadyForMoreMediaData {
                input.append(sampleBuffer)
            }
        case .audioApp, .audioMic:
            if let input = audioInput, input.isReadyForMoreMediaData {
                input.append(sampleBuffer)
            }
        @unknown default:
            break
        }
    }

    private func setRecordingState(_ recording: Bool, filename: String?) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.set(recording, forKey: recordingStateKey)
        if let filename = filename {
            defaults.set(filename, forKey: videoFilenameKey)
        }
        defaults.synchronize()

        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("com.flashcatch.broadcast.stateChanged" as CFString),
            nil, nil, true
        )
    }
}
