import AppKit
import ApplicationServices
import SwiftUI
import UniformTypeIdentifiers

struct NotchView: View {
    @ObservedObject var state: NotchStateController
    @ObservedObject var configuration: NotchConfiguration
    @ObservedObject var music: MusicModel
    @ObservedObject var system: SystemInfoModel
    @ObservedObject var shelf: FileShelf
    @ObservedObject var focus: FocusTimerModel
    @ObservedObject var calendar: CalendarModel
    @ObservedObject var presentation: IslandPresentationModel
    @ObservedObject var clipboard: ClipboardHistoryModel
    @ObservedObject var downloads: DownloadManager
    @ObservedObject var notifications: NotificationBannerModel
    @ObservedObject var brightness: BrightnessModel
    @ObservedObject var mixer: SoundMixerModel
    @ObservedObject var launcher: LauncherModel
    @ObservedObject var developerWorkspace: DeveloperWorkspaceModel
    @ObservedObject var developerTerminal: DeveloperTerminalModel
    @ObservedObject var developerAgents: DeveloperAgentModel
    @ObservedObject var developerServices: DeveloperServiceModel
    @ObservedObject var todos: TodoModel
    @ObservedObject var weather: WeatherModel
    @ObservedObject var prayer: PrayerTimesModel
    @ObservedObject var water: WaterReminderModel
    @ObservedObject var quickNotes: QuickNoteModel
    @ObservedObject var keepAwake: KeepAwakeModel
    @ObservedObject var capturePreview: CapturePreviewModel
    @ObservedObject var ambient: IdleAnimationModel
    @ObservedObject var activity: ActivityCoordinator
    @ObservedObject var clock: IslandClockModel
    @ObservedObject var nobi: NobiBlinkModel
    @ObservedObject var dropZone: ShelfDropZoneState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isDropTarget = false
    @State private var calendarMonth = Date()
    @State private var selectedCalendarDay = Date()
    @State private var calendarMonthEvents: [CalendarEntry] = []
    var openSettings: (String?) -> Void
    var requestDownload: (URL?) -> Void
    var dropTargetChanged: (Bool) -> Void

    private let rose = Color(red: 1, green: 0.36, blue: 0.45)
    var body: some View {
        let shape = NotchShape(radius: configuration.values.cornerRadius, attachesToScreenEdge: state.attachesToScreenEdge)
        return ZStack(alignment: .top) {
            if state.isOpen && configuration.values.panelStyle == "Apple Glass" && !reduceTransparency {
                PanelGlassSurface(transparency: configuration.values.glassTransparency, shape: shape)
            } else {
                shape.fill(.black)
                if state.isOpen && configuration.values.panelStyle == "Accent Glow" && !reduceTransparency {
                    shape.fill(LinearGradient(colors: [.clear, .clear, configuration.accentColor.opacity(0.24)],
                                              startPoint: .top, endPoint: .bottom))
                }
            }
            GeometryReader { geometry in
                islandContent
                    .padding(.horizontal, shape.shoulderWidth(in: geometry.size))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(.white.opacity(isDropTarget ? 0.35 : 0.08), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .contentShape(shape)
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .spring(response: configuration.values.animationDuration, dampingFraction: 0.85),
                   value: state.interaction.phase)
        .dropDestination(for: URL.self) { urls, _ in
            guard shelf.add(urls) else { return false }
            if !state.isPinned { state.togglePin() }
            presentation.select(.shelf)
            return true
        } isTargeted: { isDropTarget = $0 }
        .onChange(of: isDropTarget) { _, targeted in dropTargetChanged(targeted) }
        .onChange(of: presentation.route, initial: true) { _, route in
            if route == .music { music.prepareLyrics() }
            if route == .calendar || route == .home { calendar.refresh() }
            if route == .calendar { loadCalendarMonth() }
            if route == .home { weather.refresh(); prayer.refresh() }
            if route == .prayer { prayer.refresh() }
            if route == .developer { developerWorkspace.refresh() }
            system.setStatsVisible(route == .system && state.isExpanded)
        }
        .onChange(of: state.interaction.phase) { _, _ in
            system.setStatsVisible(presentation.route == .system && state.isExpanded && !state.isHidden)
            if state.isOpen { clock.refresh() }
        }
        .onChange(of: music.title) { _, _ in
            if presentation.route == .music { music.prepareLyrics() }
        }
        .onChange(of: calendar.access) { _, _ in loadCalendarMonth() }
        .onChange(of: calendar.entries) { _, _ in
            if presentation.route == .calendar { loadCalendarMonth() }
        }
        .contextMenu {
            Button("New download…") { requestDownload(nil) }
            Button("Add files…", action: chooseFiles)
            Button(state.isPinned ? "Unpin" : "Pin open") { state.togglePin() }
            Button("Settings…") { openSettings(nil) }
            Button("Collapse") { state.dismiss() }
            if !shelf.files.isEmpty { Button("Clear file shelf") { shelf.clear() } }
            focusMenu
        }
    }

    @ViewBuilder private var islandContent: some View {
        if let transient = presentation.transient, !state.isPinned {
            transientView(transient)
        } else if state.isExpanded {
            expanded
        } else if isDropTarget || dropZone.fileDragNearTop {
            VStack(spacing: 7) {
                Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 23)).foregroundStyle(configuration.accentColor)
                Text("Drop files into Shelf").font(.system(size: 12, weight: .semibold))
                Text("Up to 8 local files").font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
            }.frame(maxWidth: .infinity, maxHeight: .infinity).foregroundStyle(.white)
        } else if state.isPeek {
            peek
        } else {
            collapsed
        }
    }

