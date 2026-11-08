import AppKit
import ApplicationServices
import Combine
import QuartzCore
import SwiftUI

@MainActor
final class ShelfDropZoneState: ObservableObject {
    @Published var fileDragNearTop = false
}

@MainActor
final class WindowSnapController: ObservableObject {
    static let shared = WindowSnapController()
    @Published private(set) var status = "Off"
    @Published private(set) var hoverZone: SnapZone?
    private var monitors: [Any] = []
    private var overlay: NSPanel?
    private var initialPosition: CGPoint?
    private var draggedWindow: AXUIElement?
    private var currentScreen: NSScreen?
    private var enabled = false
    func configure(enabled: Bool, askPermission: Bool = false) {
        stop()
        self.enabled = enabled
        guard enabled else { status = "Off"; return }
        let trusted = askPermission
            ? AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            : AXIsProcessTrusted()
        guard trusted else { status = "Accessibility belum diizinkan. Izinkan di System Settings."; return }
        status = "Ready"
        let handlers: [(NSEvent.EventTypeMask, (NSEvent) -> Void)] = [
            (NSEvent.EventTypeMask.leftMouseDown, { [weak self] (_: NSEvent) in self?.beginDrag() }),
            (NSEvent.EventTypeMask.leftMouseDragged, { [weak self] (event: NSEvent) in self?.updateDrag(event) }),
            (NSEvent.EventTypeMask.leftMouseUp, { [weak self] (_: NSEvent) in self?.endDrag() })
        ]
        for (mask, handler) in handlers {
            if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) { monitors.append(monitor) }
        }
    }
    func refreshAuthorization() {
        guard enabled else { return }
        let isMonitoring = !monitors.isEmpty
        if AXIsProcessTrusted() != isMonitoring { configure(enabled: true) }
    }
    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        overlay?.orderOut(nil)
        draggedWindow = nil; hoverZone = nil; initialPosition = nil
    }
    func snap(_ zone: SnapZone) {
        guard enabled else { status = "Aktifkan Window Snapping di Settings"; return }
        guard AXIsProcessTrusted() else { status = "Accessibility belum diizinkan"; return }
        guard let window = focusedWindow() else { status = "Tidak ada jendela aktif yang dapat diatur"; return }
        apply(zone, to: window, screen: NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main)
    }
    private func focusedWindow() -> AXUIElement? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success else { return nil }
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private func windowPosition(_ window: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }
    private func beginDrag() {
        guard enabled, let window = focusedWindow(), let position = windowPosition(window) else { return }
        draggedWindow = window; initialPosition = position
    }
    private func updateDrag(_ event: NSEvent) {
        guard let draggedWindow, let initialPosition, let position = windowPosition(draggedWindow),
              hypot(position.x - initialPosition.x, position.y - initialPosition.y) > 8,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) else { hideOverlay(); return }
        let pointer = NSEvent.mouseLocation
        guard pointer.y >= screen.frame.maxY - 95 else { hideOverlay(); return }
        let width = min(560, screen.frame.width)
        let frame = CGRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - 95, width: width, height: 95)
        guard frame.contains(pointer) else { hideOverlay(); return }
        currentScreen = screen
        hoverZone = SnapZone.selected(at: pointer.x, in: frame)
        showOverlay(frame: frame)
    }
    private func endDrag() {
        if let zone = hoverZone, let window = draggedWindow { apply(zone, to: window, screen: currentScreen) }
        draggedWindow = nil; initialPosition = nil; hideOverlay()
    }
    private func showOverlay(frame: CGRect) {
        if overlay == nil {
            let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .statusBar; panel.isOpaque = false; panel.backgroundColor = .clear
            panel.ignoresMouseEvents = true; panel.hasShadow = true
            overlay = panel
        }
        overlay?.contentView = NSHostingView(rootView: HStack(spacing: 4) {
            ForEach(SnapZone.allCases) { zone in
                Text(zone.title).font(.system(size: 11, weight: .bold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(zone == self.hoverZone ? Color.cyan.opacity(0.5) : Color.white.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 7))
            }
        }.padding(7).background(.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 12)))
        overlay?.setFrame(frame, display: true)
        overlay?.orderFrontRegardless()
    }
    private func hideOverlay() { hoverZone = nil; overlay?.orderOut(nil) }
    private func apply(_ zone: SnapZone, to window: AXUIElement, screen: NSScreen?) {
        guard let screen else { status = "Layar tidak ditemukan"; return }
        var canPosition = DarwinBoolean(false), canSize = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &canPosition) == .success,
              AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &canSize) == .success,
              canPosition.boolValue, canSize.boolValue else {
            status = "Jendela ini tidak dapat dipindah atau diubah ukurannya"; return
        }
        let target = zone.frame(in: screen.visibleFrame)
        let mainTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        var position = CGPoint(x: target.minX, y: mainTop - target.maxY)
        var size = target.size
        guard let positionValue = AXValueCreate(.cgPoint, &position), let sizeValue = AXValueCreate(.cgSize, &size),
              AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue) == .success,
              AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue) == .success else {
            status = "Jendela menolak ukuran atau posisi baru"; return
        }
        status = "Snapped \(zone.title)"
    }
}

