import Combine
import Foundation

final class TrialManager: ObservableObject {

    private static let installDateKey = "flashcatch_install_date"
    static let trialDays = 90

    @Published private(set) var daysRemaining: Int = 0
    @Published private(set) var isTrialExpired: Bool = false

    var installDate: Date {
        if let stored = UserDefaults.standard.object(forKey: Self.installDateKey) as? Date {
            return stored
        }
        let now = Date()
        UserDefaults.standard.set(now, forKey: Self.installDateKey)
        return now
    }

    init() {
        updateTrialStatus()
    }

    func updateTrialStatus() {
        let calendar = Calendar.current
        let daysSinceInstall = calendar.dateComponents(
            [.day],
            from: installDate,
            to: Date()
        ).day ?? 0

        let remaining = max(0, Self.trialDays - daysSinceInstall)
        daysRemaining = remaining
        isTrialExpired = remaining <= 0
    }

    func resetTrial() {
        UserDefaults.standard.set(Date(), forKey: Self.installDateKey)
        updateTrialStatus()
    }

    var trialProgressFraction: Double {
        let elapsed = Self.trialDays - daysRemaining
        return min(1.0, Double(elapsed) / Double(Self.trialDays))
    }
}
