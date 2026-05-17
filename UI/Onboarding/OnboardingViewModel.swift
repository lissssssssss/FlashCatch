import Combine
import Foundation
import ReplayKit

@MainActor
final class OnboardingViewModel: ObservableObject {

    @Published var isRequesting = false
    @Published var permissionGranted = false

    var buttonTitle: String {
        permissionGranted ? "开始使用" : "授权屏幕录制"
    }

    func requestPermissions() {
        guard !isRequesting else { return }
        isRequesting = true

        let recorder = RPScreenRecorder.shared()
        if recorder.isAvailable {
            permissionGranted = true
            isRequesting = false
        } else {
            isRequesting = false
        }
    }
}