final class NotchPanel: NSPanel {
    var allowsKeyInput = false
    var escapeAction: (() -> Void)?
    var numberAction: ((Int) -> Bool)?
    var paletteAction: (() -> Void)?
    override var canBecomeKey: Bool { allowsKeyInput }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { escapeAction?() }
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "k" {
            paletteAction?(); return
        }
        if !(firstResponder is NSTextView), event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
           let value = Int(event.charactersIgnoringModifiers ?? ""), (1...9).contains(value),
           numberAction?(value) == true { return }
        super.keyDown(with: event)
    }
}

@MainActor
final class TrackingHostingView<Content: View>: NSHostingView<Content> {
    var pointerChanged: ((Bool) -> Void)?
    var verticalGesture: ((CGFloat, CGFloat) -> Bool)?
    var interactionShape: (() -> NotchShape)?
    private var area: NSTrackingArea?

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if let interactionShape, !interactionShape().contains(local, in: bounds, yIncreasesDownward: isFlipped) { return nil }
        return super.hitTest(point)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        self.area = area
    }
    override func mouseEntered(with event: NSEvent) { pointerChanged?(true) }
    override func mouseMoved(with event: NSEvent) { pointerChanged?(true) }
    override func mouseExited(with event: NSEvent) { pointerChanged?(false) }
    override func scrollWheel(with event: NSEvent) {
        if verticalGesture?(event.scrollingDeltaY, event.locationInWindow.y) == true { return }
        super.scrollWheel(with: event)
    }
}

@MainActor
final class NotchWindowManager {
    let panel: NotchPanel
    private let configuration: NotchConfiguration
    private let state: NotchStateController
    private let displays: DisplayManager
    private let presentation: IslandPresentationModel
    private let screenID: UInt32?
    private let ambient: IdleAnimationModel
    private let capturePreview: CapturePreviewModel
    private let activity: ActivityCoordinator
    private let clock: IslandClockModel
    private let nobi: NobiBlinkModel
    private let calendar: CalendarModel
    private let system: SystemInfoModel
    private let water: WaterReminderModel
    private let dropZone = ShelfDropZoneState()
    private var subscriptions = Set<AnyCancellable>()
    private var resizeTask: Task<Void, Never>?
    private var observations: [NSObjectProtocol] = []
    private var clickMonitors: [Any] = []
    private var shelfHasFiles = false
    private var shelfHasError = false
    private var downloadCount = 0
    private var clipboardCount = 0
    private var musicPlaying = false
    private var focusActive = false
    private var focusPhase: FocusTimerModel.Phase = .idle
    private var downloadActive = false
    private var showsLyrics = false
    private var resizing = false
    private var dropTargeted = false
    private var fullscreenProbe: Timer?
    private var fullscreenLeaveTask: Task<Void, Never>?
    private var fullscreenHoverActive = false
    private var fullscreenHoverMode = false
    private var spaceRefresh: Task<Void, Never>?
    private var sessionActive = true
    private var sessionLocked = false
    private var screenAwake = true
    private var lastRouteChange = Date.distantPast
    private var navigationPointer: NSPoint?
    private var navigationProbe: Timer?

