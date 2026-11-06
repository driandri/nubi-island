import AppKit
import Carbon
import Combine
import SwiftUI

@MainActor
private final class GlobalOpenShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onOpen: (() -> Void)?
    func configure(_ value: String) -> String {
        stop()
        guard !value.isEmpty else { return "" }
        let key: UInt32
        let modifiers: UInt32
        switch value {
        case "control-option-space": key = 49; modifiers = UInt32(controlKey | optionKey)
        case "control-option-n": key = 45; modifiers = UInt32(controlKey | optionKey)
        case "control-shift-space": key = 49; modifiers = UInt32(controlKey | shiftKey)
        default: return "Shortcut tidak dikenal"
        }
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, pointer in
            guard let pointer else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<GlobalOpenShortcut>.fromOpaque(pointer).takeUnretainedValue()
            Task { @MainActor in owner.onOpen?() }
            return noErr
        }
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), callback, 1, &event,
                                                Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard handlerStatus == noErr else { return "Shortcut tidak tersedia (kode \(handlerStatus))" }
        let identifier = EventHotKeyID(signature: 0x4E4F5443, id: 1)
        let status = RegisterEventHotKey(key, modifiers, identifier, GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr { stop(); return "Shortcut bentrok atau tidak tersedia (kode \(status))" }
        return "Shortcut aktif"
    }
    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil; handler = nil
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let onboarding = OnboardingStore()
    private let configuration = NotchConfiguration()
    private let displays = DisplayManager()
    private let music = MusicModel(defaults: .standard)
    private let system = SystemInfoModel()
    private lazy var lockScreen = LockScreenOverlay(configuration: configuration, music: music, system: system)
    private let shelf = FileShelf()
    private let focus = FocusTimerModel()
    private let calendar = CalendarModel()
    private let clipboard = ClipboardHistoryModel()
    private let downloads = DownloadManager()
    private let notifications = NotificationBannerModel()
    private let mixer = SoundMixerModel()
    private let launcher = LauncherModel()
    private let todos = TodoModel()
    private let weather = WeatherModel()
    private let water = WaterReminderModel()
    private let quickNotes = QuickNoteModel()
    private let keepAwake = KeepAwakeModel()
    private let capturePreview = CapturePreviewModel()
    private let activity = ActivityCoordinator()
    private let clock = IslandClockModel()
    private let nobi = NobiBlinkModel()
    private lazy var prayer = PrayerTimesModel(weather: weather)
    private lazy var prayerReminder = PrayerReminderCoordinator(prayer: prayer,
        leadMinutes: { [weak self] in self?.configuration.values.prayerReminderMinutes ?? 10 },
        enabled: { [weak self] in self?.configuration.values.prayerRemindersEnabled ?? true })
    private let settingsNavigation = SettingsNavigationModel()
    private let openShortcut = GlobalOpenShortcut()
    private var configuredShortcut = ""
    private var configuredSnap = false
    private lazy var brightness = BrightnessModel(configuration: configuration)
    private lazy var reminder = CalendarReminderCoordinator(calendar: calendar,
        reminderMinutes: { [weak self] in self?.configuration.values.calendarReminderMinutes ?? 10 },
        systemNotificationsEnabled: { [weak self] in self?.configuration.values.calendarSystemNotifications ?? false })
    private struct PanelSession {
        let state: NotchStateController
        let presentation: IslandPresentationModel
        let manager: NotchWindowManager
        let visibilitySubscription: AnyCancellable
    }
    private var panels: [UInt32: PanelSession] = [:]
    private var subscriptions = Set<AnyCancellable>()
    private var screenObserver: NSObjectProtocol?
    private var lastVolume: Int?
    private var lastMuted = false
    private var lastBrightnessByDisplay: [UInt32: Int] = [:]
    private var lastBatteryAlert: Int?
    private var lastBatteryCharging: Bool?
    private var lastInputMuted: Bool?
    private var completedDownloadIDs = Set<UUID>()
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        lockScreen.onLockChanged = { [weak self] locked in
            guard let self else { return }
            self.music.sessionLocked = locked
            if locked { self.capturePreview.stop() }
            for session in self.panels.values { session.manager.setSessionLocked(locked) }
            self.updateMusicVisibility()
        }
        lockScreen.start()
        music.startAutomaticDetection()
        lastVolume = system.volumePercent
        lastMuted = system.isMuted
        lastBrightnessByDisplay = brightness.percentByDisplay
        lastBatteryCharging = system.batteryCharging
        lastInputMuted = system.inputMuted
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NobiArtwork.menuBarImage(blinking: false)
        item.button?.toolTip = "Nubi"
        let menu = NSMenu()
        menu.addItem(withTitle: "Nubi", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        addItem("New download…", action: #selector(newDownload), key: "", to: menu)
        addItem("Settings…", action: #selector(openSettings), key: ",", to: menu)
        addItem("Panduan Awal…", action: #selector(showOnboarding), key: "", to: menu)
        addItem("Pin / Unpin", action: #selector(togglePin), key: "", to: menu)
        addItem("Collapse", action: #selector(collapse), key: "", to: menu)
        menu.addItem(.separator())
        addItem("Quit Nubi", action: #selector(quit), key: "q", to: menu)
        item.menu = menu
        statusItem = item
        nobi.configure { [weak self] in
            guard let self else { return false }
            return self.configuration.values.idleAnimation && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                && !self.music.isPlaying && self.focus.phase == .idle
                && !self.downloads.items.contains(where: { $0.state == .running })
                && !self.panels.values.contains(where: { $0.state.isOpen })
        }
        nobi.$isBlinking.sink { [weak self] blinking in
            self?.statusItem?.button?.image = NobiArtwork.menuBarImage(blinking: blinking)
        }.store(in: &subscriptions)
        openShortcut.onOpen = { [weak self] in
            guard let self, let panel = self.activePanel, !panel.state.isHidden else { return }
            panel.state.open()
            panel.presentation.select(panel.presentation.lastRoute)
        }
        configuration.shortcutStatus = openShortcut.configure(configuration.values.openShortcut)
        configuredShortcut = configuration.values.openShortcut
        configuredSnap = configuration.values.snapEnabled
        WindowSnapController.shared.configure(enabled: configuredSnap)
        reconcilePanels()
        configuration.$values.dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.lockScreen.refresh()
                self.reconcilePanels()
                self.nobi.reset()
                if self.configuredShortcut != self.configuration.values.openShortcut {
                    self.configuredShortcut = self.configuration.values.openShortcut
                    self.configuration.shortcutStatus = self.openShortcut.configure(self.configuredShortcut)
                }
                if self.configuredSnap != self.configuration.values.snapEnabled {
                    self.configuredSnap = self.configuration.values.snapEnabled
                    WindowSnapController.shared.configure(enabled: self.configuredSnap, askPermission: self.configuredSnap)
                }
            }
        }.store(in: &subscriptions)
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                 object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.displays.refresh(); self?.reconcilePanels() }
        }
        notifications.onBanner = { [weak self] in
            guard let self else { return }
            self.showGlobal(.notification)
        }
        reminder.onReminder = { [weak self] event in
            self?.showGlobal(.calendar("\(event.title) starts at \(event.start.formatted(.dateTime.hour().minute()))"))
        }
        prayerReminder.onReminder = { [weak self] event in
            self?.showGlobal(.prayer(event.prayer.name, event.prayer.displayTime, event.isDue, event.progress))
        }
        water.onReminder = { [weak self] in self?.showGlobal(.water) }
        focus.$phase.dropFirst().sink { [weak self] phase in
            guard let self else { return }
            if phase == .finished { self.showGlobal(.timer(self.focus.mode == .pomodoro ? "Sesi selesai · pilih tahap berikutnya" : "Timer selesai")) }
            Task { @MainActor in self.updateActivity() }
        }.store(in: &subscriptions)
        downloads.$items.dropFirst().sink { [weak self] items in
            guard let self else { return }
            for item in items where item.state == .completed && !self.completedDownloadIDs.contains(item.id) {
                self.completedDownloadIDs.insert(item.id)
                self.showGlobal(.download("\(item.name) selesai diunduh"))
            }
            Task { @MainActor in self.updateActivity() }
        }.store(in: &subscriptions)
        system.$batteryPercent.dropFirst().sink { [weak self] value in
            guard let self else { return }
            if let value, value <= 20, (self.lastBatteryAlert == nil || self.lastBatteryAlert! > 20) {
                self.showGlobal(.battery(value))
            }
            self.lastBatteryAlert = value
            Task { @MainActor in self.updateActivity() }
        }.store(in: &subscriptions)
        system.$batteryCharging.removeDuplicates().dropFirst().sink { [weak self] charging in
            guard let self else { return }
            if let previous = self.lastBatteryCharging, let charging, previous != charging,
               let percent = self.system.batteryPercent {
                self.showGlobal(.batteryPower(percent, charging))
            }
            self.lastBatteryCharging = charging
        }.store(in: &subscriptions)
        music.$isPlaying.removeDuplicates().dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateActivity() }
        }.store(in: &subscriptions)
        calendar.$entries.dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateActivity() }
        }.store(in: &subscriptions)
        configuration.$values.map { [$0.calendarReminderMinutes, $0.calendarSystemNotifications ? 1 : 0] }
            .removeDuplicates().dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.reminder.reschedule() }
        }.store(in: &subscriptions)
        configuration.$values.map { [$0.prayerReminderMinutes, $0.prayerRemindersEnabled ? 1 : 0] }
            .removeDuplicates().dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.prayerReminder.check() }
        }.store(in: &subscriptions)
        system.$volumePercent.dropFirst().sink { [weak self] value in
            guard let self, let value else { return }
            if let old = self.lastVolume, old != value { self.showGlobal(.volume(value, self.system.isMuted)) }
            self.lastVolume = value
        }.store(in: &subscriptions)
        system.$isMuted.dropFirst().sink { [weak self] muted in
            guard let self else { return }
            if self.lastMuted != muted, let volume = self.system.volumePercent {
                self.showGlobal(.volume(volume, muted))
            }
            self.lastMuted = muted
        }.store(in: &subscriptions)
        system.$inputMuted.removeDuplicates().dropFirst().sink { [weak self] muted in
            guard let self else { return }
            if let previous = self.lastInputMuted, let muted, previous != muted {
                self.showGlobal(.microphoneMute(muted))
            }
            self.lastInputMuted = muted
        }.store(in: &subscriptions)
        brightness.$percentByDisplay.dropFirst().sink { [weak self] values in
            guard let self else { return }
            for (displayID, value) in values {
                if let previous = self.lastBrightnessByDisplay[displayID], previous != value {
                    self.showGlobal(.brightness(value), targetDisplayID: displayID)
                }
            }
            self.lastBrightnessByDisplay = values
        }.store(in: &subscriptions)
        if onboarding.shouldPresent {
            onboarding.beginFirstRun()
            showOnboarding()
        }
    }
    private func reconcilePanels() {
        let desired = PanelTopology.desiredIDs(available: displays.displays.map(\.id),
                                               selected: configuration.values.displayID,
                                               mode: configuration.values.displayMode)
        for id in panels.keys.filter({ !desired.contains($0) }) {
            panels[id]?.manager.stop(); panels[id]?.presentation.stop(); panels.removeValue(forKey: id)
        }
        for id in desired where panels[id] == nil {
            let state = NotchStateController(configuration: configuration)
            let presentation = IslandPresentationModel()
            let ambient = IdleAnimationModel()
            let manager = NotchWindowManager(configuration: configuration, state: state, displays: displays, screenID: id,
                                             music: music, system: system, shelf: shelf, focus: focus, calendar: calendar,
                                             presentation: presentation, clipboard: clipboard, downloads: downloads,
                                             notifications: notifications, brightness: brightness, mixer: mixer, launcher: launcher,
                                             todos: todos, weather: weather, prayer: prayer, water: water, quickNotes: quickNotes,
                                             keepAwake: keepAwake, capturePreview: capturePreview, ambient: ambient,
                                             activity: activity, clock: clock, nobi: nobi,
                                             openSettings: { [weak self] category in self?.showSettings(category: category) },
                                             requestDownload: { [weak self] url in self?.requestDownload(url) })
            manager.setSessionLocked(lockScreen.isLocked)
            let visibilitySubscription = state.$interaction.dropFirst().sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.updateMusicVisibility(); self?.nobi.reset() }
            }
            panels[id] = PanelSession(state: state, presentation: presentation, manager: manager,
                                      visibilitySubscription: visibilitySubscription)
        }
        updateMusicVisibility()
    }
    private func updateMusicVisibility() {
        let lockPlayerVisible = lockScreen.isLocked && configuration.values.showOnLockScreen
        music.setVisible(lockPlayerVisible || panels.values.contains { $0.state.isOpen })
    }
    private func updateActivity() {
        activity.update(music: music.isPlaying, timer: focus.phase != .idle && focus.phase != .finished,
                        download: downloads.items.contains { $0.state == .running },
                        event: CalendarReminderCoordinator.nextTimedEvent(calendar.entries, now: .now)?.title,
                        battery: system.batteryPercent)
        nobi.reset()
    }
    private var activePanel: PanelSession? {
        let pointer = NSEvent.mouseLocation
        let pointerID = NSScreen.screens.first(where: { $0.frame.contains(pointer) }).map(DisplayManager.id(of:))
        let primaryID = NSScreen.screens.first.map(DisplayManager.id(of:)) ?? 0
        guard let target = PanelTopology.alertTarget(pointerID: pointerID, desired: Array(panels.keys), primaryID: primaryID) else { return nil }
        return panels[target]
    }
    private func showGlobal(_ value: IslandTransient, targetDisplayID: UInt32? = nil) {
        guard !lockScreen.isLocked, configuration.values.allowsAlert(value) else { return }
        guard let panel = targetDisplayID.flatMap({ panels[$0] }) ?? activePanel else { return }
        if value.isSystemHUD && panel.state.isOpen { return }
        guard activity.accepts(value) else { return }
        panel.presentation.show(value, pinned: panel.state.isPinned && !configuration.values.notificationsOnly)
    }
    private func addItem(_ title: String, action: Selector, key: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }
    @objc func openSettings() {
        showSettings(category: nil)
    }
    private func showSettings(category: String?) {
        if let category { settingsNavigation.category = category }
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 740),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Nubi Settings"
            window.contentView = NSHostingView(rootView: SettingsView(configuration: configuration, displays: displays,
                                                                     music: music, calendar: calendar, clipboard: clipboard, notifications: notifications,
                                                                     brightness: brightness, system: system, mixer: mixer, weather: weather,
                                                                     navigation: settingsNavigation))
            window.isReleasedWhenClosed = false
            positionOnSelectedDisplay(window)
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    @objc private func showOnboarding() {
        if onboardingWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
                                  styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Welcome to Nubi"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: OnboardingView(music: music, calendar: calendar,
                                                                         clipboard: clipboard, notifications: notifications,
                                                                         mixer: mixer, openSettings: { [weak self] in self?.openSettings() },
                                                                         finish: { [weak self] in
                guard let self else { return }
                self.onboarding.complete()
                self.onboardingWindow?.close()
                self.onboardingWindow = nil
            }))
            positionOnSelectedDisplay(window)
            onboardingWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }
    private func positionOnSelectedDisplay(_ window: NSWindow) {
        guard let screen = displays.screen(for: configuration.values.displayID) else { window.center(); return }
        let visible = screen.visibleFrame
        window.setFrameOrigin(NSPoint(x: visible.midX - window.frame.width / 2,
                                      y: visible.midY - window.frame.height / 2))
    }
    @objc private func togglePin() { activePanel?.state.togglePin() }
    @objc private func newDownload() { requestDownload(nil) }
    private func requestDownload(_ initialURL: URL?) {
        let field = NSTextField(string: initialURL?.absoluteString ?? "")
        field.placeholderString = "https://example.com/file.zip"
        field.frame = NSRect(x: 0, y: 0, width: 360, height: 24)
        let prompt = NSAlert()
        prompt.messageText = "New download"
        prompt.informativeText = "Enter an HTTPS URL. Choose where to save it next."
        prompt.accessoryView = field
        prompt.addButton(withTitle: "Continue")
        prompt.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard prompt.runModal() == .alertFirstButtonReturn else { return }
        guard let url = DownloadManager.validatedURL(field.stringValue) else {
            let error = NSAlert(); error.messageText = "Enter a valid HTTPS URL"; error.runModal(); return
        }
        let save = NSSavePanel()
        save.nameFieldStringValue = url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent
        save.canCreateDirectories = true
        guard save.runModal() == .OK, let destination = save.url else { return }
        downloads.start(url: url, destination: destination)
        activePanel?.presentation.select(.downloads)
    }
    @objc private func collapse() { activePanel?.state.dismiss() }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        openShortcut.stop()
        lockScreen.stop()
        for session in panels.values { session.state.dismiss(); session.manager.stop(); session.presentation.stop() }
        panels.removeAll()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        system.stop()
        clock.stop()
        nobi.stop()
        music.stop()
        focus.reset()
        calendar.stop()
        reminder.stop()
        prayerReminder.stop()
        water.stop()
        clipboard.stop()
        notifications.stop()
        downloads.stop()
        brightness.stop()
        mixer.stop()
        weather.stop()
        prayer.stop()
        quickNotes.stop()
        keepAwake.stop()
        capturePreview.stop()
        WindowSnapController.shared.stop()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        onboardingWindow?.close()
    }
}
