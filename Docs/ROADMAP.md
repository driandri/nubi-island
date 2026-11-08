# Scope and roadmap

## Implemented

- Focus timer: 15/25/50-minute presets, pause/resume/reset, collapsed countdown, and persistent in-app completion indicator. Session-only; no system notification or sound.

- Phase 1: native Xcode app, lifecycle, menu-bar item, transparent floating panel, collapsed/expanded/pinned state, hover delays, content spring transitions, display selection/change handling, local preferences, no Dock icon.
- Phase 2: collapsed dimensions, corner radius, accent, animation duration, hover inset, expand/collapse delay, monitor selection, launch-at-login controls, and reset.
- Phase 3: automatic Music and Spotify detection plus optional manual/demo modes using public Apple Events. Includes title/artist, artwork, playback commands and interpolated progress. Live-provider code builds and has mocked lifecycle tests. Apple Music detection, artwork, metadata, progress, play and pause have now been verified live; Spotify episode detection, artwork, duration, Pause, and automatic switching in both directions have also been verified live.
- Phase 4 increment: internal battery when present, output volume/mute indicator using Core Audio notifications, CPU core count fallback, temporary file shelf.
- Design increment: contextual island views, Nōtch-managed HTTPS downloads, opt-in clipboard history with optional local persistence, selected-app visible-banner mirroring through Accessibility, and a transient volume/available-brightness HUD.
- Later increments: month-view Calendar, configurable Home widgets, local Quick Notes and to-do items, water and prayer reminders, an opt-in per-app mixer, and an optional lock-screen music panel. The user confirmed the lock-screen pill, music card, and playback controls on the development Mac.

## Next work

1. Finish live-player coverage: Spotify music tracks beyond the tested podcast, no current track, previous/next commands, player restarts, permission revocation, and simultaneous playback. Music detection, artwork, metadata, progress, play/pause, and a track change have been observed successfully. Spotify duration conversion was confirmed for one podcast episode on the installed version; music tracks remain untested.
2. Validate Core Audio behavior across HDMI, USB, Bluetooth, stereo channel volume, hardware mute, and device unplug/replug. Devices without software-volume properties intentionally show the CPU fallback. The indicator is read-only.
3. Validate public IOKit brightness reporting on supported displays. A Mac mini's external monitor may not expose brightness, so the card is omitted when unavailable.
4. Validate Mixer gain by listening or measuring output, plus permission denial, multiple processes, and output changes. A live YouTube playback produced one route, and the revised UI remained responsive while its slider changed and was restored. Route setup now runs on a serial background queue after an earlier `AudioDeviceStart` call stalled the UI.
5. Validate visible-banner Accessibility mirroring on selected applications and macOS versions. The app does not read Notification Center history or replace system banners; direct reply remains unsupported.
6. Repeat the lock-screen check on other macOS versions, displays, and hardware after updates because this opt-in feature uses private WindowServer APIs. One lock/unlock cycle with visible pill, music card, and working controls has been confirmed on the development Mac.
7. Packaging: the app icon and local ZIP with installation instructions, checksum, and extraction/signature verification are implemented. Developer ID signing/notarization is needed if public distribution is wanted; sandbox migration with security-scoped file access remains optional and would require implementation work.

## Developer goals (proposed)

