import AppKit
import Combine
import EventKit
import UserNotifications

struct CalendarEntry: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarName: String
    var joinURL: URL? = nil
}

enum CalendarMonthLayout {
    static func days(containing date: Date, calendar: Calendar = .current) -> [Date] {
        guard let month = calendar.dateInterval(of: .month, for: date),
              let firstWeek = calendar.dateInterval(of: .weekOfYear, for: month.start),
              let lastDay = calendar.date(byAdding: .day, value: -1, to: month.end),
              let lastWeek = calendar.dateInterval(of: .weekOfYear, for: lastDay) else { return [] }
        let count = calendar.dateComponents([.day], from: firstWeek.start, to: lastWeek.end).day ?? 0
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: firstWeek.start) }
    }

    static func events(on day: Date, from entries: [CalendarEntry], calendar: Calendar = .current) -> [CalendarEntry] {
        guard let interval = calendar.dateInterval(of: .day, for: day) else { return [] }
        return entries.filter { $0.start < interval.end && $0.end > interval.start }
    }
}

enum CalendarMeetingLink {
    static func resolve(direct: URL?, location: String?, notes: String?) -> URL? {
        if let direct, valid(direct) { return direct }
        let hosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "webex.com", "whereby.com", "jitsi.org"]
        for text in [location, notes].compactMap({ $0 }) {
            guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { continue }
            for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let url = match.url, valid(url), let host = url.host?.lowercased(),
                      hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { continue }
                return url
            }
        }
        return nil
    }
    private static func valid(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host != nil && url.user == nil && url.password == nil
    }
}

@MainActor
final class CalendarReminderCoordinator {
    var onReminder: ((CalendarEntry) -> Void)?
    private let calendar: CalendarModel
    private let reminderMinutes: () -> Int
    private let systemNotificationsEnabled: () -> Bool
    private var subscriptions = Set<AnyCancellable>()
    private var task: Task<Void, Never>?
    private var scheduledID: String?
    private var firedIDs = Set<String>()
    private let notificationID = "notch.calendar.next-event"

    init(calendar: CalendarModel, reminderMinutes: @escaping () -> Int,
         systemNotificationsEnabled: @escaping () -> Bool) {
        self.calendar = calendar
        self.reminderMinutes = reminderMinutes
        self.systemNotificationsEnabled = systemNotificationsEnabled
        calendar.$entries.combineLatest(calendar.$access).sink { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.reschedule() }
        }.store(in: &subscriptions)
        reschedule()
    }
    static func nextTimedEvent(_ entries: [CalendarEntry], now: Date) -> CalendarEntry? {
        entries.filter { !$0.isAllDay && $0.start > now }.min { $0.start < $1.start }
    }
    static func plan(entries: [CalendarEntry], access: CalendarAccess, now: Date, leadMinutes: Int) -> (event: CalendarEntry, alertDate: Date)? {
        guard access == .fullAccess, let event = nextTimedEvent(entries, now: now) else { return nil }
        return (event, event.start.addingTimeInterval(-TimeInterval(leadMinutes * 60)))
    }
    func reschedule() {
        task?.cancel(); task = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
        let minutes = reminderMinutes()
        guard let plan = Self.plan(entries: calendar.entries, access: calendar.access, now: Date(), leadMinutes: minutes) else {
            scheduledID = nil; return
        }
        let event = plan.event
        let lead = TimeInterval(minutes * 60)
        let alertDate = plan.alertDate
        let id = "\(event.id)|\(event.start.timeIntervalSince1970)|\(lead)"
        scheduledID = id
        if !firedIDs.contains(id) {
            task = Task { [weak self] in
                let wait = max(0, alertDate.timeIntervalSinceNow)
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                guard !Task.isCancelled, let self, self.scheduledID == id,
                      self.calendar.access == .fullAccess, event.start > Date() else { return }
                self.firedIDs.insert(id)
                self.onReminder?(event)
            }
        }
        if systemNotificationsEnabled() && !firedIDs.contains(id) {
            let content = UNMutableNotificationContent()
            content.title = "Upcoming event"
            content.body = "\(event.title) starts at \(event.start.formatted(.dateTime.hour().minute()))"
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, alertDate.timeIntervalSinceNow), repeats: false)
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger))
        }
    }
    func stop() {
        task?.cancel(); subscriptions.removeAll()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
    }
}

