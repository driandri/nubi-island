import AppKit
import AVFoundation
import CoreAudio
import SwiftUI

struct PlayerArtwork: View {
    @ObservedObject var music: MusicModel
    let size: CGFloat
    let cornerRadius: CGFloat
    let tint: Color

    var body: some View {
        let placeholder = Image(systemName: music.source == .youtube ? "play.rectangle.fill" : "music.note")
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius).fill(tint.opacity(0.22))
            if let artwork = music.artwork {
                Image(nsImage: artwork).resizable().scaledToFill()
            } else if let url = music.artworkURL {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { placeholder }
            } else { placeholder }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .accessibilityHidden(true)
    }
}

struct PlaybackPillMotion: View {
    let animated: Bool
    let accent: Color
    let waveformColor: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let moving = animated && !reduceMotion
        TimelineView(.animation(minimumInterval: 0.12, paused: !moving)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 8) {
                NobiFace(blinking: moving && time.truncatingRemainder(dividingBy: 5) < 0.24,
                         outlined: true, tint: accent)
                    .frame(width: 34, height: 20)
                    .rotationEffect(.degrees(moving ? 4 * sin(time * 4) : 0))
                    .offset(y: moving ? sin(time * 4) : 0)
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { index in
                        let height = moving ? 4 + 10 * abs(sin(time * 8 + Double(index) * 1.45))
                            : CGFloat([7, 12, 6, 10, 5][index])
                        Capsule().fill(waveformColor).frame(width: 2, height: height)
                    }
                }.frame(width: 18, height: 14)
            }
        }.accessibilityHidden(true)
    }
}

private final class CameraPreviewHost: NSView {
    let preview: AVCaptureVideoPreviewLayer
    init(session: AVCaptureSession) {
        preview = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        preview.videoGravity = .resizeAspectFill
        layer?.addSublayer(preview)
    }
    required init?(coder: NSCoder) { nil }
    override func layout() { super.layout(); preview.frame = bounds }
}

struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> NSView {
        CameraPreviewHost(session: session)
    }
    func updateNSView(_ view: NSView, context: Context) { view.needsLayout = true }
}

