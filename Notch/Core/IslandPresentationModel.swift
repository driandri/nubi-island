import AppKit
import Combine
import CoreGraphics
import Foundation

struct IslandClockText {
    let date: Date
    private let locale = Locale(identifier: "id_ID")
    var shortDate: String { date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(locale)) }
    var time: String { date.formatted(.dateTime.hour().minute().locale(locale)) }
    var header: String { "\(shortDate) · \(time)" }
}

@MainActor
final class IslandClockModel: ObservableObject {
    @Published private(set) var now: Date
    private let nowSource: () -> Date
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    init(nowSource: @escaping () -> Date = Date.init, running: Bool = true) {
        self.nowSource = nowSource
        now = nowSource()
        if running { start() }
    }
    var text: IslandClockText { IslandClockText(date: now) }
    func start() {
        guard observers.isEmpty else { return }
        for name in [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange, .NSCalendarDayChanged] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                                            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        })
        refresh()
    }
    func refresh() {
        now = nowSource()
        timer?.invalidate()
        let nextMinute = (floor(now.timeIntervalSince1970 / 60) + 1) * 60
        let delay = max(0.05, nextMinute - now.timeIntervalSince1970 + 0.02)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    func stop() {
        timer?.invalidate(); timer = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }
}

enum IslandRoute: String, CaseIterable, Identifiable {
    case home = "Home", activities = "Live Activities", music = "Music", focus = "Timer", mixer = "Mixer", launcher = "Launcher", developer = "Developer", terminal = "Terminal", todos = "To-do", calculator = "Calculator", more = "More", calendar = "Calendar", downloads = "Downloads", clipboard = "Clipboard", shelf = "Shelf", prayer = "Sholat", water = "Water", notes = "Quick Notes", battery = "Battery", system = "System", actions = "Quick Actions", capture = "Camera & Mic"
    var id: String { rawValue }
    static var featureCatalog: [Self] { allCases.filter { $0 != .home && $0 != .more } }
    static let defaultTabs: [Self] = [.music, .focus, .calendar, .mixer, .launcher]
    static let maximumTabs = 5
    var navigationTitle: String { self == .more ? "Fitur" : rawValue }
    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .activities: "circle.grid.2x2.fill"
        case .music: "music.note"
        case .focus: "timer"
        case .mixer: "slider.horizontal.3"
        case .launcher: "square.grid.2x2"
        case .developer: "chevron.left.forwardslash.chevron.right"
        case .terminal: "terminal"
        case .todos: "checklist"
        case .calculator: "plus.forwardslash.minus"
        case .more: "ellipsis"
        case .calendar: "calendar"
        case .downloads: "arrow.down.circle"
        case .clipboard: "doc.on.clipboard"
        case .shelf: "tray"
        case .prayer: "moon.stars"
        case .water: "drop.fill"
        case .notes: "note.text"
        case .battery: "battery.100percent"
        case .system: "desktopcomputer"
        case .actions: "command"
        case .capture: "camera.fill"
        }
    }
}

enum IslandTransient: Equatable {
    case notification, volume(Int, Bool), brightness(Int), microphoneMute(Bool), batteryPower(Int, Bool), calendar(String), timer(String), download(String), battery(Int), prayer(String, String, Bool, Double), water
    var isSystemHUD: Bool {
        switch self { case .volume, .brightness, .microphoneMute, .batteryPower: true; default: false }
    }
    var isInternalAlert: Bool {
        switch self { case .calendar, .timer, .download, .battery, .prayer, .water: true; default: false }
    }
    var priority: Int {
        switch self {
        case .timer, .calendar, .prayer: 4
        case .battery, .download, .water: 3
        case .batteryPower: 2
        case .notification: 2
        case .volume, .brightness, .microphoneMute: 1
        }
    }
}

