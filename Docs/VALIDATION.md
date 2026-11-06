# Validation — 19 October 2026

## Executed

Environment: Apple Silicon, macOS 26.4.1, Xcode at `/Applications/Xcode.app`, Swift 6.3.3, macOS 26.5 SDK. Deployment target: macOS 14.

| Check | Result |
| --- | --- |
| Xcode Debug build, arm64, signing disabled | Passed |
| Xcode Release build, arm64, signing disabled | Passed |
| `swift test` | 40 tests passed, 0 failures |
| Swift 6 strict concurrency compilation | No Swift concurrency warnings |
| Launch built app | Process launched and remained alive |
| Short idle process sample | Main thread waiting in the AppKit event loop; sampled CPU 0.0%; physical footprint about 18.5 MB for the Debug process |
| Preference round trip and reset | Passed with isolated UserDefaults suites |
| Invalid persisted settings | Dimensions clamped and unknown accent reset |
| Hover/pin transition logic | Passed, including exit before expansion, re-entry before collapse, pinning, and explicit dismiss |
| Actual delayed controller tasks | Passed cancellation and pin survival tests |
| Geometry | Passed primary centering, negative-origin display, menu-bar offset, and oversize clamping tests |

The initial build exposed an invalid AppKit accessibility-label assignment, which was fixed. The Swift 6.3.3 compiler also crashed while lowering a direct bound setter method reference; replacing it with an explicit closure resolved the crash. Builds emit only Xcode's benign “Metadata extraction skipped. No AppIntents.framework dependency found” message; the app does not implement App Intents.

The short process sample is a smoke check, not a sustained performance benchmark. No CPU/RAM guarantees are inferred from it.

## Not verified by desktop automation

The computer-use tool repeatedly timed out when inspecting the Nōtch process, including by full bundle path. A Finder accessibility query worked, but its screenshot was blank, so there was no usable visual evidence. The following remain manual acceptance checks, not passes:

1. Confirm the pill is top-centered and the expanded content fits at every supported size.
2. Hover repeatedly across each edge; confirm expansion/collapse delay, no flicker, and pin/unpin behavior. Check rapid movement during resizing.
3. Click directly outside the current panel; confirm the underlying application receives the click. Check menu-bar interaction and the below-menu-bar placement option.
4. Open Settings from both controls; change values, quit, relaunch, and confirm values persist. Close Settings and confirm the app stays running.
5. Test the menu-bar Quit command and confirm both panel and status item disappear.
6. Connect/disconnect an external monitor; test primary selection, remembered explicit selection, resolution/scaling changes, and reconnect fallback.
7. Test native fullscreen, separate display Spaces, Stage Manager, and apps with exclusive fullscreen, with the fullscreen preference both on and off.
8. Test real drag/drop into and out of the shelf, missing files, duplicate entries, and the eight-file limit.
9. Confirm no battery row on Mac mini; test live battery notifications on a MacBook if available.
10. Install to Applications, enable login registration, approve if required, and verify after a real login. Login registration was not changed automatically during development.
11. Test VoiceOver and Reduce Motion. Controls have accessibility labels and the implementation disables transitions for Reduce Motion, but assistive-technology behavior has not been exercised.

## Follow-up implementation

Music and Spotify providers now compile using public Apple Events. A new mock-backed test suite covers explicit connection, playback command routing, permission denial, absent players, stale results after a source change, nonnegative progress, four-character event codes, and refresh scheduling only while visible. The previous increment had 19 tests. These tests do not send real Apple Events and do not prove compatibility with a live player.

The volume/mute indicator now uses Core Audio property listeners and handles default-output changes. Real device-level volume changes and unsupported HDMI/USB devices remain manual checks. Music artwork is read from the player; Spotify artwork is loaded asynchronously from allowed HTTPS image CDN hosts. Live artwork rendering remains unverified.

No Automation permission was granted by the agent and no real playback was changed by automated tests. Automatic mode now checks running players at launch; approve the macOS Automation prompt for the live checks. Brightness and notifications remain roadmap items.

## Automatic playback detection

