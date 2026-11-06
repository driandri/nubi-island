import AppKit
import Foundation
import XCTest
@testable import NotchLogic
@testable import NotchClipboard
@testable import NotchDownloads
@testable import NotchNotifications
@testable import NotchTools

final class DownloadFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "notch-test.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body = Data("fixture download".utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Length": "\(body.count)"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class IslandFeatureTests: XCTestCase {
    @MainActor
    func testClockUsesOneSnapshotForPillAndExpandedHeader() {
        var current = Date(timeIntervalSince1970: 1_800_000_000)
        let clock = IslandClockModel(nowSource: { current }, running: false)
        XCTAssertTrue(clock.text.header.contains(clock.text.time))
        let oldTime = clock.text.time
        current.addTimeInterval(60)
        clock.refresh()
        XCTAssertNotEqual(clock.text.time, oldTime)
        XCTAssertTrue(clock.text.header.contains(clock.text.time))
        clock.stop()
    }

    @MainActor
    func testNobiAppearsAfterIdleAndBlinkHonorsAnimationSetting() async throws {
        var idleSeconds = 0.0
        let idle = IdleAnimationModel(initialDelay: .milliseconds(25), blinkDuration: .milliseconds(25),
                                      previewDuration: .milliseconds(25), pollInterval: .milliseconds(5),
                                      inputIdleSeconds: { idleSeconds })
        idle.configure { true }
        XCTAssertFalse(idle.isNobiIdle)
        idleSeconds = 0.03
        try await Task.sleep(for: .milliseconds(15))
        XCTAssertTrue(idle.isNobiIdle)
        idleSeconds = 0
        try await Task.sleep(for: .milliseconds(65))
        XCTAssertFalse(idle.isNobiIdle)
        idle.stop()

        var animationsEnabled = true
        let blink = NobiBlinkModel(interval: .milliseconds(25), blinkDuration: .milliseconds(80))
        blink.configure { animationsEnabled }
        try await Task.sleep(for: .milliseconds(45))
        XCTAssertTrue(blink.isBlinking)
        animationsEnabled = false
        blink.reset()
        try await Task.sleep(for: .milliseconds(45))
        XCTAssertFalse(blink.isBlinking)
        blink.stop()
    }
    @MainActor
    func testHomeIsDefaultAndLiveActivitiesCanBeOpened() {
        let presentation = IslandPresentationModel()
        XCTAssertEqual(presentation.route, .home)
        presentation.select(.activities)
        XCTAssertEqual(presentation.route, .activities)
    }

    @MainActor
    func testLegacyDefaultSizeMigratesWithoutReplacingCustomSize() throws {
        let suite = "notch.tests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var old = NotchPreferences()
        old.width = 180; old.height = 32
        defaults.set(try JSONEncoder().encode(old), forKey: "notch.preferences.v1")
        XCTAssertEqual(NotchConfiguration(defaults: defaults).values.width, 340)
        XCTAssertEqual(NotchConfiguration(defaults: defaults).values.height, 34)
        XCTAssertTrue(NotchConfiguration(defaults: defaults).values.prayerRemindersEnabled)
        XCTAssertEqual(NotchConfiguration(defaults: defaults).values.prayerReminderMinutes, 10)

        let customSuite = "notch.tests.\(UUID())"
        let custom = try XCTUnwrap(UserDefaults(suiteName: customSuite))
        defer { custom.removePersistentDomain(forName: customSuite) }
        old.width = 220
        custom.set(try JSONEncoder().encode(old), forKey: "notch.preferences.v1")
        let loaded = NotchConfiguration(defaults: custom)
        XCTAssertEqual(loaded.values.width, 220)
        XCTAssertEqual(loaded.values.height, 32)
    }

    @MainActor
    func testTransientRespectsPinnedRoute() {
        let model = IslandPresentationModel()
        model.show(.volume(62, false), pinned: false)
        XCTAssertEqual(model.transient, .volume(62, false))
        model.show(.notification, pinned: true)
        XCTAssertEqual(model.transient, .volume(62, false))
        XCTAssertTrue(model.hasNotificationBadge)
        model.select(.downloads)
        XCTAssertNil(model.transient)
        model.stop()
    }