enum SnapZone: String, CaseIterable, Identifiable {
    case left, right, topLeft, topRight, bottomLeft, bottomRight, full
    var id: String { rawValue }
    var title: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        case .topLeft: "↖"
        case .topRight: "↗"
        case .bottomLeft: "↙"
        case .bottomRight: "↘"
        case .full: "Full"
        }
    }
    static func selected(at x: CGFloat, in frame: CGRect) -> Self {
        let fraction = min(0.999, max(0, (x - frame.minX) / max(1, frame.width)))
        return allCases[Int(fraction * CGFloat(allCases.count))]
    }
    func frame(in visible: CGRect) -> CGRect {
        let halfWidth = visible.width / 2, halfHeight = visible.height / 2
        switch self {
        case .left: return CGRect(x: visible.minX, y: visible.minY, width: halfWidth, height: visible.height)
        case .right: return CGRect(x: visible.midX, y: visible.minY, width: halfWidth, height: visible.height)
        case .topLeft: return CGRect(x: visible.minX, y: visible.midY, width: halfWidth, height: halfHeight)
        case .topRight: return CGRect(x: visible.midX, y: visible.midY, width: halfWidth, height: halfHeight)
        case .bottomLeft: return CGRect(x: visible.minX, y: visible.minY, width: halfWidth, height: halfHeight)
        case .bottomRight: return CGRect(x: visible.midX, y: visible.minY, width: halfWidth, height: halfHeight)
        case .full: return visible
        }
    }
}

@MainActor
final class ActivityCoordinator: ObservableObject {
    @Published private(set) var musicPlaying = false
    @Published private(set) var timerActive = false
    @Published private(set) var downloadActive = false
    @Published private(set) var nextEvent: String?
    @Published private(set) var batteryPercent: Int?
    private var lastAlert: IslandTransient?
    private var lastAlertDate = Date.distantPast
    private var currentPriority = 0
    func update(music: Bool, timer: Bool, download: Bool, event: String?, battery: Int?) {
        musicPlaying = music; timerActive = timer; downloadActive = download
        nextEvent = event; batteryPercent = battery
    }
    func accepts(_ alert: IslandTransient, now: Date = .now) -> Bool {
        if alert == lastAlert && now.timeIntervalSince(lastAlertDate) < 5 { return false }
        if now.timeIntervalSince(lastAlertDate) < 5 && alert.priority < currentPriority { return false }
        lastAlert = alert; lastAlertDate = now; currentPriority = alert.priority
        return true
    }
}

enum IdlePhase: Equatable { case resting, blinking, preview }

enum PanelTopology {
    static func desiredIDs(available: [UInt32], selected: UInt32, mode: String) -> [UInt32] {
        guard let primary = available.first else { return [] }
        if mode == "All" { return available }
        return [selected != 0 && available.contains(selected) ? selected : primary]
    }
    static func alertTarget(pointerID: UInt32?, desired: [UInt32], primaryID: UInt32?) -> UInt32? {
        if let pointerID, desired.contains(pointerID) { return pointerID }
        if let primaryID, desired.contains(primaryID) { return primaryID }
        return desired.first
    }
}

enum HomeLayout {
    struct Placement: Equatable {
        let column: Int
        let row: Int
        let columns: Int
        let rows: Int
    }
    static func placements(widgets: [String], wide: Set<String>, tall: Set<String>) -> [Placement] {
        placements(spans: widgets.map { (wide.contains($0) ? 2 : 1, tall.contains($0) ? 2 : 1) })
    }
    static func placements(spans: [(Int, Int)]) -> [Placement] {
        var occupied = Set<Int>()
        var result: [Placement] = []
        for span in spans {
            let columns = min(max(span.0, 1), 3)
            let rows = min(max(span.1, 1), 2)
            var row = 0
            var column = 0
            search: while true {
                for candidate in 0...(3 - columns) {
                    let cells = (row..<(row + rows)).flatMap { r in
                        (candidate..<(candidate + columns)).map { r * 3 + $0 }
                    }
                    if cells.allSatisfy({ !occupied.contains($0) }) {
                        column = candidate
                        occupied.formUnion(cells)
                        break search
                    }
                }
                row += 1
            }
            result.append(Placement(column: column, row: row, columns: columns, rows: rows))
        }
        return result
    }
    static func rowCount(widgets: [String], wide: Set<String>, tall: Set<String>) -> Int {
        placements(widgets: widgets, wide: wide, tall: tall).map { $0.row + $0.rows }.max() ?? 0
    }
    static func rows(widgets: [String], wide: Set<String>) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var used = 0
        for widget in widgets {
            let span = wide.contains(widget) ? 2 : 1
            if used + span > 3 { rows.append(row); row = []; used = 0 }
            row.append(widget); used += span
        }
        if !row.isEmpty { rows.append(row) }
        return rows
    }
}