Build for developers across editors and languages. Start with local project context, then an embedded terminal and optional AI-agent activity. The supplied Coucou screenshots inform the interaction: show the active session, its latest action, and a route back to the terminal. Keep Nubi's existing visual identity and Nobi character; [Coucou's character and artwork](https://github.com/Louis-CFM/coucou/blob/main/LICENSE-ASSETS.md) have separate usage restrictions.

1. **Project and Git hub.** Let the user add project folders explicitly. For a selected Git repository, show its branch and staged, unstaged, and untracked counts, with actions to open the folder in Finder or a chosen editor. Read Git state without changing the repository or scanning unrelated folders. Done when a changed repository matches `git status`, a clean repository is clear, and a moved or deleted folder reports a recoverable error.
2. **Embedded terminal.** Add a Terminal route backed by SwiftTerm's AppKit view and local pseudo-terminal. A shell starts in the selected project only when the user opens it; the user types commands directly. Keep the session alive when the island collapses, and end it on explicit close or app quit. Done when interactive shell input, colors, resize, copy/paste, Ctrl-C, exit, keyboard focus, and long-running output work on a selected display without blocking the island. This adds the first third-party package to the app.
3. **Read-only AI-agent activity.** Offer opt-in connections for Claude Code, Codex CLI, and Gemini CLI through their supported lifecycle hooks. Normalize local events into provider, project, session, state (working, waiting, finished, failed), and last action. Show a compact active or attention state in the island and session details in an expanded view; allow opening the related terminal. Support sessions started inside or outside Nubi. Do not store prompts, tool output, or credentials in the activity history, and do not approve agent requests from the island in this increment. Done when concurrent sessions from all three providers update and end correctly, disabled connections emit no Nubi activity, and missing or untrusted hooks explain how to reconnect.
4. **Development service status.** After local workflows work, add optional read-only GitHub pull-request/Actions and Vercel deployment status for chosen projects, with credentials in Keychain and explicit disconnect. Show only real states and link to the source service for detail. Stripe and n8n in the reference image are later candidates if they support a concrete developer workflow. Done when the selected project's current status, empty state, API failure, and expired access are distinguishable without allowing remote mutations.

Current progress: project and Git parsing pass local tests; a non-Git folder was added through the native picker. The embedded terminal passed `pwd`, Ctrl-C, 300 lines of output, paste, `exit`, restart, and navigation away and back without losing its session. Session rows can open a terminal for an available project, and hook configuration passes isolated tests for all three CLIs. GitHub PR/Actions and Vercel deployment status, separate Keychain tokens, and disconnect are implemented with isolated API tests; live authenticated responses remain unverified. A real Git folder in the picker, direct terminal resize and copy, and live CLI events also remain unverified.

These goals keep project, Git, agent, and service integrations read-only; shell commands run only when the user types them in the embedded terminal. Existing music, timer, and download activity remain visible when developer activity is present. AI approval actions, chat inside the island, automated builds, and mobile companion features require separate product decisions.

Research: [Stack Overflow Developer Survey 2026](https://survey.stackoverflow.co/2026) identifies project goals and repositories as key AI context; [Coucou](https://github.com/Louis-CFM/coucou) demonstrates session and service activity in a notch. Feasibility references: [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm), [Codex hooks](https://learn.chatgpt.com/docs/hooks), [Claude Code hooks](https://code.claude.com/docs/en/hooks), [Gemini CLI hooks](https://geminicli.com/docs/hooks/reference/), and [GitHub Actions API](https://docs.github.com/en/rest/actions/workflow-runs).

## Current limitations

- Auto mode defaults on and may prompt for Automation permission for running players. Permission cannot be bypassed. Denied providers require Retry detection after access is restored.
- Playback detection runs approximately every two seconds for running players. Full metadata refreshes while expanded, on player/state or process-ID changes, and roughly every fifteen seconds while collapsed. Track changes in the same playing app can therefore take about fifteen seconds plus one detection interval and event latency to appear while collapsed. Manual mode uses a five-second refresh.
- Automatic mode retries transient conditions and follows player launches. Automation denial requires Retry detection. Errors are visible in Settings and the widget tooltip.
- Apple Events have a three-second timeout per event, not per entire snapshot; multiple metadata reads can take longer when a player is unresponsive. They run away from the main actor. A sent playback command cannot be undone by switching providers.
- Missing Music artwork uses a placeholder. Spotify artwork loads optionally from its HTTPS image CDN and requires network access; failure does not prevent controls or metadata.
- Fullscreen behavior is configured via AppKit collection behavior but still needs validation against multiple native fullscreen applications, Stage Manager, and separate display Spaces. Exclusive fullscreen apps may cover the panel.
- Top-edge placement can cover center menu-bar content; below-menu-bar placement is available.
- Expanded dimensions are content-driven; width/height sliders control the collapsed pill.
- The animated frame uses AppKit easing; the content transition uses a SwiftUI spring.
- The panel covers its actual rectangular frame, including small transparent corners. It does not reserve a large invisible expanded window while collapsed.
- The file shelf is temporary, limited to eight URLs, and does not track renamed/deleted files automatically. Files from providers that do not supply file URLs are unsupported. Validation, normalized-path deduplication, capacity reporting, and reference-only clearing have automated coverage. One live Finder drag into the shelf succeeded; dragging files out and other file providers remain acceptance checks.
- Login registration is implemented, but successful launch after an actual logout/reboot has not been tested. Install in a stable Applications path first.
- Initial UI automation failures were resolved in a later session. Expanded layout, Settings, pinning, artwork, metadata and play/pause were observed via native accessibility and screenshot. Hover animation quality, menu-bar selection, drag/drop and fullscreen still need manual checks.

## API references

- [NSPanel](https://developer.apple.com/documentation/appkit/nspanel)
- [SMAppService registration](https://developer.apple.com/documentation/servicemanagement/smappservice/register())
- [NSAppleEventDescriptor](https://developer.apple.com/documentation/foundation/nsappleeventdescriptor)
- [Core Audio property listeners](https://developer.apple.com/documentation/coreaudio/audioobjectpropertylistenerblock)
- Player commands/properties were read from `/System/Applications/Music.app/Contents/Resources/com.apple.Music.sdef` and `/Applications/Spotify.app/Contents/Resources/Spotify.sdef` on the development machine.

Local builds must be bundle-signed using `Scripts/build-local.sh` (or an Xcode development identity). The initial linker-only signed build could not obtain Automation access. The explicit permission request and ad-hoc bundle signing resolved live Music access.

Spotify podcasts may expose an empty artist/author via the desktop scripting API. The tested episode displayed title and artwork correctly but no artist line.

A basic Music-fullscreen check, application-menu Quit/relaunch, preference persistence, standard Settings menu, and Command-comma were subsequently exercised successfully. Fullscreen coverage remains limited to this single-app scenario; consult VALIDATION.md for the exact evidence.
