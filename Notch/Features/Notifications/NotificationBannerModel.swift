import AppKit
import ApplicationServices
import Combine

struct AllowedNotificationApp: Codable, Equatable, Identifiable {
    let bundleID: String
    let name: String
    var id: String { bundleID }
}

struct AllowedNotificationWebOrigin: Codable, Equatable, Identifiable {
    let host: String
    var id: String { host }
}

struct NotificationCard: Identifiable, Equatable {
    let id: String
    let app: AllowedNotificationApp
    let title: String
    let body: String
}

enum NotificationBannerParser {
    static func parse(_ strings: [String], allowed: [AllowedNotificationApp], websites: [AllowedNotificationWebOrigin] = []) -> NotificationCard? {
        let values = strings.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if let browser = values.first, ["Google Chrome", "Safari"].contains(browser),
           let origin = websites.first(where: { site in values.dropFirst().prefix(2).contains { visibleOrigin($0, host: site.host) } }),
           let originIndex = values.dropFirst().prefix(2).firstIndex(where: { visibleOrigin($0, host: origin.host) }),
           (originIndex == 1 || values[1].caseInsensitiveCompare("WhatsApp") == .orderedSame),
           let title = values.dropFirst(originIndex + 1).first, title.count <= 300 {
            let bundleID = browser == "Safari" ? "com.apple.Safari" : "com.google.Chrome"
            let body = values.dropFirst(originIndex + 2).first ?? ""
            guard body.count <= 1_000 else { return nil }
            let app = AllowedNotificationApp(bundleID: bundleID, name: origin.host)
            return NotificationCard(id: "\(bundleID)|\(origin.host)|\(title)|\(body)", app: app, title: title, body: body)
        }
        if let first = values.first, ["Google Chrome", "Safari"].contains(first) { return nil }
        guard let index = values.prefix(3).firstIndex(where: { text in allowed.contains { matches(text, app: $0) } }),
              allowed.filter({ matches(values[index], app: $0) }).count == 1,
              let app = allowed.first(where: { matches(values[index], app: $0) }),
              values.count > index + 1 else { return nil }
        let title = values[index + 1]
        let body = values.dropFirst(index + 2).first ?? ""
        guard title.count <= 300, body.count <= 1_000 else { return nil }
        return NotificationCard(id: "\(app.bundleID)|\(title)|\(body)", app: app, title: title, body: body)
    }
    static func visibleOrigin(_ text: String, host: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value == host.lowercased() || value == "https://\(host.lowercased())"
    }
    private static func matches(_ text: String, app: AllowedNotificationApp) -> Bool {
        if app.name.caseInsensitiveCompare(text) == .orderedSame { return true }
        return app.bundleID.lowercased().contains("whatsapp") && text.caseInsensitiveCompare("WhatsApp") == .orderedSame
    }
}