    @MainActor
    func testActivityPriorityAndDeduplication() {
        let coordinator = ActivityCoordinator()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(coordinator.accepts(.volume(40, false), now: start))
        XCTAssertFalse(coordinator.accepts(.volume(40, false), now: start.addingTimeInterval(1)))
        XCTAssertTrue(coordinator.accepts(.volume(40, true), now: start.addingTimeInterval(1)))
        XCTAssertTrue(coordinator.accepts(.timer("Done"), now: start.addingTimeInterval(2)))
        XCTAssertFalse(coordinator.accepts(.brightness(50), now: start.addingTimeInterval(3)))
        XCTAssertTrue(coordinator.accepts(.brightness(50), now: start.addingTimeInterval(7)))
        XCTAssertTrue(IslandTransient.microphoneMute(true).isSystemHUD)
        XCTAssertTrue(IslandTransient.batteryPower(70, true).isSystemHUD)
        XCTAssertGreaterThan(IslandTransient.batteryPower(70, true).priority,
                             IslandTransient.microphoneMute(true).priority)
        coordinator.update(music: true, timer: true, download: false, event: "Meeting", battery: 19)
        XCTAssertTrue(coordinator.musicPlaying)
        XCTAssertTrue(coordinator.timerActive)
        XCTAssertEqual(coordinator.nextEvent, "Meeting")
        XCTAssertEqual(coordinator.batteryPercent, 19)
    }

    func testSnapZoneGeometry() {
        let screen = CGRect(x: -1200, y: 100, width: 1200, height: 800)
        XCTAssertEqual(SnapZone.left.frame(in: screen), CGRect(x: -1200, y: 100, width: 600, height: 800))
        XCTAssertEqual(SnapZone.topRight.frame(in: screen), CGRect(x: -600, y: 500, width: 600, height: 400))
        XCTAssertEqual(SnapZone.full.frame(in: screen), screen)
        XCTAssertEqual(SnapZone.selected(at: -1200, in: screen), .left)
        XCTAssertEqual(SnapZone.selected(at: 0, in: screen), .full)
    }

    @MainActor
    func testLauncherPinsAndReorders() throws {
        let suite = "notch.launcher.tests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = LauncherModel(roots: [], defaults: defaults)
        let a = LaunchableApp(name: "A", bundleID: "a", url: URL(fileURLWithPath: "/Applications/A.app"))
        let b = LaunchableApp(name: "B", bundleID: "b", url: URL(fileURLWithPath: "/Applications/B.app"))
        model.togglePin(a); model.togglePin(b); model.movePinned(b, by: -1)
        XCTAssertEqual(model.pinnedIDs, ["b", "a"])
        XCTAssertEqual(LauncherModel(roots: [], defaults: defaults).pinnedIDs, ["b", "a"])
        XCTAssertEqual(QuickActionID.search("screen"), [.screenshot, .snapFull])
    }

    func testClipboardClassificationPinSearchAndLimit() {
        XCTAssertEqual(ClipboardEntry.from("#30d158")?.kind, .color)
        XCTAssertEqual(ClipboardEntry.from("https://example.com")?.kind, .link)
        XCTAssertEqual(ClipboardEntry.from("npm run build")?.kind, .text)
        XCTAssertNil(ClipboardEntry.from(String(repeating: "x", count: 16_385)))
        var store = ClipboardHistoryStore()
        for value in ["a", "b", "c", "d", "b"] { store.add(ClipboardEntry.from(value)!) }
        XCTAssertEqual(store.entries.map(\.value), ["b", "d", "c", "a"])
        store.setPinned("text-a", to: true)
        for number in 0..<32 { store.add(ClipboardEntry.from("item \(number)")!) }
        XCTAssertEqual(store.entries.count, 30)
        XCTAssertTrue(store.entries.contains(where: { $0.value == "a" && $0.isPinned }))
        XCTAssertEqual(store.filtered("item 31").map(\.value), ["item 31"])
        store.clear()
        XCTAssertTrue(store.entries.isEmpty)
    }

