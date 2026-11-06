import Foundation

/// Shows onboarding for a genuinely new installation, while preserving an unfinished first run.
@MainActor
final class OnboardingStore {
    private static let completedKey = "notch.onboarding.completed.v1"
    private static let pendingKey = "notch.onboarding.pending.v1"
    private let defaults: UserDefaults
    private let freshInstallation: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        freshInstallation = defaults.object(forKey: "notch.design-size-migration.v1") == nil &&
            defaults.data(forKey: "notch.preferences.v1") == nil
    }

    var shouldPresent: Bool {
        !defaults.bool(forKey: Self.completedKey) &&
            (defaults.bool(forKey: Self.pendingKey) || freshInstallation)
    }

    func beginFirstRun() {
        guard shouldPresent else { return }
        defaults.set(true, forKey: Self.pendingKey)
    }

    func complete() {
        defaults.set(true, forKey: Self.completedKey)
        defaults.removeObject(forKey: Self.pendingKey)
    }
}
