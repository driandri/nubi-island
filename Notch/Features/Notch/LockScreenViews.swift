import SwiftUI

struct LockScreenPill: View {
    @ObservedObject var configuration: NotchConfiguration
    @ObservedObject var system: SystemInfoModel
    var safeTop: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = NotchShape(radius: configuration.values.cornerRadius, attachesToScreenEdge: true)
        let animate = configuration.values.idleAnimation && !reduceMotion
        TimelineView(.animation(minimumInterval: 0.15, paused: !animate)) { context in
            let blink = animate && context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 12) < 0.28
            HStack {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.white.opacity(0.8))
                    .accessibilityHidden(true)
                Spacer()
                if system.batteryCharging == true {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Mengisi daya")
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 23)
            .overlay {
                NobiFace(blinking: blink, outlined: true, tint: configuration.accentColor)
                    .frame(width: 36, height: 21)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, safeTop)
        .background(.black, in: shape)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(system.batteryCharging == true ? "Nubi, Mac terkunci, mengisi daya" : "Nubi, Mac terkunci")
    }
}

struct LockScreenMusicCard: View {
    @ObservedObject var configuration: NotchConfiguration
    @ObservedObject var music: MusicModel
    var canControl: () -> Bool = { true }
    private let rose = Color(red: 1, green: 0.36, blue: 0.45)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: configuration.values.cornerRadius, style: .continuous)
        HStack(spacing: 12) {
            PlayerArtwork(music: music, size: 68, cornerRadius: 11, tint: rose)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(music.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(music.artist.isEmpty ? music.source.rawValue : music.artist)
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.76)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if music.isPlaying {
                        PlaybackPillMotion(animated: configuration.values.animateMusic,
                                           accent: configuration.accentColor, waveformColor: rose)
                            .fixedSize()
                    }
                }
                if music.duration > 0 {
                    TimelineView(.animation(minimumInterval: 1, paused: !music.isPlaying)) { context in
                        let elapsed = music.elapsed(at: context.date)
                        HStack(spacing: 7) {
                            Text(time(elapsed))
                            ProgressView(value: elapsed, total: music.duration)
                                .tint(rose)
                                .controlSize(.mini)
                                .accessibilityLabel("Progres musik")
                            Text(time(music.duration))
                        }
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.76))
                    }
                }
                HStack(spacing: 14) {
                    control("Lagu sebelumnya", symbol: "backward.end.fill") { music.skip(-1) }
                    control(music.isPlaying ? "Jeda" : "Putar",
                            symbol: music.isPlaying ? "pause.fill" : "play.fill", primary: true) { music.toggle() }
                    control("Lagu berikutnya", symbol: "forward.end.fill") { music.skip(1) }
                }
                .frame(maxWidth: .infinity)
                .disabled(!music.controlsEnabled)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .background {
            if configuration.values.panelStyle == "Apple Glass" {
                PanelGlassSurface(transparency: configuration.values.glassTransparency * 0.6, shape: shape)
            } else {
                shape.fill(.black)
                if configuration.values.panelStyle == "Accent Glow" {
                    shape.fill(.linearGradient(colors: [.clear, configuration.accentColor.opacity(0.17)],
                                               startPoint: .top, endPoint: .bottom))
                }
            }
        }
        .overlay { shape.strokeBorder(.white.opacity(0.18)).allowsHitTesting(false) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Musik")
    }

    private func control(_ label: String, symbol: String, primary: Bool = false,
                         action: @escaping () -> Void) -> some View {
        Button {
            if canControl() { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: primary ? 14 : 11, weight: .semibold))
                .foregroundStyle(primary ? .black : .white)
                .frame(width: 30, height: 30)
                .background(primary ? .white : .clear, in: Circle())
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func time(_ seconds: Double) -> String {
        let value = Int(seconds)
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