@MainActor
final class NotificationBannerModel: ObservableObject {
    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: Self.enabledKey); bind() } }
    @Published private(set) var allowedApps: [AllowedNotificationApp]
    @Published private(set) var allowedWebOrigins: [AllowedNotificationWebOrigin]
    @Published private(set) var latest: NotificationCard?
    @Published private(set) var status = "Off"
    var onBanner: (() -> Void)?
    private static let enabledKey = "notch.notifications.enabled"
    private static let appsKey = "notch.notifications.allowed-apps"
    private static let sitesKey = "notch.notifications.allowed-web-origins"
    private let defaults: UserDefaults
    private var observers: [(AXObserver, CFRunLoopSource)] = []
    private var pollTimer: Timer?
    private var clearTask: Task<Void, Never>?
    private var lastSignature: String?
    private var latestElement: AXUIElement?
    private var trustedAtBind: Bool?
    private var workspaceToken: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.bool(forKey: Self.enabledKey)
        allowedApps = defaults.data(forKey: Self.appsKey).flatMap { try? JSONDecoder().decode([AllowedNotificationApp].self, from: $0) } ?? []
        allowedWebOrigins = defaults.data(forKey: Self.sitesKey).flatMap { try? JSONDecoder().decode([AllowedNotificationWebOrigin].self, from: $0) } ?? []
        workspaceToken = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                                                          object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  ["com.apple.notificationcenterui", "com.apple.UserNotificationCenter"].contains(app.bundleIdentifier ?? "") else { return }
            Task { @MainActor [weak self] in self?.bind() }
        }
        bind()
    }
    func requestAccess() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        bind()
    }
    func refreshAuthorization() {
        if AXIsProcessTrusted() != trustedAtBind { bind() }
    }
    func addApp(bundleID: String, name: String) {
        guard !bundleID.isEmpty, !name.isEmpty else { return }
        allowedApps.removeAll { $0.bundleID == bundleID }
        allowedApps.append(AllowedNotificationApp(bundleID: bundleID, name: name))
        saveApps(); bind()
    }
    func removeApp(_ app: AllowedNotificationApp) { allowedApps.removeAll { $0 == app }; saveApps(); bind() }
    func addWebOrigin(_ value: String) -> Bool {
        let host = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard host.contains("."), !host.contains("/"), !host.contains(":"),
              host.range(of: "^[a-z0-9][a-z0-9.-]*[a-z0-9]$", options: .regularExpression) != nil else { return false }
        if !allowedWebOrigins.contains(where: { $0.host == host }) { allowedWebOrigins.append(.init(host: host)) }
        saveSites(); bind(); return true
    }
    func removeWebOrigin(_ origin: AllowedNotificationWebOrigin) {
        allowedWebOrigins.removeAll { $0 == origin }; saveSites(); bind()
    }
    private func saveApps() { defaults.set(try? JSONEncoder().encode(allowedApps), forKey: Self.appsKey) }
    private func saveSites() { defaults.set(try? JSONEncoder().encode(allowedWebOrigins), forKey: Self.sitesKey) }

    private func bind() {
        unbind()
        trustedAtBind = AXIsProcessTrusted()
        guard enabled else { status = "Off"; return }
        guard !allowedApps.isEmpty || !allowedWebOrigins.isEmpty else { status = "Select apps or sites to mirror"; return }
        guard trustedAtBind == true else { status = "Accessibility access needed"; return }
        for bundleID in ["com.apple.notificationcenterui", "com.apple.UserNotificationCenter"] {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
                var observer: AXObserver?
                guard AXObserverCreate(app.processIdentifier, { _, _, _, context in
                    guard let context else { return }
                    let model = Unmanaged<NotificationBannerModel>.fromOpaque(context).takeUnretainedValue()
                    Task { @MainActor in model.scan() }
                }, &observer) == .success, let observer else { continue }
                let element = AXUIElementCreateApplication(app.processIdentifier)
                let context = Unmanaged.passUnretained(self).toOpaque()
                _ = AXObserverAddNotification(observer, element, kAXWindowCreatedNotification as CFString, context)
                let source = AXObserverGetRunLoopSource(observer)
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
                observers.append((observer, source))
            }
        }
        guard !observers.isEmpty else { status = "Notification UI unavailable"; return }
        status = "Watching visible banners; web banners need a visible site origin"
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scan() }
        }
    }
    private func unbind() {
        pollTimer?.invalidate(); pollTimer = nil
        for (_, source) in observers { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
        observers.removeAll()
        latest = nil; latestElement = nil; clearTask?.cancel()
    }
    private func scan() {
        guard enabled, AXIsProcessTrusted() else { return }
        for bundleID in ["com.apple.notificationcenterui", "com.apple.UserNotificationCenter"] {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
                let element = AXUIElementCreateApplication(app.processIdentifier)
                var raw: CFTypeRef?
                guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &raw) == .success,
                      let windows = raw as? [AXUIElement] else { continue }
                for window in windows {
                    guard isBanner(window) else { continue }
                    let strings = text(in: window, depth: 0)
                    guard let card = NotificationBannerParser.parse(strings, allowed: allowedApps, websites: allowedWebOrigins), card.id != lastSignature else { continue }
                    lastSignature = card.id; latest = card; latestElement = window
                    onBanner?()
                    clearTask?.cancel()
                    clearTask = Task { [weak self] in
                        try? await Task.sleep(for: .seconds(5))
                        guard !Task.isCancelled else { return }
                        self?.latest = nil; self?.latestElement = nil
                    }
                    return
                }
            }
        }
        lastSignature = nil
    }
    private func isBanner(_ window: AXUIElement) -> Bool {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { return false }
        let value = raw as! AXValue
        guard AXValueGetType(value) == .cgSize else { return false }
        var size = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &size) else { return false }
        var visibleRaw: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, "AXVisible" as CFString, &visibleRaw) == .success,
           let visible = visibleRaw as? Bool, !visible { return false }
        return (250...700).contains(size.width) && (50...300).contains(size.height)
    }
    private func text(in element: AXUIElement, depth: Int) -> [String] {
        guard depth < 8 else { return [] }
        var result: [String] = []
        var raw: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &raw) == .success,
           let value = raw as? String { result.append(value) }
        for attribute in [kAXTitleAttribute, kAXDescriptionAttribute] {
            raw = nil
            if AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
               let value = raw as? String, !result.contains(value) { result.append(value) }
        }
        raw = nil
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &raw) == .success,
           let children = raw as? [AXUIElement] {
            for child in children.prefix(30) { result += text(in: child, depth: depth + 1) }
        }
        return result
    }
    func openLatest() {
        guard let card = latest else { return }
        if let latestElement, AXUIElementPerformAction(latestElement, kAXPressAction as CFString) == .success { return }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: card.app.bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }
    func stop() {
        unbind(); status = "Off"
        if let workspaceToken { NSWorkspace.shared.notificationCenter.removeObserver(workspaceToken) }
        workspaceToken = nil
    }
}
