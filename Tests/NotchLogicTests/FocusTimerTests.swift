import XCTest
@testable import NotchFocus

final class FocusTimerTests: XCTestCase {
    @MainActor
    func testPauseResumePreservesRemainingTime() {
        var clock = ContinuousClock.now
        let model = FocusTimerModel(now: { clock })
        defer { model.reset() }
        model.start(seconds: 60)
        clock = clock.advanced(by: .seconds(12.5))
        model.pause()
        XCTAssertEqual(model.phase, .paused)
        XCTAssertEqual(model.remainingSeconds, 48)
        clock = clock.advanced(by: .seconds(100))
        model.refresh()
        XCTAssertEqual(model.remainingSeconds, 48)
        model.resume()
        clock = clock.advanced(by: .seconds(47.5))
        model.refresh()
        XCTAssertEqual(model.phase, .finished)
        XCTAssertEqual(model.remainingSeconds, 0)
    }

    @MainActor
    func testLateCallbackCompletesAndResetPreventsOldDeadline() {
        var clock = ContinuousClock.now
        let model = FocusTimerModel(now: { clock })
        model.start(seconds: 15 * 60)
        clock = clock.advanced(by: .seconds(3600))
        model.refresh()
        XCTAssertEqual(model.phase, .finished)
        XCTAssertEqual(model.label, "Focus done")
        model.reset()
        model.refresh()
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(model.remainingSeconds, 0)
    }

    @MainActor
    func testRestartReplacesDeadlineAndInvalidDurationsAreIgnored() {
        var clock = ContinuousClock.now
        let model = FocusTimerModel(now: { clock })
        defer { model.reset() }
        model.start(seconds: 60)
        clock = clock.advanced(by: .seconds(50))
        model.start(seconds: 120)
        model.start(seconds: .nan)
        model.start(seconds: -1)
        clock = clock.advanced(by: .seconds(10))
        model.refresh()
        XCTAssertEqual(model.remainingSeconds, 110)
        XCTAssertEqual(model.phase, .running)
        XCTAssertEqual(model.label, "01:50")
    }

    @MainActor
    func testScheduledTaskCompletesAndCanRestart() async throws {
        let model = FocusTimerModel(tickInterval: .milliseconds(10))
        defer { model.reset() }
        model.start(seconds: 0.03)
        for _ in 0..<100 {
            if model.phase == .finished { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.phase, .finished)
        model.start(seconds: 50 * 60)
        XCTAssertEqual(model.phase, .running)
        XCTAssertEqual(model.remainingSeconds, 3000)
    }
}