    private var collapsed: some View {
        Button { openLastRoute() } label: {
            Group {
                if music.isPlaying { nowPlayingPill }
                else { idlePill }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showsNobiOnly ? "Nobi, buka Nubi" : "Open Nubi")
        .accessibilityValue(pillAccessibilityValue)
        .help("Click to open Nubi")
    }

    private var nowPlayingPill: some View {
        VStack(spacing: 3) {
            HStack(spacing: 8) {
                PlayerArtwork(music: music, size: 27, cornerRadius: 7, tint: rose)
                VStack(alignment: .leading, spacing: 1) {
                    Text(music.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    Text(pillArtist).font(.system(size: 10)).foregroundStyle(.white.opacity(0.76)).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                pillActivities
                pillBadges
                PlaybackPillMotion(animated: configuration.values.animateMusic && !state.isHidden,
                                   accent: configuration.accentColor, waveformColor: rose)
                    .fixedSize()
            }
            if music.duration > 0 {
                TimelineView(.animation(minimumInterval: 1, paused: state.isHidden)) { context in
                    GeometryReader { geometry in
                        let progress = min(1, max(0, music.elapsed(at: context.date) / music.duration))
                        Capsule().fill(.white.opacity(0.2))
                            .overlay(alignment: .leading) {
                                Capsule().fill(rose).frame(width: geometry.size.width * progress)
                            }
                    }.frame(height: 2)
                }.accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
    }

    private var idlePill: some View {
        HStack(spacing: 8) {
            if showsNobiOnly {
                Spacer(minLength: 0)
                NobiFace(blinking: nobi.isBlinking || ambient.phase == .blinking)
                    .frame(width: 66, height: 27).accessibilityHidden(true)
                Spacer(minLength: 0)
            } else {
                if isQuietIdle {
                    NobiFace(blinking: nobi.isBlinking, tint: configuration.accentColor)
                        .frame(width: 42, height: 22).accessibilityHidden(true)
                }
                pillActivities
                if focus.phase == .idle && activePillDownload == nil {
                    if let session = activeDeveloperSession {
                        Image(systemName: "terminal").foregroundStyle(session.state == .working ? configuration.accentColor : .orange)
                        Text("\(session.provider.title) · \(developerStatusLabel(session))")
                            .lineLimit(1)
                    } else if let event = imminentEvent {
                        Image(systemName: "calendar.badge.clock").foregroundStyle(.cyan)
                        Text(event.title).lineLimit(1).frame(maxWidth: 145, alignment: .leading)
                        Text(event.start.formatted(.dateTime.hour().minute())).foregroundStyle(.white.opacity(0.55))
                    } else if let battery = activity.batteryPercent, battery <= 20 {
                        Image(systemName: "battery.25percent").foregroundStyle(.orange)
                        Text("Battery \(battery)%")
                    } else if ambient.phase == .preview { idlePreview }
                    else { idleSummary }
                }
                Spacer(minLength: 0)
                pillBadges
            }
        }
    }

    private var activePillDownload: DownloadItem? { downloads.items.first { $0.state == .running } }

    @ViewBuilder private var pillActivities: some View {
        if focus.phase != .idle || activePillDownload != nil {
            HStack(spacing: 7) {
                if focus.phase != .idle {
                    Label {
                        Text(focus.label).monospacedDigit()
                    } icon: {
                        Image(systemName: focus.phase == .finished ? "checkmark.circle.fill" : "timer").foregroundStyle(.orange)
                    }.labelStyle(PillActivityLabelStyle())
                }
                if let download = activePillDownload {
                    if focus.phase != .idle {
                        Rectangle().fill(.white.opacity(0.22)).frame(width: 1, height: 13)
                    }
                    Label {
                        Text("\(Int((download.progress * 100).rounded()))%")
                            .monospacedDigit().foregroundStyle(.white.opacity(0.8))
                    } icon: {
                        Image(systemName: "arrow.down.circle").foregroundStyle(.cyan)
                    }.labelStyle(PillActivityLabelStyle())
                }
            }.fixedSize(horizontal: true, vertical: false)
        }
    }

    @ViewBuilder private var pillBadges: some View {
        if music.isPlaying, let session = activeDeveloperSession {
            Image(systemName: "terminal").foregroundStyle(session.state == .working ? configuration.accentColor : .orange)
                .accessibilityLabel("\(session.provider.title), \(session.state.rawValue)")
        }
        if presentation.hasNotificationBadge { Circle().fill(rose).frame(width: 6, height: 6) }
        if configuration.values.showStatus { Circle().fill(configuration.accentColor).frame(width: 5, height: 5) }
    }

    private var pillArtist: String { music.artist.isEmpty ? music.source.rawValue : music.artist }

    private var pillAccessibilityValue: String {
        var values: [String] = []
        if music.isPlaying { values.append("Music: \(music.title), \(pillArtist)") }
        if focus.phase != .idle { values.append("Focus: \(focus.label)") }
        if let download = activePillDownload { values.append("Download: \(Int((download.progress * 100).rounded()))%") }
        if let session = activeDeveloperSession { values.append("\(session.provider.title): \(session.state.rawValue)") }
        return values.joined(separator: ". ")
    }

    private var imminentEvent: CalendarEntry? {
        guard let event = calendar.nextEvent, !event.isAllDay,
              event.start.timeIntervalSince(clock.now) > 0,
              event.start.timeIntervalSince(clock.now) <= 600 else { return nil }
        return event
    }
    private var isQuietIdle: Bool {
        !music.isPlaying && focus.phase == .idle
            && !downloads.items.contains(where: { $0.state == .running })
            && activeDeveloperSession == nil && imminentEvent == nil && (activity.batteryPercent ?? 100) > 20
    }
    private var activeDeveloperSession: DeveloperAgentSession? {
        developerAgents.sessions.first { $0.state == .waiting || $0.state == .failed }
            ?? developerAgents.sessions.first { $0.state == .working }
    }
    private func developerStatusLabel(_ session: DeveloperAgentSession) -> String {
        switch session.state {
        case .waiting: "Perlu perhatian"
        case .failed: "Gagal"
        case .working: "Bekerja"
        case .idle, .finished: "Selesai"
        }
    }
    private var showsNobiOnly: Bool { ambient.isNobiIdle && ambient.phase != .preview && isQuietIdle }

    private func openLastRoute() {
        clock.refresh()
        state.open()
        presentation.select(activeDeveloperSession.map { $0.state == .waiting || $0.state == .failed } == true
                            ? .developer : presentation.lastRoute)
    }

    private var peek: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Text(clock.text.header).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
                if configuration.values.showSystemInfo { systemIndicators }
                Button("Buka Home") { openRoute(.home) }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(configuration.accentColor)
            }
            peekPrimary
            HStack(spacing: 8) {
                if music.isPlaying && focus.phase != .idle && focus.phase != .finished {
                    peekSummary(.focus, title: focus.label, detail: "Timer")
                }
                if (music.isPlaying || (focus.phase != .idle && focus.phase != .finished)),
                   let event = calendar.nextEvent {
                    peekSummary(.calendar, title: event.title, detail: peekEventTime(event))
                } else if let weather = weather.snapshot {
                    peekSummary(.home, title: "\(weather.temperature)° · \(weather.description)",
                                detail: weather.place, symbol: weather.symbol)
                } else {
                    Button { openRoute(.more) } label: {
                        Label("Lihat semua fitur", systemImage: "square.grid.2x2")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 9).frame(minHeight: 32)
                    }.foregroundStyle(configuration.accentColor)
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 35).padding(.bottom, 10)
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    @ViewBuilder private var peekPrimary: some View {
        if music.isPlaying {
            HStack(spacing: 9) {
                if let artwork = music.artwork {
                    Image(nsImage: artwork).resizable().scaledToFill().frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                } else {
                    Image(systemName: "music.note").foregroundStyle(rose).frame(width: 36, height: 36)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(music.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(music.artist).font(.system(size: 11)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button { music.toggle() } label: { Image(systemName: "pause.fill").frame(width: 32, height: 32) }
                    .disabled(!music.controlsEnabled).accessibilityLabel("Jeda musik")
                peekDetail(.music)
            }.modifier(PeekCard())
        } else if focus.phase == .running || focus.phase == .paused {
            HStack(spacing: 9) {
                Image(systemName: "timer").foregroundStyle(.orange).frame(width: 36)
                Text(focus.label).font(.system(size: 17, weight: .semibold)).monospacedDigit()
                Spacer(minLength: 0)
                Button(focus.phase == .running ? "Jeda" : "Lanjut") {
                    if focus.phase == .running { focus.pause() } else { focus.resume() }
                }.frame(minHeight: 32)
                peekDetail(.focus)
            }.modifier(PeekCard())
        } else if let event = calendar.nextEvent {
            peekSummary(.calendar, title: event.title, detail: peekEventTime(event))
        } else {
            peekSummary(.calendar, title: "Agenda", detail: calendar.access == .fullAccess
                        ? "Belum ada acara mendatang" : "Hubungkan Kalender")
        }
    }

    private func peekSummary(_ route: IslandRoute, title: String, detail: String, symbol: String? = nil) -> some View {
        Button { openRoute(route) } label: {
            HStack(spacing: 9) {
                Image(systemName: symbol ?? route.symbol)
                    .foregroundStyle(configuration.accentColor).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(detail).font(.system(size: 10)).foregroundStyle(.white.opacity(0.76)).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(.white.opacity(0.7))
            }.modifier(PeekCard())
        }.accessibilityLabel("\(route.navigationTitle), \(title), \(detail)")
    }

    private func peekDetail(_ route: IslandRoute) -> some View {
        Button { openRoute(route) } label: {
            Image(systemName: "arrow.up.right").font(.system(size: 11)).frame(width: 32, height: 32)
        }.accessibilityLabel("Buka \(route.navigationTitle)")
    }

    private func peekEventTime(_ event: CalendarEntry) -> String {
        let day = event.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale(identifier: "id_ID")))
        return event.isAllDay ? "\(day) · Sepanjang hari" : "\(day) · \(event.start.formatted(.dateTime.hour().minute()))"
    }

    private func openRoute(_ route: IslandRoute) {
        state.open()
        presentation.select(route)
    }

    private var systemIndicators: some View {
        HStack(spacing: 8) {
            if let battery = system.batteryPercent {
                Label("\(battery)%", systemImage: system.batteryCharging == true ? "battery.100percent.bolt" : "battery.100percent")
                    .accessibilityLabel("Baterai \(battery) persen")
            }
            if let volume = system.volumePercent {
                Label(system.isMuted ? "Mute" : "\(volume)%", systemImage: system.isMuted ? "speaker.slash" : "speaker.wave.2")
                    .accessibilityLabel(system.isMuted ? "Suara dibisukan" : "Volume \(volume) persen")
            }
        }.font(.system(size: 10, weight: .medium)).monospacedDigit().foregroundStyle(.white.opacity(0.82))
    }

    private var idlePreview: some View {
        HStack(spacing: 7) {
            Image(systemName: previewSymbol).foregroundStyle(configuration.accentColor)
            Text(previewText).lineLimit(1).foregroundStyle(.white.opacity(0.9))
        }
        .font(.system(size: 11, weight: .semibold))
    }
    private var previewSymbol: String {
        if presentation.lastRoute == .calendar, calendar.nextEvent != nil { return "calendar" }
        if presentation.lastRoute == .clipboard, !clipboard.entries.isEmpty { return "doc.on.clipboard" }
        if presentation.lastRoute == .shelf, !shelf.files.isEmpty { return "tray" }
        if let snapshot = weather.snapshot { return snapshot.symbol }
        if calendar.nextEvent != nil { return "calendar" }
        return "calendar.circle"
    }
    private var previewText: String {
        if presentation.lastRoute == .calendar, let event = calendar.nextEvent { return "Next: \(event.title) · \(event.start.formatted(.dateTime.hour().minute()))" }
        if presentation.lastRoute == .clipboard, !clipboard.entries.isEmpty { return "\(clipboard.entries.count) recent copies" }
        if presentation.lastRoute == .shelf, !shelf.files.isEmpty { return "\(shelf.files.count) files on shelf" }
        if let snapshot = weather.snapshot { return "\(snapshot.place) · \(snapshot.temperature)° · \(snapshot.description)" }
        if let event = calendar.nextEvent { return "Next: \(event.title) · \(event.start.formatted(.dateTime.hour().minute()))" }
        return Date().formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private var idleSummary: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                Text("NUBI").tracking(1.4).fontWeight(.semibold)
                Rectangle().fill(.white.opacity(0.24)).frame(width: 1, height: 12)
                Text(clock.text.shortDate).foregroundStyle(.white.opacity(0.82))
                Spacer(minLength: 3)
                Text(clock.text.time).monospacedDigit().foregroundStyle(.white.opacity(0.65))
            }
            HStack(spacing: 7) {
                Image(systemName: "calendar").foregroundStyle(configuration.accentColor)
                Text(clock.now.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "id_ID"))))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer(minLength: 2)
                Text(clock.text.time).monospacedDigit().foregroundStyle(.white.opacity(0.65))
            }
            HStack(spacing: 5) {
                Image(systemName: "calendar").foregroundStyle(configuration.accentColor)
                Text(clock.now.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "id_ID"))))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .lineLimit(1)
        .accessibilityLabel("Tanggal dan waktu saat ini")
    }

    private var expanded: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button { state.togglePin() } label: {
                    HStack(spacing: 5) {
                        Text("NUBI").tracking(1.5)
                        Image(systemName: state.isPinned ? "pin.fill" : "pin")
                    }
                }.help(state.isPinned ? "Unpin" : "Pin open")
                Spacer(minLength: 0)
                Text(clock.text.header)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if presentation.route == .home && presentation.isEditingHome {
                    Button("Selesai") { presentation.finishHomeEditing() }
                        .foregroundStyle(.cyan)
                        .accessibilityLabel("Selesai mengatur Home")
                } else if presentation.hasNotificationBadge {
                    Button {
                        notifications.openLatest(); presentation.clearNotificationBadge()
                    } label: { Image(systemName: "bell.badge.fill").foregroundStyle(rose) }
                        .accessibilityLabel("Open latest notification")
                }
                if !presentation.isEditingHome {
                    if configuration.values.showSystemInfo { systemIndicators }
                    Button { openSettings(nil) } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                    Button { state.dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close panel")
                        .help("Close panel")
                }
            }
            .font(.system(size: 10, weight: .semibold))
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.78))
            Group {
                switch presentation.route {
                case .home: homeContent
                case .activities: activityContent
                case .music: musicContent
                case .focus: focusContent
                case .mixer: MixerPanel(mixer: mixer, capturePreview: capturePreview)
                case .launcher: LauncherPanel(launcher: launcher)
                case .developer: DeveloperHubPanel(
                    workspace: developerWorkspace, launcher: launcher, agents: developerAgents,
                    services: developerServices,
                    openTerminal: {
                        guard let project = developerWorkspace.selectedProject else { return }
                        developerTerminal.start(in: project)
                        presentation.select(.terminal)
                    },
                    openAgentTerminal: { session in
                        var isDirectory: ObjCBool = false
                        guard session.projectPath.hasPrefix("/"),
                              FileManager.default.fileExists(atPath: session.projectPath, isDirectory: &isDirectory),
                              isDirectory.boolValue else { return }
                        let url = URL(fileURLWithPath: session.projectPath, isDirectory: true)
                        developerWorkspace.add(url)
                        if let project = developerWorkspace.selectedProject {
                            developerTerminal.start(in: project)
                            presentation.select(.terminal)
                        }
                    }
                )
                case .terminal: DeveloperTerminalPanel(workspace: developerWorkspace, terminal: developerTerminal) {
                    presentation.select(.developer)
                }
                case .todos: TodoPanel(todos: todos)
                case .calculator: CalculatorPanel()
                case .more: moreContent
                case .calendar: calendarContent
                case .downloads: downloadContent
                case .clipboard: clipboardContent
                case .shelf: shelfContent
                case .prayer: prayerContent
                case .water: WaterPanel(water: water)
                case .notes: quickNoteContent
                case .battery: batteryContent
                case .system: systemContent
                case .actions: QuickActionsPanel(perform: performQuickAction)
                case .capture: captureContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Spacer(minLength: 0)
            bottomNavigation
        }
        .padding(.horizontal, 18)
        .padding(.top, 35)
        .padding(.bottom, 12)
    }

    private var bottomNavigation: some View {
        HStack(spacing: 5) {
            navigationButton(.home, showTitle: true)
            if !configuration.values.featureTabs.isEmpty {
                ViewThatFits(in: .horizontal) {
                    featureNavigationTabs
                    ScrollView(.horizontal) { featureNavigationTabs }.scrollIndicators(.hidden)
                }
            }
            Spacer(minLength: 0)
            navigationButton(.more, showTitle: true)
        }
        .padding(4)
        .background(.white.opacity(0.09), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Navigasi panel")
    }

    private var featureNavigationTabs: some View {
        HStack(spacing: 2) {
            ForEach(configuration.values.featureTabs) { route in
                navigationButton(route, showTitle: presentation.route == route)
            }
        }.fixedSize(horizontal: true, vertical: false)
    }

    private func navigationButton(_ route: IslandRoute, showTitle: Bool) -> some View {
        let selected = presentation.route == route
        return Button { presentation.select(route) } label: {
            HStack(spacing: 4) {
                Image(systemName: route == .more ? "square.grid.2x2" : route.symbol)
                if showTitle { Text(route.navigationTitle).lineLimit(1) }
            }
            .font(.system(size: 11, weight: selected ? .semibold : .medium))
            .foregroundStyle(selected ? .white : .white.opacity(0.76))
            .padding(.horizontal, showTitle ? 9 : 5)
            .frame(minWidth: 32, minHeight: 30)
            .background(selected ? .white.opacity(0.17) : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(route.navigationTitle)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .help(route.navigationTitle)
    }

    private var homeContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(presentation.isEditingHome ? "ATUR HOME" : "HOME")
                    .font(.system(size: 10, weight: .bold)).tracking(1.4)
                Spacer()
                if !presentation.isEditingHome {
                    Button("Customize") {
                        if !state.isPinned { state.togglePin() }
                        presentation.toggleHomeEditing()
                    }.font(.system(size: 10)).foregroundStyle(configuration.accentColor)
                    .buttonStyle(.plain)
                }
            }
            if presentation.isEditingHome { widgetPicker }
            ScrollView {
                if configuration.values.homeWidgets.isEmpty {
                    Text("Belum ada widget. Pilih dari daftar di atas.")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, minHeight: 100)
                } else { HomeCanvasLayout(spacing: 10) {
                    ForEach(configuration.values.homeWidgets, id: \.self) { widget in
                        homeWidgetTile(widget)
                            .layoutValue(key: HomeSpanKey.self,
                                         value: HomeSpan(columns: configuration.values.wideWidgets.contains(widget) ? 2 : 1,
                                                         rows: configuration.values.tallWidgets.contains(widget) ? 2 : 1))
                    }
                } }
            }
            if !presentation.isEditingHome { HStack(spacing: 8) {
                homeShortcut(.activities, detail: "Live")
                homeShortcut(.downloads, detail: "\(downloads.items.filter { $0.state == .running }.count) active")
                homeShortcut(.clipboard, detail: "\(clipboard.entries.count) saved")
                homeShortcut(.shelf, detail: "\(shelf.files.count) files")
            } }
        }
    }

    private let widgetCatalog = ["Calendar", "Music", "Timer", "Developer", "Calculator", "Prayer", "Water", "Weather", "Battery",
                                 "Quick Notes", "Clipboard", "Keep Awake", "System", "Shelf", "Agenda",
                                 "Mixer", "To-do", "Launcher", "Downloads", "Quick Actions", "Camera & Mic"]
    private func label(for widget: String) -> String {
        switch widget {
        case "Prayer": "Sholat"
        case "Water": "Minum"
        case "Weather": "Cuaca"
        case "Battery": "Baterai"
        default: widget
        }
    }
    private var widgetPicker: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("TAMBAH WIDGET").font(.system(size: 9, weight: .semibold)).tracking(1)
                .foregroundStyle(.white.opacity(0.72))
            WidgetChipsLayout(spacing: 5) {
                    ForEach(widgetCatalog, id: \.self) { widget in
                        let added = configuration.values.homeWidgets.contains(widget)
                        Button {
                            if added { configuration.values.homeWidgets.removeAll { $0 == widget } }
                            else { configuration.values.homeWidgets.append(widget) }
                        } label: {
                            Text((added ? "✓ " : "+ ") + label(for: widget))
                                .font(.system(size: 10, weight: .semibold)).lineLimit(1)
                                .padding(.horizontal, 9).frame(height: 25)
                                .foregroundStyle(.white.opacity(0.94))
                                .background(added ? configuration.accentColor.opacity(0.28) : .white.opacity(0.18), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(added ? "Hapus \(label(for: widget))" : "Tambah \(label(for: widget))")
                    }
                    Button("Reset") { resetHomeWidgets() }
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 9).frame(height: 25)
                        .background(.white.opacity(0.18), in: Capsule())
                        .buttonStyle(.plain)
            }
            Text("Pakai panah untuk mengurutkan. Ikon ukuran: Compact, Wide, Tall.")
                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.72))
        }
    }
    @ViewBuilder private func homeWidgetTile(_ widget: String) -> some View {
        if presentation.isEditingHome {
            homeWidget(widget)
                .overlay(alignment: .topTrailing) { editControls(widget).padding(7) }
                .overlay { RoundedRectangle(cornerRadius: 20).stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(.white.opacity(0.35)) }
                .accessibilityAction(named: Text("Move earlier")) { shiftWidget(widget, by: -1) }
                .accessibilityAction(named: Text("Move later")) { shiftWidget(widget, by: 1) }
        } else {
            homeWidget(widget)
                .overlay(alignment: .bottomLeading) {
                    if widget == "Timer" && configuration.values.tallWidgets.contains(widget) {
                        HStack(spacing: 7) {
                            Button(focus.phase == .idle ? "Mulai" : focus.phase == .running ? "Jeda" : "Lanjut") {
                                switch focus.phase {
                                case .idle, .finished: focus.setMode(.standard); focus.start(seconds: 25 * 60)
                                case .running: focus.pause()
                                case .paused: focus.resume()
                                }
                            }
                            Button("Reset") { focus.reset() }
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .buttonStyle(.bordered)
                        .padding(.leading, 12).padding(.bottom, 28)
                    }
                }
        }
    }
    private func editControls(_ widget: String) -> some View {
        let index = configuration.values.homeWidgets.firstIndex(of: widget) ?? 0
        return HStack(spacing: 4) {
            Button { shiftWidget(widget, by: -1) } label: { Image(systemName: "arrow.left") }
                .disabled(index == 0)
                .accessibilityLabel("Pindah \(label(for: widget)) ke kiri")
            Button { shiftWidget(widget, by: 1) } label: { Image(systemName: "arrow.right") }
                .disabled(index >= configuration.values.homeWidgets.count - 1)
                .accessibilityLabel("Pindah \(label(for: widget)) ke kanan")
            Button { cycleWidgetSize(widget) } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                .accessibilityLabel("Ubah ukuran \(label(for: widget)), saat ini \(sizeLabel(widget))")
                .help("Ukuran berikutnya: Compact → Wide → Tall")
            Button {
                configuration.values.homeWidgets.removeAll { $0 == widget }
            } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.white, .red) }
                .accessibilityLabel("Hapus \(label(for: widget)) dari Home")
        }
        .font(.system(size: 13, weight: .semibold)).buttonStyle(.plain)
        .padding(3).background(.black.opacity(0.75), in: Capsule())
    }
    private enum WidgetSize { case compact, wide, tall }
    private func sizeLabel(_ widget: String) -> String {
        if configuration.values.tallWidgets.contains(widget) { return "Tall" }
        if configuration.values.wideWidgets.contains(widget) { return "Wide" }
        return "Compact"
    }
    private func cycleWidgetSize(_ widget: String) {
        resizeWidget(widget, size: configuration.values.wideWidgets.contains(widget) ? .tall
                     : configuration.values.tallWidgets.contains(widget) ? .compact : .wide)
    }
    private func resizeWidget(_ widget: String, size: WidgetSize) {
        configuration.values.wideWidgets.removeAll { $0 == widget }
        configuration.values.tallWidgets.removeAll { $0 == widget }
        if size == .wide { configuration.values.wideWidgets.append(widget) }
        if size == .tall { configuration.values.tallWidgets.append(widget) }
    }
    private func shiftWidget(_ widget: String, by offset: Int) {
        var list = configuration.values.homeWidgets
        guard let index = list.firstIndex(of: widget), list.indices.contains(index + offset) else { return }
        list.swapAt(index, index + offset)
        configuration.values.homeWidgets = list
    }
    private func resetHomeWidgets() {
        configuration.values.homeWidgets = ["Calendar", "Music", "Timer"]
        configuration.values.wideWidgets = []
        configuration.values.tallWidgets = []
    }

    @ViewBuilder private func homeWidget(_ widget: String) -> some View {
        switch widget {
        case "Calendar":
            homeCard(route: .calendar, title: "Calendar", symbol: "calendar", tint: .cyan, contentAtTop: true) {
                homeCalendarDays
            }
        case "Music":
            homeCard(route: .music, title: "Music", symbol: "music.note", tint: rose) {
                    Text(music.isPlaying ? music.title : "Ready to play")
                        .font(.system(size: 15, weight: .bold)).lineLimit(2)
                    Text(music.isPlaying ? music.artist : "Apple Music · Spotify · YouTube")
                        .font(.system(size: 10)).lineLimit(2)
            }
        case "Timer":
            homeCard(route: .focus, title: "Timer", symbol: "timer", tint: .purple) {
                    Text(focus.phase == .idle ? "25:00" : focus.label)
                        .font(.system(size: 27, weight: .bold)).monospacedDigit().lineLimit(1)
                    Text(focus.phase == .idle ? "Ready to start" : focus.stageLabel)
                        .font(.system(size: 10)).lineLimit(1)
            }
        case "Mixer":
            homeCard(route: .mixer, title: "Mixer", symbol: "slider.horizontal.3", tint: .cyan) {
                Text(mixer.systemVolume.map { "\($0)%" } ?? "—").font(.system(size: 27, weight: .bold))
                Text("\(mixer.applications.count) audio apps").font(.system(size: 10))
            }
        case "To-do":
            homeCard(route: .todos, title: "To-do", symbol: "checklist", tint: .orange) {
                Text("\(todos.openCount)").font(.system(size: 27, weight: .bold))
                Text("tasks open").font(.system(size: 10))
            }
        case "Launcher":
            homeCard(route: .launcher, title: "Launcher", symbol: "square.grid.2x2", tint: .blue) {
                Text("\(launcher.apps.count)").font(.system(size: 27, weight: .bold))
                Text("applications").font(.system(size: 10))
            }
        case "Developer":
            homeCard(route: .developer, title: "Developer", symbol: "chevron.left.forwardslash.chevron.right", tint: configuration.accentColor) {
                Text(developerWorkspace.selectedProject?.name ?? "Belum ada proyek")
                    .font(.system(size: 15, weight: .bold)).lineLimit(2)
                Text(activeDeveloperSession.map { "\($0.provider.title) · \(developerStatusLabel($0))" } ?? "Proyek, Git, terminal")
                    .font(.system(size: 10)).lineLimit(2)
            }
        case "Calculator":
            homeCard(route: .calculator, title: "Calculator", symbol: "plus.forwardslash.minus", tint: .green) {
                Text("1 + 1").font(.system(size: 23, weight: .bold))
                Text("Quick calculations").font(.system(size: 10))
            }
        case "Downloads":
            homeCard(route: .downloads, title: "Downloads", symbol: "arrow.down.circle", tint: .cyan) {
                Text("\(downloads.items.filter { $0.state == .running }.count)").font(.system(size: 27, weight: .bold))
                Text("active downloads").font(.system(size: 10))
            }
        case "Agenda":
            homeCard(route: .calendar, title: "Agenda", symbol: "list.bullet.rectangle", tint: .cyan) {
                Text(calendar.entries.first?.title ?? "No upcoming events").font(.system(size: 14, weight: .bold)).lineLimit(2)
                Text(calendar.entries.first.map { $0.isAllDay ? "All day" : $0.start.formatted(.dateTime.weekday(.abbreviated).hour().minute()) } ?? "Connect Calendar")
                    .font(.system(size: 10)).lineLimit(1)
            }
        case "Clipboard":
            homeCard(route: .clipboard, title: "Clipboard", symbol: "doc.on.clipboard", tint: .purple) {
                Text("\(clipboard.entries.count)").font(.system(size: 27, weight: .bold))
                Text(clipboard.enabled ? "recent copies" : "Enable in Settings").font(.system(size: 10))
            }
        case "Shelf":
            homeCard(route: .shelf, title: "Shelf", symbol: "tray", tint: .orange) {
                Text("\(shelf.files.count)").font(.system(size: 27, weight: .bold))
                Text("files nearby").font(.system(size: 10))
            }
        case "System":
            homeCard(route: .system, title: "System", symbol: "desktopcomputer", tint: .green) {
                Text(system.volumePercent.map { "\($0)%" } ?? "—").font(.system(size: 27, weight: .bold))
                Text(system.batteryPercent.map { "Battery \($0)% · system volume" } ?? "system volume")
                    .font(.system(size: 10)).lineLimit(1)
            }
        case "Weather":
            homeCard(route: .home, title: "Weather", symbol: "cloud.sun", tint: .blue,
                     onTap: { openSettings("Home") }) {
                Text(weather.snapshot.map { "\($0.temperature)°" } ?? (weather.loading ? "…" : "—"))
                    .font(.system(size: 27, weight: .bold))
                Text(weather.snapshot.map { "\($0.place) · \($0.description)" } ?? weather.status)
                    .font(.system(size: 10)).lineLimit(2)
                Text("Open-Meteo").font(.system(size: 8)).foregroundStyle(.white.opacity(0.6))
            }
        case "Prayer":
            homeCard(route: .prayer, title: "Sholat", symbol: "moon.stars", tint: .yellow) {
                Text(prayer.nextPrayer.map { "\($0.name) \($0.displayTime)" } ?? (prayer.loading ? "Memuat…" : "Atur kota"))
                    .font(.system(size: 17, weight: .bold)).lineLimit(2)
                Text(prayer.nextPrayer.map { "\(max(0, Int($0.date.timeIntervalSince(prayer.now) / 60))) menit lagi · \(weather.resolvedLocation?.name ?? "")" }
                     ?? (weather.resolvedLocation == nil ? "Pilih kota di Home settings" : "Coba refresh jadwal"))
                    .font(.system(size: 10)).lineLimit(2)
                if let next = prayer.nextPrayer {
                    let previous = prayer.times.last(where: { $0.date < next.date })?.date
                        ?? Calendar.current.startOfDay(for: next.date)
                    ProgressView(value: min(1, max(0, prayer.now.timeIntervalSince(previous)
                            / max(1, next.date.timeIntervalSince(previous)))))
                        .tint(.cyan).accessibilityHidden(true)
                }
            }
        case "Water":
            homeCard(route: .water, title: "Minum", symbol: "drop.fill", tint: .blue) {
                Text("\(WaterAmount.liters(water.todayML)) / \(WaterAmount.liters(water.snapshot.goalML)) L")
                    .font(.system(size: 18, weight: .bold)).lineLimit(1)
                Text(water.goalReached ? "Target tercapai" : water.snapshot.enabled ? "Pengingat aktif" : "Pengingat belum aktif")
                    .font(.system(size: 10))
                ProgressView(value: water.progress).tint(.blue).accessibilityHidden(true)
            }
        case "Battery":
            homeCard(route: .battery, title: "Baterai", symbol: "battery.100percent", tint: .green) {
                Text(system.batteryPercent.map { "\($0)%" } ?? "N/A").font(.system(size: 27, weight: .bold))
                Text(system.batteryPercent == nil ? "No battery on this Mac" : "Mac battery")
                    .font(.system(size: 10)).lineLimit(2)
            }
        case "Quick Notes":
            homeCard(route: .notes, title: "Quick Notes", symbol: "note.text", tint: .orange) {
                Text(quickNotes.preview).font(.system(size: 14, weight: .semibold)).lineLimit(3)
                Text("Local note").font(.system(size: 10))
            }
        case "Keep Awake":
            homeCard(route: .home, title: "Keep Awake", symbol: keepAwake.active ? "sun.max.fill" : "moon.zzz", tint: .cyan,
                     onTap: { keepAwake.toggle() }) {
                Text(keepAwake.active ? "Aktif" : "Mati").font(.system(size: 22, weight: .bold))
                Text(keepAwake.status)
                    .font(.system(size: 10)).lineLimit(2)
            }
        case "Quick Actions":
            homeCard(route: .actions, title: "Quick Actions", symbol: "command", tint: .cyan) {
                Text("⌘K").font(.system(size: 24, weight: .bold))
                Text("Search commands").font(.system(size: 10))
            }
        case "Camera & Mic":
            homeCard(route: .capture, title: "Camera & Mic", symbol: "camera.fill", tint: .purple) {
                Text(capturePreview.cameraActive || capturePreview.microphoneActive ? "Active" : "Off")
                    .font(.system(size: 22, weight: .bold))
                Text("Preview only").font(.system(size: 10))
            }
        default: EmptyView()
        }
    }

    private var moreContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Semua fitur").font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("Atur tab") { openSettings("Navigasi") }
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(configuration.accentColor)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                    ForEach(IslandRoute.featureCatalog) { route in
                        Button { presentation.select(route) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Image(systemName: route.symbol).font(.system(size: 15))
                                    .foregroundStyle(configuration.accentColor)
                                Text(route.navigationTitle).font(.system(size: 11, weight: .medium)).lineLimit(2)
                            }.padding(9).frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }
            }
        }.buttonStyle(.plain)
    }

    private func homeCard<Content: View>(route: IslandRoute, title: String, symbol: String,
                                          tint: Color, contentAtTop: Bool = false, onTap: (() -> Void)? = nil,
                                          @ViewBuilder content: () -> Content) -> some View {
        Button {
            guard !presentation.isEditingHome else { return }
            if let onTap { onTap() } else { presentation.select(route) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title).font(.system(size: 11, weight: .semibold))
                    Spacer(minLength: 0)
                    Image(systemName: symbol).font(.system(size: 16, weight: .semibold))
                }
                if !contentAtTop { Spacer(minLength: 0) }
                content()
                if contentAtTop { Spacer(minLength: 0) }
                if route != .calendar {
                    Image(systemName: "arrow.up.right").font(.system(size: 9)).frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .foregroundStyle(.white)
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 150, maxHeight: .infinity, alignment: .topLeading)
            .background(LinearGradient(colors: [Color(white: 0.075), tint.opacity(0.18)],
                                       startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!presentation.isEditingHome)
        .accessibilityHidden(presentation.isEditingHome)
        .accessibilityLabel("Open \(title)")
    }

    private func homeShortcut(_ route: IslandRoute, detail: String) -> some View {
        Button { presentation.select(route) } label: {
            HStack(spacing: 5) {
                Image(systemName: route.symbol)
                VStack(alignment: .leading, spacing: 2) {
                    Text(route.rawValue).font(.system(size: 9, weight: .semibold)).lineLimit(1)
                    Text(detail).font(.system(size: 8)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
        }.buttonStyle(.plain)
    }

    private var homeCalendarDays: some View {
        let current = Calendar.current
        let days = CalendarMonthLayout.days(containing: clock.now, calendar: current)
        return VStack(alignment: .leading, spacing: 4) {
            Text(clock.now.formatted(.dateTime.month(.wide).locale(Locale(identifier: "id_ID"))))
                .font(.system(size: 10, weight: .semibold))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 1) {
                ForEach(days, id: \.self) { day in
                    let today = current.isDate(day, inSameDayAs: clock.now)
                    let inMonth = current.isDate(day, equalTo: clock.now, toGranularity: .month)
                    Text(day.formatted(.dateTime.day()))
                        .font(.system(size: 9, weight: today ? .bold : .medium)).monospacedDigit()
                        .foregroundStyle(.white.opacity(inMonth ? 1 : 0.65))
                        .frame(maxWidth: .infinity, minHeight: 12)
                        .background(today ? Color.cyan.opacity(0.4) : .clear, in: Capsule())
                }
            }.accessibilityHidden(true)
        }.frame(maxWidth: 240, alignment: .leading)
    }

    private var calendarContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("CALENDAR", systemImage: "calendar")
                    .font(.system(size: 10, weight: .bold)).tracking(1.2)
                Spacer()
                Button("Open Calendar") { calendar.openCalendar() }
                    .font(.system(size: 10)).foregroundStyle(.cyan)
            }
            if calendar.access == .notDetermined || calendar.access == .writeOnly {
                Text("See your next events without leaving Nubi")
                    .font(.system(size: 13, weight: .medium))
                Button(calendar.isRequesting ? "Requesting access…" : "Connect Calendar") { calendar.requestAccess() }
                    .disabled(calendar.isRequesting)
                    .buttonStyle(.borderedProminent).tint(.cyan)
            } else if calendar.access != .fullAccess {
                Text(calendar.statusText).font(.system(size: 12)).foregroundStyle(.white.opacity(0.58))
            } else {
                HStack(alignment: .top, spacing: 18) {
                    monthGrid.frame(maxWidth: .infinity, alignment: .topLeading)
                    Rectangle().fill(.white.opacity(0.12)).frame(width: 1)
                    VStack(alignment: .leading, spacing: 12) {
                        Text(selectedCalendarDay.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(Locale(identifier: "id_ID"))))
                            .font(.system(size: 12, weight: .semibold))
                        calendarEventList(CalendarMonthLayout.events(on: selectedCalendarDay, from: calendarMonthEvents),
                                          empty: "Tidak ada acara pada tanggal ini")
                            .frame(maxHeight: .infinity, alignment: .top)
                        Divider()
                        Text("UPCOMING · 7 HARI").font(.system(size: 10, weight: .bold)).tracking(0.8)
                            .foregroundStyle(.white.opacity(0.58))
                        calendarEventList(calendar.entries, empty: "Belum ada acara mendatang")
                            .frame(maxHeight: .infinity, alignment: .top)
                    }.frame(width: 245, alignment: .leading)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var monthGrid: some View {
        VStack(spacing: 9) {
            HStack {
                Text(calendarMonth.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "id_ID"))))
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button("Hari ini") { calendarMonth = .now; selectedCalendarDay = .now; loadCalendarMonth() }
                    .font(.system(size: 10)).foregroundStyle(.cyan)
                Button { shiftCalendarMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Bulan sebelumnya")
                Button { shiftCalendarMonth(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Bulan berikutnya")
            }
            let days = CalendarMonthLayout.days(containing: calendarMonth)
            let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<7, id: \.self) { offset in
                    Text(calendarWeekdaySymbols[(Calendar.current.firstWeekday - 1 + offset) % 7])
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                }
                ForEach(days, id: \.self) { day in
                    let selected = Calendar.current.isDate(day, inSameDayAs: selectedCalendarDay)
                    let inMonth = Calendar.current.isDate(day, equalTo: calendarMonth, toGranularity: .month)
                    let hasEvent = !CalendarMonthLayout.events(on: day, from: calendarMonthEvents).isEmpty
                    Button {
                        selectedCalendarDay = day
                        if !inMonth { calendarMonth = day; loadCalendarMonth() }
                    } label: {
                        VStack(spacing: 2) {
                            Text(day.formatted(.dateTime.day()))
                                .font(.system(size: 11, weight: selected ? .bold : .regular))
                            Circle().fill(hasEvent ? Color.cyan : .clear).frame(width: 3, height: 3)
                        }
                        .foregroundStyle(inMonth ? .white : .white.opacity(0.6))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(selected ? Color.cyan.opacity(0.3) : Calendar.current.isDateInToday(day) ? .white.opacity(0.12) : .clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                    }.accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                }
            }
        }
    }

    private func calendarEventList(_ events: [CalendarEntry], empty: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if events.isEmpty {
                    Text(empty).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                }
                ForEach(events) { event in
                    HStack(alignment: .top, spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).fill(.cyan).frame(width: 3)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.title).font(.system(size: 11, weight: .semibold)).lineLimit(2)
                            Text(event.isAllDay ? "Sepanjang hari" : event.start.formatted(.dateTime.hour().minute()))
                                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.55))
                        }
                        Spacer(minLength: 0)
                        if let url = event.joinURL {
                            Button("Join") { NSWorkspace.shared.open(url) }
                                .font(.system(size: 10, weight: .semibold)).foregroundStyle(.cyan)
                        }
                    }.padding(7).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func shiftCalendarMonth(_ offset: Int) {
        guard let date = Calendar.current.date(byAdding: .month, value: offset, to: calendarMonth) else { return }
        calendarMonth = date
        selectedCalendarDay = Calendar.current.dateInterval(of: .month, for: date)?.start ?? date
        loadCalendarMonth()
    }

    private func loadCalendarMonth() {
        calendarMonthEvents = calendar.events(inMonthContaining: calendarMonth)
    }

    private var calendarWeekdaySymbols: [String] {
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: "id_ID")
        return calendar.shortStandaloneWeekdaySymbols
    }

    private var prayerContent: some View {
        PrayerPanel(prayer: prayer, weather: weather, openSettings: { openSettings("Home") })
    }

    private var quickNoteContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("QUICK NOTES", systemImage: "note.text")
                    .font(.system(size: 10, weight: .bold)).tracking(1)
                Spacer()
                Text("Saved on this Mac").font(.system(size: 9)).foregroundStyle(.white.opacity(0.65))
            }
            TextEditor(text: $quickNotes.text)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Quick note")
            if let error = quickNotes.error { Text(error).font(.system(size: 10)).foregroundStyle(.orange) }
        }.onDisappear { quickNotes.save() }
    }

    private var activityContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LIVE ACTIVITIES").font(.system(size: 10, weight: .bold)).tracking(1.2).foregroundStyle(.white.opacity(0.6))
            if music.isPlaying {
                Button { presentation.select(.music) } label: {
                    Label("\(music.title) · \(music.artist)", systemImage: "waveform")
                        .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                }.foregroundStyle(rose)
            }
            if focus.phase != .idle {
                Button { presentation.select(.focus) } label: {
                    Label("Focus · \(focus.label)", systemImage: "timer")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.foregroundStyle(.orange)
            }
            ForEach(downloads.items.filter { $0.state == .running }.prefix(2)) { item in
                Button { presentation.select(.downloads) } label: {
                    HStack {
                        Label(item.name, systemImage: "arrow.down.circle").lineLimit(1)
                        Spacer()
                        Text("\(Int((item.progress * 100).rounded()))%").monospacedDigit()
                    }
                }.foregroundStyle(.cyan)
            }
            if !music.isPlaying && focus.phase == .idle && !downloads.items.contains(where: { $0.state == .running }) {
                Text("No active music, timer or download").foregroundStyle(.white.opacity(0.55))
            }
        }.font(.system(size: 11)).buttonStyle(.plain)
    }

    private var musicContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                PlayerArtwork(music: music, size: 70, cornerRadius: 14, tint: rose)
                VStack(alignment: .leading, spacing: 5) {
                    Text("MUSIC PLAYER").font(.system(size: 9, weight: .bold)).tracking(1.2)
                        .foregroundStyle(rose)
                    Text(music.title).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                    Text(music.artist).font(.system(size: 11)).foregroundStyle(.white.opacity(0.62)).lineLimit(1)
                    Text(music.connected ? music.message : (music.permissionMessage ?? music.browserMessage ?? music.message))
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.75)).lineLimit(2)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 10) {
                    Image(systemName: "waveform").font(.system(size: 18)).foregroundStyle(rose)
                    Button { music.toggleLyrics() } label: {
                        Label(music.showsLyrics ? "Less" : "Lyrics", systemImage: "text.quote")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.78))
                }
            }
            lyricSurface
                .frame(maxWidth: .infinity, minHeight: music.showsLyrics ? 160 : 72,
                       maxHeight: music.showsLyrics ? 160 : 72)
                .background(LinearGradient(colors: [rose.opacity(0.08), configuration.accentColor.opacity(0.19)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 14))
            TimelineView(.animation(minimumInterval: 1, paused: !music.isPlaying)) { context in
                let elapsed = music.elapsed(at: context.date)
                HStack(spacing: 8) {
                    Text(time(elapsed))
                    ProgressView(value: elapsed, total: max(1, music.duration))
                        .tint(rose).accessibilityLabel("Playback progress")
                    Text("-" + time(max(0, music.duration - elapsed)))
                }
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.64))
            }
            HStack {
                Text(music.source.rawValue).font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                Spacer()
                HStack(spacing: 26) {
                    Button { music.skip(-1) } label: { Image(systemName: "backward.end.fill") }
                        .accessibilityLabel("Previous track")
                    Button { music.toggle() } label: {
                        Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18))
                    }.accessibilityLabel(music.isPlaying ? "Pause" : "Play")
                    Button { music.skip(1) } label: { Image(systemName: "forward.end.fill") }
                        .accessibilityLabel("Next track")
                }
                .buttonStyle(.plain).foregroundStyle(.white).disabled(!music.controlsEnabled)
                Spacer()
                if configuration.values.showSystemInfo, let volume = system.volumePercent {
                    Label(system.isMuted ? "Muted" : "\(volume)%", systemImage: system.isMuted ? "speaker.slash" : "speaker.wave.2")
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                }
            }
        }
    }

    @ViewBuilder private var lyricSurface: some View {
        if music.lyrics.isEmpty {
            HStack(spacing: 9) {
                Image(systemName: "text.quote").foregroundStyle(rose)
                Text(music.lyricsMessage).font(.system(size: 11)).foregroundStyle(.white.opacity(0.62))
                Spacer(minLength: 0)
            }.padding(13)
        } else if music.showsLyrics {
            ScrollViewReader { reader in
                ScrollView {
                    TimelineView(.animation(minimumInterval: 1, paused: !music.isPlaying)) { context in
                        let current = music.elapsed(at: context.date)
                        let active = music.lyrics.lastIndex { ($0.time ?? .infinity) <= current }
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(music.lyrics.indices, id: \.self) { index in
                                Text(music.lyrics[index].text)
                                    .font(.system(size: 12, weight: active == index ? .semibold : .regular))
                                    .foregroundStyle(active == index ? .white : .white.opacity(0.55))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                            }
                        }
                        .padding(13)
                        .onAppear { if let active { reader.scrollTo(active, anchor: .center) } }
                        .onChange(of: active) { _, next in
                            if let next {
                                if reduceMotion { reader.scrollTo(next, anchor: .center) }
                                else { withAnimation(.easeInOut(duration: 0.3)) { reader.scrollTo(next, anchor: .center) } }
                            }
                        }
                    }
                }
            }
        } else {
            TimelineView(.animation(minimumInterval: 1, paused: !music.isPlaying)) { context in
                let current = music.elapsed(at: context.date)
                let active = music.lyrics.lastIndex { ($0.time ?? .infinity) <= current }
                let index = active ?? 0
                VStack(alignment: .leading, spacing: 5) {
                    Text(music.lyrics[index].text)
                        .font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    if music.lyrics.indices.contains(index + 1) {
                        Text(music.lyrics[index + 1].text)
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
            }
        }
    }

    private var focusContent: some View {
        TimerPanel(timer: focus)
    }

    private var downloadContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("DOWNLOADS").font(.system(size: 10, weight: .bold)).tracking(1.2).foregroundStyle(.white.opacity(0.65))
                Spacer()
                Button { requestDownload(nil) } label: { Image(systemName: "plus.circle.fill") }
                    .accessibilityLabel("New download")
            }
            if downloads.items.isEmpty { Text("Start a download from an HTTPS URL").foregroundStyle(.white.opacity(0.55)) }
            ForEach(downloads.items.prefix(2)) { item in
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle").foregroundStyle(.cyan)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name).lineLimit(1)
                        if item.state == .running { ProgressView(value: item.progress).tint(.cyan) }
                        else if case .failed(let message) = item.state { Text(message).lineLimit(1).foregroundStyle(.orange) }
                        else { Text(item.state == .completed ? "Complete" : "Cancelled").foregroundStyle(.white.opacity(0.55)) }
                    }
                    if item.state == .running {
                        Button { downloads.cancel(item.id) } label: { Image(systemName: "xmark.circle") }.accessibilityLabel("Cancel download")
                    } else if item.state == .completed {
                        Button { NSWorkspace.shared.activateFileViewerSelecting([item.destination]) } label: { Image(systemName: "folder") }
                            .accessibilityLabel("Show in Finder")
                    } else {
                        Button { requestDownload(item.url) } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Retry download")
                    }
                }
            }
        }.font(.system(size: 11)).buttonStyle(.plain)
    }

    private var clipboardContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CLIPBOARD").font(.system(size: 10, weight: .bold)).tracking(1.2)
                Spacer()
                if !clipboard.entries.isEmpty { Button("Clear") { clipboard.clear() } }
            }.foregroundStyle(.white.opacity(0.7))
            if clipboard.enabled {
                TextField("Cari riwayat clipboard", text: $clipboard.searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
            }
            if !clipboard.enabled { Text("Enable clipboard history in Settings").foregroundStyle(.white.opacity(0.55)) }
            else if clipboard.entries.isEmpty { Text("Your next copies will appear here (up to 30)").foregroundStyle(.white.opacity(0.55)) }
            else if clipboard.visibleEntries.isEmpty { Text("Tidak ada hasil pencarian").foregroundStyle(.white.opacity(0.7)) }
            ScrollView {
            ForEach(Array(clipboard.visibleEntries.enumerated()), id: \.element.id) { pair in
                let entry = pair.element
                HStack(spacing: 8) {
                    if pair.offset < 9 { Text("\(pair.offset + 1)").font(.system(size: 9, weight: .bold)).frame(width: 14).foregroundStyle(.white.opacity(0.65)) }
                    if entry.kind == .color { Circle().fill(swatch(entry.value)).frame(width: 15, height: 15) }
                    else { Image(systemName: entry.kind == .link ? "link" : "text.alignleft").frame(width: 15) }
                    Text(entry.value).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    Button { clipboard.setPinned(entry, to: !entry.isPinned) } label: {
                        Image(systemName: entry.isPinned ? "pin.fill" : "pin")
                    }.accessibilityLabel(entry.isPinned ? "Lepas pin" : "Pin item")
                    if entry.kind == .link, let url = URL(string: entry.value) {
                        Button("Buka") { NSWorkspace.shared.open(url) }
                    }
                    Button(AXIsProcessTrusted() ? "Tempel" : "Salin") {
                        if AXIsProcessTrusted() { _ = clipboard.paste(entry) }
                        else { clipboard.copy(entry) }
                    }.foregroundStyle(.cyan)
                }.font(.system(size: 11)).padding(7).background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
            }
            }
            if let error = clipboard.storageError { Text(error).font(.system(size: 10)).foregroundStyle(.orange) }
        }.font(.system(size: 11)).buttonStyle(.plain)
    }

    private var shelfContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("FILE SHELF").font(.system(size: 10, weight: .bold)).tracking(1.2)
                Spacer()
                Button { shelf.captureScreenshot() } label: { Image(systemName: "camera.viewfinder") }
                    .accessibilityLabel("Capture screenshot")
                Button { shelf.createZIP() } label: { Image(systemName: "archivebox") }
                    .disabled(shelf.files.isEmpty).accessibilityLabel("Create ZIP")
                Button { chooseFiles() } label: { Image(systemName: "plus.circle.fill") }.accessibilityLabel("Add files to shelf")
            }
            Text(shelf.files.isEmpty ? "Drop files here to keep them nearby" : "\(shelf.files.count) files on shelf")
                .foregroundStyle(.white.opacity(0.55))
            if !shelf.files.isEmpty { TextField("Search file or recognized text", text: $shelf.searchQuery).textFieldStyle(.roundedBorder) }
            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(shelf.searchResults, id: \.self) { url in
                        HStack(spacing: 5) {
                            Button { shelf.reveal(url) } label: { Label(url.lastPathComponent, systemImage: "doc").lineLimit(1) }
                                .draggable(url)
                            if url.pathExtension.lowercased() == "zip" {
                                Button("Unzip") { shelf.openZIP(url) }.foregroundStyle(.cyan)
                            }
                            if shelf.processingOCR.contains(url) { ProgressView().controlSize(.mini) }
                            Button { shelf.remove(url) } label: { Image(systemName: "xmark") }
                                .accessibilityLabel("Remove \(url.lastPathComponent) from shelf")
                        }.padding(7).background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        if let text = shelf.recognizedText[url], !text.isEmpty {
                            Text(text).font(.system(size: 9)).foregroundStyle(.white.opacity(0.55)).lineLimit(2)
                        } else if shelf.recognizedText[url] != nil {
                            Text("No text recognized").font(.system(size: 9)).foregroundStyle(.white.opacity(0.55))
                        }
                    }
                }
            }
            if let error = shelf.error { Button(error + " ×") { shelf.error = nil }.foregroundStyle(.orange) }
            if let error = shelf.ocrError { Text(error).foregroundStyle(.orange) }
        }.font(.system(size: 11)).buttonStyle(.plain)
    }

    private var batteryContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("BATTERY", systemImage: "battery.100percent").font(.system(size: 11, weight: .bold))
            if let percent = system.batteryPercent {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(percent)%").font(.system(size: 38, weight: .bold)).monospacedDigit()
                    Text(system.batteries.first(where: { $0.name == "InternalBattery-0" || $0.name == "Mac battery" })?.charging == true ? "Charging" : "Mac battery")
                        .foregroundStyle(.white.opacity(0.55))
                }
                ProgressView(value: Double(percent), total: 100).tint(.green)
            } else { Text("Battery data unavailable on this Mac").foregroundStyle(.white.opacity(0.55)) }
            ForEach(system.batteries.filter { $0.percent != system.batteryPercent || system.batteryPercent == nil }) { source in
                HStack { Text(source.name); Spacer(); Text("\(source.percent)%") }
                    .font(.system(size: 11))
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var captureContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CAMERA & MICROPHONE").font(.system(size: 11, weight: .bold)).tracking(1.2)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    CameraPreviewView(session: capturePreview.cameraSession)
                        .frame(width: 270, height: 180)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Button(capturePreview.cameraActive ? "Stop camera" : "Start camera") {
                        if capturePreview.cameraActive { capturePreview.stopCamera() }
                        else { Task { await capturePreview.startCamera() } }
                    }
                    Text(capturePreview.cameraStatus).font(.system(size: 9)).foregroundStyle(.white.opacity(0.6))
                }
                VStack(alignment: .leading, spacing: 10) {
                    Label("Microphone", systemImage: "mic.fill")
                    ProgressView(value: Double(capturePreview.microphoneLevel)).tint(.cyan)
                    Button(capturePreview.microphoneActive ? "Stop microphone" : "Show input level") {
                        if capturePreview.microphoneActive { capturePreview.stopMicrophone() }
                        else { Task { await capturePreview.startMicrophone() } }
                    }
                    Text(capturePreview.microphoneStatus).font(.system(size: 9)).foregroundStyle(.white.opacity(0.6))
                }
            }
        }.font(.system(size: 11)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var systemContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("SYSTEM", systemImage: "desktopcomputer").font(.system(size: 11, weight: .bold))
            if let stats = system.stats {
                HStack(spacing: 16) {
                    statCard("CPU", value: "\(stats.cpuPercent)%", detail: String(format: "Load %.2f", stats.loadAverage), color: .cyan)
                    statCard("MEMORY", value: "\(stats.memoryPercent)%", detail: String(format: "%.1f / %.1f GB", stats.memoryUsedGB, stats.memoryTotalGB), color: .green)
                }
            } else { Text("Loading system stats…").foregroundStyle(.white.opacity(0.55)) }
            HStack {
                Label(system.volumePercent.map { "Volume \($0)%" } ?? "Volume unavailable", systemImage: "speaker.wave.2")
                Spacer()
                Label(system.batteryPercent.map { "Battery \($0)%" } ?? "No battery", systemImage: "battery.100percent")
            }.font(.system(size: 10)).foregroundStyle(.white.opacity(0.65))
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func performQuickAction(_ action: QuickActionID) {
        let routes: [QuickActionID: IslandRoute] = [
            .home: .home, .music: .music, .timer: .focus, .calendar: .calendar,
            .clipboard: .clipboard, .shelf: .shelf, .launcher: .launcher,
            .todos: .todos, .calculator: .calculator, .battery: .battery, .system: .system
        ]
        if let route = routes[action] { presentation.select(route) }
        else if action == .screenshot { shelf.captureScreenshot() }
        else {
            let zones: [QuickActionID: SnapZone] = [
                .snapLeft: .left, .snapRight: .right, .snapTopLeft: .topLeft,
                .snapTopRight: .topRight, .snapBottomLeft: .bottomLeft,
                .snapBottomRight: .bottomRight, .snapFull: .full
            ]
            if let zone = zones[action] { WindowSnapController.shared.snap(zone) }
        }
    }

    private func statCard(_ title: String, value: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 9, weight: .bold)).tracking(1.2).foregroundStyle(color)
            Text(value).font(.system(size: 25, weight: .bold)).monospacedDigit()
            Text(detail).font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private func transientView(_ transient: IslandTransient) -> some View {
        switch transient {
        case .notification:
            if let card = notifications.latest {
                Button { notifications.openLatest() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "bell.fill").foregroundStyle(rose)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(card.app.name + " · " + card.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                            Text(card.body).font(.system(size: 10)).foregroundStyle(.white.opacity(0.72)).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right").font(.system(size: 10))
                    }.padding(.horizontal, 17).padding(.top, 34)
                }.buttonStyle(.plain)
            }
        case .calendar(let title):
            transientAction(title, symbol: "calendar.badge.clock", tint: .cyan, route: .calendar)
        case .timer(let title):
            transientAction(title, symbol: "timer", tint: .orange, route: .focus)
        case .download(let title):
            transientAction(title, symbol: "arrow.down.circle", tint: .cyan, route: .downloads)
        case .battery(let percent):
            transientAction("Battery rendah · \(percent)%", symbol: "battery.25percent", tint: .orange, route: .battery)
        case .prayer(let name, let time, let due, let progress):
            Button { state.open(); presentation.select(.prayer) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 11) {
                        Image(systemName: "moon.fill").font(.system(size: 18)).foregroundStyle(.white)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name).font(.system(size: 15, weight: .bold))
                            Text(due ? "Saatnya sholat" : "Waktu sholat segera tiba")
                                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.58))
                        }
                        Spacer()
                        Text(time).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    }
                    ProgressView(value: progress).tint(.indigo)
                }.padding(.horizontal, 18).padding(.top, 32)
            }.buttonStyle(.plain)
        case .water:
            Button { openRoute(.water) } label: {
                HStack(spacing: 12) {
                    ThirstyNobi()
                    Text("Waktunya minum air").font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(maxHeight: .infinity)
                .padding(.top, 26)
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityHint("Buka panel Minum")
        case .volume(let value, let muted): volumeHUD(value: value, muted: muted)
        case .brightness(let value):
            Button { openLastRoute() } label: { hud(symbol: "sun.max", value: value, tint: .yellow) }
                .buttonStyle(.plain)
        case .microphoneMute(let muted):
            Button { state.open(); presentation.select(.mixer) } label: {
                simpleHUD(muted ? "Mikrofon dibisukan" : "Mikrofon aktif",
                          symbol: muted ? "mic.slash.fill" : "mic.fill", tint: .cyan)
            }.buttonStyle(.plain)
        case .batteryPower(let percent, let charging):
            Button { state.open(); presentation.select(.battery) } label: {
                simpleHUD(charging ? "Mengisi daya · \(percent)%" : "Daya baterai · \(percent)%",
                          symbol: charging ? "battery.100percent.bolt" : "battery.100percent", tint: .green)
            }.buttonStyle(.plain)
        }
    }
    private func transientAction(_ title: String, symbol: String, tint: Color, route: IslandRoute) -> some View {
        Button { state.open(); presentation.select(route) } label: {
            HStack(spacing: 9) {
                Image(systemName: symbol).foregroundStyle(tint)
                Text(title).lineLimit(2).font(.system(size: 11, weight: .semibold))
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 10))
            }.padding(.horizontal, 18).padding(.top, 23)
        }.buttonStyle(.plain)
    }
    private func volumeHUD(value: Int, muted: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .foregroundStyle(.white).frame(width: 18)
            Slider(value: Binding(
                get: { Double(system.volumePercent ?? value) },
                set: { mixer.setSystemVolume(Int($0.rounded())) }
            ), in: 0...100)
                .tint(.white)
                .accessibilityLabel("System volume")
            Text(muted ? "Mute" : "\(system.volumePercent ?? value)")
                .monospacedDigit().frame(width: 35, alignment: .trailing)
            Button { openLastRoute() } label: { Image(systemName: "arrow.up.right") }
                .buttonStyle(.plain).accessibilityLabel("Open Nubi")
        }.font(.system(size: 11, weight: .semibold)).padding(.horizontal, 18).frame(maxHeight: .infinity)
    }
    private func hud(symbol: String, value: Int, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint).frame(width: 18)
            ProgressView(value: Double(value), total: 100).tint(tint)
            Text("\(value)").monospacedDigit().frame(width: 25, alignment: .trailing)
        }.font(.system(size: 11, weight: .semibold)).padding(.horizontal, 18).frame(maxHeight: .infinity)
    }
    private func simpleHUD(_ title: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint).frame(width: 20)
            Text(title).font(.system(size: 12, weight: .semibold))
            Spacer()
        }.padding(.horizontal, 18).frame(maxHeight: .infinity)
    }
    private var focusMenu: some View {
        Menu {
            ForEach([1, 2, 3, 5, 10, 25], id: \.self) { minutes in
                Button("Start \(minutes) minutes") { focus.setMode(.standard); focus.start(seconds: Double(minutes * 60)) }
            }
            if focus.phase != .idle { Button("Reset timer") { focus.reset() } }
        } label: { Label("Start", systemImage: "play.circle.fill") }
    }
    private func chooseFiles() {
        shelf.chooseFiles { if !state.isPinned { state.togglePin() }; presentation.select(.shelf) }
    }
    private func time(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
    private func swatch(_ hex: String) -> Color {
        let value = Int(hex.dropFirst(), radix: 16) ?? 0
        return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}

private struct HomeSpan: Equatable {
    let columns: Int
    let rows: Int
}

private struct HomeSpanKey: LayoutValueKey {
    static let defaultValue = HomeSpan(columns: 1, rows: 1)
}

private struct HomeCanvasLayout: Layout {
    let spacing: CGFloat
    private let rowHeight: CGFloat = 150
    private func placements(_ subviews: Subviews) -> [HomeLayout.Placement] {
        HomeLayout.placements(spans: subviews.map { view in
            let span = view[HomeSpanKey.self]
            return (span.columns, span.rows)
        })
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = placements(subviews).map { $0.row + $0.rows }.max() ?? 0
        return CGSize(width: proposal.width ?? 524,
                      height: CGFloat(rows) * rowHeight + CGFloat(max(0, rows - 1)) * spacing)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = max(0, (bounds.width - 2 * spacing) / 3)
        for (view, placement) in zip(subviews, placements(subviews)) {
            let x = bounds.minX + CGFloat(placement.column) * (width + spacing)
            let y = bounds.minY + CGFloat(placement.row) * (rowHeight + spacing)
            let cardWidth = CGFloat(placement.columns) * width + CGFloat(placement.columns - 1) * spacing
            let cardHeight = CGFloat(placement.rows) * rowHeight + CGFloat(placement.rows - 1) * spacing
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: cardWidth, height: cardHeight))
        }
    }
}

private struct WidgetChipsLayout: Layout {
    let spacing: CGFloat
    private func positions(_ subviews: Subviews, width: CGFloat) -> ([CGPoint], CGFloat) {
        var points: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (points, y + rowHeight)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 524
        return CGSize(width: width, height: positions(subviews, width: width).1)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let points = positions(subviews, width: bounds.width).0
        for (view, point) in zip(subviews, points) {
            view.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }
}

private struct PillActivityLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.icon; configuration.title }
    }
}

private struct PeekCard: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(.horizontal, 9).padding(.vertical, 5)
            .frame(minHeight: 40)
            .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct PanelGlassSurface<S: Shape>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let transparency: Double
    let shape: S

    var body: some View {
        if transparency == 0 || reduceTransparency {
            shape.fill(.black)
        } else {
            ZStack {
                if #available(macOS 26.0, *) {
                    shape.fill(.clear).glassEffect(.regular, in: shape)
                } else {
                    NativePanelMaterial().clipShape(shape)
                }
                shape.fill(.black.opacity(1 - transparency))
            }
        }
    }
}

private struct NativePanelMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

