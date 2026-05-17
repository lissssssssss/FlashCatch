import Combine
import ReplayKit
import Photos

@MainActor
final class PermissionManager: ObservableObject {

    @Published var screenRecordAvailable = false
    @Published var photoLibraryAuthorized = false

    func checkAllPermissions() {
        screenRecordAvailable = RPScreenRecorder.shared().isAvailable
        let photoStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        photoLibraryAuthorized = (photoStatus == .authorized || photoStatus == .limited)
    }

    func checkScreenRecordPermission() -> Bool {
        let available = RPScreenRecorder.shared().isAvailable
        screenRecordAvailable = available
        return available
    }

    func requestPhotoLibraryPermission() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        let granted = (status == .authorized || status == .limited)
        photoLibraryAuthorized = granted
        return granted
    }
}
