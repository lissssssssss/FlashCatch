import ReplayKit
import AVFoundation

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

class SampleHandler: RPBroadcastSampleHandler {

    // Recording
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var sessionStarted = false
    private var outputURL: URL?

    // Circular buffer
    private var bufferWriter: AVAssetWriter?
    private var bufferVideoInput: AVAssetWriterInput?
    private var bufferAudioInput: AVAssetWriterInput?
    private var bufferSessionStarted = false
    private var bufferDuration: TimeInterval = 20
    private var isBufferPhase = true
    private var bufferSegments: [URL] = []
    private var segmentIndex = 0
    private var currentSegmentStartTime: CMTime = .zero
    private let segmentDuration: TimeInterval = 5

    private var container: URL?
    private var isSwitchingMode = false

    // MARK: - Broadcast Lifecycle

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        guard let sharedContainer = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            finishBroadcastWithError(NSError(domain: "FlashCatch", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "无法访问共享容器"
            ]))
            return
        }
        container = sharedContainer

        if let defaults = UserDefaults(suiteName: appGroupID) {
            let saved = defaults.integer(forKey: bufferDurationKey)
            bufferDuration = saved > 0 ? TimeInterval(saved) : 20
            defaults.set(false, forKey: finishedWritingKey)
            defaults.set(false, forKey: startRecordingSignalKey)
            defaults.set(false, forKey: stopRecordingSignalKey)
            defaults.synchronize()
        }

        cleanOldFiles(in: sharedContainer)
        startNewBufferSegment(in: sharedContainer)
        registerForAppCommands()

        setRecordingState(true, filename: nil, bufferFilename: nil)
    }

    override func broadcastPaused() {}
    override func broadcastResumed() {}

    override func broadcastFinished() {
        unregisterFromAppCommands()

        if isBufferPhase {
            // 用户在缓冲阶段直接结束 broadcast，丢弃缓冲
            cleanupSegments()
            setRecordingState(false, filename: nil, bufferFilename: nil)
        } else {
            // 用户在录制阶段结束 broadcast，正常保存
            finalizeRecording()
        }
    }

    // MARK: - Process Samples

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard !isSwitchingMode else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if isBufferPhase {
            processBufferSample(sampleBuffer, type: sampleBufferType, timestamp: timestamp)
        } else {
            processRecordingSample(sampleBuffer, type: sampleBufferType, timestamp: timestamp)
        }
    }

    // MARK: - Buffer Phase

    private func processBufferSample(_ sampleBuffer: CMSampleBuffer, type: RPSampleBufferType, timestamp: CMTime) {
        guard let writer = bufferWriter else { return }

        if !bufferSessionStarted {
            writer.startWriting()
            writer.startSession(atSourceTime: timestamp)
            bufferSessionStarted = true
            currentSegmentStartTime = timestamp
        }

        guard writer.status == .writing else { return }

        let elapsed = CMTimeGetSeconds(CMTimeSubtract(timestamp, currentSegmentStartTime))
        if elapsed >= segmentDuration {
            rotateBufferSegment(at: timestamp)
            return
        }

        appendSample(sampleBuffer, type: type, videoInput: bufferVideoInput, audioInput: bufferAudioInput)
    }

    private func rotateBufferSegment(at timestamp: CMTime) {
        guard let container = container else { return }

        bufferVideoInput?.markAsFinished()
        bufferAudioInput?.markAsFinished()
        bufferWriter?.finishWriting { }

        bufferSessionStarted = false
        bufferVideoInput = nil
        bufferAudioInput = nil
        bufferWriter = nil

        let maxSegments = Int(ceil(bufferDuration / segmentDuration))
        while bufferSegments.count > maxSegments {
            let old = bufferSegments.removeFirst()
            try? FileManager.default.removeItem(at: old)
        }

        startNewBufferSegment(in: container)
    }

    private func startNewBufferSegment(in container: URL) {
        segmentIndex += 1
        let filename = "buf_seg_\(segmentIndex).mp4"
        let fileURL = container.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: fileURL)

        do {
            let writer = try AVAssetWriter(outputURL: fileURL, fileType: .mp4)
            let vInput = createVideoInput()
            let aInput = createAudioInput()
            writer.add(vInput)
            writer.add(aInput)

            bufferWriter = writer
            bufferVideoInput = vInput
            bufferAudioInput = aInput
            bufferSessionStarted = false
            bufferSegments.append(fileURL)
        } catch {}
    }

    // MARK: - Recording Phase

    private func processRecordingSample(_ sampleBuffer: CMSampleBuffer, type: RPSampleBufferType, timestamp: CMTime) {
        guard let writer = assetWriter else { return }

        if !sessionStarted {
            writer.startWriting()
            writer.startSession(atSourceTime: timestamp)
            sessionStarted = true
        }

        guard writer.status == .writing else { return }
        appendSample(sampleBuffer, type: type, videoInput: videoInput, audioInput: audioInput)
    }

    // MARK: - Mode Switching

    private func switchToRecordingMode() {
        guard isBufferPhase, let container = container else { return }
        isSwitchingMode = true

        // 1. 结束当前缓冲段
        bufferVideoInput?.markAsFinished()
        bufferAudioInput?.markAsFinished()
        bufferWriter?.finishWriting { }
        bufferSessionStarted = false
        bufferVideoInput = nil
        bufferAudioInput = nil
        bufferWriter = nil

        // 2. 合并缓冲分片为 buffer 文件
        let validSegments = bufferSegments.filter { FileManager.default.fileExists(atPath: $0.path) }
        if !validSegments.isEmpty {
            let bufferFilename = "buffer_\(Int(Date().timeIntervalSince1970)).mp4"
            let bufferDest = container.appendingPathComponent(bufferFilename)
            try? FileManager.default.removeItem(at: bufferDest)

            if validSegments.count == 1 {
                try? FileManager.default.copyItem(at: validSegments[0], to: bufferDest)
            } else {
                // 同步合并（简单拼接第一个文件，后续由 App 异步合并所有）
                // 这里直接保留分片文件，让 App 合并
                try? FileManager.default.copyItem(at: validSegments[0], to: bufferDest)
                // 对于多分片，用 concatenation 辅助文件
                mergeSegmentsSynchronously(validSegments, to: bufferDest)
            }

            if let defaults = UserDefaults(suiteName: appGroupID) {
                defaults.set(bufferFilename, forKey: bufferFilenameKey)
                defaults.synchronize()
            }
        }
        cleanupSegments()

        // 3. 创建录制用的 AssetWriter
        let recordFilename = "recording_\(Int(Date().timeIntervalSince1970)).mp4"
        let recordURL = container.appendingPathComponent(recordFilename)
        try? FileManager.default.removeItem(at: recordURL)
        outputURL = recordURL

        do {
            let writer = try AVAssetWriter(outputURL: recordURL, fileType: .mp4)
            let vInput = createVideoInput()
            let aInput = createAudioInput()
            writer.add(vInput)
            writer.add(aInput)

            assetWriter = writer
            videoInput = vInput
            audioInput = aInput
            sessionStarted = false
        } catch {}

        // 4. 切换模式
        isBufferPhase = false
        isSwitchingMode = false
    }

    private func finalizeRecording() {
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()

        guard let writer = assetWriter, writer.status == .writing else {
            let recordingFilename = outputURL?.lastPathComponent
            setRecordingState(false, filename: recordingFilename, bufferFilename: nil)
            return
        }

        let recordingFilename = outputURL?.lastPathComponent
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting {
            semaphore.signal()
        }
        semaphore.wait()

        setRecordingState(false, filename: recordingFilename, bufferFilename: nil)
    }

    // MARK: - App Command Listener

    private func registerForAppCommands() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(
            center,
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer = observer else { return }
                let handler = Unmanaged<SampleHandler>.fromOpaque(observer).takeUnretainedValue()
                handler.handleAppCommand()
            },
            commandNotificationName as CFString,
            nil,
            .deliverImmediately
        )
    }

    private func unregisterFromAppCommands() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterRemoveObserver(center, Unmanaged.passUnretained(self).toOpaque(), nil, nil)
    }

    private func handleAppCommand() {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.synchronize()

        if defaults.bool(forKey: startRecordingSignalKey) {
            defaults.set(false, forKey: startRecordingSignalKey)
            defaults.synchronize()
            switchToRecordingMode()
        }

        if defaults.bool(forKey: stopRecordingSignalKey) {
            defaults.set(false, forKey: stopRecordingSignalKey)
            defaults.synchronize()
            finalizeRecording()
        }
    }

    // MARK: - Segment Merge (synchronous, for use in Extension)

    private func mergeSegmentsSynchronously(_ segments: [URL], to destination: URL) {
        try? FileManager.default.removeItem(at: destination)

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return }

        var insertTime: CMTime = .zero

        for segURL in segments {
            let asset = AVURLAsset(url: segURL)
            guard let vTrack = asset.tracks(withMediaType: .video).first else { continue }
            let duration = vTrack.timeRange.duration

            try? videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: vTrack, at: insertTime)
            if let aTrack = asset.tracks(withMediaType: .audio).first {
                try? audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: aTrack, at: insertTime)
            }
            insertTime = CMTimeAdd(insertTime, duration)
        }

        let semaphore = DispatchSemaphore(value: 0)
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else { return }
        exporter.outputURL = destination
        exporter.outputFileType = .mp4
        exporter.exportAsynchronously {
            semaphore.signal()
        }
        semaphore.wait()
    }

    // MARK: - Helpers

    private func appendSample(_ sampleBuffer: CMSampleBuffer, type: RPSampleBufferType, videoInput: AVAssetWriterInput?, audioInput: AVAssetWriterInput?) {
        switch type {
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

    private func createVideoInput() -> AVAssetWriterInput {
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1080,
            AVVideoHeightKey: 1920,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 6_000_000
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        return input
    }

    private func createAudioInput() -> AVAssetWriterInput {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000
        ]
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        return input
    }

    private func cleanOldFiles(in container: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: container, includingPropertiesForKeys: nil) else { return }
        for file in files where file.lastPathComponent.hasPrefix("buf_seg_") || file.lastPathComponent.hasPrefix("buffer_") || file.lastPathComponent.hasPrefix("recording_") {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func cleanupSegments() {
        for seg in bufferSegments {
            try? FileManager.default.removeItem(at: seg)
        }
        bufferSegments.removeAll()
    }

    private func setRecordingState(_ recording: Bool, filename: String?, bufferFilename: String?) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.set(recording, forKey: recordingStateKey)
        if let filename = filename {
            defaults.set(filename, forKey: videoFilenameKey)
        }
        if let bufferFilename = bufferFilename {
            defaults.set(bufferFilename, forKey: bufferFilenameKey)
        }
        if !recording {
            defaults.set(true, forKey: finishedWritingKey)
        }
        defaults.synchronize()

        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(stateChangedNotificationName as CFString),
            nil, nil, true
        )
    }
}
