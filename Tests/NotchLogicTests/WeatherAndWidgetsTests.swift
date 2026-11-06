import Foundation
import XCTest
@testable import NotchWeather
@testable import NotchTools
@testable import NotchWater

final class WeatherAndWidgetsTests: XCTestCase {
    func testPrayerTimesUseRequestedDayAndLocationTimeZone() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Asia/Jakarta"))
        let values = ["Fajr": "04:06 (+07)", "Dhuhr": "11:43 (+07)", "Asr": "15:02 (+07)",
                      "Maghrib": "17:52 (+07)", "Isha": "19:01 (+07)"]
        let times = PrayerTimeParser.times(values, day: "06-11-2026", timeZone: zone)
        XCTAssertEqual(times.map(\.name), ["Subuh", "Zuhur", "Asar", "Magrib", "Isya"])
        XCTAssertEqual(times.first?.displayTime, "04:06")
        let formatter = DateFormatter()
        formatter.timeZone = zone; formatter.dateFormat = "dd-MM-yyyy HH:mm"
        XCTAssertEqual(times.first.map { formatter.string(from: $0.date) }, "06-11-2026 04:06")
        XCTAssertEqual(PrayerTimeParser.times(["Fajr": "invalid"], day: "06-11-2026", timeZone: zone).count, 0)
        let before = times[3].date.addingTimeInterval(-600)
        XCTAssertEqual(PrayerReminderSchedule.events(times: times, now: before, leadMinutes: 10)
            .map { $0.prayer.name }, ["Magrib"])
        XCTAssertEqual(PrayerReminderSchedule.events(times: times, now: before, leadMinutes: 10)
            .first?.progress, 0)
        XCTAssertEqual(PrayerReminderSchedule.events(times: times, now: times[3].date,
                                                     leadMinutes: 10).first?.isDue, true)
        XCTAssertTrue(PrayerReminderSchedule.events(times: times,
            now: times[3].date.addingTimeInterval(91), leadMinutes: 10).isEmpty)
    }

    @MainActor
    func testWaterReminderRecordsPersistsAndDeduplicates() throws {
        XCTAssertEqual(WaterAmount.liters(250), "0.25")
        XCTAssertEqual(WaterAmount.liters(1500), "1.5")
        let suite = "nubi.water.tests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var now = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 9)))
        let water = WaterReminderModel(defaults: defaults, nowSource: { now }, running: false)
        var reminders = 0
        water.onReminder = { reminders += 1 }
        water.setEnabled(true)
        now.addTimeInterval(3600)
        water.tick()
        water.tick()
        XCTAssertEqual(reminders, 1)
        water.drink(500)
        XCTAssertEqual(water.todayML, 500)
        XCTAssertEqual(water.progress, 1.0 / 3.0, accuracy: 0.001)
        water.setGoal(500)
        now.addTimeInterval(3600)
        water.tick()
        XCTAssertEqual(reminders, 1)
        let restored = WaterReminderModel(defaults: defaults, nowSource: { now }, running: false)
        XCTAssertEqual(restored.todayML, 500)
        XCTAssertEqual(restored.snapshot.goalML, 500)
        restored.undoLastDrink()
        XCTAssertEqual(restored.todayML, 0)
        water.stop(); restored.stop()
    }

    @MainActor
    func testQuickNoteSavesLocallyAndReloads() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("notch-notes-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("quick-note.txt")
        let note = QuickNoteModel(fileURL: url)
        note.text = "Satu\nDua"
        note.save()
        XCTAssertEqual(note.preview, "Satu")
        XCTAssertEqual(QuickNoteModel(fileURL: url).text, "Satu\nDua")
        note.stop()
    }
}