Four additional mock-backed tests cover switching from paused Music to playing Spotify and back while collapsed, preserving the current provider when both play, permission denial without repeated prompts while the other provider remains usable, and persisted preferences/no events when no player is running. Total: 23 tests. Detection itself sends no playback commands. End-to-end permission approval and real-player detection still require a live check.

## Live validation and Automation repair

A later native UI session showed automatic detection disabled and Automation reads rejected. Automatic detection was enabled. Nōtch was absent from the macOS Automation list, and `codesign -dv` showed only a linker signature (`Identifier=Notch`, Info.plist not bound). The application now includes the Automation entitlement and explicitly requests consent through `AEDeterminePermissionToAutomateTarget`. `Scripts/build-local.sh` creates a complete ad-hoc signature; verification succeeds with identifier `com.personal.notch`, Info.plist binding, and sealed resources.

Executed after this repair:

- Signed Release build passed; `codesign --verify --deep --strict` passed.
- All 23 automated tests passed again. Tests use fake players and do not touch live playback.
- Native UI showed **Auto-detected Apple Music**, real track title/artist, duration and progress.
- A screenshot confirmed the expanded layout and live Music artwork rendered correctly.
- The UI reflected a different real track after a user-driven track change.
- Play was clicked from a paused state and the button changed to Pause. Pause was then clicked and the button returned to Play; the initial paused state was restored. Updates can take one detection interval.
- Settings opened and closed successfully; the auto-detection toggle was confirmed on.

The agent did not click a system permission-grant control or change unrelated privacy settings. Access became available through the repaired app's normal macOS consent flow. No claim is made that Spotify, previous/next, fullscreen, display hot-plugging, or login-after-reboot has been tested. Native screenshot inspection is now available, superseding the initial UI-inspection blocker for the specific checks above.

## Spotify live verification and permission isolation

After the user confirmed Spotify Automation approval:

- The signed Release build passed, including strict bundle-signature verification; all 25 automated tests passed.
- A live Spotify episode was resumed briefly without replacing the queue. Nōtch automatically switched from paused Apple Music to Spotify and displayed its title, artwork, progress, and 16:15 duration, matching Spotify. This confirms millisecond-to-second duration conversion for the installed desktop version and the tested episode.
- The Pause button in Nōtch paused Spotify, confirmed by Spotify's own button changing back to Play.
- Resuming the existing Apple Music track caused Nōtch to switch back to Apple Music automatically. Music was left playing, and Spotify paused. The Spotify episode was moved back fifteen seconds for the short test and left several seconds before its original position; its queue was not replaced.
- The tested Spotify podcast returned an empty artist field; the title and artwork were present. Empty podcast author metadata remains a provider limitation.

An OS consent dialog previously occupied the serial player executor and stalled detection for the other provider. Authorization now runs separately from the player-event executor. State probes use a noninteractive permission check; sources awaiting consent are excluded from probes while other sources remain usable. Settings shows which provider needs approval. Mode changes and shutdown invalidate pending authorization results. Two regression tests cover an unresolved Spotify permission while Music remains usable, and a late permission result after switching to Demo.

Not yet exercised live: Spotify music tracks (the live item was a podcast), previous/next commands, simultaneous playback, permission revocation, display hot-plugging, fullscreen, and login-after-reboot.

## Fullscreen, relaunch, and Settings entry points

A native UI session exercised Music's fullscreen mode with Nōtch's **Show in fullscreen spaces** preference enabled. Music's View menu showed **Exit Full Screen**, confirming the mode. Nōtch remained accessible through its native accessibility tree and its panel screenshot rendered the current track. Music was returned to windowed mode, confirmed by **Enter Full Screen** in its menu. This is a basic single-app check, not proof of compositor behavior in all fullscreen apps, Spaces layouts, or exclusive fullscreen games.

The native Nōtch application menu's Quit command terminated the process (verified absent with `pgrep`). Relaunch restored automatic Music detection without a manual connection. Width 320 pt, height approximately 27.895 pt, corner radius 30 pt, Orange accent, animation/delay values, fullscreen-on, and auto-detection-on persisted. No preference reset or login-item change was performed.

