import Foundation
import XCTest
@testable import NotchCalendar

@MainActor
private final class StubCalendarService: CalendarService {
    var access: CalendarAccess = .notDetermined
    var shouldGrant = true
    var queryCount = 0
    var requestCount = 0
    var requestedWindow: (Date, Date)?
    var upcoming: [CalendarEntry] = []

    func requestFullAccess() async throws -> Bool {
        requestCount += 1
        access = shouldGrant ? .fullAccess : .denied
        return shouldGrant
    }

    func events(from start: Date, to end: Date) -> [CalendarEntry] {
        queryCount += 1
        requestedWindow = (start, end)
        return upcoming.filter { $0.start < end && $0.end > start }
    }
}

final class CalendarModelTests: XCTestCase {
    func testMonthGridIncludesAdjacentDaysAndOverlappingEvents() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 6)))
        let days = CalendarMonthLayout.days(containing: day, calendar: calendar)
        XCTAssertEqual(days.count, 42)
        XCTAssertEqual(calendar.component(.month, from: try XCTUnwrap(days.first)), 10)
        XCTAssertEqual(calendar.component(.month, from: try XCTUnwrap(days.last)), 12)
        let novemberFirst = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1)))
        let event = CalendarEntry(id: "overnight", title: "Overnight", start: novemberFirst.addingTimeInterval(-3600),
                                  end: novemberFirst.addingTimeInterval(3600), isAllDay: false, calendarName: "Work")
        XCTAssertEqual(CalendarMonthLayout.events(on: novemberFirst, from: [event], calendar: calendar), [event])
    }

    @MainActor
    func testVisibleMonthLoadsMoreThan64EventsWithoutChangingUpcoming() throws {
        let service = StubCalendarService()
        service.access = .fullAccess
        let now = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 6)))
        let december = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 10)))
        service.upcoming = (0..<70).map { index in
            CalendarEntry(id: "event-\(index)", title: "Event \(index)",
                          start: december.addingTimeInterval(Double(index * 60)),
                          end: december.addingTimeInterval(Double(index * 60 + 1800)),
                          isAllDay: false, calendarName: "Work")
        }
        let model = CalendarModel(service: service, now: { now })
        defer { model.stop() }
        XCTAssertTrue(model.entries.isEmpty)
        XCTAssertEqual(model.events(inMonthContaining: december).count, 70)
    }
    func testMeetingLinkAcceptsOnlyHTTPSAndKnownProvidersInNotes() {
        XCTAssertEqual(CalendarMeetingLink.resolve(direct: URL(string: "https://example.com/meeting"), location: nil, notes: nil)?.host, "example.com")
        XCTAssertNil(CalendarMeetingLink.resolve(direct: URL(string: "http://example.com"), location: nil, notes: "See https://evil.example/chat"))
        XCTAssertEqual(CalendarMeetingLink.resolve(direct: nil, location: "Join https://meet.google.com/abc-defg-hij", notes: nil)?.host, "meet.google.com")
        XCTAssertNil(CalendarMeetingLink.resolve(direct: nil, location: "https://fake-zoom.us/abc", notes: nil))
    }
    @MainActor
    func testReminderSkipsAllDayAndExpiredEvents() {
        let now = Date()
        let allDay = CalendarEntry(id: "all-day", title: "Holiday", start: now.addingTimeInterval(60),
                                   end: now.addingTimeInterval(3600), isAllDay: true, calendarName: "Personal")
        let upcoming = CalendarEntry(id: "upcoming", title: "Call", start: now.addingTimeInterval(600),
                                     end: now.addingTimeInterval(1800), isAllDay: false, calendarName: "Work")
        let expired = CalendarEntry(id: "expired", title: "Old", start: now.addingTimeInterval(-100),
                                    end: now.addingTimeInterval(100), isAllDay: false, calendarName: "Work")
        XCTAssertEqual(CalendarReminderCoordinator.nextTimedEvent([allDay, upcoming, expired], now: now), upcoming)
        let original = CalendarReminderCoordinator.plan(entries: [allDay, upcoming], access: .fullAccess, now: now, leadMinutes: 10)
        XCTAssertEqual(original?.event.id, "upcoming")
        XCTAssertEqual(original?.alertDate, upcoming.start.addingTimeInterval(-600))
        let moved = CalendarEntry(id: "upcoming", title: "Call", start: now.addingTimeInterval(1200),
                                  end: now.addingTimeInterval(2400), isAllDay: false, calendarName: "Work")
        XCTAssertEqual(CalendarReminderCoordinator.plan(entries: [moved], access: .fullAccess, now: now, leadMinutes: 5)?.alertDate,
                       moved.start.addingTimeInterval(-300))
        XCTAssertNil(CalendarReminderCoordinator.plan(entries: [moved], access: .denied, now: now, leadMinutes: 10))
    }
    @MainActor
    func testCalendarReadsOnlyAfterAccessAndClearsOnRevocation() async throws {
        let service = StubCalendarService()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let event = CalendarEntry(id: "event-1", title: "Planning", start: now.addingTimeInterval(3600),
                                  end: now.addingTimeInterval(5400), isAllDay: false, calendarName: "Work")
        service.upcoming = [event]
        let model = CalendarModel(service: service, now: { now })
        defer { model.stop() }

        XCTAssertEqual(model.access, .notDetermined)
        XCTAssertTrue(model.entries.isEmpty)
        XCTAssertEqual(service.queryCount, 0)

        model.requestAccess()
        for _ in 0..<50 {
            if model.access == .fullAccess { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.entries, [event])
        XCTAssertEqual(service.requestCount, 1)
        XCTAssertEqual(service.requestedWindow?.0, now)
        XCTAssertGreaterThan(service.requestedWindow?.1 ?? now, now.addingTimeInterval(6 * 86_400))

        service.access = .denied
        model.refresh()
        XCTAssertTrue(model.entries.isEmpty)
        XCTAssertEqual(model.access, .denied)
    }

    @MainActor
    func testDeniedCalendarNeverQueriesEvents() async throws {
        let service = StubCalendarService()
        service.shouldGrant = false
        let model = CalendarModel(service: service)
        defer { model.stop() }
        model.requestAccess()
        for _ in 0..<50 {
            if !model.isRequesting { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.access, .denied)
        XCTAssertEqual(service.queryCount, 0)
        XCTAssertTrue(model.entries.isEmpty)
    }
}