@MainActor
final class IdleAnimationModel: ObservableObject {
    @Published private(set) var phase: IdlePhase = .resting
    @Published private(set) var isNobiIdle = false
    private var task: Task<Void, Never>?
    private var canAnimate: () -> Bool = { false }
    private let initialDelay: Duration
    private let blinkDuration: Duration
    private let previewDuration: Duration
    private let pollInterval: Duration
    private let inputIdleSeconds: () -> TimeInterval
    private var observers: [NSObjectProtocol] = []
    private var suspended = false
    private var needsNewInput = false
    init(initialDelay: Duration = .seconds(15 * 60), blinkDuration: Duration = .milliseconds(180),
         previewDuration: Duration = .seconds(2), pollInterval: Duration = .seconds(1),
         inputIdleSeconds: @escaping () -> TimeInterval = {
             CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: CGEventType(rawValue: UInt32.max)!)
         }) {
        self.initialDelay = initialDelay; self.blinkDuration = blinkDuration
        self.previewDuration = previewDuration; self.pollInterval = pollInterval
        self.inputIdleSeconds = inputIdleSeconds
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.suspend() }
            })
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.resumeAfterInput() }
            })
        }
    }
    func configure(_ predicate: @escaping () -> Bool) { canAnimate = predicate; reset() }
    func reset() {
        task?.cancel(); phase = .resting; isNobiIdle = false
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let idle = self.inputIdleSeconds()
                if idle.isFinite && idle < 5 { self.needsNewInput = false }
                let threshold = Double(self.initialDelay.components.seconds)
                    + Double(self.initialDelay.components.attoseconds) / 1e18
                if !self.suspended && !self.needsNewInput && self.canAnimate() && idle.isFinite && idle >= threshold {
                    if !self.isNobiIdle {
                        self.isNobiIdle = true
                        self.phase = .blinking
                        try? await Task.sleep(for: self.blinkDuration)
                        guard !Task.isCancelled else { return }
                        self.phase = .preview
                        try? await Task.sleep(for: self.previewDuration)
                        guard !Task.isCancelled else { return }
                        self.phase = .resting
                    }
                } else if self.isNobiIdle || self.phase != .resting {
                    self.isNobiIdle = false
                    self.phase = .resting
                }
                try? await Task.sleep(for: self.pollInterval)
            }
        }
    }
    private func suspend() { suspended = true; task?.cancel(); phase = .resting; isNobiIdle = false }
    private func resumeAfterInput() { suspended = false; needsNewInput = true; reset() }
    func stop() {
        task?.cancel(); phase = .resting; isNobiIdle = false
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers.removeAll()
    }
}

@MainActor
final class NobiBlinkModel: ObservableObject {
    @Published private(set) var isBlinking = false
    private var task: Task<Void, Never>?
    private var canBlink: () -> Bool = { false }
    private let interval: Duration
    private let blinkDuration: Duration
    init(interval: Duration = .seconds(30), blinkDuration: Duration = .milliseconds(180)) {
        self.interval = interval; self.blinkDuration = blinkDuration
    }
    func configure(_ predicate: @escaping () -> Bool) { canBlink = predicate; reset() }
    func reset() {
        task?.cancel(); isBlinking = false
        guard canBlink() else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(for: self.interval)
                guard !Task.isCancelled, self.canBlink() else { return }
                self.isBlinking = true
                try? await Task.sleep(for: self.blinkDuration)
                guard !Task.isCancelled else { return }
                self.isBlinking = false
            }
        }
    }
    func stop() { task?.cancel(); task = nil; isBlinking = false }
}

@MainActor
final class IslandPresentationModel: ObservableObject {
    @Published var route: IslandRoute = .home
    @Published private(set) var transient: IslandTransient?
    @Published private(set) var hasNotificationBadge = false
    @Published private(set) var lastRoute: IslandRoute = .home
    @Published private(set) var isEditingHome = false
    private var clearTask: Task<Void, Never>?

    func show(_ value: IslandTransient, pinned: Bool) {
        if pinned {
            if value == .notification || value.isInternalAlert {
                hasNotificationBadge = true
                clearTask?.cancel()
                clearTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                    self?.hasNotificationBadge = false
                }
            }
            return
        }
        transient = value
        clearTask?.cancel()
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.transient = nil
        }
    }

    func select(_ route: IslandRoute) {
        self.route = route
        if route != .home { isEditingHome = false }
        if route != .home && route != .more { lastRoute = route }
        transient = nil
        clearTask?.cancel()
        hasNotificationBadge = false
    }
    func toggleHomeEditing() { route = .home; isEditingHome.toggle() }
    func finishHomeEditing() { isEditingHome = false }

    func clearNotificationBadge() { hasNotificationBadge = false }

    func stop() { clearTask?.cancel(); transient = nil }
}
