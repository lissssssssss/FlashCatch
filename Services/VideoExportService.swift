import AVFoundation
import ReplayKit

final class VideoExportService {

    func recordContinuation(duration: TimeInterval = 5.0) async throws -> URL {
        let tempURL = TempFileManager.shared.createTempURL(prefix: "cont_")
        let recorder = RPScreenRecorder.shared()

        recorder.startRecording()
        try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        try await recorder.stopRecording(withOutput: tempURL)

        return tempURL
    }

    func mergeClips(bufferClip: URL, continuationClip: URL) async throws -> URL {
        let composition = AVMutableComposition()
        let bufferAsset = AVURLAsset(url: bufferClip)
        let contAsset = AVURLAsset(url: continuationClip)

        let bufferDuration = try await bufferAsset.load(.duration)
        let contDuration = try await contAsset.load(.duration)

        // Video track
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ExportError.trackCreationFailed
        }

        let bufferVideoTracks = try await bufferAsset.loadTracks(withMediaType: .video)
        guard let bufferVideoTrack = bufferVideoTracks.first else {
            throw ExportError.noVideoTrack
        }

        let contVideoTracks = try await contAsset.loadTracks(withMediaType: .video)
        guard let contVideoTrack = contVideoTracks.first else {
            throw ExportError.noVideoTrack
        }

        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: bufferDuration),
            of: bufferVideoTrack,
            at: .zero
        )
        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: contDuration),
            of: contVideoTrack,
            at: bufferDuration
        )

        // Audio track
        if let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) {
            let bufferAudioTracks = try? await bufferAsset.loadTracks(withMediaType: .audio)
            if let bufferAudioTrack = bufferAudioTracks?.first {
                try? compositionAudioTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: bufferDuration),
                    of: bufferAudioTrack,
                    at: .zero
                )
            }

            let contAudioTracks = try? await contAsset.loadTracks(withMediaType: .audio)
            if let contAudioTrack = contAudioTracks?.first {
                try? compositionAudioTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: contDuration),
                    of: contAudioTrack,
                    at: bufferDuration
                )
            }
        }

        // Export
        let outputURL = TempFileManager.shared.createTempURL(prefix: "merged_")

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw ExportError.exportSessionFailed
        }

        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4

        await exporter.export()

        guard exporter.status == .completed else {
            throw exporter.error ?? ExportError.unknown
        }

        return outputURL
    }
}