Code review of the standard application menu found that the SwiftUI Settings scene was empty even though the notch/menu-bar entry points used the real AppKit settings window. The Settings command group now routes the standard menu and Command-comma to that same reusable window. The signed Release build passed and its signature verified. Native UI checks confirmed the Settings menu opens the populated window and Command-comma reopens it after closing. This small menu-routing change was verified manually; no redundant automated tests were added or rerun. The existing suite's last result remains 25 passing tests.

Playback was left paused throughout these checks. Context-menu Collapse was also exercised to return the panel to its compact state. The status-item Quit entry, display hot-plugging, launch-after-login, and exhaustive fullscreen combinations remain separate acceptance checks.

## File shelf validation and rejected drops

The shelf now rejects unavailable local files and non-file URLs before accepting a drop. Paths are standardized before deduplication. Capacity remains eight references, with partial drops retaining valid entries and reporting skipped items. Rejected drops no longer pin the notch. The context menu offers Clear file shelf when populated; removing or clearing entries does not delete source files. Finder reveal rechecks whether the reference still exists.

Six new tests cover rejected URLs, normalized duplicates, capacity and partial acceptance, mixed valid/invalid drops, stale references before reveal, and preservation of a real temporary source file after removing and clearing references. All 31 tests passed with zero failures. The signed Release build and strict code-signature verification passed.

The latest build was relaunched and its native accessibility state immediately showed the existing Apple Music track, Trophies (feat. Drake), paused. Playback and user preferences were not changed. Actual Finder drag/drop into and out of the panel remains unverified; model tests do not establish that native drag interaction works end to end.

## Native file picker and live shelf checks

Added an Add files… context-menu command and a labeled + button opening NSOpenPanel. Multiple files and folders can be selected, with the same validation and eight-reference limit as drops. A successful selection pins the panel; cancellation preserves contents. The signed Release build passed, signature verification passed, and all 31 tests passed again.

Live native UI checks used only a generated fixture at `/tmp/notch-shelf-check/Shelf-check.txt`:

- Opened the picker from the + button, cancelled it, and reopened it successfully.
- Selected the fixture and observed one shelf item; a screenshot confirmed the row fits the expanded panel.
- Clicked Reveal in Finder and confirmed Finder selected that exact file.
- Selected the same fixture again; the shelf stayed at one item.
- Removed its reference with ×; the shelf returned to its empty state. Reading the source fixture confirmed its contents remained intact.

An initial navigation attempt timed out in the UI tool. A process sample showed the main thread waiting in the AppKit event loop; Escape restored UI inspection, and subsequent navigation and selection succeeded. This does not establish the cause of the timeout. Cross-window Finder drag/drop remains unverified because the available UI observations did not provide a reliable shared coordinate frame. Playback remained paused throughout these checks.

## Collapsed metadata and player restart regression

Automatic detection previously refreshed collapsed metadata only when the source or playing state changed. Consecutive tracks with the same playing state could leave stale metadata indefinitely until expansion. The model now records a monotonic snapshot timestamp and fetches metadata after fifteen seconds, on the next detection cycle. It also records the snapshot's process ID so a restarted player refreshes immediately on its next scan even when source and playback state match.

Two mock-backed regression tests verify a same-provider track change while collapsed without any playback commands, fewer metadata reads than state probes, and a new player process refreshing before the metadata deadline. All 33 tests passed. The signed Release build and strict signature verification passed, with no Swift concurrency warnings. These regressions use fake players; they do not constitute live track-change or player-restart tests.

## Metadata failure recovery — 20 October 2026

Metadata failures now receive the same fifteen-second retry backoff as state-probe failures. Previously a player could report playing successfully but fail every metadata read, win every scan, and prevent a healthy alternative from connecting. Subsequent scans now exclude that source during its retry delay. Permission-denial and pending-consent handling remain separate.

Three mock-backed tests verify healthy-provider fallback, automatic recovery after the delay, and Retry detection bypassing the delay. All 36 tests passed; the signed Release build and strict signature verification passed. No live-player timeout or permission failure was induced.

## Local package — 20 October 2026

`Scripts/package-local.sh` completed a signed Release build, copied the bundle and installation/limitations documentation into a ZIP, extracted that ZIP into a temporary validation directory, and verified the extracted bundle's strict signature and byte-identical executable. The published ZIP's SHA-256 verification returned OK. The script cleans only its own mktemp staging directory and leaves the app checkout and preferences intact.

