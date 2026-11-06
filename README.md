# Nubi

A small native macOS menu-bar utility that places a virtual notch at the top center of an external display. SwiftUI provides the interface; a transparent, nonactivating AppKit `NSPanel` hosts it. No Electron, webview, backend, telemetry, or third-party dependencies.

## Build and run

Requires macOS 14 or later and Xcode with the macOS SDK. Developed and built on Apple Silicon with Xcode's Swift 6.3.3 toolchain and tested for launch on macOS 26.4.1.

Open `Notch.xcodeproj`, select the **Notch** scheme and **My Mac**, then Run. If Xcode requests signing, choose your personal development team under Signing & Capabilities. The app has no Dock icon: use its capsule-shaped menu-bar item for Settings, Pin / Unpin, Collapse, and Quit.

For a local build without a development team, use the ad-hoc signed build script:

```sh
./Scripts/build-local.sh
open build/Build/Products/Release/Nubi.app
```

Quit the development copy before running a different build. For regular use, copy `Nubi.app` from the build directory into `~/Applications` or `/Applications`, launch that copy, then enable Launch at login in Settings. Login registration is handled by Apple's `SMAppService`; macOS may require approval in System Settings → General → Login Items. The script signs the complete bundle with its `com.personal.notch` identifier and the Apple Events entitlement, then verifies the signature. Do not use `CODE_SIGNING_ALLOWED=NO` for a runnable music-integration build: a linker-only signature does not bind the privacy usage text to the app. This is an ad-hoc personal build, not Developer ID signed or notarized for distribution. macOS may request Automation approval again after rebuilding; a development signing identity and stable installation path are preferable for regular use.

## Package for personal use

```sh
./Scripts/package-local.sh
```

Creates `build/packages/Nubi-1.0.0-local.zip` and its SHA-256 checksum. The script builds and verifies the signed bundle, packages installation instructions and limitations, then extracts the ZIP and verifies its signature and executable before publishing the archive. See [installation instructions](Docs/INSTALL.md). This remains an ad-hoc local build, not a notarized public release.

## Use

