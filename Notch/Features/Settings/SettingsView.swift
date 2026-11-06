import SwiftUI
import ServiceManagement
import ApplicationServices
import AVFoundation
import CoreGraphics
import UserNotifications

@MainActor
final class SettingsNavigationModel: ObservableObject {
    @Published var category = "Tampilan"
}

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case appearance = "Tampilan", home = "Home", navigation = "Navigasi", displays = "Layar", integrations = "Integrasi", general = "Umum"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .appearance: "paintbrush"
        case .home: "square.grid.2x2"
        case .navigation: "rectangle.bottomthird.inset.filled"
        case .displays: "display.2"
        case .integrations: "puzzlepiece.extension"
        case .general: "gearshape"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var configuration: NotchConfiguration
    @ObservedObject var displays: DisplayManager
    @ObservedObject var music: MusicModel
    @ObservedObject var calendar: CalendarModel
    @ObservedObject var clipboard: ClipboardHistoryModel
    @ObservedObject var notifications: NotificationBannerModel
    @ObservedObject var brightness: BrightnessModel
    @ObservedObject var system: SystemInfoModel
    @ObservedObject var mixer: SoundMixerModel
    @ObservedObject var weather: WeatherModel
    @ObservedObject var navigation: SettingsNavigationModel
    @ObservedObject private var snap = WindowSnapController.shared
    private var category: SettingsCategory { SettingsCategory(rawValue: navigation.category) ?? .appearance }
    @State private var city = ""
    @State private var site = ""
    @State private var siteError = false
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginMessage: String?
    @State private var calendarNotificationStatus: UNAuthorizationStatus?
    @State private var requestingCalendarNotifications = false
    @State private var calendarNotificationError = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("NUBI").font(.system(size: 12, weight: .bold, design: .rounded)).tracking(2)
                    .padding(.horizontal, 10).padding(.bottom, 12)
                ForEach(SettingsCategory.allCases) { item in
                    Button { navigation.category = item.rawValue } label: {
                        Label(item.rawValue, systemImage: item.symbol)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(9)
                            .background(category == item ? Color.accentColor.opacity(0.2) : .clear,
                                        in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain)
                }
                Spacer()
            }
            .frame(width: 140).padding(14).background(.regularMaterial)
            Divider()
        Form {
            if category == .appearance {
            Section("Appearance") {
                HStack(spacing: 8) {
                    themePreview("Classic Black", colors: [.black, Color(white: 0.13)])
                    themePreview("Apple Glass", colors: [Color(white: 0.6), Color(white: 0.18)])
                    themePreview("Accent Glow", colors: [.black, configuration.accentColor.opacity(0.7)])
                }
                slider("Width", value: $configuration.values.width, range: 120...380, suffix: "pt")
                slider("Height", value: $configuration.values.height, range: 24...60, suffix: "pt")
                slider("Corner radius", value: $configuration.values.cornerRadius, range: 4...30, suffix: "pt")
                Picker("Accent", selection: $configuration.values.accent) {
                    ForEach(["Mint", "Blue", "Violet", "Orange"], id: \.self) { Text($0) }
                }
                Picker("Panel style", selection: $configuration.values.panelStyle) {
                    Text("Classic Black").tag("Classic Black")
                    Text("Apple Glass").tag("Apple Glass")
                    Text("Accent Glow").tag("Accent Glow")
                }
                if configuration.values.panelStyle == "Apple Glass" {
                    HStack {
                        Text("Transparansi").frame(width: 135, alignment: .leading)
                        Slider(value: $configuration.values.glassTransparency, in: 0...0.55, step: 0.01)
                            .accessibilityLabel("Transparansi Apple Glass")
                        Text(configuration.values.glassTransparency.formatted(.percent.precision(.fractionLength(0))))
                            .monospacedDigit().foregroundStyle(.secondary).frame(width: 58, alignment: .trailing)
                    }
                }
                Text("Apple Glass berlaku di Peek dan panel terbuka. Kurangi Transparansi memakai latar solid.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Tampilkan Nobi setelah 15 menit tanpa input", isOn: $configuration.values.idleAnimation)
                Text("Waktu idle dihitung dari input mouse dan keyboard terakhir. Nobi kembali ke pill biasa saat ada input.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Animate playing music in the pill", isOn: $configuration.values.animateMusic)
                Toggle("Show status dot", isOn: $configuration.values.showStatus)
                Toggle("Tampilkan info sistem di panel", isOn: $configuration.values.showSystemInfo)
            }
            }
            if category == .home {
            Section("Home widgets") {
                Text("Choose cards and their order in the Nubi Home panel.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(configuration.values.homeWidgets + widgetChoices.filter { !configuration.values.homeWidgets.contains($0) }, id: \.self) { widget in
                    HStack {
                        Toggle(widget, isOn: Binding(get: { configuration.values.homeWidgets.contains(widget) },
                                                     set: { setWidget(widget, visible: $0) }))
                        Spacer()
                        if configuration.values.homeWidgets.contains(widget) {
                            Picker("Size", selection: Binding(get: { widgetSize(widget) },
                                                              set: { setWidgetSize(widget, size: $0) })) {
                                Text("Compact").tag("Compact")
                                Text("Wide").tag("Wide")
                                Text("Tall").tag("Tall")
                            }.frame(width: 108)
                            Button { moveWidget(widget, offset: -1) } label: { Image(systemName: "arrow.up") }
                                .disabled(configuration.values.homeWidgets.first == widget)
                                .accessibilityLabel("Move \(widget) up")
                            Button { moveWidget(widget, offset: 1) } label: { Image(systemName: "arrow.down") }
                                .disabled(configuration.values.homeWidgets.last == widget)
                                .accessibilityLabel("Move \(widget) down")
                        }
                    }
                }
                Button("Restore default widgets") {
                    configuration.values.homeWidgets = ["Calendar", "Music", "Timer"]
                    configuration.values.wideWidgets = []
                    configuration.values.tallWidgets = []
                }
            }
            Section("Home height") {
                Picker("Height", selection: Binding(get: { configuration.values.homeHeight == 0 ? "Auto" : "Custom" },
                                                  set: { configuration.values.homeHeight = $0 == "Auto" ? 0 : 500 })) {
                    Text("Auto").tag("Auto"); Text("Custom").tag("Custom")
                }
                if configuration.values.homeHeight > 0 { slider("Custom height", value: $configuration.values.homeHeight, range: 320...800, suffix: "pt") }
                Text("Home scrolls when cards exceed the panel height.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Weather · Open-Meteo") {
                HStack {
                    Text("City")
                    TextField("City name", text: $city).onSubmit { weather.setCity(city) }
                    Button("Use city") { weather.setCity(city) }
                }
                Button("Use current location") { weather.requestLocation() }
                Button("Refresh") { weather.refresh(force: true) }
                Text(weather.snapshot.map { "\($0.place): \($0.temperature)° · \($0.description)" } ?? weather.status)
                    .font(.caption).foregroundStyle(.secondary)
                Text("Weather data: Open-Meteo. Location is requested only by your action. Personal, noncommercial use.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Sholat uses the same city or location, with AlAdhan calculation method 20 (Kemenag). Local mosque times may differ.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Pengingat waktu sholat di island", isOn: $configuration.values.prayerRemindersEnabled)
                if configuration.values.prayerRemindersEnabled {
                    Picker("Ingatkan sebelum waktu sholat", selection: $configuration.values.prayerReminderMinutes) {
                        Text("5 menit").tag(5)
                        Text("10 menit").tag(10)
                        Text("30 menit").tag(30)
                    }
                }
            }
            }
            if category == .appearance {
            Section("Interaction") {
                slider("Animation duration", value: $configuration.values.animationDuration, range: 0.1...0.8, suffix: "s")
                slider("Expand delay", value: $configuration.values.expandDelay, range: 0...1.5, suffix: "s")
                slider("Collapse delay", value: $configuration.values.collapseDelay, range: 0.1...2, suffix: "s")
                slider("Hover edge inset", value: $configuration.values.hoverInset, range: 0...8, suffix: "pt")
                Text("A larger inset requires the pointer to move farther inside the collapsed notch. Click the notch or pin icon to keep it open.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Shortcut buka Nubi", selection: $configuration.values.openShortcut) {
                    Text("Mati").tag("")
                    Text("Control + Option + Space").tag("control-option-space")
                    Text("Control + Option + N").tag("control-option-n")
                    Text("Control + Shift + Space").tag("control-shift-space")
                }
                Text("Shortcut awalnya mati dan hanya membuka Nubi saat panel tidak Hidden.")
                    .font(.caption).foregroundStyle(.secondary)
                if !configuration.shortcutStatus.isEmpty {
                    Text(configuration.shortcutStatus).font(.caption).foregroundStyle(.secondary)
                }
            }
            }
            if category == .navigation { navigationSettings }
            if category == .displays {
            Section("Display") {
                Picker("Panels", selection: $configuration.values.displayMode) {
                    Text("One display").tag("Single"); Text("All displays").tag("All")
                }
                Picker("Monitor", selection: $configuration.values.displayID) {
                    Text("Primary display").tag(UInt32(0))
                    ForEach(displays.displays) { Text($0.name).tag($0.id) }
                    if configuration.values.displayID != 0 && !displays.displays.contains(where: { $0.id == configuration.values.displayID }) {
                        Text("Disconnected display (using primary)").tag(configuration.values.displayID)
                    }
                }.disabled(configuration.values.displayMode == "All")
                Toggle("Place below the menu bar", isOn: $configuration.values.belowMenuBar)
                Toggle("Selalu tampil di fullscreen", isOn: $configuration.values.showInFullScreen)
                Text("Jika dimatikan, arahkan pointer ke tengah tepi atas layar fullscreen untuk memunculkan pill.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Layar kunci") {
                Toggle("Tampilkan Nubi dan musik saat terkunci", isOn: $configuration.values.showOnLockScreen)
                Text("Judul, artis, dan cover musik bisa terlihat sebelum Mac dibuka. Kartu tampil di layar utama.")
                    .font(.caption).foregroundStyle(.secondary)
                if !configuration.lockScreenStatus.isEmpty {
                    Text(configuration.lockScreenStatus).font(.caption).foregroundStyle(.orange)
                }
                DisclosureGroup("Pratinjau") {
                    VStack(spacing: 12) {
                        LockScreenPill(configuration: configuration, system: system)
                            .frame(width: 184, height: 32)
                        if music.hasLockScreenTrack {
                            LockScreenMusicCard(configuration: configuration, music: music)
                                .frame(maxWidth: LockScreenLayout.cardSize.width)
                                .frame(height: LockScreenLayout.cardSize.height)
                        } else {
                            Text("Putar musik untuk melihat kartu di sini.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
            }
            Section("Aplikasi pengecualian") {
                Button("Tambah aplikasi…", action: chooseExcludedApp)
                ForEach(configuration.values.excludedApps, id: \.self) { bundleID in
                    HStack {
                        Text(NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID })?.localizedName ?? bundleID)
                        Spacer()
                        Button("Hapus") { configuration.values.excludedApps.removeAll { $0 == bundleID } }
                    }
                }
                Text("Panel Hidden saat aplikasi pilihan berada di depan. Daftar awal kosong; aturan layar penuh aktif secara bawaan.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            }
            if category == .integrations {
            Section("Music") {
                Toggle("Automatically detect playing music", isOn: Binding(get: { music.automaticDetection }, set: { music.setAutomatic($0) }))
                Picker("Manual player", selection: Binding(get: { music.source }, set: { music.select($0) })) {
                    ForEach(MusicSource.allCases) { Text($0.rawValue).tag($0) }
                }.disabled(music.automaticDetection)
                if music.automaticDetection || music.source != .demo {
                    Button(music.isBusy ? "Connecting…" : (music.automaticDetection ? "Retry detection" : "Connect / Refresh")) { music.connect() }
                        .disabled(music.isBusy)
                    Text("Auto mode follows Apple Music, Spotify, and playing YouTube tabs in Chrome. It checks Chrome tab URLs and reads playback only on YouTube watch pages. Allow Automation when macOS asks. For YouTube, also enable Chrome → View → Developer → Allow JavaScript from Apple Events.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Look up missing lyrics online", isOn: Binding(get: { music.onlineLyricsEnabled }, set: { music.setOnlineLyrics($0) }))
                Text("The Lyrics button first uses Apple Music track lyrics. When enabled, missing lyrics are requested from LRCLIB using the song title, artist, and duration. Results depend on that catalog.")
                    .font(.caption).foregroundStyle(.secondary)
                Text(music.message).font(.caption).foregroundStyle(.secondary)
                if let browserMessage = music.browserMessage { Text(browserMessage).font(.caption).foregroundStyle(.orange) }
                if let permissionMessage = music.permissionMessage {
                    Text(permissionMessage).font(.caption).foregroundStyle(.orange)
                }
            }
            Section("Clipboard") {
                Toggle("Remember recent copies", isOn: $clipboard.enabled)
                Toggle("Simpan riwayat di Mac ini", isOn: $clipboard.persistHistory).disabled(!clipboard.enabled)
                Text("Hingga 30 teks, tautan, atau warna HEX. Penyimpanan antar sesi meminta pilihan terpisah; tipe private, transient, dan file dilewati.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Abaikan aplikasi…", action: chooseIgnoredClipboardApp)
                ForEach(clipboard.ignoredApps, id: \.self) { bundleID in
                    HStack { Text(bundleID); Spacer(); Button("Hapus") { clipboard.removeIgnoredApp(bundleID) } }
                }
                if let error = clipboard.storageError { Text(error).font(.caption).foregroundStyle(.orange) }
                if !clipboard.entries.isEmpty { Button("Clear clipboard history") { clipboard.clear() } }
            }
            Section("Calendar") {
                Text(calendar.statusText).font(.caption).foregroundStyle(.secondary)
                if calendar.access == .notDetermined || calendar.access == .writeOnly {
                    Button(calendar.isRequesting ? "Requesting access…" : "Connect Calendar") { calendar.requestAccess() }
                        .disabled(calendar.isRequesting)
                }
                if calendar.access == .denied || calendar.access == .restricted {
                    Button("Buka izin Kalender di System Settings") { calendar.openAccessSettings() }
                }
                Button("Open Calendar") { calendar.openCalendar() }
                Picker("Island warning before event", selection: $configuration.values.calendarReminderMinutes) {
                    Text("5 minutes").tag(5); Text("10 minutes").tag(10); Text("30 minutes").tag(30)
                }
                Toggle("Also send a macOS notification", isOn: Binding(
                    get: { configuration.values.calendarSystemNotifications },
                    set: { setCalendarNotifications($0) }))
                    .disabled(requestingCalendarNotifications || calendarNotificationStatus == .denied)
                if calendarNotificationStatus == .denied {
                    Text("Izinkan notifikasi Nubi di Pengaturan Sistem untuk memakai pengingat Calendar.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Buka pengaturan notifikasi") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
                    }
                } else if requestingCalendarNotifications {
                    Text("Menunggu izin notifikasi macOS").font(.caption).foregroundStyle(.secondary)
                } else if calendarNotificationError {
                    Text("Izin notifikasi tidak dapat diminta. Coba lagi dari Settings.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("All-day events appear in Agenda without a timed warning.").font(.caption).foregroundStyle(.secondary)
                Text("Nubi reads upcoming events for Home and Calendar. EventKit requires full Calendar access to read events; Nubi does not create or change them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Notifications") {
                Toggle("Notifications-Only Mode", isOn: $configuration.values.notificationsOnly)
                Text("Saat aktif, panel membuka hanya untuk alert; menu bar dan Settings tetap tersedia.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Mirror selected app banners", isOn: $notifications.enabled)
                Text(notifications.status).font(.caption).foregroundStyle(.secondary)
                Button("Request Accessibility access") { notifications.requestAccess() }
                Button("Add application…", action: chooseNotificationApp)
                ForEach(notifications.allowedApps) { app in
                    HStack {
                        Text(app.name)
                        Spacer()
                        Button("Remove") { notifications.removeApp(app) }
                    }
                }
                HStack {
                    Text("Site origin")
                    TextField("Site host, e.g. web.whatsapp.com", text: $site)
                    Button("Allow site") { siteError = !notifications.addWebOrigin(site); if !siteError { site = "" } }
                }
                if siteError { Text("Enter a domain without https:// or a path.").foregroundStyle(.orange) }
                ForEach(notifications.allowedWebOrigins) { origin in
                    HStack { Text(origin.host); Spacer(); Button("Remove") { notifications.removeWebOrigin(origin) } }
                }
                Text("Chrome and Safari web banners require a visible site origin. Ambiguous banners are ignored.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Only visible banners from selected apps are mirrored. macOS keeps its original banner; Nubi does not store notification content or reply to messages.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Window Snapping") {
                Toggle("Snap jendela ke zona notch", isOn: $configuration.values.snapEnabled)
                Text("Seret jendela aplikasi ke tepi atas layar, lalu lepas pada target. Quick Actions menyediakan zona yang sama.")
                    .font(.caption).foregroundStyle(.secondary)
                Text(snap.status).font(.caption).foregroundStyle(.secondary)
                Button("Buka izin Accessibility") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
                }
            }
            Section("System HUD") {
                Toggle("Volume dan mute output", isOn: $configuration.values.hudVolume)
                Toggle("Brightness", isOn: $configuration.values.hudBrightness)
                Toggle("Baterai rendah dan pengisian", isOn: $configuration.values.hudBattery)
                Toggle("Mute mikrofon", isOn: $configuration.values.hudMicrophone)
                Text(brightness.percent.map { "Brightness layar terpilih: \($0)%" } ?? "Brightness tidak tersedia pada layar terpilih")
                    .font(.caption).foregroundStyle(.secondary)
                if system.batteryPercent == nil {
                    Text("Baterai internal tidak terdeteksi pada Mac ini.").font(.caption).foregroundStyle(.secondary)
                }
                Text(system.inputMuted.map { $0 ? "Mute mikrofon: aktif" : "Mute mikrofon: nonaktif" }
                     ?? "Status mute mikrofon tidak tersedia pada perangkat input ini")
                    .font(.caption).foregroundStyle(.secondary)
                Text("HUD macOS tetap tampil. Meter input mikrofon hanya berjalan setelah diaktifkan di panel Mixer atau Camera & Mic.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Capture & Preview") {
                LabeledContent("Screen Recording", value: CGPreflightScreenCaptureAccess() ? "Granted" : "Not granted · requested by screenshot picker")
                LabeledContent("Camera", value: capturePermission(.video))
                LabeledContent("Microphone", value: capturePermission(.audio))
                Text("Screenshot, kamera, dan mikrofon meminta izin hanya saat fiturnya dipilih. Preview kamera dan level mikrofon tidak menyimpan konten.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Buka izin Screen Recording") { openPrivacySettings("Privacy_ScreenCapture") }
                    Button("Kamera") { openPrivacySettings("Privacy_Camera") }
                    Button("Mikrofon") { openPrivacySettings("Privacy_Microphone") }
                }
            }
            Section("Sound Mixer") {
                Toggle("Mix audio from all playing applications", isOn: Binding(get: { mixer.enabled }, set: { mixer.setEnabled($0) }))
                Text(mixer.status).font(.caption).foregroundStyle(.secondary)
                Button(mixer.sessionActive ? "Ulangi routing audio" : "Mulai mixer untuk sesi ini") { mixer.retry() }
                    .disabled(!mixer.enabled)
                Text("Per-app volume requires macOS 14.2 or newer and System Audio Recording permission. macOS asks when mixing starts. Nubi processes audio in memory and does not record it.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Open Screen & System Audio Recording Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
                }
            }
            Section("Access overview") {
                LabeledContent("Calendar", value: calendar.statusText)
                LabeledContent("Accessibility", value: AXIsProcessTrusted() ? "Granted" : "Not granted")
                LabeledContent("Notification banners", value: notifications.enabled ? notifications.status : "Off")
                LabeledContent("Clipboard history", value: clipboard.enabled ? (clipboard.persistHistory ? "On · saved locally" : "On · session only") : "Off")
                LabeledContent("Music Automation", value: music.permissionMessage ?? music.message)
                LabeledContent("System audio", value: mixer.enabled ? mixer.status : "Off")
            }
            }
            if category == .general {
            Section("General") {
                Toggle("Launch at login", isOn: Binding(get: { loginEnabled }, set: { enabled in setLogin(enabled) }))
                if let loginMessage { Text(loginMessage).font(.caption).foregroundStyle(.orange) }
                Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
                Button("Reset to defaults") { configuration.reset() }
                Text("Reset keeps your login-item choice. Nubi runs in the menu bar. Music automatically follows the playing app by default. Files on the shelf are references and are cleared when you quit.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            }
        }
        .formStyle(.grouped)
        }
        .frame(width: 720, height: 740)
        .onAppear { refreshSettingsStatus(); city = weather.manualCity }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshSettingsStatus()
        }
    }
    private var navigationSettings: some View {
        let pinned = configuration.values.featureTabs
        return Section("Tab di bagian bawah panel") {
            Text("Home dan Fitur selalu tersedia. Pilih sampai lima tab dan gunakan panah untuk mengubah urutannya.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(pinned + IslandRoute.featureCatalog.filter { !pinned.contains($0) }) { route in
                let index = pinned.firstIndex(of: route)
                HStack {
                    Toggle(isOn: Binding(get: { configuration.values.featureTabs.contains(route) },
                                         set: { setNavigationTab(route, visible: $0) })) {
                        Label(route.navigationTitle, systemImage: route.symbol)
                    }
                    .disabled(index == nil && pinned.count >= IslandRoute.maximumTabs)
                    if let index {
                        Button { moveNavigationTab(index, by: -1) } label: { Image(systemName: "arrow.up") }
                            .disabled(index == 0).accessibilityLabel("Naikkan tab \(route.navigationTitle)")
                        Button { moveNavigationTab(index, by: 1) } label: { Image(systemName: "arrow.down") }
                            .disabled(index == pinned.count - 1).accessibilityLabel("Turunkan tab \(route.navigationTitle)")
                    }
                }
            }
            Button("Pulihkan tab bawaan") { configuration.values.navigationTabs = IslandRoute.defaultTabs.map(\.rawValue) }
        }
    }
    private func setNavigationTab(_ route: IslandRoute, visible: Bool) {
        var tabs = configuration.values.featureTabs.filter { $0 != route }
        if visible {
            guard tabs.count < IslandRoute.maximumTabs else { return }
            tabs.append(route)
        }
        configuration.values.navigationTabs = tabs.map(\.rawValue)
    }
    private func moveNavigationTab(_ index: Int, by offset: Int) {
        var tabs = configuration.values.featureTabs
        guard tabs.indices.contains(index), tabs.indices.contains(index + offset) else { return }
        tabs.swapAt(index, index + offset)
        configuration.values.navigationTabs = tabs.map(\.rawValue)
    }
    private func refreshSettingsStatus() {
        refreshLogin()
        notifications.refreshAuthorization()
        snap.refreshAuthorization()
        calendar.refresh()
        Task { await refreshCalendarNotificationStatus() }
    }
    private func refreshCalendarNotificationStatus() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        calendarNotificationStatus = status
        if status == .denied { configuration.values.calendarSystemNotifications = false }
    }
    private func setCalendarNotifications(_ enabled: Bool) {
        if !enabled {
            configuration.values.calendarSystemNotifications = false
            return
        }
        guard !requestingCalendarNotifications else { return }
        requestingCalendarNotifications = true
        calendarNotificationError = false
        Task {
            defer { requestingCalendarNotifications = false }
            do {
                configuration.values.calendarSystemNotifications = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound])
            } catch {
                calendarNotificationError = true
            }
            await refreshCalendarNotificationStatus()
        }
    }
    private let widgetChoices = ["Calendar", "Music", "Timer", "Calculator", "Prayer", "Water", "Weather", "Battery", "Quick Notes", "Clipboard", "Keep Awake", "System", "Shelf", "Agenda", "Mixer", "To-do", "Launcher", "Downloads", "Quick Actions", "Camera & Mic"]
    private func themePreview(_ name: String, colors: [Color]) -> some View {
        Button { configuration.values.panelStyle = name } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 11)
                    .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                    .frame(height: 52)
                    .overlay {
                        if name == "Apple Glass" {
                            PanelGlassSurface(transparency: configuration.values.glassTransparency,
                                              shape: RoundedRectangle(cornerRadius: 9))
                                .padding(.horizontal, 8).padding(.vertical, 5)
                        }
                    }
                    .overlay(alignment: .top) { Capsule().fill(.black).frame(width: 60, height: 11) }
                Text(name).font(.system(size: 10)).lineLimit(1)
            }
            .padding(5)
            .background(configuration.values.panelStyle == name ? Color.accentColor.opacity(0.2) : .clear,
                        in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).frame(maxWidth: .infinity)
    }
    private func widgetSize(_ widget: String) -> String {
        if configuration.values.tallWidgets.contains(widget) { return "Tall" }
        if configuration.values.wideWidgets.contains(widget) { return "Wide" }
        return "Compact"
    }
    private func setWidgetSize(_ widget: String, size: String) {
        configuration.values.wideWidgets.removeAll { $0 == widget }
        configuration.values.tallWidgets.removeAll { $0 == widget }
        if size == "Wide" { configuration.values.wideWidgets.append(widget) }
        if size == "Tall" { configuration.values.tallWidgets.append(widget) }
    }
    private func setWidget(_ widget: String, visible: Bool) {
        var widgets = configuration.values.homeWidgets
        if visible && !widgets.contains(widget) { widgets.append(widget) }
        if !visible { widgets.removeAll { $0 == widget } }
        configuration.values.homeWidgets = widgets
    }
    private func moveWidget(_ widget: String, offset: Int) {
        var widgets = configuration.values.homeWidgets
        guard let index = widgets.firstIndex(of: widget), widgets.indices.contains(index + offset) else { return }
        widgets.swapAt(index, index + offset)
        configuration.values.homeWidgets = widgets
    }
    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        HStack {
            Text(title).frame(width: 135, alignment: .leading)
            Slider(value: value, in: range)
            Text(suffix == "s" ? String(format: "%.2f s", value.wrappedValue) : String(format: "%.0f pt", value.wrappedValue))
                .monospacedDigit().foregroundStyle(.secondary).frame(width: 58, alignment: .trailing)
        }
    }
    private func refreshLogin() {
        let status = SMAppService.mainApp.status
        loginEnabled = status == .enabled
        if status == .requiresApproval {
            loginMessage = "Approve Nubi in System Settings → General → Login Items."
        } else if loginMessage == "Approve Nubi in System Settings → General → Login Items." {
            loginMessage = nil
        }
    }
    private func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginMessage = nil
        } catch { loginMessage = error.localizedDescription }
        refreshLogin()
    }
    private func chooseNotificationApp() {
        let panel = NSOpenPanel()
        panel.message = "Choose an application to allow its visible notifications in Nubi"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, url.pathExtension.lowercased() == "app",
              let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else { return }
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        notifications.addApp(bundleID: identifier, name: name)
    }
    private func chooseExcludedApp() {
        guard let identifier = chooseApplicationID(message: "Pilih aplikasi yang menyembunyikan Nubi") else { return }
        if !configuration.values.excludedApps.contains(identifier) { configuration.values.excludedApps.append(identifier) }
    }
    private func chooseIgnoredClipboardApp() {
        guard let identifier = chooseApplicationID(message: "Pilih aplikasi yang salinannya diabaikan") else { return }
        clipboard.addIgnoredApp(identifier)
    }
    private func chooseApplicationID(message: String) -> String? {
        let panel = NSOpenPanel()
        panel.message = message
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, url.pathExtension.lowercased() == "app" else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }
    private func capturePermission(_ mediaType: AVMediaType) -> String {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized: "Granted"
        case .denied: "Denied · open System Settings"
        case .restricted: "Restricted"
        case .notDetermined: "Not requested"
        @unknown default: "Unavailable"
        }
    }
    private func openPrivacySettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