enum CalendarAccess: Equatable {
    case notDetermined, fullAccess, denied, restricted, writeOnly
}

@MainActor
protocol CalendarService {
    var access: CalendarAccess { get }
    func requestFullAccess() async throws -> Bool
    func events(from start: Date, to end: Date) -> [CalendarEntry]
}

@MainActor
final class EventKitCalendarService: CalendarService {
    private let store = EKEventStore()

    var access: CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notDetermined
        case .fullAccess, .authorized: .fullAccess
        case .writeOnly: .writeOnly
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .restricted
        }
    }

    func requestFullAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    func events(from start: Date, to end: Date) -> [CalendarEntry] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter { $0.endDate > start }
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                CalendarEntry(id: event.eventIdentifier ?? UUID().uuidString,
                              title: event.title?.isEmpty == false ? event.title : "Untitled event",
                              start: event.startDate, end: event.endDate,
                              isAllDay: event.isAllDay, calendarName: event.calendar.title,
                              joinURL: CalendarMeetingLink.resolve(direct: event.url, location: event.location, notes: event.notes))
            }
    }
}

@MainActor
final class CalendarModel: ObservableObject {
    @Published private(set) var access: CalendarAccess = .notDetermined
    @Published private(set) var entries: [CalendarEntry] = []
    @Published private(set) var isRequesting = false
    @Published private(set) var errorMessage: String?

    private let service: any CalendarService
    private let now: () -> Date
    private var storeObserver: NSObjectProtocol?
    private var appObserver: NSObjectProtocol?

    init(service: any CalendarService = EventKitCalendarService(), now: @escaping () -> Date = Date.init) {
        self.service = service
        self.now = now
        refresh()
        storeObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        appObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    var nextEvent: CalendarEntry? { entries.first }

    var statusText: String {
        if let errorMessage { return errorMessage }
        return switch access {
        case .notDetermined: "Connect Calendar to see your upcoming events"
        case .fullAccess: entries.isEmpty ? "No events in the next seven days" : "Upcoming events"
        case .denied: "Calendar access denied. Enable Nubi in System Settings → Privacy & Security → Calendars."
        case .restricted: "Calendar access is restricted on this Mac"
        case .writeOnly: "Full Calendar access is needed to show events"
        }
    }

    func refresh() {
        access = service.access
        guard access == .fullAccess else { entries = []; return }
        let start = now()
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(7 * 86_400)
        entries = service.events(from: start, to: end)
        errorMessage = nil
    }

    func events(inMonthContaining date: Date) -> [CalendarEntry] {
        let days = CalendarMonthLayout.days(containing: date)
        guard access == .fullAccess, let first = days.first,
              let last = days.last,
              let end = Calendar.current.date(byAdding: .day, value: 1, to: last) else { return [] }
        return service.events(from: first, to: end)
    }

    func requestAccess() {
        guard !isRequesting, access == .notDetermined || access == .writeOnly else { return }
        isRequesting = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let granted = try await service.requestFullAccess()
                self.isRequesting = false
                self.refresh()
                if !granted && self.access == .notDetermined { self.access = .denied }
            } catch {
                self.isRequesting = false
                self.errorMessage = "Could not request Calendar access: \(error.localizedDescription)"
                self.refresh()
            }
        }
    }

    func openCalendar() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        NSWorkspace.shared.open(url)
    }

    func openAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(url)
    }

    func stop() {
        if let storeObserver { NotificationCenter.default.removeObserver(storeObserver) }
        if let appObserver { NotificationCenter.default.removeObserver(appObserver) }
        storeObserver = nil; appObserver = nil
        entries = []
    }
}