    init(configuration: NotchConfiguration, state: NotchStateController, displays: DisplayManager, screenID: UInt32? = nil,
         music: MusicModel, system: SystemInfoModel, shelf: FileShelf, focus: FocusTimerModel, calendar: CalendarModel,
         presentation: IslandPresentationModel, clipboard: ClipboardHistoryModel, downloads: DownloadManager,
         notifications: NotificationBannerModel, brightness: BrightnessModel,
         mixer: SoundMixerModel, launcher: LauncherModel, developerWorkspace: DeveloperWorkspaceModel,
         developerTerminal: DeveloperTerminalModel, developerAgents: DeveloperAgentModel,
         developerServices: DeveloperServiceModel,
         todos: TodoModel, weather: WeatherModel,
         prayer: PrayerTimesModel, water: WaterReminderModel, quickNotes: QuickNoteModel, keepAwake: KeepAwakeModel, capturePreview: CapturePreviewModel,
         ambient: IdleAnimationModel, activity: ActivityCoordinator, clock: IslandClockModel, nobi: NobiBlinkModel,
         openSettings: @escaping (String?) -> Void, requestDownload: @escaping (URL?) -> Void) {
        self.configuration = configuration; self.state = state; self.displays = displays; self.presentation = presentation
        self.screenID = screenID; self.ambient = ambient; self.capturePreview = capturePreview; self.activity = activity
        self.clock = clock; self.nobi = nobi; self.calendar = calendar; self.system = system; self.water = water
        ambient.configure { [weak state, weak presentation, weak music, weak focus, weak downloads, weak configuration, weak calendar, weak system] in
            guard let state, let presentation, let configuration else { return false }
            return configuration.values.idleAnimation && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                && !state.isOpen && !state.interaction.pointerInside && presentation.transient == nil
                && !(music?.isPlaying ?? false) && focus?.phase == .idle
                && !(downloads?.items.contains { $0.state == .running } ?? false)
                && !(calendar?.nextEvent.map { !$0.isAllDay && $0.start.timeIntervalSinceNow > 0 && $0.start.timeIntervalSinceNow <= 600 } ?? false)
                && (system?.batteryPercent ?? 100) > 20
        }
        panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.acceptsMouseMovedEvents = true
        panel.setAccessibilityLabel("Nubi")
        panel.escapeAction = { [weak state] in state?.dismiss() }
        panel.paletteAction = { [weak state, weak presentation] in
            state?.open(); presentation?.select(.actions)
        }
        panel.numberAction = { [weak state, weak presentation, weak clipboard] number in
            guard state?.isExpanded == true, presentation?.route == .clipboard, clipboard?.enabled == true else { return false }
            return clipboard?.pasteVisible(at: number - 1) ?? false
        }
        let host = TrackingHostingView(rootView: NotchView(state: state, configuration: configuration, music: music,
                                                          system: system, shelf: shelf, focus: focus, calendar: calendar, presentation: presentation,
                                                          clipboard: clipboard, downloads: downloads, notifications: notifications,
                                                          brightness: brightness, mixer: mixer, launcher: launcher,
                                                          developerWorkspace: developerWorkspace, developerTerminal: developerTerminal,
                                                          developerAgents: developerAgents, developerServices: developerServices,
                                                          todos: todos, weather: weather,
                                                          prayer: prayer, water: water, quickNotes: quickNotes, keepAwake: keepAwake, capturePreview: capturePreview, ambient: ambient, activity: activity, clock: clock, nobi: nobi, dropZone: dropZone,
                                                          openSettings: openSettings, requestDownload: requestDownload,
                                                          dropTargetChanged: { [weak self] targeted in
                                                              self?.dropTargeted = targeted
                                                              self?.layout(animated: true)
                                                          }))
        host.sizingOptions = []
        host.interactionShape = {
            NotchShape(radius: configuration.values.cornerRadius, attachesToScreenEdge: state.attachesToScreenEdge)
        }
        host.pointerChanged = { [weak self] inside in self?.handlePointer(inside) }
        host.verticalGesture = { [weak self] delta, y in
            guard let self, abs(delta) >= 18, !self.state.isHidden else { return false }
            guard !self.state.isExpanded || y >= self.panel.frame.height - 72 else { return false }
            if delta < 0 {
                self.state.open(); self.presentation.select(self.presentation.lastRoute)
            } else { self.state.dismiss() }
            return true
        }
        panel.contentView = host
        configuration.$values.dropFirst().sink { [weak self] values in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let alert = self.presentation.transient, !values.allowsAlert(alert) { self.presentation.stop() }
                self.ambient.reset()
                self.layout(animated: false)
            }
        }.store(in: &subscriptions)
        state.$interaction.map(\.phase).removeDuplicates().dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in
                if state.isHidden || !state.isExpanded { capturePreview.stop() }
                if !state.isExpanded { self?.clearNavigationPointer() }
                self?.updateKeyboardFocus(activate: false)
                self?.layout(animated: true)
                self?.ambient.reset()
            }
        }.store(in: &subscriptions)
        state.$interaction.dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.ambient.reset() }
        }.store(in: &subscriptions)
        presentation.$route.dropFirst().sink { [weak self] route in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.lastRouteChange = .now
                self.state.navigationChanged()
                self.guardNavigationPointer()
                if route != .capture && route != .mixer { capturePreview.stop() }
                self.updateKeyboardFocus(activate: true)
                self.layout(animated: true)
            }
        }.store(in: &subscriptions)
        presentation.$isEditingHome.dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.layout(animated: true) }
        }.store(in: &subscriptions)
        presentation.$transient.dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.ambient.reset(); self?.layout(animated: true) }
        }.store(in: &subscriptions)
        ambient.$phase.dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.layout(animated: true) }
        }.store(in: &subscriptions)
        music.$isPlaying.removeDuplicates().sink { [weak self] playing in
            self?.musicPlaying = playing
            self?.updateActivity()
            Task { @MainActor [weak self] in self?.ambient.reset(); self?.layout(animated: true) }
        }.store(in: &subscriptions)
        music.$showsLyrics.sink { [weak self] visible in
            self?.showsLyrics = visible
            Task { @MainActor [weak self] in self?.layout(animated: true) }
        }.store(in: &subscriptions)
        focus.$phase.sink { [weak self] phase in
            self?.focusActive = phase != .idle
            self?.focusPhase = phase
            self?.updateActivity()
            Task { @MainActor [weak self] in self?.ambient.reset(); self?.layout(animated: true) }
        }.store(in: &subscriptions)
        shelf.$files.combineLatest(shelf.$error).sink { [weak self] files, error in
            self?.shelfHasFiles = !files.isEmpty
            self?.shelfHasError = error != nil
            Task { @MainActor [weak self] in self?.layout(animated: false) }
        }.store(in: &subscriptions)
        downloads.$items.sink { [weak self] items in
            self?.downloadCount = items.count
            self?.downloadActive = items.contains { $0.state == .running }
            self?.updateActivity()
            Task { @MainActor [weak self] in self?.ambient.reset(); self?.layout(animated: false) }
        }.store(in: &subscriptions)
        clipboard.$entries.sink { [weak self] entries in
            self?.clipboardCount = entries.count
            Task { @MainActor [weak self] in self?.layout(animated: false) }
        }.store(in: &subscriptions)
        water.$showingSettings.dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.layout(animated: true) }
        }.store(in: &subscriptions)
        calendar.$access.dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.layout(animated: true) }
        }.store(in: &subscriptions)
        observations.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                    object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.displays.refresh(); self?.layout(animated: false) }
        })
        observations.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshSpace() }
        })
        for name in [NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.sessionDidResignActiveNotification,
                     NSWorkspace.screensDidWakeNotification, NSWorkspace.screensDidSleepNotification] {
            observations.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let name = note.name
                Task { @MainActor in self?.sessionChanged(name) }
            })
        }
        observations.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshSpace() }
        })
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: { [weak self] _ in
            guard let self else { return }
            let dragPasteboard = NSPasteboard(name: .drag)
            let hasFile = dragPasteboard.types?.contains(.fileURL) == true
            let screen = self.screenID.flatMap { self.displays.exactScreen(for: $0) }
            let pointer = NSEvent.mouseLocation
            let nearTop = screen.map { abs(pointer.x - $0.frame.midX) <= 300 && pointer.y >= $0.frame.maxY - 110 && pointer.y <= $0.frame.maxY } ?? false
            let active = hasFile && nearTop && !self.state.isHidden
            if self.dropZone.fileDragNearTop != active {
                self.dropZone.fileDragNearTop = active
                self.layout(animated: true)
            }
        }) { clickMonitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] _ in
            guard let self, self.dropZone.fileDragNearTop else { return }
            self.dropZone.fileDragNearTop = false
            self.layout(animated: true)
        }) { clickMonitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            guard let self, self.state.isExpanded, !self.state.isPinned,
                  !self.resizing, Date().timeIntervalSince(self.lastRouteChange) > 0.75,
                  !self.containsIslandPoint(NSEvent.mouseLocation) else { return }
            self.state.dismiss()
        }) { clickMonitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            if let self, self.state.isExpanded, !self.state.isPinned,
               !self.resizing, Date().timeIntervalSince(self.lastRouteChange) > 0.75,
               !self.containsIslandPoint(NSEvent.mouseLocation) { self.state.dismiss() }
            return event
        }) { clickMonitors.append(monitor) }
        layout(animated: false)
    }

    private func containsIslandPoint(_ point: NSPoint) -> Bool {
        let shape = NotchShape(radius: configuration.values.cornerRadius, attachesToScreenEdge: state.attachesToScreenEdge)
        return shape.contains(point, in: panel.frame, yIncreasesDownward: false)
    }

    private func handlePointer(_ entered: Bool) {
        if resizing || state.isHidden { return }
        let inset = state.isOpen || presentation.transient != nil ? 0 : configuration.values.hoverInset
        let pointer = NSEvent.mouseLocation
        let inside = panel.frame.insetBy(dx: inset, dy: 0).contains(pointer) && containsIslandPoint(pointer)
        let actual = entered && inside
        if actual { clearNavigationPointer() }
        else if let origin = navigationPointer {
            let pointer = NSEvent.mouseLocation
            if hypot(pointer.x - origin.x, pointer.y - origin.y) < 4 { return }
            clearNavigationPointer()
        }
        if actual && !state.interaction.pointerInside { ambient.reset() }
        state.pointerChanged(inside: actual, opensPeek: !fullscreenHoverMode)
    }

    private func guardNavigationPointer() {
        guard state.isExpanded && !state.isPinned else { return }
        navigationPointer = NSEvent.mouseLocation
        guard navigationProbe == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let origin = self.navigationPointer else { return }
                let pointer = NSEvent.mouseLocation
                if hypot(pointer.x - origin.x, pointer.y - origin.y) >= 4 { self.handlePointer(true) }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        navigationProbe = timer
    }

    private func clearNavigationPointer() {
        navigationPointer = nil
        navigationProbe?.invalidate(); navigationProbe = nil
    }

    private func startFullscreenProbe() {
        guard fullscreenProbe == nil else { return }
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshFullscreenHover() }
        }
        RunLoop.main.add(timer, forMode: .common)
        fullscreenProbe = timer
    }

    private var targetScreen: NSScreen? {
        screenID.flatMap { displays.exactScreen(for: $0) }
            ?? (screenID == nil ? displays.screen(for: configuration.values.displayID) : nil)
    }

    private func sessionChanged(_ notification: Notification.Name) {
        switch notification {
        case NSWorkspace.sessionDidBecomeActiveNotification: sessionActive = true
        case NSWorkspace.sessionDidResignActiveNotification: sessionActive = false
        case NSWorkspace.screensDidWakeNotification: screenAwake = true
        case NSWorkspace.screensDidSleepNotification: screenAwake = false
        default: return
        }
        resetFullscreenHover()
        refreshSpace()
    }

    func setSessionLocked(_ locked: Bool) {
        guard sessionLocked != locked else { return }
        sessionLocked = locked
        if locked { presentation.stop() }
        refreshSpace()
    }

    private func refreshSpace() {
        spaceRefresh?.cancel()
        layout(animated: false, reorder: true)
        guard sessionActive && screenAwake && !sessionLocked else { return }
        spaceRefresh = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            self?.layout(animated: false, reorder: true)
        }
    }

    private func resetFullscreenHover() {
        fullscreenProbe?.invalidate(); fullscreenProbe = nil
        fullscreenLeaveTask?.cancel(); fullscreenLeaveTask = nil
        fullscreenHoverActive = false
        fullscreenHoverMode = false
    }

    private func refreshFullscreenHover() {
        guard fullscreenHoverMode, let screen = targetScreen else { return }
        guard fullscreenApplication(on: screen) != nil else {
            layout(animated: false, reorder: true)
            return
        }

        let pointer = NSEvent.mouseLocation
        let zone = PanelVisibility.fullscreenHoverZone(screen: screen.frame,
                                                       pillWidth: max(340, CGFloat(configuration.values.width)))
        if zone.contains(pointer) || (fullscreenHoverActive && containsIslandPoint(pointer)) || state.isPinned {
            fullscreenLeaveTask?.cancel(); fullscreenLeaveTask = nil
            if !fullscreenHoverActive {
                fullscreenHoverActive = true
                layout(animated: false, reorder: true)
            }
        } else if fullscreenHoverActive && fullscreenLeaveTask == nil {
            fullscreenLeaveTask = Task { [weak self] in
                guard let self else { return }
                do { try await Task.sleep(for: .seconds(self.configuration.values.collapseDelay)) } catch { return }
                self.fullscreenLeaveTask = nil
                let pointer = NSEvent.mouseLocation
                guard !zone.contains(pointer), !self.containsIslandPoint(pointer), !self.state.isPinned else { return }
                self.fullscreenHoverActive = false
                self.layout(animated: false)
            }
        }
    }

    private func updateKeyboardFocus(activate: Bool) {
        let acceptsInput = state.isExpanded
        if !acceptsInput && panel.isKeyWindow { panel.resignKey() }
        panel.allowsKeyInput = acceptsInput
        if acceptsInput && activate { panel.makeKeyAndOrderFront(nil) }
    }

    func layout(animated: Bool, reorder: Bool = false) {
        guard let screen = targetScreen, sessionActive, screenAwake, !sessionLocked else {
            resetFullscreenHover()
            resizeTask?.cancel()
            resizing = false
            state.setHidden(true)
            panel.orderOut(nil)
            return
        }
        let values = configuration.values
        let fullscreenApp = fullscreenApplication(on: screen)
        let foregroundApp = fullscreenApp ?? NSWorkspace.shared.frontmostApplication
        let excluded = foregroundApp?.bundleIdentifier.map(values.excludedApps.contains) ?? false
        let fullscreen = fullscreenApp != nil
        let internalAlert = presentation.transient?.isInternalAlert == true
        if fullscreen && !values.showInFullScreen && !excluded && !values.notificationsOnly {
            fullscreenHoverMode = true
            startFullscreenProbe()
        } else {
            resetFullscreenHover()
        }
        let hidden = PanelVisibility.hidden(excluded: excluded, fullscreen: fullscreen && !values.showInFullScreen,
                                            hoverReveal: fullscreenHoverActive || presentation.transient != nil,
                                            notificationsOnly: values.notificationsOnly, internalAlert: internalAlert)
        state.setHidden(hidden)
        if hidden {
            resizeTask?.cancel()
            resizing = false
            dropZone.fileDragNearTop = false
            panel.orderOut(nil)
            return
        }
        let size: CGSize
        if let transient = presentation.transient, !state.isPinned {
            switch transient {
            case .notification: size = CGSize(width: 370, height: 94)
            case .calendar, .timer, .download, .battery: size = CGSize(width: 390, height: 76)
            case .prayer: size = CGSize(width: 405, height: 94)
            case .water: size = CGSize(width: 390, height: 92)
            case .volume, .brightness, .microphoneMute, .batteryPower: size = CGSize(width: 320, height: 48)
            }
        } else if state.isExpanded {
            switch presentation.route {
            case .home:
                let rows = HomeLayout.rowCount(widgets: values.homeWidgets, wide: Set(values.wideWidgets), tall: Set(values.tallWidgets))
                let automatic = CGFloat(205 + rows * 160)
                let editorHeight = CGFloat(max(450, 290 + rows * 160))
                size = CGSize(width: 560, height: presentation.isEditingHome ? editorHeight : values.homeHeight > 0 ? CGFloat(values.homeHeight) : automatic)
            case .activities:
                let activeCount = (musicPlaying ? 1 : 0) + (focusActive ? 1 : 0) + (downloadActive ? 1 : 0)
                size = CGSize(width: 440, height: 158 + max(1, activeCount) * 28)
            case .music: size = CGSize(width: 500, height: showsLyrics ? 430 : 340)
            case .focus: size = CGSize(width: 430, height: focusPhase == .idle ? 315 : 220)
            case .mixer: size = CGSize(width: 540, height: 480)
            case .launcher: size = CGSize(width: 460, height: 380)
            case .developer: size = CGSize(width: 650, height: 440)
            case .terminal: size = CGSize(width: 720, height: 500)
            case .todos: size = CGSize(width: 460, height: 350)
            case .calculator: size = CGSize(width: 390, height: 390)
            case .more: size = CGSize(width: 530, height: 465)
            case .calendar:
                size = calendar.access == .fullAccess
                    ? CGSize(width: 690, height: 445) : CGSize(width: 500, height: 210)
            case .downloads: size = CGSize(width: 440, height: downloadCount == 0 ? 185 : 175 + min(2, downloadCount) * 38)
            case .clipboard: size = CGSize(width: 460, height: 240 + min(7, clipboardCount) * 30)
            case .shelf: size = CGSize(width: 440, height: 220 + (shelfHasFiles ? 100 : 0) + (shelfHasError ? 22 : 0))
            case .prayer: size = CGSize(width: 560, height: 475)
            case .water: size = CGSize(width: 540, height: water.showingSettings ? 395 : 312)
            case .notes: size = CGSize(width: 460, height: 330)
            case .battery: size = CGSize(width: 420, height: 245)
            case .system: size = CGSize(width: 440, height: 250)
            case .actions: size = CGSize(width: 460, height: 350)
            case .capture: size = CGSize(width: 520, height: 370)
            }
        } else if dropTargeted || dropZone.fileDragNearTop {
            size = CGSize(width: 560, height: 140)
        } else if state.isPeek {
            size = CGSize(width: 510, height: 164)
        } else if musicPlaying {
            let companionCount = (focusActive ? 1 : 0) + (downloadActive ? 1 : 0)
            size = CGSize(width: max(values.width, 390 + 35 * CGFloat(companionCount)), height: max(values.height, 44))
        } else {
            let activeCount = (focusActive ? 1 : 0) + (downloadActive ? 1 : 0)
            let upcoming = calendar.nextEvent.map { !$0.isAllDay && $0.start.timeIntervalSince(clock.now) > 0
                && $0.start.timeIntervalSince(clock.now) <= 600 } ?? false
            let nobiOnly = ambient.isNobiIdle && activeCount == 0 && !upcoming && (system.batteryPercent ?? 100) > 20
            size = CGSize(width: ambient.phase == .preview ? max(values.width, 430) : nobiOnly ? min(values.width, 112) : activeCount > 1 ? max(values.width, 380) : values.width,
                          height: ambient.phase == .preview ? max(values.height, 54) : values.height)
        }
        let height = min(size.height, screen.frame.height)
        let attached = !values.belowMenuBar || fullscreen
        let shape = NotchShape(radius: values.cornerRadius, attachesToScreenEdge: attached)
        let shoulder = shape.shoulderWidth(in: CGSize(width: screen.frame.width, height: height))
        let width = min(size.width + 2 * shoulder, screen.frame.width)
        state.setAttachesToScreenEdge(attached)
        let top = attached ? screen.frame.maxY : screen.visibleFrame.maxY
        let frame = PanelGeometry.frame(screen: screen.frame, top: top, requestedSize: CGSize(width: width, height: height))
        resizeTask?.cancel()
        let duration = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? values.animationDuration : 0
        resizing = duration > 0
        if duration > 0 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else { panel.setFrame(frame, display: true) }
        if reorder || !panel.isVisible { panel.orderFrontRegardless() }
        resizeTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(duration + 0.03)) } catch { return }
            guard let self else { return }
            self.resizing = false
            self.handlePointer(true)
        }
    }

    private func updateActivity() { state.activityChanged(musicPlaying || focusActive || downloadActive) }

    private func fullscreenApplication(on screen: NSScreen) -> NSRunningApplication? {
        let display = CGDisplayBounds(DisplayManager.id(of: screen))
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for window in windows {
            guard let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != ownPID,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let raw = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: raw as CFDictionary),
                  display.contains(CGPoint(x: bounds.midX, y: bounds.midY)),
                  bounds.width >= display.width * 0.5, bounds.height >= display.height * 0.5 else { continue }
            guard PanelVisibility.fillsDisplay(bounds, display: display, safeTop: screen.safeAreaInsets.top) else { return nil }
            return NSRunningApplication(processIdentifier: pid)
        }
        return nil
    }

    func stop() {
        clearNavigationPointer()
        resetFullscreenHover()
        spaceRefresh?.cancel()
        clickMonitors.forEach(NSEvent.removeMonitor)
        clickMonitors.removeAll()
        resizeTask?.cancel()
        ambient.stop()
        for observer in observations {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observations.removeAll()
        panel.orderOut(nil)
    }
}
