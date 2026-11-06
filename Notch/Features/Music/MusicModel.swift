import AppKit
import Combine
import CoreServices

// Four-character codes are taken from the installed players' public scripting dictionaries.
enum MusicSource: String, CaseIterable, Identifiable, Sendable {
    case demo = "Demo", appleMusic = "Apple Music", spotify = "Spotify", youtube = "YouTube (Chrome)"
    var id: String { rawValue }
    var bundleID: String {
        switch self {
        case .demo: ""
        case .appleMusic: "com.apple.Music"
        case .spotify: "com.spotify.client"
        case .youtube: "com.google.Chrome"
        }
    }
}

struct PlaybackSnapshot: Sendable {
    var title: String
    var artist: String
    var duration: Double
    var position: Double
    var playing: Bool
    var artwork: Data?
    var artworkURL: URL? = nil
    var lyrics: String? = nil
}

func mediaCode(_ value: String) -> UInt32 {
    precondition(value.utf8.count == 4)
    return value.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
}

/// Serial background executor: no AppKit work or blocking Apple Events on the main actor.
protocol PlayerService: Sendable {
    func authorize(pid: Int32, source: MusicSource) async throws
    func playing(pid: Int32, source: MusicSource) async throws -> Bool
    func snapshot(pid: Int32, source: MusicSource) async throws -> PlaybackSnapshot
    func command(_ command: String, pid: Int32, source: MusicSource) async throws
}

extension PlayerService {
    func authorize(pid: Int32, source: MusicSource) async throws {}
    func playing(pid: Int32, source: MusicSource) async throws -> Bool {
        try await snapshot(pid: pid, source: source).playing
    }
}

