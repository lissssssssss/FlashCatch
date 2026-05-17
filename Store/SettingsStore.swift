import Combine
import Foundation

final class SettingsStore: ObservableObject {

    enum BufferDuration: Int, CaseIterable, Identifiable {
        case s15 = 15
        case s20 = 20
        case s25 = 25
        case s30 = 30

        var id: Int { rawValue }

        var displayName: String {
            "\(rawValue) 秒"
        }
    }

    enum VideoQuality: String, CaseIterable, Identifiable {
        case hd720 = "720P"
        case hd1080 = "1080P"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .hd720: return "720P（省电）"
            case .hd1080: return "1080P（高清）"
            }
        }
    }

    @Published var bufferDuration: Int {
        didSet { UserDefaults.standard.set(bufferDuration, forKey: "bufferDuration") }
    }
    @Published var videoQuality: String {
        didSet { UserDefaults.standard.set(videoQuality, forKey: "videoQuality") }
    }
    @Published var hapticEnabled: Bool {
        didSet { UserDefaults.standard.set(hapticEnabled, forKey: "hapticEnabled") }
    }
    @Published var onboardingCompleted: Bool {
        didSet { UserDefaults.standard.set(onboardingCompleted, forKey: "onboardingCompleted") }
    }

    init() {
        let defaults = UserDefaults.standard
        self.bufferDuration = defaults.object(forKey: "bufferDuration") as? Int ?? 20
        self.videoQuality = defaults.string(forKey: "videoQuality") ?? VideoQuality.hd1080.rawValue
        self.hapticEnabled = defaults.object(forKey: "hapticEnabled") as? Bool ?? true
        self.onboardingCompleted = defaults.bool(forKey: "onboardingCompleted")
    }

    var bufferTimeInterval: TimeInterval {
        TimeInterval(bufferDuration)
    }

    var selectedQuality: VideoQuality {
        VideoQuality(rawValue: videoQuality) ?? .hd1080
    }
}
