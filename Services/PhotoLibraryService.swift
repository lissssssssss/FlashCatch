import Photos
import UIKit

final class PhotoLibraryService {

    enum AuthorizationStatus {
        case authorized
        case denied
        case notDetermined
    }

    func currentStatus() -> AuthorizationStatus {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            return .authorized
        case .denied, .restricted:
            return .denied
        default:
            return .notDetermined
        }
    }

    func requestAuthorization() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    @discardableResult
    func saveVideoToAlbum(url: URL) async throws -> String {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            throw PhotoError.notAuthorized
        }

        var localIdentifier: String?

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                localIdentifier = request?.placeholderForCreatedAsset?.localIdentifier
            }
        } catch {
            throw PhotoError.saveFailed(underlying: error)
        }

        guard let identifier = localIdentifier else {
            throw PhotoError.saveFailed(underlying: nil)
        }

        return identifier
    }

    // MARK: - Read Operations

    func fetchThumbnail(assetIdentifier: String, size: CGSize = CGSize(width: 120, height: 120)) async -> UIImage? {
        guard let asset = fetchAsset(identifier: assetIdentifier) else { return nil }

        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    func fetchVideoURL(assetIdentifier: String) async -> URL? {
        guard let asset = fetchAsset(identifier: assetIdentifier) else { return nil }

        return await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .automatic

            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                if let urlAsset = avAsset as? AVURLAsset {
                    continuation.resume(returning: urlAsset.url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func fetchDuration(assetIdentifier: String) -> TimeInterval {
        guard let asset = fetchAsset(identifier: assetIdentifier) else { return 0 }
        return asset.duration
    }

    func deleteAsset(assetIdentifier: String) async throws {
        guard let asset = fetchAsset(identifier: assetIdentifier) else { return }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets([asset] as NSArray)
        }
    }

    // MARK: - Private

    private func fetchAsset(identifier: String) -> PHAsset? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        return result.firstObject
    }
}