actor PlayerBridge: PlayerService {
    private let youtube = YouTubeBridge()
    nonisolated func authorize(pid: Int32, source: MusicSource) async throws {
        // A system consent dialog may wait indefinitely. Keep it off the serial player executor.
        let status = await Task.detached(priority: .userInitiated) {
            let target = NSAppleEventDescriptor(processIdentifier: pid)
            return AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, true)
        }.value
        try Task.checkCancellation()
        guard status == noErr else { throw Failure.response(status) }
    }
    private var authorizedPIDs = Set<Int32>()
    private var cachedArtwork: (key: String, data: Data)?
    enum Failure: LocalizedError {
        case response(Int32)
        var errorDescription: String? {
            switch self {
            case .response(-1743): return "Automation access denied. Allow Nubi in System Settings → Privacy & Security → Automation, then reconnect."
            case .response(-1744): return "Waiting for Automation permission. Respond to the macOS permission dialog."
            case .response(-1712): return "The player did not respond. Try reconnecting."
            case .response(let code): return "Player unavailable (Apple Events error \(code)). Reconnect to retry."
            }
        }
    }
    private func send(pid: Int32, suite: String, command: String, object: NSAppleEventDescriptor? = nil) throws -> NSAppleEventDescriptor {
        if !authorizedPIDs.contains(pid) {
            let target = NSAppleEventDescriptor(processIdentifier: pid)
            let permission = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false)
            guard permission == noErr else { throw Failure.response(permission) }
            authorizedPIDs.insert(pid)
        }
        let event = NSAppleEventDescriptor(eventClass: mediaCode(suite), eventID: mediaCode(command),
                                          targetDescriptor: NSAppleEventDescriptor(processIdentifier: pid),
                                          returnID: -1, transactionID: 0)
        if let object { event.setParam(object, forKeyword: mediaCode("----")) }
        let reply: NSAppleEventDescriptor
        do { reply = try event.sendEvent(options: [.waitForReply, .canInteract], timeout: 3) }
        catch { authorizedPIDs.remove(pid); throw Failure.response(Int32((error as NSError).code)) }
        let code = reply.paramDescriptor(forKeyword: mediaCode("errn"))?.int32Value ?? 0
        guard code == 0 else {
            if code == -1743 { authorizedPIDs.remove(pid) }
            throw Failure.response(code)
        }
        return reply.paramDescriptor(forKeyword: mediaCode("----")) ?? .null()
    }
    private func property(_ name: String, of container: NSAppleEventDescriptor = .null()) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: mediaCode("prop")), forKeyword: mediaCode("want"))
        record.setDescriptor(NSAppleEventDescriptor(enumCode: mediaCode("prop")), forKeyword: mediaCode("form"))
        record.setDescriptor(NSAppleEventDescriptor(typeCode: mediaCode(name)), forKeyword: mediaCode("seld"))
        record.setDescriptor(container, forKeyword: mediaCode("from"))
        return record.coerce(toDescriptorType: mediaCode("obj "))!
    }
    func playing(pid: Int32, source: MusicSource) async throws -> Bool {
        try Task.checkCancellation()
        if source == .youtube {
            do { return try await youtube.playing() }
            catch YouTubeBrowserError.unavailable { return false }
        }
        return try send(pid: pid, suite: "core", command: "getd", object: property("pPlS")).enumCodeValue == mediaCode("kPSP")
    }
    func snapshot(pid: Int32, source: MusicSource) async throws -> PlaybackSnapshot {
        if source == .youtube { return try await youtube.snapshot() }
        func read(_ name: String, of object: NSAppleEventDescriptor = .null()) throws -> NSAppleEventDescriptor {
            try Task.checkCancellation()
            return try send(pid: pid, suite: "core", command: "getd", object: property(name, of: object))
        }
        let playing = try read("pPlS").enumCodeValue == mediaCode("kPSP")
        let track = property("pTrk")
        // Spotify may omit metadata for ads, podcasts, or while changing tracks.
        // Playback state is enough to keep controls connected.
        let title = (try? read("pnam", of: track).stringValue) ?? (playing ? "Now playing" : "No track selected")
        let artist = (try? read("pArt", of: track).stringValue) ?? source.rawValue
        let duration = (try? read("pDur", of: track).doubleValue) ?? 0
        let position = (try? read("pPos").doubleValue) ?? 0
        let artworkKey = "\(pid):\(title):\(artist):\(duration)"
        var art: Data? = cachedArtwork?.key == artworkKey ? cachedArtwork?.data : nil
        var artworkURL: URL?
        if source == .spotify, let address = try? read("aUrl", of: track).stringValue,
           let url = URL(string: address), url.scheme == "https", let host = url.host,
           host.hasSuffix(".scdn.co") || host.hasSuffix(".spotifycdn.com") { artworkURL = url }
        if source == .appleMusic && art == nil {
            let record = NSAppleEventDescriptor.record()
            record.setDescriptor(NSAppleEventDescriptor(typeCode: mediaCode("cArt")), forKeyword: mediaCode("want"))
            record.setDescriptor(NSAppleEventDescriptor(enumCode: mediaCode("indx")), forKeyword: mediaCode("form"))
            record.setDescriptor(NSAppleEventDescriptor(int32: 1), forKeyword: mediaCode("seld"))
            record.setDescriptor(track, forKeyword: mediaCode("from"))
            if let object = record.coerce(toDescriptorType: mediaCode("obj ")),
               let data = try? read("pRaw", of: object).data, data.count <= 8 * 1024 * 1024 {
                art = data
                cachedArtwork = (artworkKey, data)
            }
        }
        // Spotify desktop returns duration in milliseconds despite some sdef versions saying seconds.
        let lyrics = source == .appleMusic ? try? read("pLyr", of: track).stringValue : nil
        return PlaybackSnapshot(title: title, artist: artist, duration: max(0, duration / (source == .spotify ? 1000 : 1)),
                                position: max(0, position), playing: playing, artwork: art, artworkURL: artworkURL, lyrics: lyrics)
    }
    func command(_ command: String, pid: Int32, source: MusicSource) async throws {
        try Task.checkCancellation()
        if source == .youtube { try await youtube.command(command); return }
        _ = try send(pid: pid, suite: source == .appleMusic ? "hook" : "spfy", command: command)
    }
}

