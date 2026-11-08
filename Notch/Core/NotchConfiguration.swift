import AppKit
import Combine
import SwiftUI

struct NotchPreferences: Codable, Equatable {
    var width: Double = 340
    var height: Double = 34
    var cornerRadius: Double = 17
    var animationDuration: Double = 0.3
    var expandDelay: Double = 0.15
    var collapseDelay: Double = 0.4
    var hoverInset: Double = 0
    var displayID: UInt32 = 0
    var accent = "Mint"
    var showSystemInfo = true
    var showStatus = true
    var showInFullScreen = false
    var showOnLockScreen = false
    var belowMenuBar = false
    var panelStyle = "Classic Black"
    var glassTransparency = 0.32
    var navigationTabs = IslandRoute.defaultTabs.map(\.rawValue)
    var animateMusic = true
    var homeWidgets = ["Calendar", "Music", "Timer"]
    var displayMode = "Single"
    var idleAnimation = true
    var hudVolume = true
    var hudBrightness = true
    var hudBattery = true
    var hudMicrophone = true
    var homeHeight: Double = 0
    var wideWidgets: [String] = []
    var tallWidgets: [String] = []
    var calendarReminderMinutes = 10
    var calendarSystemNotifications = false
    var prayerRemindersEnabled = true
    var prayerReminderMinutes = 10
    var excludedApps: [String] = []
    var notificationsOnly = false
    var snapEnabled = false
    var openShortcut = ""