No application logic changed in this packaging increment; the last automated suite result remains 36 passing tests. Installation to Applications, launch-after-login, Gatekeeper distribution, Developer ID signing, and notarization were not performed by this packaging check.

## Installation to a stable user Applications path — 20 October 2026

No existing Notch.app was present at either `/Applications/Notch.app` or `~/Applications/Notch.app`. The signed build was copied to `/Users/devzahirerp/Applications/Notch.app`; strict signature verification and executable comparison both passed. The live shelf was confirmed empty before quitting the development copy through its application menu.

The installed copy launched successfully. Native accessibility showed the existing Apple Music track NUEVAYoL, paused, immediately after launch. No playback commands or permission-grant actions were used. Launch-at-login registration and actual login/reboot behavior remain untested.

## Focus timer — 20 October 2026

Added an independent focus timer with 15/25/50-minute presets, pause/resume/reset, collapsed countdown, and an in-app completion state. Four tests cover fractional pause/resume accounting, late callbacks completing without negative time, reset and replacement sessions, invalid input, and real scheduled completion/restart. All 40 tests passed. The signed universal Release build and installed bundle signature verification passed with no Swift concurrency warnings.

The previous installed bundle was backed up under build/backups before replacing it. Native UI and screenshots confirmed the new expanded layout, starting 25 minutes, pause/resume, a decreasing collapsed countdown, selecting 15 minutes, and reset returning to Start 25 min. Native menu activation was verified with keyboard navigation after pointer selection did not activate the command through the automation tool. The test timer was reset after verification. Music remained paused. Full-duration completion and actual sleep/wake were not exercised live; completion and elapsed-time jumps are covered by tests. No system notifications, login registration changes, or playback commands were introduced.

## Dynamic Island design increment — 5 November 2026

The native island now has contextual Music, Focus, Downloads, Clipboard, and Shelf views, plus temporary notification and system HUD cards. Size migration changes only stored legacy 180×32 pt defaults; other stored dimensions remain untouched. The new clipboard and selected-app notification integrations default off.

`swift test` passed all 48 tests. New tests cover size migration, transient presentation while pinned, clipboard classification, opt-in monitoring, session clearing and three-entry deduplication, notification allowlist parsing and persistence, HTTPS URL validation and downgrade rejection, cancellation before file commit, and a fixture-backed download saved to its selected path. `Scripts/build-local.sh` passed a signed universal Release build and strict signature verification.

Native accessibility and screenshots confirmed the collapsed pill, expanded Music panel with empty and Demo metadata, Focus, empty Downloads/Clipboard/Shelf views, the focused URL entry dialog, and the new Settings controls. The temporary Demo selection was restored to automatic detection. The built app was left collapsed. The reference HTML's local `file:` tab could not be inspected by browser automation, so the comparison used the HTML's structure, text, styles, and dimensions.

Live Accessibility permission, an actual external-app notification banner, direct paste into another app, a real network download through the UI, system volume-key HUD, and brightness on a supported display were not exercised. The selected external display on this Mac did not report a supported brightness value. These integrations need user-authorized live checks; no privacy permission was granted during validation.

## Live Activities, YouTube, and lyrics — 5 November 2026

Added a Live Activities route and a collapsed summary that presents music, focus, and downloads together. Added Chrome YouTube watch-tab probing through its public AppleScript dictionary, with a Settings message when browser automation is unavailable. Added Apple Music track lyrics and optional LRCLIB fallback for missing Apple Music/Spotify/YouTube lyrics, including synchronized line timing and source credit.

The full suite passed 54 tests, including native-lyrics precedence, online-lyrics preference, synchronized-LRC parsing, YouTube source selection and foreground priority with an injected player, and Live Activities default navigation. The signed universal Release build and strict signature verification passed. Native UI showed the Live Activities route, Music lyrics loaded from LRCLIB for the current Apple Music song, and a collapsed pill showing the song and a temporary 15-minute Focus countdown simultaneously. The test timer was reset, and Nōtch was left collapsed on Live Activities. Actual YouTube playback detection and Spotify lyrics for a real song were not exercised; they depend on Chrome Automation/JavaScript settings and the selected song's availability in LRCLIB.