@MainActor
final class MusicModel: ObservableObject {
    @Published private(set) var automaticDetection = true
    @Published private(set) var source: MusicSource = .demo
    @Published private(set) var isPlaying = false
    @Published private(set) var title = "A little room to focus"
    @Published private(set) var artist = "Nubi · Demo track"
    @Published private(set) var duration: TimeInterval = 180
    @Published private(set) var artwork: NSImage?
    @Published private(set) var artworkURL: URL?
    @Published private(set) var message = "Preview only · no audio playback"
    @Published private(set) var isBusy = false
    @Published private(set) var connected = false
    @Published private(set) var permissionMessage: String?
    @Published private(set) var browserMessage: String?
    @Published private(set) var lyrics: [LyricLine] = []
    @Published private(set) var lyricsMessage = "Lyrics are not available for this track"
    @Published private(set) var lyricsCredit = ""
    @Published var showsLyrics = false
    @Published private(set) var onlineLyricsEnabled = true
    private var startedAt: Date?
    private var accumulated: TimeInterval = 0
    private var index = 0
    private var generation = 0
    private var visible = false
    private var refreshTask: Task<Void, Never>?
    private var commandInFlight = false
    private var stopped = false
    private let bridge: any PlayerService
    private let lyricsService: any LyricsService
    private var lyricsTask: Task<Void, Never>?
    private var lyricsKey: String?
    private var lyricsLookupKey: String?
    private let runningPID: (MusicSource) -> Int32?
    private let frontmostBundleID: () -> String?
    private let refreshInterval: Duration
    private let detectionInterval: Duration
    private let failureRetryInterval: TimeInterval
    private let collapsedMetadataInterval: Duration
    private var lastSnapshotAt: ContinuousClock.Instant?
    private var snapshotPID: Int32?
    private let defaults: UserDefaults?
    private var blockedSources = Set<MusicSource>()
    private var retryAfter: [MusicSource: Date] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []
    private var detectionStarted = false
    private var permissionTasks: [MusicSource: Task<Void, Never>] = [:]
    var sessionLocked = false
    var hasLockScreenTrack: Bool { connected && source != .demo && (isPlaying || duration > 0) }
    init(bridge: any PlayerService = PlayerBridge(), lyricsService: any LyricsService = LRCLIBLyricsService(), refreshInterval: Duration = .seconds(5), detectionInterval: Duration = .seconds(2), collapsedMetadataInterval: Duration = .seconds(15), failureRetryInterval: TimeInterval = 15, defaults: UserDefaults? = nil, frontmostBundleID: @escaping () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }, runningPID: @escaping (MusicSource) -> Int32? = { source in
        NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleID).first?.processIdentifier
    }) {
        self.defaults = defaults
        self.automaticDetection = defaults?.object(forKey: "notch.music.automatic") as? Bool ?? true
        self.onlineLyricsEnabled = defaults?.object(forKey: "notch.music.onlineLyrics") as? Bool ?? true
        self.failureRetryInterval = max(0, failureRetryInterval)
        self.collapsedMetadataInterval = collapsedMetadataInterval
        self.detectionInterval = detectionInterval
        self.refreshInterval = refreshInterval
        self.bridge = bridge
        self.lyricsService = lyricsService
        self.runningPID = runningPID
        self.frontmostBundleID = frontmostBundleID
    }
    var controlsEnabled: Bool { !commandInFlight && ((!automaticDetection && source == .demo) || connected) }

    func elapsed(at date: Date) -> TimeInterval {
        let elapsed = max(0, accumulated + (startedAt.map { date.timeIntervalSince($0) } ?? 0))
        return source == .demo ? elapsed.truncatingRemainder(dividingBy: 180) : min(elapsed, duration)
    }
    func select(_ source: MusicSource) {
        setAutomatic(false)
        generation += 1
        refreshTask?.cancel()
        self.source = source
        connected = false; isBusy = false; commandInFlight = false; isPlaying = false
        startedAt = nil; accumulated = 0; artwork = nil; artworkURL = nil
        clearLyrics()
        title = source == .demo ? "A little room to focus" : "Connect \(source.rawValue)"
        artist = source == .demo ? "Nubi · Demo track" : "Open the player, then connect in Settings"
        duration = source == .demo ? 180 : 0
        message = source == .demo ? "Preview only · no audio playback" : "Not connected"
    }
    func connect() {
        if automaticDetection {
            blockedSources.removeAll(); retryAfter.removeAll()
            scanPlayers()
        } else { request() }
    }
    func startAutomaticDetection() {
        guard !detectionStarted else { return }
        detectionStarted = true
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      ["com.apple.Music", "com.spotify.client", "com.google.Chrome"].contains(app.bundleIdentifier ?? "") else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.automaticDetection else { return }
                    self.scanPlayers()
                }
            })
        }
        if automaticDetection { setAutomatic(true) }
    }
    func setAutomatic(_ enabled: Bool) {
        generation += 1; refreshTask?.cancel(); isBusy = false; commandInFlight = false
        cancelPermissionTasks()
        automaticDetection = enabled
        defaults?.set(enabled, forKey: "notch.music.automatic")
        blockedSources.removeAll(); retryAfter.removeAll()
        if enabled {
            connected = false; isPlaying = false; startedAt = nil
            clearLyrics()
            title = "Waiting for music"; artist = "Apple Music, Spotify or YouTube"
            message = "Checking running music players…"
            artwork = nil; artworkURL = nil; duration = 0; accumulated = 0
            scanPlayers()
        } else if connected { scheduleRefresh() }
    }
    func setVisible(_ visible: Bool) {
        self.visible = visible
        if automaticDetection {
            if visible { scanPlayers() }
            return
        }
        refreshTask?.cancel()
        if visible && connected { request() }
    }
    func stop() {
        stopped = true
        generation += 1; refreshTask?.cancel(); isBusy = false; commandInFlight = false
        lyricsTask?.cancel()
        cancelPermissionTasks()
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        workspaceObservers.removeAll(); detectionStarted = false
    }
    func toggle() {
        guard controlsEnabled else { return }
        if source != .demo { request(command: "PlPs"); return }
        if isPlaying { accumulated = elapsed(at: .now); startedAt = nil } else { startedAt = .now }
        isPlaying.toggle()
    }
    func setOnlineLyrics(_ enabled: Bool) {
        onlineLyricsEnabled = enabled
        defaults?.set(enabled, forKey: "notch.music.onlineLyrics")
        lyricsTask?.cancel(); lyricsTask = nil
        lyricsLookupKey = nil
        if enabled && (showsLyrics || visible) { requestOnlineLyrics() }
        else if !enabled && lyricsCredit == "Lyrics: LRCLIB" { lyrics = []; lyricsCredit = ""; lyricsMessage = "Online lyrics disabled" }
    }
    func prepareLyrics() { requestOnlineLyrics() }
    func toggleLyrics() {
        showsLyrics.toggle()
        if showsLyrics { lyricsLookupKey = nil; requestOnlineLyrics() }
    }
    func skip(_ offset: Int) {
        guard controlsEnabled else { return }
        if source != .demo { request(command: offset < 0 ? "Prev" : "Next"); return }
        let tracks = ["A little room to focus", "Above the everyday", "Quiet hours"]
        index = (index + offset + tracks.count) % tracks.count
        title = tracks[index]; accumulated = 0; startedAt = isPlaying ? .now : nil
    }
    private func request(command: String? = nil) {
        guard source != .demo, !commandInFlight, !stopped else { return }
        generation += 1 // A user command supersedes a background player scan.
        refreshTask?.cancel()
        isBusy = false
        guard let pid = runningPID(source) else {
            disconnected("Open \(source.rawValue), then reconnect in Settings."); scheduleRefresh(); return
        }
        let selected = source, token = generation
        commandInFlight = true
        isBusy = true
        refreshTask = Task { [weak self, bridge] in
            do {
                try Task.checkCancellation()
                if let command { try await bridge.command(command, pid: pid, source: selected) }
                try Task.checkCancellation()
                let snapshot = try await bridge.snapshot(pid: pid, source: selected)
                guard let self, self.generation == token else { return }
                self.apply(snapshot, source: selected, pid: pid)
                self.isBusy = false; self.commandInFlight = false
                self.scheduleRefresh()
            } catch {
                guard let self, self.generation == token else { return }
                self.isBusy = false; self.commandInFlight = false
                if error is CancellationError { self.scheduleRefresh() }
                else {
                    if case PlayerBridge.Failure.response(-1744) = error { self.requestPermission(selected, pid: pid) }
                    else if command != nil && self.connected { self.message = "Player response delayed. Checking playback again…" }
                    else { self.disconnected(error.localizedDescription) }
                    self.scheduleRefresh()
                }
            }
        }
    }
    private func apply(_ snapshot: PlaybackSnapshot, source: MusicSource, pid: Int32) {
        lastSnapshotAt = .now
        snapshotPID = pid
        self.source = source
        title = snapshot.title; artist = snapshot.artist
        duration = snapshot.duration.isFinite ? min(604800, max(0, snapshot.duration)) : 0
        accumulated = snapshot.position.isFinite ? min(duration, max(0, snapshot.position)) : 0
        startedAt = snapshot.playing ? .now : nil; isPlaying = snapshot.playing
        artwork = snapshot.artwork.flatMap(NSImage.init(data:)); artworkURL = snapshot.artworkURL
        connected = true; message = "\(automaticDetection ? "Auto-detected" : "Connected to") \(source.rawValue)"
        if source == .youtube { browserMessage = nil }
        updateLyrics(snapshot: snapshot, source: source)
    }
    private func clearLyrics() {
        lyricsTask?.cancel(); lyricsTask = nil; lyricsKey = nil
        lyricsLookupKey = nil
        lyrics = []; lyricsCredit = ""; lyricsMessage = "Lyrics are not available for this track"
    }
    private func updateLyrics(snapshot: PlaybackSnapshot, source: MusicSource) {
        let key = "\(source.rawValue):\(snapshot.title):\(snapshot.artist):\(Int(snapshot.duration))"
        guard lyricsKey != key else { return }
        clearLyrics()
        lyricsKey = key
        if let native = snapshot.lyrics?.trimmingCharacters(in: .whitespacesAndNewlines), !native.isEmpty {
            lyrics = native.components(separatedBy: .newlines).map { LyricLine(time: nil, text: $0) }
            lyricsCredit = "Lyrics: Apple Music"
            lyricsMessage = ""
        } else if showsLyrics { requestOnlineLyrics() }
    }
    private func requestOnlineLyrics() {
        guard lyrics.isEmpty, onlineLyricsEnabled, connected, source != .demo else { return }
        let key = "\(source.rawValue):\(title):\(artist):\(Int(duration))"
        guard lyricsKey == key, lyricsLookupKey != key else { return }
        lyricsLookupKey = key
        lyricsTask?.cancel()
        lyricsMessage = "Looking up lyrics…"
        let song = title, performer = artist, length = duration, service = lyricsService
        lyricsTask = Task { [weak self] in
            do {
                let result = try await service.lookup(title: song, artist: performer, duration: length)
                guard let self, self.lyricsKey == key, !Task.isCancelled else { return }
                self.lyrics = result?.lines ?? []
                self.lyricsCredit = result?.credit ?? ""
                self.lyricsMessage = result == nil ? "No lyrics found for this recording" : ""
            } catch {
                guard let self, self.lyricsKey == key, !Task.isCancelled else { return }
                self.lyricsMessage = "Lyrics lookup unavailable"
            }
        }
    }
    private func scanPlayers() {
        guard automaticDetection, !isBusy, !stopped else { return }
        refreshTask?.cancel()
        let foreground = MusicSource.allCases.first { $0 != .demo && $0.bundleID == frontmostBundleID() }
        let order = [foreground, source == .demo ? nil : source, .appleMusic, .spotify, .youtube]
            .compactMap { $0 }.reduce(into: [MusicSource]()) { result, player in
                if !result.contains(player) { result.append(player) }
            }
        let candidates = order.compactMap { player -> (MusicSource, Int32)? in
            guard !blockedSources.contains(player), permissionTasks[player] == nil, (retryAfter[player] ?? .distantPast) <= .now,
                  let pid = runningPID(player) else { return nil }
            return (player, pid)
        }
        guard !candidates.isEmpty else {
            disconnected(blockedSources.isEmpty ? "Waiting for Music, Spotify or YouTube to play" : "Allow Automation in System Settings, then click Retry detection.")
            title = "Waiting for music"; artist = "Apple Music, Spotify or YouTube"
            scheduleRefresh(); return
        }
        isBusy = true
        let token = generation
        refreshTask = Task { [weak self, bridge] in
            var available: [(MusicSource, Int32, Bool)] = []
            for (player, pid) in candidates {
                do {
                    try Task.checkCancellation()
                    let playing = try await bridge.playing(pid: pid, source: player)
                    guard let self, self.generation == token else { return }
                    if player == .youtube { self.browserMessage = nil }
                    available.append((player, pid, playing))
                    if playing && ((player == self.source && self.connected) ||
                                   (player == .youtube && self.frontmostBundleID() == player.bundleID)) {
                        break
                    }
                } catch {
                    guard let self, self.generation == token else { return }
                    if player == .youtube { self.browserMessage = error.localizedDescription }
                    if case PlayerBridge.Failure.response(-1744) = error { self.requestPermission(player, pid: pid) }
                    else if case PlayerBridge.Failure.response(-1743) = error { self.blockedSources.insert(player) }
                    else { self.retryAfter[player] = .now.addingTimeInterval(self.failureRetryInterval) }
                }
            }
            guard let self, self.generation == token else { return }
            let foregroundYouTube = self.frontmostBundleID() == MusicSource.youtube.bundleID
                ? available.first(where: { $0.0 == .youtube && $0.2 }) : nil
            let winner = foregroundYouTube ?? available.first(where: { $0.0 == self.source && $0.2 }) ?? available.first(where: { $0.2 }) ??
                available.first(where: { $0.0 == self.source }) ?? available.first
            if let (selected, pid, playing) = winner {
                do {
                    // Keep collapsed metadata fresh without reading artwork on every state probe.
                    let metadataDue = self.lastSnapshotAt.map { $0.duration(to: .now) >= self.collapsedMetadataInterval } ?? true
                    if selected != self.source || pid != self.snapshotPID || !self.connected || playing != self.isPlaying || self.visible || metadataDue {
                        let snapshot = try await bridge.snapshot(pid: pid, source: selected)
                        guard self.generation == token else { return }
                        self.apply(snapshot, source: selected, pid: pid)
                    }
                } catch {
                    guard self.generation == token else { return }
                    if case PlayerBridge.Failure.response(-1744) = error { self.requestPermission(selected, pid: pid) }
                    else if case PlayerBridge.Failure.response(-1743) = error { self.blockedSources.insert(selected) }
                    else { self.retryAfter[selected] = .now.addingTimeInterval(self.failureRetryInterval) }
                    self.disconnected(error.localizedDescription)
                }
            } else {
                self.disconnected(self.browserMessage ?? (self.blockedSources.isEmpty ? "Waiting for a player" : "Automation access required. Allow access and retry in Settings."))
                self.title = "Waiting for music"
            }
            self.isBusy = false
            self.scheduleRefresh()
        }
    }
    private func cancelPermissionTasks() {
        for task in permissionTasks.values { task.cancel() }
        permissionTasks.removeAll(); permissionMessage = nil
    }
    private func updatePermissionMessage() {
        let names = permissionTasks.keys.map(\.rawValue).sorted().joined(separator: ", ")
        permissionMessage = names.isEmpty ? nil : "Allow Nubi to access \(names) in the macOS permission dialog. Other connected players remain available."
    }
    private func requestPermission(_ player: MusicSource, pid: Int32) {
        guard !sessionLocked, permissionTasks[player] == nil else { return }
        let token = generation
        permissionTasks[player] = Task { [weak self, bridge] in
            var failure: Error?
            do { try await bridge.authorize(pid: pid, source: player) } catch { failure = error }
            guard let self, self.generation == token else { return }
            self.permissionTasks[player] = nil
            self.updatePermissionMessage()
            if let failure {
                self.blockedSources.insert(player)
                self.permissionMessage = "\(player.rawValue): \(failure.localizedDescription)"
            }
            if self.automaticDetection { self.scanPlayers() }
            else if failure == nil && self.source == player { self.request() }
        }
        updatePermissionMessage()
    }
    private func disconnected(_ message: String) {
        connected = false; isPlaying = false; startedAt = nil; accumulated = 0
        clearLyrics()
        title = "Player unavailable"; artist = source.rawValue; artwork = nil; artworkURL = nil; duration = 0
        self.message = message
    }
    private func scheduleRefresh() {
        guard !stopped else { return }
        if automaticDetection {
            guard [MusicSource.appleMusic, .spotify, .youtube].contains(where: { runningPID($0) != nil && !blockedSources.contains($0) && permissionTasks[$0] == nil }) else { return }
        } else { guard visible && connected else { return } }
        let interval = automaticDetection ? detectionInterval : refreshInterval
        refreshTask = Task { [weak self] in
            do { try await Task.sleep(for: interval) } catch { return }
            guard let self else { return }
            if self.automaticDetection { self.scanPlayers() } else { self.request() }
        }
    }
}
