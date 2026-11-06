import CoreAudio
import Foundation
import XCTest
@testable import NotchFocus
@testable import NotchLogic
@testable import NotchMixer
@testable import NotchTools

final class ExpansionTests: XCTestCase {
    @MainActor
    func testOnboardingAppearsOnlyForNewOrUnfinishedInstallation() throws {
        let suite = "notch.onboarding.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = OnboardingStore(defaults: defaults)
        XCTAssertTrue(first.shouldPresent)
        first.beginFirstRun()
        defaults.set(true, forKey: "notch.design-size-migration.v1")
        XCTAssertTrue(OnboardingStore(defaults: defaults).shouldPresent)
        first.complete()
        XCTAssertFalse(OnboardingStore(defaults: defaults).shouldPresent)

        let olderSuite = "notch.onboarding.legacy.\(UUID())"
        let older = try XCTUnwrap(UserDefaults(suiteName: olderSuite))
        defer { older.removePersistentDomain(forName: olderSuite) }
        older.set(true, forKey: "notch.design-size-migration.v1")
        XCTAssertFalse(OnboardingStore(defaults: older).shouldPresent)
    }

    @MainActor
    func testOldPreferencesKeepValuesAndGainWidgetDefaults() throws {
        let suite = "notch.expansion.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let old = """
        {"width":312,"height":41,"cornerRadius":16,"animationDuration":0.3,"expandDelay":0.15,"collapseDelay":0.4,"hoverInset":0,"displayID":0,"accent":"Blue","showSystemInfo":true,"showStatus":true,"showInFullScreen":false,"belowMenuBar":false}
        """
        defaults.set(Data(old.utf8), forKey: "notch.preferences.v1")
        let model = NotchConfiguration(defaults: defaults)
        XCTAssertEqual(model.values.width, 312)
        XCTAssertEqual(model.values.height, 41)
        XCTAssertEqual(model.values.accent, "Blue")
        XCTAssertEqual(model.values.homeWidgets, ["Calendar", "Music", "Timer"])
        model.values.homeWidgets = ["Timer", "To-do", "Timer", "Unknown"]
        let reloaded = NotchConfiguration(defaults: defaults)
        XCTAssertEqual(reloaded.values.homeWidgets, ["Timer", "To-do"])
    }

    @MainActor
    func testPomodoroNeedsManualAdvanceAndLongBreakAfterFourFocusSessions() {
        var clock = ContinuousClock.now
        let timer = FocusTimerModel(now: { clock })
        defer { timer.reset() }
        timer.startPomodoro()
        for session in 1...4 {
            clock = clock.advanced(by: .seconds(25 * 60))
            timer.refresh()
            XCTAssertEqual(timer.phase, .finished)
            XCTAssertEqual(timer.completedFocusSessions, session)
            XCTAssertEqual(timer.stage, .focus)
            timer.advancePomodoro()
            XCTAssertEqual(timer.stage, session == 4 ? .longBreak : .shortBreak)
            XCTAssertEqual(timer.remainingSeconds, session == 4 ? 15 * 60 : 5 * 60)
            clock = clock.advanced(by: .seconds(timer.remainingSeconds))
            timer.refresh()
            XCTAssertEqual(timer.phase, .finished)
            timer.advancePomodoro()
            XCTAssertEqual(timer.stage, .focus)
            XCTAssertEqual(timer.completedFocusSessions, session)
        }
    }

    @MainActor
    func testTodoPersistsAndLauncherSearchesInstalledAppFixture() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("notch-tools-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let todoURL = root.appendingPathComponent("support/todos.json")
        let todos = TodoModel(fileURL: todoURL)
        todos.add("  Read documentation  ")
        todos.add("  ")
        XCTAssertEqual(todos.items.count, 1)
        todos.toggle(todos.items[0].id)
        XCTAssertEqual(TodoModel(fileURL: todoURL).openCount, 0)

        let appURL = root.appendingPathComponent("Applications/Example.app")
        let contents = appURL.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: NSDictionary = ["CFBundleIdentifier": "test.example", "CFBundleName": "Example"]
        XCTAssertTrue(plist.write(to: contents.appendingPathComponent("Info.plist"), atomically: true))
        let launcher = LauncherModel(roots: [root.appendingPathComponent("Applications")])
        XCTAssertEqual(launcher.results(for: "exam").map(\.name), ["Example"])
        XCTAssertTrue(launcher.results(for: "missing").isEmpty)
    }

    func testCalculatorOperationsAndDivisionByZero() {
        var calculator = CalculatorEngine()
        for key in ["1", "2", "+", "3", "="] { calculator.input(key) }
        XCTAssertEqual(calculator.display, "15")
        calculator.input("%")
        XCTAssertEqual(calculator.display, "0.15")
        calculator.input("C")
        for key in ["8", "÷", "0", "="] { calculator.input(key) }
        XCTAssertEqual(calculator.display, "Error")
        XCTAssertEqual(calculator.error, "Cannot divide by zero")
        calculator.input("C")
        XCTAssertEqual(calculator.display, "0")
    }

    func testMixerGainAndFormatGuard() {
        XCTAssertEqual(MixerDSP.apply(0.8, gain: 0.25), 0.2, accuracy: 0.0001)
        let flags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked
        let format = AudioStreamBasicDescription(mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
                                                 mFormatFlags: flags, mBytesPerPacket: 8, mFramesPerPacket: 1,
                                                 mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        XCTAssertTrue(MixerDSP.canPassThrough(input: format, output: format))
        var incompatible = format
        incompatible.mSampleRate = 44_100
        XCTAssertFalse(MixerDSP.canPassThrough(input: format, output: incompatible))
    }

    @MainActor
    func testMixerDoesNotRequestCaptureOnRelaunch() throws {
        let suite = "notch.mixer.session.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "notch.mixer.enabled.v1")
        let mixer = SoundMixerModel(defaults: defaults)
        defer { mixer.stop() }
        XCTAssertTrue(mixer.enabled)
        XCTAssertFalse(mixer.sessionActive)
        XCTAssertTrue(mixer.status.contains("Mulai"))
    }

    func testTopEdgeDoesNotMoveWhenPanelChangesSize() {
        let screen = CGRect(x: -1920, y: 120, width: 1920, height: 1080)
        let small = PanelGeometry.frame(screen: screen, top: screen.maxY, requestedSize: CGSize(width: 340, height: 34))
        let large = PanelGeometry.frame(screen: screen, top: screen.maxY, requestedSize: CGSize(width: 560, height: 400))
        XCTAssertEqual(small.maxY, large.maxY)
        XCTAssertEqual(small.midX, large.midX)
    }
}