    enum CodingKeys: String, CodingKey {
        case width, height, cornerRadius, animationDuration, expandDelay, collapseDelay, hoverInset
        case displayID, accent, showSystemInfo, showStatus, showInFullScreen, showOnLockScreen, belowMenuBar
        case panelStyle, animateMusic, homeWidgets, displayMode, idleAnimation, homeHeight, wideWidgets, tallWidgets
        case hudVolume, hudBrightness, hudBattery, hudMicrophone, glassTransparency, navigationTabs
        case calendarReminderMinutes, calendarSystemNotifications, prayerRemindersEnabled, prayerReminderMinutes
        case excludedApps, notificationsOnly, snapEnabled, openShortcut
    }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        width = try c.decodeIfPresent(Double.self, forKey: .width) ?? width
        height = try c.decodeIfPresent(Double.self, forKey: .height) ?? height
        cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? cornerRadius
        animationDuration = try c.decodeIfPresent(Double.self, forKey: .animationDuration) ?? animationDuration
        expandDelay = try c.decodeIfPresent(Double.self, forKey: .expandDelay) ?? expandDelay
        collapseDelay = try c.decodeIfPresent(Double.self, forKey: .collapseDelay) ?? collapseDelay
        hoverInset = try c.decodeIfPresent(Double.self, forKey: .hoverInset) ?? hoverInset
        displayID = try c.decodeIfPresent(UInt32.self, forKey: .displayID) ?? displayID
        accent = try c.decodeIfPresent(String.self, forKey: .accent) ?? accent
        showSystemInfo = try c.decodeIfPresent(Bool.self, forKey: .showSystemInfo) ?? showSystemInfo
        showStatus = try c.decodeIfPresent(Bool.self, forKey: .showStatus) ?? showStatus
        showInFullScreen = try c.decodeIfPresent(Bool.self, forKey: .showInFullScreen) ?? showInFullScreen
        showOnLockScreen = try c.decodeIfPresent(Bool.self, forKey: .showOnLockScreen) ?? showOnLockScreen
        belowMenuBar = try c.decodeIfPresent(Bool.self, forKey: .belowMenuBar) ?? belowMenuBar
        panelStyle = try c.decodeIfPresent(String.self, forKey: .panelStyle) ?? panelStyle
        glassTransparency = try c.decodeIfPresent(Double.self, forKey: .glassTransparency) ?? glassTransparency
        navigationTabs = try c.decodeIfPresent([String].self, forKey: .navigationTabs) ?? navigationTabs
        animateMusic = try c.decodeIfPresent(Bool.self, forKey: .animateMusic) ?? animateMusic
        homeWidgets = try c.decodeIfPresent([String].self, forKey: .homeWidgets) ?? homeWidgets
        displayMode = try c.decodeIfPresent(String.self, forKey: .displayMode) ?? displayMode
        idleAnimation = try c.decodeIfPresent(Bool.self, forKey: .idleAnimation) ?? idleAnimation
        hudVolume = try c.decodeIfPresent(Bool.self, forKey: .hudVolume) ?? hudVolume
        hudBrightness = try c.decodeIfPresent(Bool.self, forKey: .hudBrightness) ?? hudBrightness
        hudBattery = try c.decodeIfPresent(Bool.self, forKey: .hudBattery) ?? hudBattery
        hudMicrophone = try c.decodeIfPresent(Bool.self, forKey: .hudMicrophone) ?? hudMicrophone
        homeHeight = try c.decodeIfPresent(Double.self, forKey: .homeHeight) ?? homeHeight
        wideWidgets = try c.decodeIfPresent([String].self, forKey: .wideWidgets) ?? wideWidgets
        tallWidgets = try c.decodeIfPresent([String].self, forKey: .tallWidgets) ?? tallWidgets
        calendarReminderMinutes = try c.decodeIfPresent(Int.self, forKey: .calendarReminderMinutes) ?? calendarReminderMinutes
        calendarSystemNotifications = try c.decodeIfPresent(Bool.self, forKey: .calendarSystemNotifications) ?? calendarSystemNotifications
        prayerRemindersEnabled = try c.decodeIfPresent(Bool.self, forKey: .prayerRemindersEnabled) ?? prayerRemindersEnabled
        prayerReminderMinutes = try c.decodeIfPresent(Int.self, forKey: .prayerReminderMinutes) ?? prayerReminderMinutes
        excludedApps = try c.decodeIfPresent([String].self, forKey: .excludedApps) ?? excludedApps
        notificationsOnly = try c.decodeIfPresent(Bool.self, forKey: .notificationsOnly) ?? notificationsOnly
        snapEnabled = try c.decodeIfPresent(Bool.self, forKey: .snapEnabled) ?? snapEnabled
        openShortcut = try c.decodeIfPresent(String.self, forKey: .openShortcut) ?? openShortcut
    }

    mutating func sanitize() {
        width = width.isFinite ? min(max(width, 120), 380) : 340
        height = height.isFinite ? min(max(height, 24), 60) : 34
        cornerRadius = cornerRadius.isFinite ? min(max(cornerRadius, 4), 30) : 17
        animationDuration = animationDuration.isFinite ? min(max(animationDuration, 0.1), 0.8) : 0.3
        expandDelay = expandDelay.isFinite ? min(max(expandDelay, 0), 1.5) : 0.15
        collapseDelay = collapseDelay.isFinite ? min(max(collapseDelay, 0.1), 2) : 0.4
        hoverInset = hoverInset.isFinite ? min(max(hoverInset, 0), 8) : 0
        if !["Mint", "Blue", "Violet", "Orange"].contains(accent) { accent = "Mint" }
        if panelStyle == "Solid" { panelStyle = "Classic Black" }
        if panelStyle == "Accent glow" { panelStyle = "Accent Glow" }
        if !["Classic Black", "Apple Glass", "Accent Glow"].contains(panelStyle) { panelStyle = "Classic Black" }
        glassTransparency = glassTransparency.isFinite ? min(max(glassTransparency, 0), 0.55) : 0.32
        navigationTabs = featureTabs.map(\.rawValue)
        if !["Single", "All"].contains(displayMode) { displayMode = "Single" }
        homeHeight = homeHeight.isFinite && homeHeight > 0 ? min(max(homeHeight, 320), 800) : 0
        if ![5, 10, 30].contains(calendarReminderMinutes) { calendarReminderMinutes = 10 }
        if ![5, 10, 30].contains(prayerReminderMinutes) { prayerReminderMinutes = 10 }
        excludedApps = Array(Set(excludedApps.filter { !$0.isEmpty })).sorted()
        if !["", "control-option-space", "control-option-n", "control-shift-space"].contains(openShortcut) { openShortcut = "" }
        let valid = ["Calendar", "Music", "Timer", "Mixer", "To-do", "Launcher", "Developer", "Calculator", "Downloads", "Agenda", "Clipboard", "Shelf", "System", "Weather", "Prayer", "Water", "Battery", "Quick Notes", "Keep Awake", "Quick Actions", "Camera & Mic"]
        var seen = Set<String>()
        homeWidgets = homeWidgets.filter { valid.contains($0) && seen.insert($0).inserted }
        seen.removeAll()
        wideWidgets = wideWidgets.filter { valid.contains($0) && seen.insert($0).inserted }
        seen.removeAll()
        tallWidgets = tallWidgets.filter { valid.contains($0) && !wideWidgets.contains($0) && seen.insert($0).inserted }
    }

    var featureTabs: [IslandRoute] {
        var seen = Set<IslandRoute>()
        return Array(navigationTabs.compactMap(IslandRoute.init(rawValue:))
            .filter { $0 != .home && $0 != .more && seen.insert($0).inserted }
            .prefix(IslandRoute.maximumTabs))
    }

    func allowsAlert(_ alert: IslandTransient) -> Bool {
        if notificationsOnly && !alert.isInternalAlert { return false }
        switch alert {
        case .volume: return hudVolume
        case .brightness: return hudBrightness
        case .battery, .batteryPower: return hudBattery
        case .microphoneMute: return hudMicrophone
        case .prayer: return prayerRemindersEnabled
        default: return true
        }
    }
}

@MainActor
final class NotchConfiguration: ObservableObject {
    @Published var shortcutStatus = ""
    @Published var lockScreenStatus = ""
    private let defaults: UserDefaults
    private static let key = "notch.preferences.v1"
    private static let designMigrationKey = "notch.design-size-migration.v1"
    @Published var values: NotchPreferences {
        didSet {
            let encoded = try? JSONEncoder().encode(values)
            defaults.set(encoded, forKey: Self.key)
        }
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Self.key)
        var loaded = stored
            .flatMap { try? JSONDecoder().decode(NotchPreferences.self, from: $0) } ?? NotchPreferences()
        let migrateSize = stored != nil && !defaults.bool(forKey: Self.designMigrationKey)
            && loaded.width == 180 && loaded.height == 32
        if migrateSize { loaded.width = 340; loaded.height = 34 }
        loaded.sanitize()
        values = loaded
        if migrateSize, let encoded = try? JSONEncoder().encode(loaded) { defaults.set(encoded, forKey: Self.key) }
        defaults.set(true, forKey: Self.designMigrationKey)
    }
    func reset() { values = NotchPreferences() }
    var accentColor: Color {
        switch values.accent {
        case "Blue": return .cyan
        case "Violet": return .purple
        case "Orange": return .orange
        default: return Color(red: 0.48, green: 0.93, blue: 0.74)
        }
    }
}
