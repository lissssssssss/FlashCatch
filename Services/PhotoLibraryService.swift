import Photos

final class PhotoLibraryService {

    enum AuthorizationStatus {
        case authorized
        case denied
        case notDetermined
    }

    func currentStatus() -> AuthorizationStatus {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
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
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        return status == .authorized || status == .limited
    }

    @discardableResult
    func saveVideoToAlbum(url: URL) async throws -> String {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
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
}
