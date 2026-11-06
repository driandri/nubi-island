import XCTest
@testable import NotchLogic

final class ControllerTests: XCTestCase {
    @MainActor
    func testFullscreenHoverRevealsCollapsedPillUntilClick() async throws {
        let suite = "notch.tests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = NotchConfiguration(defaults: defaults)
        preferences.values.expandDelay = 0.01
        let controller = NotchStateController(configuration: preferences)
        controller.setHidden(true)
        controller.setHidden(false)
        controller.pointerChanged(inside: true, opensPeek: false)
        try await Task.sleep(for: .milliseconds(35))
        XCTAssertEqual(controller.interaction.phase, .collapsed)
        controller.open()
        XCTAssertEqual(controller.interaction.phase, .expanded)
        controller.setHidden(true)
        controller.setHidden(false)
        XCTAssertEqual(controller.interaction.phase, .collapsed)
    }

    @MainActor
    func testPersistenceAndReset() throws {
        let suite = "notch.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = NotchConfiguration(defaults: defaults)
        configuration.values.width = 230
        configuration.values.accent = "Blue"
        let reloaded = NotchConfiguration(defaults: defaults)
        XCTAssertEqual(reloaded.values.width, 230)
        XCTAssertEqual(reloaded.values.accent, "Blue")
        reloaded.reset()
        XCTAssertEqual(NotchConfiguration(defaults: defaults).values, NotchPreferences())
    }

    @MainActor
    func testInvalidStoredValuesAreClamped() throws {
        let suite = "notch.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = NotchConfiguration(defaults: defaults)
        configuration.values.width = -100
        configuration.values.height = 999
        configuration.values.accent = "Invalid"
        let reloaded = NotchConfiguration(defaults: defaults)
        XCTAssertEqual(reloaded.values.width, 120)
        XCTAssertEqual(reloaded.values.height, 60)
        XCTAssertEqual(reloaded.values.accent, "Mint")
    }

    @MainActor
    func testRapidExitCancelsScheduledExpansion() async throws {
        let suite = "notch.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = NotchConfiguration(defaults: defaults)
        configuration.values.expandDelay = 0.02
        configuration.values.collapseDelay = 0.02
        let controller = NotchStateController(configuration: configuration)
        controller.pointerChanged(inside: true)
        controller.pointerChanged(inside: false)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(controller.isExpanded)
        controller.pointerChanged(inside: true)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(controller.isPeek)
        controller.pointerChanged(inside: false)
        controller.togglePin()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(controller.isPinned)
        controller.dismiss()
    }

    @MainActor
    func testClickOpenSurvivesImmediatePointerExit() async throws {
        let suite = "notch.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = NotchConfiguration(defaults: defaults)
        configuration.values.collapseDelay = 0.1
        let controller = NotchStateController(configuration: configuration)
        controller.pointerChanged(inside: true)
        controller.open()
        controller.pointerChanged(inside: false)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertTrue(controller.isExpanded)
        controller.dismiss()
        XCTAssertFalse(controller.isExpanded)
    }

    @MainActor
    func testRouteChangeCancelsCollapseDuringResize() async throws {
        let defaults = UserDefaults(suiteName: "notch.tests.\(UUID().uuidString)")!
        let controller = NotchStateController(configuration: NotchConfiguration(defaults: defaults))
        controller.pointerChanged(inside: true)
        controller.open()
        controller.pointerChanged(inside: false)
        controller.navigationChanged()
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(controller.isExpanded)
        controller.dismiss()
    }
}