struct TimerPanel: View {
    @ObservedObject var timer: FocusTimerModel
    @State private var customMinutes = 15
    @State private var showsCustom = false
    private let orange = Color(red: 1, green: 0.61, blue: 0.31)
    var body: some View {
        VStack(spacing: 15) {
            Picker("Timer mode", selection: Binding(get: { timer.mode }, set: { timer.setMode($0) })) {
                ForEach(FocusTimerModel.Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().frame(width: 190)
            if timer.phase == .idle {
                VStack(spacing: 3) {
                    Text(timer.mode == .standard ? "Set a Timer" : "Pomodoro")
                        .font(.system(size: 16, weight: .bold))
                    Text(timer.mode == .standard ? "Pick a duration to start a countdown" : "25 min focus · 5 min break · long break after 4")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.48))
                }
                if timer.mode == .standard {
                    HStack(spacing: 8) {
                        ForEach([1, 2, 3, 5, 10, 25], id: \.self) { minutes in
                            Button { timer.start(seconds: Double(minutes * 60)) } label: {
                                VStack(spacing: 0) {
                                    Text("\(minutes)").font(.system(size: 21, weight: .bold))
                                    Text("min").font(.system(size: 9)).foregroundStyle(.white.opacity(0.55))
                                }.frame(width: 54, height: 54).background(.white.opacity(0.11), in: Circle())
                            }.buttonStyle(.plain)
                        }
                    }
                    Button { showsCustom.toggle() } label: { Label("Custom · \(customMinutes) minutes", systemImage: "slider.horizontal.3") }
                        .buttonStyle(.plain).font(.system(size: 11)).padding(.horizontal, 14).padding(.vertical, 5)
                        .background(.white.opacity(0.09), in: Capsule())
                    if showsCustom {
                        HStack {
                            Stepper("\(customMinutes) minutes", value: $customMinutes, in: 1...180)
                            Button("Start") { timer.start(seconds: Double(customMinutes * 60)) }
                        }.font(.system(size: 11)).frame(maxWidth: 280)
                    }
                } else {
                    Button { timer.startPomodoro() } label: { Label("Start focus", systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent).tint(orange)
                }
            } else {
                HStack(spacing: 16) {
                    ZStack {
                        Circle().stroke(.white.opacity(0.12), lineWidth: 5)
                        Circle().trim(from: 0, to: timer.progress).stroke(orange, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: timer.stage == .focus ? "timer" : "cup.and.saucer.fill")
                    }.frame(width: 70, height: 70).foregroundStyle(orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(timer.mode == .pomodoro ? timer.stageLabel.uppercased() : "TIMER")
                            .font(.system(size: 10, weight: .bold)).tracking(1.2).foregroundStyle(.white.opacity(0.55))
                        Text(timer.label).font(.system(size: 29, weight: .bold)).monospacedDigit()
                        if timer.mode == .pomodoro {
                            Text("\(timer.completedFocusSessions) focus sessions complete")
                                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                        }
                    }
                    Spacer()
                    if timer.phase == .finished && timer.mode == .pomodoro {
                        Button("Start \(timer.nextStageLabel)") { timer.advancePomodoro() }
                            .buttonStyle(.borderedProminent).tint(orange)
                    } else if timer.phase != .finished {
                        Button { timer.phase == .running ? timer.pause() : timer.resume() } label: {
                            Image(systemName: timer.phase == .running ? "pause.fill" : "play.fill")
                        }.buttonStyle(.bordered)
                    }
                    Button { timer.reset() } label: { Image(systemName: "stop.fill") }
                        .buttonStyle(.bordered).accessibilityLabel("Reset timer")
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MixerPanel: View {
    @ObservedObject var mixer: SoundMixerModel
    @ObservedObject var capturePreview: CapturePreviewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SOUND MIXER").font(.system(size: 11, weight: .bold)).tracking(1.2)
                Spacer()
                Button("Reset") { mixer.resetGains() }.foregroundStyle(.cyan)
            }
            HStack(spacing: 12) {
                devicePicker("Output", selected: mixer.selectedOutput, devices: mixer.outputDevices, action: mixer.selectOutput)
                devicePicker("Input", selected: mixer.selectedInput, devices: mixer.inputDevices, action: mixer.selectInput)
            }
            levelRow("System", value: mixer.systemVolume, action: mixer.setSystemVolume)
            levelRow("Input gain", value: mixer.inputGain, action: mixer.setInputGain)
            HStack(spacing: 8) {
                Text("Mic meter").frame(width: 75, alignment: .leading)
                ProgressView(value: Double(capturePreview.microphoneLevel)).tint(.cyan)
                Button(capturePreview.microphoneActive ? "Stop" : "Aktifkan") {
                    if capturePreview.microphoneActive { capturePreview.stopMicrophone() }
                    else { Task { await capturePreview.startMicrophone() } }
                }.foregroundStyle(.cyan)
            }
            Text(capturePreview.microphoneStatus).font(.system(size: 9)).foregroundStyle(.white.opacity(0.55))
            Divider().overlay(.white.opacity(0.18))
            HStack {
                Text("APPLICATIONS").font(.system(size: 9, weight: .bold)).tracking(1.2).foregroundStyle(.white.opacity(0.5))
                Spacer()
                if mixer.enabled {
                    Button(mixer.sessionActive ? "Retry" : "Mulai") { mixer.retry() }.foregroundStyle(.cyan)
                }
                Toggle("Mix apps", isOn: Binding(get: { mixer.enabled }, set: { mixer.setEnabled($0) }))
                    .toggleStyle(.switch).font(.system(size: 10))
            }
            if mixer.applications.isEmpty { Text("No applications are producing audio").foregroundStyle(.white.opacity(0.48)) }
            ScrollView {
                VStack(spacing: 7) {
                    ForEach(mixer.applications) { app in
                        HStack(spacing: 8) {
                            if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 18, height: 18) }
                            else { Image(systemName: "app.fill").frame(width: 18) }
                            Text(app.name).lineLimit(1).frame(width: 90, alignment: .leading)
                            Slider(value: Binding(get: { Double(app.gain) }, set: { mixer.setGain(Int($0), for: app.id) }), in: 0...100)
                                .tint(.cyan).disabled(!mixer.enabled || !app.available)
                            Text("\(app.gain)%").monospacedDigit().frame(width: 36, alignment: .trailing)
                        }
                        if let detail = app.detail { Text(detail).font(.system(size: 9)).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading) }
                    }
                }
            }.frame(maxHeight: 125)
            Text(mixer.status).font(.system(size: 9)).foregroundStyle(.white.opacity(0.55)).lineLimit(2)
        }.font(.system(size: 11)).buttonStyle(.plain)
    }
    private func devicePicker(_ title: String, selected: AudioObjectID, devices: [MixerDevice], action: @escaping (AudioObjectID) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 9)).foregroundStyle(.white.opacity(0.55))
            Picker(title, selection: Binding(get: { selected }, set: { action($0) })) {
                ForEach(devices) { device in Text(device.name).tag(device.id) }
            }.labelsHidden().frame(maxWidth: .infinity)
        }
    }
    private func levelRow(_ title: String, value: Int?, action: @escaping (Int) -> Void) -> some View {
        HStack {
            Text(title).frame(width: 75, alignment: .leading)
            if let value {
                Slider(value: Binding(get: { Double(value) }, set: { action(Int($0)) }), in: 0...100).tint(.cyan)
                Text("\(value)%").monospacedDigit().frame(width: 35, alignment: .trailing)
            } else { Text("Unavailable on this device").foregroundStyle(.white.opacity(0.4)); Spacer() }
        }
    }
}