    @MainActor
    func testClipboardMonitoringRequiresOptInAndClearsOnStop() async throws {
        let suite = "notch.tests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let model = ClipboardHistoryModel(defaults: defaults, pasteboard: board)
        XCTAssertFalse(model.enabled)
        board.clearContents(); board.setString("before opt-in", forType: .string)
        XCTAssertTrue(model.entries.isEmpty)
        model.enabled = true
        board.clearContents(); board.setString("https://example.com", forType: .string)
        for _ in 0..<20 {
            if !model.entries.isEmpty { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(model.entries.first?.kind, .link)
        model.stop()
        XCTAssertTrue(model.entries.isEmpty)
        let relaunched = ClipboardHistoryModel(defaults: defaults, pasteboard: board)
        XCTAssertTrue(relaunched.enabled)
        XCTAssertTrue(relaunched.entries.isEmpty)
        relaunched.stop()
    }

    @MainActor
    func testClipboardPersistenceRequiresSeparateOptIn() async throws {
        let suite = "notch.tests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("notch-clipboard-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let model = ClipboardHistoryModel(defaults: defaults, pasteboard: board, fileURL: file)
        model.enabled = true
        board.clearContents(); board.setString("private test", forType: .string)
        for _ in 0..<20 {
            if !model.entries.isEmpty { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        model.persistHistory = true
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        model.stop()
        let again = ClipboardHistoryModel(defaults: defaults, pasteboard: board, fileURL: file)
        XCTAssertEqual(again.entries.first?.value, "private test")
        again.persistHistory = false
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        again.stop()
    }

    func testNotificationRequiresAllowlistedSource() {
        let allowed = [AllowedNotificationApp(bundleID: "com.example.messages", name: "Messages")]
        XCTAssertNil(NotificationBannerParser.parse(["Other", "Private", "Text"], allowed: allowed))
        let card = NotificationBannerParser.parse(["Messages", "Rina", "Meeting at three"], allowed: allowed)
        XCTAssertEqual(card?.app.bundleID, "com.example.messages")
        XCTAssertEqual(card?.body, "Meeting at three")
    }

    func testWebNotificationRequiresVisibleExactOrigin() {
        let sites = [AllowedNotificationWebOrigin(host: "web.whatsapp.com")]
        XCTAssertNil(NotificationBannerParser.parse(["Google Chrome", "Rina", "Hello"], allowed: [], websites: sites))
        XCTAssertNil(NotificationBannerParser.parse(["Google Chrome", "evilweb.whatsapp.com", "Rina", "Hello"], allowed: [], websites: sites))
        XCTAssertNil(NotificationBannerParser.parse(["Google Chrome", "Rina", "See web.whatsapp.com", "Hello"], allowed: [], websites: sites))
        let card = NotificationBannerParser.parse(["Google Chrome", "web.whatsapp.com", "Rina", "Hello"], allowed: [], websites: sites)
        XCTAssertEqual(card?.app.name, "web.whatsapp.com")
        XCTAssertEqual(card?.body, "Hello")
        XCTAssertNil(NotificationBannerParser.parse(["Safari", "Unknown site", "Rina"],
                                                   allowed: [.init(bundleID: "com.apple.Safari", name: "Safari")], websites: sites))
    }

    func testPanelTopologyHandlesHotplugAndOneGlobalAlert() {
        XCTAssertEqual(PanelTopology.desiredIDs(available: [1, 2], selected: 2, mode: "Single"), [2])
        XCTAssertEqual(PanelTopology.desiredIDs(available: [1, 2], selected: 2, mode: "All"), [1, 2])
        XCTAssertEqual(PanelTopology.desiredIDs(available: [1], selected: 2, mode: "Single"), [1])
        XCTAssertEqual(PanelTopology.alertTarget(pointerID: 2, desired: [1, 2], primaryID: 1), 2)
        XCTAssertEqual(PanelTopology.alertTarget(pointerID: 3, desired: [1, 2], primaryID: 1), 1)
    }
    func testHomeLayoutPreservesOrderWithWideCards() {
        XCTAssertEqual(HomeLayout.rows(widgets: ["Calendar", "Music", "Timer", "Weather"],
                                       wide: ["Calendar", "Music"]), [["Calendar"], ["Music", "Timer"], ["Weather"]])
    }
    func testHomeLayoutPlacesTallAndWideCardsWithoutOverlap() {
        let cards = ["Calendar", "Music", "Timer", "Prayer", "Calculator"]
        let placements = HomeLayout.placements(widgets: cards, wide: ["Music", "Prayer"], tall: ["Timer"])
        XCTAssertEqual(placements.count, cards.count)
        var occupied = Set<Int>()
        for placement in placements {
            for row in placement.row..<(placement.row + placement.rows) {
                for column in placement.column..<(placement.column + placement.columns) {
                    XCTAssertTrue(occupied.insert(row * 3 + column).inserted)
                }
            }
        }
        XCTAssertEqual(HomeLayout.rowCount(widgets: cards, wide: ["Music", "Prayer"], tall: ["Timer"]), 3)
    }

    @MainActor
    func testNewPreferencesMigrateWithoutOverwritingExistingChoices() throws {
        let suite = "notch.tests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var legacy = NotchPreferences()
        legacy.width = 255; legacy.displayID = 42; legacy.panelStyle = "Accent glow"
        legacy.homeWidgets = ["Timer", "Calendar"]
        var data = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        for key in ["displayMode", "idleAnimation", "homeHeight", "wideWidgets", "tallWidgets", "calendarReminderMinutes", "calendarSystemNotifications",
                    "hudVolume", "hudBrightness", "hudBattery", "hudMicrophone", "glassTransparency", "navigationTabs",
                    "showOnLockScreen"] {
            data.removeValue(forKey: key)
        }
        defaults.set(try JSONSerialization.data(withJSONObject: data), forKey: "notch.preferences.v1")
        let values = NotchConfiguration(defaults: defaults).values
        XCTAssertEqual(values.width, 255)
        XCTAssertEqual(values.displayID, 42)
        XCTAssertEqual(values.panelStyle, "Accent Glow")
        XCTAssertEqual(values.homeWidgets, ["Timer", "Calendar"])
        XCTAssertEqual(values.displayMode, "Single")
        XCTAssertEqual(values.calendarReminderMinutes, 10)
        XCTAssertTrue(values.tallWidgets.isEmpty)
        XCTAssertTrue(values.hudVolume && values.hudBrightness && values.hudBattery && values.hudMicrophone)
        XCTAssertEqual(values.featureTabs, [.music, .focus, .calendar, .mixer, .launcher])
        XCTAssertEqual(values.glassTransparency, 0.32)
        XCTAssertFalse(values.showOnLockScreen)
    }

    func testNavigationSettingsKeepOrderAndAllowAnEmptyBar() throws {
        var preferences = NotchPreferences()
        preferences.navigationTabs = ["Clipboard", "Home", "Clipboard", "Calendar", "Missing", "More",
                                      "Timer", "Shelf", "Mixer", "Launcher"]
        preferences.glassTransparency = 0.9
        preferences.sanitize()
        XCTAssertEqual(preferences.featureTabs, [.clipboard, .calendar, .focus, .shelf, .mixer])
        XCTAssertEqual(preferences.glassTransparency, 0.55)
        preferences.navigationTabs = []
        let restored = try JSONDecoder().decode(NotchPreferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertTrue(restored.featureTabs.isEmpty)
    }

    func testBatteryToggleControlsLowBatteryAndChargingAlerts() {
        var preferences = NotchPreferences()
        XCTAssertTrue(preferences.allowsAlert(.battery(15)))
        XCTAssertTrue(preferences.allowsAlert(.batteryPower(55, true)))
        preferences.hudBattery = false
        XCTAssertFalse(preferences.allowsAlert(.battery(15)))
        XCTAssertFalse(preferences.allowsAlert(.batteryPower(55, true)))
        XCTAssertTrue(preferences.allowsAlert(.timer("Selesai")))
    }

    @MainActor
    func testIdlePhasesCancelAndRespectPredicate() async throws {
        var idleSeconds = 1.0
        let model = IdleAnimationModel(initialDelay: .milliseconds(15), blinkDuration: .milliseconds(20),
                                       previewDuration: .milliseconds(30), pollInterval: .milliseconds(5),
                                       inputIdleSeconds: { idleSeconds })
        var allowed = true
        model.configure { allowed }
        try await Task.sleep(for: .milliseconds(90))
        XCTAssertTrue(model.isNobiIdle)
        XCTAssertEqual(model.phase, .resting)
        allowed = false
        model.reset()
        XCTAssertEqual(model.phase, .resting)
        idleSeconds = 0
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(model.phase, .resting)
    }

    @MainActor
    func testNobiUsesFifteenMinutesOfInputIdleAndWaitsForInputAfterWake() async throws {
        var seconds = 899.0
        let model = IdleAnimationModel(initialDelay: .seconds(900), blinkDuration: .milliseconds(5),
                                       previewDuration: .milliseconds(5), pollInterval: .milliseconds(5),
                                       inputIdleSeconds: { seconds })
        defer { model.stop() }
        model.configure { true }
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertFalse(model.isNobiIdle)
        seconds = 901
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(model.isNobiIdle)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidSleepNotification, object: NSWorkspace.shared)
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertFalse(model.isNobiIdle)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidWakeNotification, object: NSWorkspace.shared)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertFalse(model.isNobiIdle)
        seconds = 0
        try await Task.sleep(for: .milliseconds(10))
        seconds = 901
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(model.isNobiIdle)
    }

    @MainActor
    func testNotificationAllowlistPersistsButContentDoesNot() throws {
        let suite = "notch.tests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = NotificationBannerModel(defaults: defaults)
        model.addApp(bundleID: "com.example.messages", name: "Messages")
        XCTAssertTrue(model.addWebOrigin("web.whatsapp.com"))
        XCTAssertFalse(model.addWebOrigin("https://web.whatsapp.com"))
        XCTAssertEqual(NotificationBannerModel(defaults: defaults).allowedApps.map(\.bundleID), ["com.example.messages"])
        XCTAssertEqual(NotificationBannerModel(defaults: defaults).allowedWebOrigins.map(\.host), ["web.whatsapp.com"])
        XCTAssertNil(NotificationBannerModel(defaults: defaults).latest)
        model.removeApp(model.allowedApps[0])
        XCTAssertTrue(NotificationBannerModel(defaults: defaults).allowedApps.isEmpty)
        model.stop()
    }

    @MainActor
    func testDownloadURLValidationAndHTTPSRedirect() throws {
        XCTAssertNotNil(DownloadManager.validatedURL(" https://example.com/file.zip "))
        XCTAssertNil(DownloadManager.validatedURL("http://example.com/file.zip"))
        XCTAssertNil(DownloadManager.validatedURL("https://user:pass@example.com/file.zip"))
        let redirect = HTTPSRedirectGuard()
        let source = try XCTUnwrap(URL(string: "https://example.com/file"))
        let response = try XCTUnwrap(HTTPURLResponse(url: source, statusCode: 302, httpVersion: nil, headerFields: nil))
        let task = URLSession.shared.dataTask(with: source)
        let refused = expectation(description: "Refuse HTTP downgrade")
        redirect.urlSession(.shared, task: task, willPerformHTTPRedirection: response,
                            newRequest: URLRequest(url: URL(string: "http://example.com/file")!)) { request in
            XCTAssertNil(request)
            refused.fulfill()
        }
        wait(for: [refused], timeout: 1)
        let gate = DownloadCancellationGate()
        let id = UUID()
        gate.cancel(id)
        var wrote = false
        XCTAssertFalse(try gate.performIfActive(id) { wrote = true })
        XCTAssertFalse(wrote)
        let committed = UUID()
        XCTAssertTrue(try gate.performIfActive(committed) { wrote = true })
        XCTAssertFalse(gate.cancel(committed))
    }

    @MainActor
    func testDownloadSavesChosenFile() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DownloadFixtureProtocol.self]
        let manager = DownloadManager(configuration: configuration)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("notch-download-\(UUID()).txt")
        defer { manager.stop(); try? FileManager.default.removeItem(at: destination) }
        manager.start(url: URL(string: "https://notch-test.invalid/fixture.txt")!, destination: destination)
        for _ in 0..<40 {
            if manager.items.first?.state == .completed { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(manager.items.first?.state, .completed)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "fixture download")
    }

}
