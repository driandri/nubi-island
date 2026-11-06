import AppKit
import SwiftUI

@MainActor
final class LockScreenOverlay {
    private let configuration: NotchConfiguration
    private let music: MusicModel
    private let system: SystemInfoModel
    private var space: LockScreenSpace?
    private var pill: NSPanel?
    private var card: NSPanel?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var poll: Timer?
    private var failedAttempts = 0
    private(set) var isLocked = false
    var onLockChanged: ((Bool) -> Void)?

    init(configuration: NotchConfiguration, music: MusicModel, system: SystemInfoModel) {
        self.configuration = configuration
        self.music = music
        self.system = system
    }

    func start() {
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, names: ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"].map(Notification.Name.init(rawValue:)))
        observe(NSWorkspace.shared.notificationCenter, names: [
            NSWorkspace.screensDidWakeNotification, NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.sessionDidResignActiveNotification
        ])
        observe(.default, names: [NSApplication.didChangeScreenParametersNotification])
        refresh()
    }

    func refresh() {
        let enabled = configuration.values.showOnLockScreen
        if enabled && poll == nil {
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
            RunLoop.main.add(timer, forMode: .common)
            poll = timer
        } else if !enabled {
            poll?.invalidate()
            poll = nil
            failedAttempts = 0
            if !configuration.lockScreenStatus.isEmpty { configuration.lockScreenStatus = "" }
        }

        let locked = Self.sessionIsLocked()
        if locked != isLocked {
            isLocked = locked
            failedAttempts = 0
            onLockChanged?(locked)
        }
        guard enabled, locked, failedAttempts < 3, let screen = NSScreen.screens.first,
              CGDisplayIsAsleep(DisplayManager.id(of: screen)) == 0 else {
            hide()
            return
        }
        if space == nil { space = LockScreenSpace() }
        guard let space else { failed(); return }

        let safeTop = screen.safeAreaInsets.top
        let cameraWidth = screen.auxiliaryTopLeftArea.flatMap { left in
            screen.auxiliaryTopRightArea.map { $0.minX - left.maxX }
        } ?? 0
        let pillFrame = LockScreenLayout.pillFrame(on: screen.frame, safeTop: safeTop, cameraWidth: cameraWidth)
        if pill?.frame != pillFrame {
            pill?.orderOut(nil)
            pill = makePanel(frame: pillFrame, interactive: false,
                             content: LockScreenPill(configuration: configuration, system: system, safeTop: safeTop))
        }
        let cardFrame = music.hasLockScreenTrack ? LockScreenLayout.cardFrame(on: screen.frame) : nil
        if let cardFrame {
            if card == nil {
                card = makePanel(frame: cardFrame, interactive: true,
                                 content: LockScreenMusicCard(configuration: configuration, music: music,
                                                               canControl: Self.sessionIsLocked))
            }
        } else {
            card?.orderOut(nil)
            card = nil
        }
        if let card, let cardFrame, card.frame != cardFrame { card.setFrame(cardFrame, display: true) }
        if space.present([pill, card].compactMap { $0 }) {
            failedAttempts = 0
            if !configuration.lockScreenStatus.isEmpty { configuration.lockScreenStatus = "" }
        } else { failed() }
    }

    func stop() {
        poll?.invalidate()
        poll = nil
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        hide()
    }

    private func observe(_ center: NotificationCenter, names: [Notification.Name]) {
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
            observers.append((center, token))
        }
    }

    private static func sessionIsLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session[kCGSessionOnConsoleKey as String] as? Bool == true
            && session[kCGSessionLoginDoneKey as String] as? Bool == true
            && session["CGSSessionScreenIsLocked"] as? Bool == true
    }

    private func makePanel<Content: View>(frame: CGRect, interactive: Bool, content: Content) -> NSPanel {
        let panel = LockScreenPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                    backing: .buffered, defer: false)
        panel.canBecomeVisibleWithoutLogin = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = !interactive
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: content)
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }

    private func failed() {
        failedAttempts += 1
        if failedAttempts == 3 { configuration.lockScreenStatus = "Panel layar kunci gagal ditampilkan oleh macOS." }
        hide()
    }

    private func hide() {
        pill?.orderOut(nil)
        card?.orderOut(nil)
        pill = nil
        card = nil
        space?.hide()
    }
}

private final class LockScreenPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// Only these dedicated panels enter the private WindowServer space.
@MainActor
private final class LockScreenSpace {
    private typealias Connection = @convention(c) () -> Int32
    private typealias Create = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SetLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias Visibility = @convention(c) (Int32, CFArray) -> Int32
    private typealias MoveWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32
    private let connection: Int32
    private let space: Int32
    private let showSpace: Visibility
    private let hideSpace: Visibility
    private let moveWindows: MoveWindows
    private var visible = false

    init?() {
        // See Lakr233/SkyLightWindow for the WindowServer calling convention.
        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"
        guard let library = dlopen(path, RTLD_LAZY | RTLD_NODELETE) else { return nil }
        defer { dlclose(library) }
        func load<T>(_ name: String, _: T.Type) -> T? {
            dlsym(library, name).map { unsafeBitCast($0, to: T.self) }
        }
        guard let mainConnection = load("SLSMainConnectionID", Connection.self),
              let create = load("SLSSpaceCreate", Create.self),
              let setLevel = load("SLSSpaceSetAbsoluteLevel", SetLevel.self),
              let show = load("SLSShowSpaces", Visibility.self),
              let hide = load("SLSHideSpaces", Visibility.self),
              let move = load("SLSSpaceAddWindowsAndRemoveFromSpaces", MoveWindows.self) else { return nil }
        let connection = mainConnection()
        guard connection > 0 else { return nil }
        let space = create(connection, 1, 0)
        guard space > 0, setLevel(connection, space, 400) == 0 else { return nil }
        self.connection = connection
        self.space = space
        showSpace = show
        hideSpace = hide
        moveWindows = move
    }

    func present(_ panels: [NSPanel]) -> Bool {
        guard showSpace(connection, [space] as CFArray) == 0 else { return false }
        visible = true
        let windows = panels.map(\.windowNumber)
        guard windows.allSatisfy({ $0 > 0 }) else { return false }
        for panel in panels where !panel.isVisible { panel.orderFrontRegardless() }
        return moveWindows(connection, space, windows as CFArray, 7) == 0
    }

    func hide() {
        guard visible else { return }
        _ = hideSpace(connection, [space] as CFArray)
        visible = false
    }
}