struct LauncherPanel: View {
    @ObservedObject var launcher: LauncherModel
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LAUNCHER").font(.system(size: 11, weight: .bold)).tracking(1.2)
            TextField("Search installed applications", text: $query).textFieldStyle(.roundedBorder).focused($searchFocused)
            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(launcher.results(for: query)) { app in
                        HStack(spacing: 9) {
                            Button { launcher.open(app) } label: {
                              HStack(spacing: 9) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 22, height: 22)
                                Text(app.name)
                                Spacer()
                                Image(systemName: "arrow.up.right").foregroundStyle(.white.opacity(0.35))
                              }
                            }.buttonStyle(.plain)
                            if launcher.isPinned(app) {
                                Button { launcher.movePinned(app, by: -1) } label: { Image(systemName: "chevron.up") }
                                    .disabled(launcher.pinnedIDs.first == app.id)
                                Button { launcher.movePinned(app, by: 1) } label: { Image(systemName: "chevron.down") }
                                    .disabled(launcher.pinnedIDs.last == app.id)
                            }
                            Button { launcher.togglePin(app) } label: {
                                Image(systemName: launcher.isPinned(app) ? "pin.fill" : "pin")
                            }.accessibilityLabel(launcher.isPinned(app) ? "Unpin \(app.name)" : "Pin \(app.name)")
                        }.padding(6).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            if let error = launcher.error { Text(error).foregroundStyle(.orange) }
        }.font(.system(size: 11)).onAppear { launcher.refresh(); searchFocused = true }
    }
}

struct QuickActionsPanel: View {
    let perform: (QuickActionID) -> Void
    @ObservedObject private var snap = WindowSnapController.shared
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("QUICK ACTIONS").font(.system(size: 11, weight: .bold)).tracking(1.2)
            TextField("Cari perintah…", text: $query).textFieldStyle(.roundedBorder).focused($searchFocused)
                .onSubmit { if let first = QuickActionID.search(query).first { perform(first) } }
            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(QuickActionID.search(query)) { action in
                        Button { perform(action) } label: {
                            Label(action.title, systemImage: action.symbol)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(7).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                }
            }
            Text("⌘K membuka palette saat panel aktif · \(snap.status)")
                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.55))
        }.font(.system(size: 11)).onAppear { searchFocused = true }
    }
}

struct TodoPanel: View {
    @ObservedObject var todos: TodoModel
    @State private var draft = ""
    @FocusState private var entryFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("TO-DO").font(.system(size: 11, weight: .bold)).tracking(1.2); Spacer(); Text("\(todos.openCount) open").foregroundStyle(.white.opacity(0.5)) }
            HStack {
                TextField("Add a task", text: $draft).textFieldStyle(.roundedBorder).focused($entryFocused)
                    .onSubmit(add)
                Button { add() } label: { Image(systemName: "plus.circle.fill") }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(todos.items) { item in
                        HStack(spacing: 8) {
                            Button { todos.toggle(item.id) } label: { Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle") }
                                .accessibilityLabel(item.isComplete ? "Mark incomplete" : "Complete task")
                            Text(item.title).strikethrough(item.isComplete).foregroundStyle(item.isComplete ? .white.opacity(0.4) : .white)
                            Spacer()
                            Button { todos.remove(item.id) } label: { Image(systemName: "trash") }.accessibilityLabel("Delete task")
                        }.padding(7).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            if todos.items.isEmpty { Text("Add your first task").foregroundStyle(.white.opacity(0.48)) }
            if let error = todos.error { Text(error).foregroundStyle(.orange) }
        }.font(.system(size: 11)).buttonStyle(.plain).onAppear { entryFocused = true }
    }
    private func add() { todos.add(draft); draft = "" }
}

struct CalculatorPanel: View {
    @State private var calculator = CalculatorEngine()
    @FocusState private var focused: Bool
    private let rows = [["C", "±", "%", "÷"], ["7", "8", "9", "×"], ["4", "5", "6", "−"], ["1", "2", "3", "+"], ["⌫", "0", ".", "="]]
    var body: some View {
        VStack(spacing: 9) {
            Text("CALCULATOR").font(.system(size: 11, weight: .bold)).tracking(1.2).frame(maxWidth: .infinity, alignment: .leading)
            Text(calculator.display).font(.system(size: 30, weight: .medium)).monospacedDigit().lineLimit(1)
                .minimumScaleFactor(0.5).frame(maxWidth: .infinity, alignment: .trailing)
            if let error = calculator.error { Text(error).font(.system(size: 9)).foregroundStyle(.orange) }
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 7) {
                    ForEach(row, id: \.self) { key in
                        Button { calculator.input(key) } label: {
                            Text(key).frame(maxWidth: .infinity).frame(height: 33)
                                .background(key == "=" ? .orange : .white.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
        .focusable().focused($focused).onAppear { focused = true }
        .onKeyPress { press in
            let key = String(press.characters)
            let mapped: String
            switch key { case "-": mapped = "−"; case "*": mapped = "×"; case "/": mapped = "÷"; case "\r": mapped = "="; default: mapped = key }
            if rows.flatMap({ $0 }).contains(mapped) { calculator.input(mapped); return .handled }
            if press.key == .delete { calculator.input("⌫"); return .handled }
            if press.key == .escape { calculator.input("C"); return .handled }
            return .ignored
        }
    }
}