The generated Chrome probe and control AppleScript sources compiled with `osacompile` without executing any browser tab. The final signed build was relaunched and detected the current Apple Music track in the collapsed pill.

The running app is the project build under `build/Build/Products/Release`. The separate copy under `~/Applications` was not replaced.

## Home, Music layout, and Calendar — 5 November 2026

The expanded panel now opens on Home with Calendar, Music, and Focus cards, quick feature shortcuts, and bottom navigation. Music has larger artwork, lyric preview, elapsed and remaining time, and playback controls; the Lyrics button opens the synchronized scroll view. Calendar uses EventKit and shows the next seven days only after full access is available. It does not change or persist events.

`swift test` passed 57 tests, including calendar grant/denial and event-data clearing, Home default navigation, and lyric-preview lookup. `Scripts/build-local.sh` produced a signed universal Release build and passed strict signature verification. Native inspection confirmed the Home layout, Music with a current lyric preview, and Calendar with events when access was available. After the final rebuild, Home showed **Connect Calendar**, so access must be granted for the currently running build. No permission prompt was clicked and no calendar entry was changed. The current build was launched from the project path and left collapsed. The copy under `~/Applications` was not replaced.

## Mixer, timer, and Home tools — 5 November 2026

Added Standard/Pomodoro timer UI, animated music waveform, stable navigation positions, a top-anchored resize guard, configurable Home cards, launcher, local to-do, calculator, and an opt-in Core Audio process-tap mixer. Preferences decode older records without losing customized dimensions. Mixer routes are enabled only after the user turns on mixing; unsupported formats and failures stop the tap and restore the original app route.

`swift test` passed 63 tests, including new tests for old-preference decoding, card ordering sanitization, four Pomodoro cycles with manual stage transitions, to-do persistence, launcher discovery, calculator errors, mixer gain/format guard, and top-edge geometry. The arm64 Debug build passed. `Scripts/build-local.sh` passed a signed universal Release build and strict signature verification; `plutil -lint` passed for Info.plist and the Xcode project. No source compiler warnings remained.

A temporary Core Audio probe created and destroyed a private tap and aggregate device without starting capture. A generic tap reported 48 kHz input against this Mac's 44.1 kHz output; binding the tap to the selected output device reported 44.1 kHz for both streams. The mixer implementation now uses the device-bound tap and refuses incompatible formats before starting an IOProc.

Native screenshots showed the collapsed pill and expanded Home and Mixer panels. The first Home screenshot exposed clipped cards, and navigation positions shifted with active-label width; both were corrected and rebuilt. The final collapsed pill was inspected after relaunch. The computer's pointer injection did not reach the panel after the final rebuild, so the revised Home/Timer/Launcher/To-do/Calculator layouts and text focus were not rechecked visually.

System Audio Recording was not granted or denied during this run. Live per-app capture and volume, an output-device change during mixing, two simultaneous audio apps, microphone gain on other hardware, keyboard focus, Reduce Motion, and multi-display hover behavior remain manual checks. The separate `~/Applications` copy was not replaced.

## First-run guide and mixer permission loop — 6 November 2026

Added a first-run introduction and quick setup window based on the supplied visual references, with actual Nōtch integrations and actions. Existing installations do not suddenly show the guide; users can reopen it from the menu-bar item. The guide and Settings windows center on the selected display. Denied Calendar access now opens the relevant macOS privacy settings instead of leaving an inactive Connect action. The quick setup layout was inspected on screen.

The mixer now requires an explicit **Mulai** action in each app session even if its saved preference is enabled. It starts one audio route to check capture, pauses when no usable buffer or audible sample arrives, and pauses after an output-device change. This prevents a saved preference or newly detected process from repeatedly creating taps at launch after macOS denies System Audio Recording. The saved mixer preference was still enabled during a Release launch, and no audio permission dialog appeared. The final suite passed 65 tests; the ad-hoc signed universal Release build and strict signature verification passed. A denied/allowed live tap, per-app gain, and the operating system's persistence of permission after rebuilding still need manual testing; ad-hoc signatures may cause macOS to ask again on a later explicit start.

## Idle pill date — 6 November 2026

