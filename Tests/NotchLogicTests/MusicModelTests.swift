import XCTest
@testable import NotchMedia

private actor StubPlayer: PlayerService {
    var commands: [String] = []
    var reads = 0
    let fails: Bool
    let delay: Duration
    init(fails: Bool = false, delay: Duration = .zero) { self.fails = fails; self.delay = delay }
    func snapshot(pid: Int32, source: MusicSource) async throws -> PlaybackSnapshot {
        reads += 1
        if delay != .zero { try? await Task.sleep(for: delay) }
        if fails { throw PlayerBridge.Failure.response(-1743) }
        return PlaybackSnapshot(title: "Test song", artist: "Test artist", duration: 240,
                                position: 60, playing: true, artwork: nil)
    }
    func command(_ command: String, pid: Int32, source: MusicSource) async throws { commands.append(command) }
}

final class MusicModelTests: XCTestCase {
    @MainActor
    private func waitForIdle(_ model: MusicModel) async throws {
        for _ in 0..<100 {
            if !model.isBusy { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Music request did not finish")
    }
    @MainActor
    func testExplicitConnectionAndCommands() async throws {
        let bridge = StubPlayer()
        let model = MusicModel(bridge: bridge, runningPID: { $0 == .youtube ? nil : 42 })
        model.select(.appleMusic)
        XCTAssertFalse(model.connected)
        let initialReads = await bridge.reads
        XCTAssertEqual(initialReads, 0, "Selecting a provider must not request permission")
        model.connect()
        try await waitForIdle(model)
        XCTAssertTrue(model.connected)
        XCTAssertEqual(model.title, "Test song")
        XCTAssertEqual(model.duration, 240)
        XCTAssertTrue(model.isPlaying)
        XCTAssertGreaterThanOrEqual(model.elapsed(at: .now), 60)
        model.toggle()
        try await waitForIdle(model)
        model.skip(1)
        try await waitForIdle(model)
        let commands = await bridge.commands
        XCTAssertEqual(commands, ["PlPs", "Next"])
        model.stop()
    }
    @MainActor
    func testDeniedConnectionClearsPlaybackAndDisablesControls() async throws {
        let model = MusicModel(bridge: StubPlayer(fails: true), runningPID: { $0 == .youtube ? nil : 42 })
        model.select(.spotify)
        model.connect()
        try await waitForIdle(model)
        XCTAssertFalse(model.connected)
        XCTAssertFalse(model.controlsEnabled)
        XCTAssertFalse(model.isPlaying)
        XCTAssertTrue(model.message.contains("Automation access denied"))
        model.stop()
    }
    @MainActor
    func testAbsentPlayerDoesNotSendOrLaunch() async {
        let bridge = StubPlayer()
        let model = MusicModel(bridge: bridge, runningPID: { _ in nil })
        model.select(.appleMusic)
        model.connect()
        XCTAssertFalse(model.isBusy)
        XCTAssertFalse(model.connected)
        let reads = await bridge.reads
        XCTAssertEqual(reads, 0)
        XCTAssertTrue(model.message.contains("Open Apple Music"))
    }
    @MainActor
    func testOldResponseCannotOverwriteNewSource() async throws {
        let model = MusicModel(bridge: StubPlayer(delay: .milliseconds(80)), runningPID: { $0 == .youtube ? nil : 42 })
        model.select(.appleMusic)
        model.connect()
        try await Task.sleep(for: .milliseconds(10))
        model.select(.demo)
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(model.source, .demo)
        XCTAssertEqual(model.title, "A little room to focus")
        XCTAssertFalse(model.connected)
        XCTAssertFalse(model.isPlaying)
    }
    @MainActor
    func testDemoProgressNeverNegative() {
        let model = MusicModel()
        model.toggle()
        XCTAssertEqual(model.elapsed(at: .distantPast), 0)
        model.select(.spotify)
        XCTAssertEqual(model.elapsed(at: .now), 0)
    }
    @MainActor
    func testRefreshRunsOnlyWhileVisibleAndStopsOnShutdown() async throws {
        let bridge = StubPlayer()
        let model = MusicModel(bridge: bridge, refreshInterval: .milliseconds(20), runningPID: { $0 == .youtube ? nil : 42 })
        model.select(.appleMusic)
        model.connect()
        try await waitForIdle(model)
        try await Task.sleep(for: .milliseconds(70))
        let hiddenReads = await bridge.reads
        XCTAssertEqual(hiddenReads, 1)
        model.setVisible(true)
        try await Task.sleep(for: .milliseconds(90))
        let visibleReads = await bridge.reads
        XCTAssertGreaterThan(visibleReads, hiddenReads)
        model.stop()
        let stoppedReads = await bridge.reads
        try await Task.sleep(for: .milliseconds(70))
        let finalReads = await bridge.reads
        XCTAssertEqual(finalReads, stoppedReads)
    }
    func testDictionaryCodes() {
        XCTAssertEqual(mediaCode("pPlS"), 0x70506c53)
        XCTAssertEqual(mediaCode("----"), 0x2d2d2d2d)
    }

    func testYouTubeTabSelectionKeepsPausedVideoAndFollowsPlayingTab() {
        let other = YouTubeTabCandidate(url: "https://www.youtube.com/watch?v=other",
                                        snapshot: PlaybackSnapshot(title: "Other", artist: "YouTube", duration: 30,
                                                                   position: 0, playing: false, artwork: nil))
        let preferred = YouTubeTabCandidate(url: "https://www.youtube.com/watch?v=preferred",
                                            snapshot: PlaybackSnapshot(title: "Preferred", artist: "YouTube", duration: 30,
                                                                       position: 10, playing: false, artwork: nil))
        XCTAssertEqual(YouTubeTabSelection.choose([other, preferred], preferredURL: preferred.url)?.url, preferred.url)
        let playing = YouTubeTabCandidate(url: other.url,
                                          snapshot: PlaybackSnapshot(title: "Other", artist: "YouTube", duration: 30,
                                                                     position: 1, playing: true, artwork: nil))
        XCTAssertEqual(YouTubeTabSelection.choose([playing, preferred], preferredURL: preferred.url)?.url, playing.url)
    }
}

private actor AutoPlayer: PlayerService {
    var states: [MusicSource: Bool] = [.appleMusic: false, .spotify: true]
    var denied = Set<MusicSource>()
    var probes: [MusicSource: Int] = [:]
    var commands: [(String, MusicSource)] = []
    func setPlaying(_ value: Bool, source: MusicSource) { states[source] = value }
    func deny(_ source: MusicSource) { denied.insert(source) }
    func playing(pid: Int32, source: MusicSource) throws -> Bool {
        probes[source, default: 0] += 1
        if denied.contains(source) { throw PlayerBridge.Failure.response(-1743) }
        return states[source] ?? false
    }
    func snapshot(pid: Int32, source: MusicSource) -> PlaybackSnapshot {
        PlaybackSnapshot(title: "Song from \(source.rawValue)", artist: "Artist", duration: 200, position: 30,
                         playing: states[source] ?? false, artwork: nil)
    }
    func command(_ command: String, pid: Int32, source: MusicSource) { commands.append((command, source)) }
}

private actor SlowScanPlayer: PlayerService {
    var slow = false
    var commands: [String] = []
    func setSlow(_ value: Bool) { slow = value }
    func playing(pid: Int32, source: MusicSource) async throws -> Bool {
        if slow { try await Task.sleep(for: .milliseconds(160)) }
        return true
    }
    func snapshot(pid: Int32, source: MusicSource) -> PlaybackSnapshot {
        PlaybackSnapshot(title: "Song", artist: "Artist", duration: 180, position: 5, playing: true, artwork: nil)
    }
    func command(_ command: String, pid: Int32, source: MusicSource) { commands.append(command) }
}

extension MusicModelTests {
    @MainActor
    func testPausedYouTubeStaysSelectedAndCanResume() async throws {
        let bridge = AutoPlayer()
        await bridge.setPlaying(true, source: .youtube)
        await bridge.setPlaying(false, source: .spotify)
        let model = MusicModel(bridge: bridge, detectionInterval: .milliseconds(20),
                               frontmostBundleID: { "com.google.Chrome" },
                               runningPID: { $0 == .spotify ? nil : 42 })
        defer { model.stop() }
        model.setAutomatic(true)
        try await waitForIdle(model)
        XCTAssertEqual(model.source, .youtube)
        XCTAssertTrue(model.isPlaying)
        await bridge.setPlaying(false, source: .youtube)
        for _ in 0..<30 {
            if !model.isPlaying { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.source, .youtube)
        XCTAssertTrue(model.connected)
        XCTAssertTrue(model.controlsEnabled)
        model.toggle()
        try await waitForIdle(model)
        let commands = await bridge.commands
        XCTAssertTrue(commands.contains(where: { $0.0 == "PlPs" && $0.1 == .youtube }))
    }

    @MainActor
    func testPlaybackCommandInterruptsBackgroundScan() async throws {
        let bridge = SlowScanPlayer()
        let model = MusicModel(bridge: bridge, detectionInterval: .milliseconds(30),
                               runningPID: { $0 == .spotify ? 42 : nil })
        defer { model.stop() }
        model.setAutomatic(true)
        try await waitForIdle(model)
        XCTAssertTrue(model.connected)
        await bridge.setSlow(true)
        for _ in 0..<30 {
            if model.isBusy { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(model.isBusy, "The next automatic scan should be in progress")
        XCTAssertTrue(model.controlsEnabled, "A background scan must not disable playback controls")
        model.toggle()
        try await waitForIdle(model)
        let commands = await bridge.commands
        XCTAssertEqual(commands, ["PlPs"])
        XCTAssertTrue(model.connected)
    }
    @MainActor
    func testAutoSelectsPlayingAppAndSwitchesWhileCollapsed() async throws {
        let bridge = AutoPlayer()
        let model = MusicModel(bridge: bridge, detectionInterval: .milliseconds(20), runningPID: { $0 == .youtube ? nil : 42 })
        model.setAutomatic(true)
        try await waitForIdle(model)
        XCTAssertEqual(model.source, .spotify)
        XCTAssertTrue(model.isPlaying)
        await bridge.setPlaying(false, source: .spotify)
        await bridge.setPlaying(true, source: .appleMusic)
        try await Task.sleep(for: .milliseconds(90))
        XCTAssertEqual(model.source, .appleMusic)
        XCTAssertTrue(model.connected)
        // No command should be sent merely because playback was detected.
        let commands = await bridge.commands
        XCTAssertTrue(commands.isEmpty)
        model.stop()
    }
    @MainActor
    func testAutoKeepsCurrentPlayerWhenBothPlay() async throws {
        let bridge = AutoPlayer()
        let model = MusicModel(bridge: bridge, detectionInterval: .milliseconds(20),
                               frontmostBundleID: { "com.apple.Music" },
                               runningPID: { $0 == .youtube ? nil : 42 })
        model.setAutomatic(true)
        try await waitForIdle(model)
        XCTAssertEqual(model.source, .spotify)
        await bridge.setPlaying(true, source: .appleMusic)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(model.source, .spotify)
        model.stop()
    }
    @MainActor
    func testAutoDenialDoesNotBlockOtherPlayerOrRepeatedlyPrompt() async throws {
        let bridge = AutoPlayer()
        await bridge.deny(.appleMusic)
        let model = MusicModel(bridge: bridge, detectionInterval: .milliseconds(20), runningPID: { $0 == .youtube ? nil : 42 })
        model.setAutomatic(true)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.source, .spotify)
        XCTAssertTrue(model.connected)
        let probes = await bridge.probes
        XCTAssertEqual(probes[.appleMusic], 1)
        XCTAssertGreaterThan(probes[.spotify] ?? 0, 1)
        model.stop()
    }
    @MainActor
    func testAutomaticPreferenceSurvivesRestartAndNoPlayerSendsNoEvents() async throws {
        let suite = "notch.auto.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let bridge = AutoPlayer()
        let model = MusicModel(bridge: bridge, defaults: defaults, runningPID: { _ in nil })
        XCTAssertTrue(model.automaticDetection)
        model.setAutomatic(true)
        XCTAssertFalse(model.connected)
        XCTAssertFalse(model.controlsEnabled)
        let probes = await bridge.probes
        XCTAssertTrue(probes.isEmpty)
        model.setAutomatic(false)
        let reloaded = MusicModel(defaults: defaults, runningPID: { _ in nil })
        XCTAssertFalse(reloaded.automaticDetection)
        model.stop(); reloaded.stop()
    }
}

private actor LyricTestPlayer: PlayerService {
    let native: String?
    init(native: String?) { self.native = native }
    func snapshot(pid: Int32, source: MusicSource) -> PlaybackSnapshot {
        PlaybackSnapshot(title: "Test song", artist: "Test artist", duration: 120, position: 35,
                         playing: true, artwork: nil, lyrics: native)
    }
    func command(_ command: String, pid: Int32, source: MusicSource) {}
}

private actor LyricTestService: LyricsService {
    private(set) var calls = 0
    func lookup(title: String, artist: String, duration: TimeInterval) -> LyricsResult? {
        calls += 1
        return LyricsResult(lines: [LyricLine(time: 30, text: "Synchronized line")], credit: "Lyrics: LRCLIB")
    }
}

extension MusicModelTests {
    @MainActor
    func testNativeLyricsTakePriorityOverOnlineLookup() async throws {
        let service = LyricTestService()
        let model = MusicModel(bridge: LyricTestPlayer(native: "First line\nSecond line"),
                               lyricsService: service, runningPID: { $0 == .youtube ? nil : 42 })
        defer { model.stop() }
        model.select(.appleMusic)
        model.connect()
        try await waitForIdle(model)
        model.toggleLyrics()
        XCTAssertEqual(model.lyrics.map(\.text), ["First line", "Second line"])
        XCTAssertEqual(model.lyricsCredit, "Lyrics: Apple Music")
        let nativeCalls = await service.calls
        XCTAssertEqual(nativeCalls, 0)
    }

    @MainActor
    func testAutoDetectsYouTubeWhenItIsThePlayingSource() async throws {
        let model = MusicModel(bridge: LyricTestPlayer(native: nil), detectionInterval: .seconds(60),
                               runningPID: { $0 == .youtube ? 42 : nil })
        defer { model.stop() }
        model.setAutomatic(true)
        try await waitForIdle(model)
        XCTAssertTrue(model.connected)
        XCTAssertEqual(model.source, .youtube)
        XCTAssertTrue(model.isPlaying)
    }

    @MainActor
    func testForegroundYouTubeTakesOverWhileMusicAlsoPlays() async throws {
        let model = MusicModel(bridge: LyricTestPlayer(native: nil), detectionInterval: .seconds(60),
                               frontmostBundleID: { "com.google.Chrome" },
                               runningPID: { [.appleMusic, .youtube].contains($0) ? 42 : nil })
        defer { model.stop() }
        model.setAutomatic(true)
        try await waitForIdle(model)
        XCTAssertEqual(model.source, .youtube)
    }

    @MainActor
    func testOnlineLyricsLoadOnRequestAndHonorPreference() async throws {
        let service = LyricTestService()
        let model = MusicModel(bridge: LyricTestPlayer(native: nil), lyricsService: service,
                               runningPID: { $0 == .youtube ? nil : 42 })
        defer { model.stop() }
        model.select(.spotify)
        model.connect()
        try await waitForIdle(model)
        XCTAssertTrue(model.lyrics.isEmpty)
        model.setOnlineLyrics(false)
        model.toggleLyrics()
        let disabledCalls = await service.calls
        XCTAssertEqual(disabledCalls, 0)
        model.setOnlineLyrics(true)
        for _ in 0..<50 {
            if !model.lyrics.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.lyrics.first?.text, "Synchronized line")
        XCTAssertEqual(model.lyricsCredit, "Lyrics: LRCLIB")
        let enabledCalls = await service.calls
        XCTAssertEqual(enabledCalls, 1)
    }

    @MainActor
    func testMusicPreviewLoadsLyricsWithoutOpeningFullLyrics() async throws {
        let service = LyricTestService()
        let model = MusicModel(bridge: LyricTestPlayer(native: nil), lyricsService: service,
                               runningPID: { $0 == .appleMusic ? 42 : nil })
        defer { model.stop() }
        model.select(.appleMusic)
        model.connect()
        try await waitForIdle(model)
        model.prepareLyrics()
        for _ in 0..<50 {
            if !model.lyrics.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(model.showsLyrics)
        XCTAssertEqual(model.lyrics.first?.text, "Synchronized line")
        let calls = await service.calls
        XCTAssertEqual(calls, 1)
    }

    func testSynchronizedLyricsParseAndSort() {
        let lines = LRCLIBLyricsService.parseSynced("[00:35.50] Later\n[00:12.00] Earlier\n[invalid] ignored")
        XCTAssertEqual(lines.map(\.text), ["Earlier", "Later"])
        XCTAssertEqual(lines.map(\.time), [12, 35.5])
    }
}

private actor PermissionPlayer: PlayerService {
    private var authorized = false
    private var permission: CheckedContinuation<Void, any Error>?
    private var musicPlaying = true
    var authorizationCount = 0
    func playing(pid: Int32, source: MusicSource) throws -> Bool {
        if source == .spotify && !authorized { throw PlayerBridge.Failure.response(-1744) }
        return source == .spotify || musicPlaying
    }
    func snapshot(pid: Int32, source: MusicSource) -> PlaybackSnapshot {
        PlaybackSnapshot(title: source.rawValue, artist: "Test", duration: 120, position: 1,
                         playing: source == .spotify || musicPlaying, artwork: nil)
    }
    func command(_ command: String, pid: Int32, source: MusicSource) {}
    func authorize(pid: Int32, source: MusicSource) async throws {
        authorizationCount += 1
        try await withCheckedThrowingContinuation { permission = $0 }
    }
    func allow() { authorized = true; permission?.resume(); permission = nil }
    func pauseMusic() { musicPlaying = false }
}

extension MusicModelTests {
    @MainActor
    func testPermissionDialogDoesNotBlockOtherPlayer() async throws {
        let bridge = PermissionPlayer()
        let model = MusicModel(bridge: bridge, detectionInterval: .milliseconds(20), runningPID: { $0 == .youtube ? nil : 42 })
        model.setAutomatic(true)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(model.source, .appleMusic)
        XCTAssertTrue(model.connected)
        XCTAssertNotNil(model.permissionMessage)
        let count = await bridge.authorizationCount
        XCTAssertEqual(count, 1, "A pending dialog must not be opened repeatedly")
        await bridge.pauseMusic()
        await bridge.allow()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(model.source, .spotify)
        XCTAssertTrue(model.isPlaying)
        XCTAssertNil(model.permissionMessage)
        model.stop()
    }
    @MainActor
    func testLatePermissionResultCannotExitManualMode() async throws {
        let bridge = PermissionPlayer()
        let model = MusicModel(bridge: bridge, detectionInterval: .milliseconds(20), runningPID: { $0 == .youtube ? nil : 42 })
        model.setAutomatic(true)
        try await Task.sleep(for: .milliseconds(80))
        model.select(.demo)
        await bridge.allow()
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertFalse(model.automaticDetection)
        XCTAssertEqual(model.source, .demo)
        XCTAssertNil(model.permissionMessage)
        model.stop()
    }
}

private actor ChangingTrackPlayer: PlayerService {
    private var title = "First track"
    private(set) var snapshots = 0
    private(set) var probes = 0
    private(set) var commands = 0
    func changeTrack() { title = "Second track" }
    func playing(pid: Int32, source: MusicSource) -> Bool { probes += 1; return true }
    func snapshot(pid: Int32, source: MusicSource) -> PlaybackSnapshot {
        snapshots += 1
        return PlaybackSnapshot(title: title, artist: "Artist", duration: 240, position: 0, playing: true, artwork: nil)
    }
    func command(_ command: String, pid: Int32, source: MusicSource) { commands += 1 }
}

extension MusicModelTests {
    @MainActor
    func testCollapsedTrackChangesRefreshWithoutPlaybackCommands() async throws {
        let bridge = ChangingTrackPlayer()
        let model = MusicModel(bridge: bridge, detectionInterval: .milliseconds(10),
                               collapsedMetadataInterval: .milliseconds(120), runningPID: { $0 == .appleMusic ? 42 : nil })
        defer { model.stop() }
        model.setAutomatic(true)
        try await waitForIdle(model)
        XCTAssertEqual(model.title, "First track")
        await bridge.changeTrack()
        for _ in 0..<100 {
            if model.title == "Second track" { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.title, "Second track", "Metadata must update even when playing state stays unchanged")
        let snapshots = await bridge.snapshots
        let probes = await bridge.probes
        let commands = await bridge.commands
        XCTAssertGreaterThan(probes, snapshots, "Metadata reads must be less frequent than lightweight probes")
        XCTAssertEqual(commands, 0)
    }

    @MainActor
    func testRestartedPlayerRefreshesBeforeMetadataDeadline() async throws {
        let bridge = ChangingTrackPlayer()
        var pid: Int32 = 42
        let model = MusicModel(bridge: bridge, detectionInterval: .seconds(60),
                               collapsedMetadataInterval: .seconds(60), runningPID: { $0 == .appleMusic ? pid : nil })
        defer { model.stop() }
        model.setAutomatic(true)
        try await waitForIdle(model)
        await bridge.changeTrack()
        model.connect()
        try await waitForIdle(model)
        XCTAssertEqual(model.title, "First track", "Unchanged probes should not repeatedly fetch metadata")
        pid = 43
        model.connect()
        try await waitForIdle(model)
        XCTAssertEqual(model.title, "Second track", "A new process must not reuse the old player's metadata")
        let snapshots = await bridge.snapshots
        XCTAssertEqual(snapshots, 2)
    }
}

private actor FailingMetadataPlayer: PlayerService {
    var fails = true
    var musicReads = 0
    func recover() { fails = false }
    func playing(pid: Int32, source: MusicSource) -> Bool { true }
    func snapshot(pid: Int32, source: MusicSource) throws -> PlaybackSnapshot {
        if source == .appleMusic {
            musicReads += 1
            if fails { throw PlayerBridge.Failure.response(-1712) }
        }
        return PlaybackSnapshot(title: source.rawValue, artist: "Test", duration: 120, position: 0, playing: true, artwork: nil)
    }
    func command(_ command: String, pid: Int32, source: MusicSource) {}
}

extension MusicModelTests {
    @MainActor
    func testMetadataFailureBacksOffAndLetsOtherPlayerConnect() async throws {
        let bridge = FailingMetadataPlayer()
        let model = MusicModel(bridge: bridge, detectionInterval: .milliseconds(10),
                               failureRetryInterval: 60, runningPID: { $0 == .youtube ? nil : 42 })
        defer { model.stop() }
        model.setAutomatic(true)
        for _ in 0..<100 {
            if model.connected && model.source == .spotify { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(model.connected)
        XCTAssertEqual(model.source, .spotify)
        let reads = await bridge.musicReads
        XCTAssertEqual(reads, 1, "A failed metadata read must not monopolize every detection cycle")
    }

    @MainActor
    func testMetadataFailureRecoversAutomaticallyAfterBackoff() async throws {
        let bridge = FailingMetadataPlayer()
        let model = MusicModel(bridge: bridge, detectionInterval: .milliseconds(10),
                               failureRetryInterval: 0.12, runningPID: { $0 == .appleMusic ? 42 : nil })
        defer { model.stop() }
        model.setAutomatic(true)
        try await waitForIdle(model)
        XCTAssertFalse(model.connected)
        await bridge.recover()
        for _ in 0..<100 {
            if model.connected { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(model.connected)
        XCTAssertEqual(model.title, "Apple Music")
    }

    @MainActor
    func testRetryDetectionBypassesMetadataBackoff() async throws {
        let bridge = FailingMetadataPlayer()
        let model = MusicModel(bridge: bridge, detectionInterval: .seconds(60),
                               failureRetryInterval: 60, runningPID: { $0 == .appleMusic ? 42 : nil })
        defer { model.stop() }
        model.setAutomatic(true)
        try await waitForIdle(model)
        XCTAssertFalse(model.connected)
        await bridge.recover()
        model.connect()
        try await waitForIdle(model)
        XCTAssertTrue(model.connected)
    }
}
