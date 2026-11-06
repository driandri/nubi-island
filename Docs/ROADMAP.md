# Scope and roadmap

## Implemented

- Focus timer: 15/25/50-minute presets, pause/resume/reset, collapsed countdown, and persistent in-app completion indicator. Session-only; no system notification or sound.

- Phase 1: native Xcode app, lifecycle, menu-bar item, transparent floating panel, collapsed/expanded/pinned state, hover delays, content spring transitions, display selection/change handling, local preferences, no Dock icon.
- Phase 2: collapsed dimensions, corner radius, accent, animation duration, hover inset, expand/collapse delay, monitor selection, launch-at-login controls, and reset.
- Phase 3: automatic Music and Spotify detection plus optional manual/demo modes using public Apple Events. Includes title/artist, artwork, playback commands and interpolated progress. Live-provider code builds and has mocked lifecycle tests. Apple Music detection, artwork, metadata, progress, play and pause have now been verified live; Spotify episode detection, artwork, duration, Pause, and automatic switching in both directions have also been verified live.
- Phase 4 increment: internal battery when present, output volume/mute indicator using Core Audio notifications, CPU core count fallback, temporary file shelf.
- Design increment: contextual island views, Nōtch-managed HTTPS downloads, opt-in in-memory clipboard history, selected-app visible-banner mirroring through Accessibility, and a transient volume/available-brightness HUD.

## Next work

1. Finish live-player coverage: Spotify music tracks beyond the tested podcast, no current track, previous/next commands, player restarts, permission revocation, and simultaneous playback. Music detection, artwork, metadata, progress, play/pause, and a track change have been observed successfully. Spotify's installed dictionary describes duration in seconds although desktop integrations commonly receive milliseconds; the adapter divides by 1000 and needs confirmation against the installed player version.
2. Validate Core Audio behavior across HDMI, USB, Bluetooth, stereo channel volume, hardware mute, and device unplug/replug. Devices without software-volume properties intentionally show the CPU fallback. The indicator is read-only.
3. Validate public IOKit brightness reporting on supported displays. A Mac mini's external monitor may not expose brightness, so the card is omitted when unavailable.
4. Validate visible-banner Accessibility mirroring on selected applications and macOS versions. The app does not read Notification Center history or replace system banners; direct reply remains unsupported.
5. Packaging: local ZIP with installation instructions, checksum, and extraction/signature verification is implemented. Remaining: app icon, Developer ID signing/notarization if distribution is wanted, and optional sandbox migration with security-scoped file access.

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
- The file shelf is temporary, limited to eight URLs, and does not track renamed/deleted files automatically. Files from providers that do not supply file URLs are unsupported. Validation, normalized-path deduplication, capacity reporting, and reference-only clearing have automated coverage; live Finder drag/drop remains an acceptance check.
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