The collapsed pill now shows an accent calendar icon, localized Indonesian date, and time while there is no music, timer, or download. Smaller saved widths use a compact date layout. The signed Release build passed, and the idle pill was inspected in a native screenshot on the selected display. Minute alignment was adjusted afterward; the live minute rollover and narrow-width fallback were not visually exercised.
## Instalasi build terbaru — 6 November 2026

Build Release universal terbaru dipasang ke `/Users/devzahirerp/Applications/Notch.app` dari hasil `Scripts/build-local.sh`. Salinan sebelumnya disimpan di `build/backups/Notch-before-install-20261106-033831.app`. `codesign --verify --deep --strict` lulus untuk salinan terpasang, dan SHA-256 executable sama dengan hasil build (`c57224df023a10fda597fa3c1c8ae4229b40ca2a00ee56a97166a38511f5e994`). Pada permintaan berikutnya, proses dari direktori build sudah tidak berjalan dan salinan terpasang dibuka melalui `open -a`. Proses baru PID 68878 tetap berjalan dari `~/Applications/Notch.app` setelah pemeriksaan ulang; tidak ada proses Nōtch dari direktori build.

## Editor Home dalam panel dan widget tambahan — 6 November 2026

Home kini memiliki editor langsung di panel: chip tambah/hapus, ukuran Compact/Wide/Tall, dan panah urutan dengan aksi Accessibility. Kartu Sholat memakai kota/lokasi cuaca yang dipilih pengguna dan menampilkan lima waktu serta waktu berikutnya; Quick Notes disimpan sebagai teks lokal; Keep Awake menahan tidur layar melalui assertion IOKit sampai dimatikan atau Nōtch keluar. Semua pilihan widget dan ukurannya kompatibel dengan preferensi lama.

`swift test` lulus 74 dari 74 tes, termasuk migrasi ukuran/urutan, penempatan kartu tanpa tumpang tindih, parser jadwal Sholat dengan zona waktu, dan simpan/muat Quick Notes. Build Release universal bertanda tangan lulus dan salinan terpasang lolos `codesign --verify --deep --strict` dengan hash executable yang sama seperti build. Pemeriksaan native menunjukkan editor, tambah/hapus, perubahan ketiga ukuran, dan panah urutan bekerja. Seret kartu tidak memberi hasil konsisten pada panel native dalam uji UI, sehingga pengurutan memakai panah yang teruji. Quick Notes dapat diketik dan catatan uji dihapus lagi. Keep Awake dihidupkan lalu dimatikan lagi. Kota uji Bogor memuat cuaca dan lima waktu Sholat di panel; kota kemudian dikosongkan kembali. Panel tidak dipin setelah uji. Tidak ada izin lokasi baru yang diberikan.

## Calendar, Nobi idle, HUD, dan fullscreen — 6 November 2026

Calendar kini menampilkan bulan penuh, agenda tanggal terpilih, dan daftar upcoming yang dapat digulir. Nobi masuk fase robot setelah 15 menit tanpa input mouse atau keyboard, satu kali animasi masuk, lalu kembali saat ada input. HUD mendapat status daya baterai dan mute mikrofon; brightness dibaca per layar yang mendukung. Panel yang disembunyikan pada aplikasi fullscreen kini memiliki zona hover di tepi atas dan pemeriksaan pemulihan saat keluar fullscreen. Perpindahan rute menahan collapse akibat perubahan ukuran sampai pointer bergerak.

`swift test` lulus 94 tes. `Scripts/build-local.sh` lulus build Release bertanda tangan dan verifikasi signature. Build dari folder proyek dijalankan dan diperiksa lewat accessibility tree: Home, Calendar, Music/YouTube, Mixer, dan pengaturan HUD/layar. Kalender dengan izin sempat memperlihatkan grid dan agenda; pada proses build ad-hoc berikutnya izin perlu diminta kembali. Tiga layar terdeteksi dan mode All displays tersimpan, tetapi hover aplikasi fullscreen dan posisi semua panel belum diuji langsung. Brightness layar terpilih tidak tersedia; baterai internal juga tidak ada pada Mac mini ini. Rincian per-flow dan batas uji tercatat di `Docs/FLOW-AUDIT-2026-11-06.md`.