- **Timer:** Standard offers 1/2/3/5/10/25-minute presets and a custom 1–180-minute duration. Pomodoro alternates 25-minute focus, 5-minute breaks, and a 15-minute break after four focus sessions; each next stage starts only when clicked. Pause, resume, and reset are available while running. The collapsed pill keeps the countdown visible alongside music. Sessions include sleep time, stay in memory, and do not send system notifications.
- Hover over the pill to expand; leave it to collapse after the configured delay.
- The collapsed island shows the current date and time while idle. During activity it shows playing music with an animated waveform, an active timer, and a running download together. Opening it starts on Home, with Calendar, Music, and Timer cards plus shortcuts to Live Activities, Downloads, Clipboard, and File Shelf. Use **Customize** or Settings to show, hide, and reorder Home cards. The bottom bar opens Home, Music, Timer, Mixer, Launcher, and More; More contains the remaining views. New notifications and supported system HUD changes appear briefly when the island is not pinned; pinning keeps the selected view visible.
- **Calendar:** open its Home card or bottom-bar view and choose Connect Calendar to request EventKit access. Nubi then shows up to three upcoming events in its panel and a next-event preview on Home. Open Calendar launches the macOS app. Events stay in memory and are cleared when Nubi quits; Nubi does not edit calendars. macOS grants full Calendar access for reading events, which can be revoked in System Settings → Privacy & Security → Calendars.
- **Sholat:** choose a city or enable location in Home settings. The Sholat panel shows the next prayer, a countdown, progress, and all five times from AlAdhan's Kemenag calculation. Island reminders appear before and at prayer time while Nubi is running; the lead time can be set to 5, 10, or 30 minutes. Local mosque times may differ.
- **Water reminder:** add Minum to Home or open Water from More. Record each drink, set a daily goal, serving size, and interval, and inspect today's chart. Reminders are off until enabled, appear in the island from 08.00 to 21.00 while Nubi runs, and stop after the goal is reached. The last seven days of entries are stored locally in UserDefaults.
- Click the collapsed pill to expand and pin. Click the header's pin control to pin/unpin. Unpinning while hovered leaves the panel expanded until the pointer leaves.
- Right-click for Pin, Settings, and Collapse. The menu-bar item remains available even when the panel is collapsed. The standard Settings menu and ⌘, (when Nubi is active) open the same Settings window.
- Customize collapsed width/height, corner radius, accent, panel glow, waveform animation, Home cards, animation duration, hover edge inset, and expand/collapse delays.
- **Sound Mixer:** choose the default output and input device, adjust system volume and input gain where supported, and view applications using audio. Enable **Mix apps** and press **Mulai** to begin routing applications through Nubi for this session. macOS 14.2 or later and System Audio Recording permission are required for per-app gain; macOS asks when the first route starts. A saved mixer preference never starts capture on app launch. Nubi checks one audio source first and pauses routing if no usable audio arrives; press **Mulai** again after checking permission. Output-device changes also pause routing. Captured audio is processed in memory, never saved. The mixer is off by default; macOS 14.0–14.1 still supports device and system-volume controls.
- **Launcher, To-do, Calculator:** Launcher searches applications in `/Applications`, `/System/Applications`, and `~/Applications`. To-do items are saved locally in Application Support and support add, complete, and delete. Calculator supports decimal arithmetic, percent, sign, clear, backspace, and keyboard input. These text controls take focus only after opening their panel.
- Select a monitor or follow the primary display. A disconnected selection falls back to the primary display and reconnects when available.
- Enable **Place below the menu bar** if the top-center overlay covers menu titles. **Show in fullscreen spaces** is optional and defaults off.
- Drag up to eight file URLs onto the notch, or use the + button / “Add files…” context-menu command to choose files and folders through the native macOS picker. The shelf pins open only when a valid local file is accepted. Duplicate paths do not consume extra slots; unavailable files and overflow are reported. Click a filename to reveal it in Finder, drag it elsewhere, or remove its reference with ×. Use the context menu’s “Clear file shelf” to remove all references. Quitting clears the shelf; files are never copied, moved, or deleted by shelf removal.
- **Downloads:** choose New download from the menu-bar item, island, or context menu. Enter an HTTPS URL and choose a save location for each download. The island shows progress, cancel, retry, completion, and Reveal in Finder. Active downloads are cancelled when Nubi quits. HTTP URLs, credential-bearing URLs, and redirects away from HTTPS are rejected.
- **Clipboard:** enable session-only history in Settings. Nubi then keeps at most three recent text, web link, or color entries in memory; it skips file and concealed/transient pasteboard types. Text can be pasted into the frontmost app when Accessibility access is granted, or copied again otherwise. Links open in the default app, and colors copy their HEX value. Clear the history in Settings or quit Nubi to remove it.
- **Notifications:** opt in under Settings, grant Accessibility access through macOS, and add the application bundles whose visible banners may be mirrored. Nubi shows a short-lived card for a recognized banner and opens its source when clicked. It does not read Notification Center history, send replies, save message content, or hide the original macOS banner. Unrecognized banners are ignored.
- **System HUD:** output-volume changes appear briefly in the island. Brightness appears only when the selected display reports a value through the public IOKit display interface; unsupported external displays show no brightness card. The macOS HUD remains visible.
- **Automatic music detection is on by default.** Play a song in Music, Spotify, or a YouTube watch tab in Chrome and allow macOS Automation access when requested. For YouTube, enable **Chrome → View → Developer → Allow JavaScript from Apple Events**. Nubi checks Chrome tab URLs and reads playback only on YouTube watch tabs. It follows a playing source within roughly two seconds, even while collapsed. It never launches a player or starts playback by itself.
- If several sources play, the currently selected source stays active; a playing YouTube tab takes over when Chrome is in front. When the selected source pauses, another playing source takes over. With no running supported app, detection waits for a launch event instead of polling.
- Open Music to see larger artwork, title, artist, current lyric lines, progress, and previous/play-pause/next controls. While collapsed, lightweight state probes keep playback detection active; full metadata refreshes on player/state changes, player process restarts, expansion, and approximately every 15 seconds while collapsed. While expanded, metadata updates about every two seconds in Auto mode.
- Automatic detection is remembered between launches. Disable it in **Settings → Music** to use manual selection or Demo mode. If access was denied, allow it in System Settings → Privacy & Security → Automation and click **Retry detection**; denied players are not repeatedly prompted. A pending permission dialog for one player does not stop the other connected player.
- Music artwork comes from the player. Spotify artwork optionally loads from its HTTPS image CDN while visible; metadata and playback do not require a Nubi backend or Spotify Web API account. Missing artwork falls back to a symbol.
- Music previews the current lyric lines. Press **Lyrics** to expand the scrollable view. Nubi first reads Apple Music track lyrics when available, then looks up missing lyrics from [LRCLIB](https://lrclib.net/docs) using the song title, artist, and duration. This lookup can be disabled in Settings. Synced lyrics highlight the current line; catalog misses show an explicit message.
- The Music footer shows output volume/mute state when the device exposes software volume. It follows output-device changes using Core Audio notifications.

Preferences are stored locally under the `com.personal.notch` UserDefaults domain, including Home layout and per-app mixer gains. To-do items are stored separately in Application Support. Reset to defaults resets appearance, Home layout, interaction, and display choices; it intentionally preserves the independently managed login-item registration and mixer gains.

## Validation

```sh
swift test
```

The Swift package is a test harness for the actual models used by the Xcode app. It does not replace the app project. Tests cover interaction, configuration migration, geometry, media, timer transitions, local to-do persistence, launcher discovery, calculator operations, and mixer gain/format checks. Tests do not request Automation or System Audio Recording permission or change real playback.

See [validation notes](Docs/VALIDATION.md) for executed checks and the remaining hardware/UI checks. See [architecture](Docs/ARCHITECTURE.md) and [roadmap and limitations](Docs/ROADMAP.md).
