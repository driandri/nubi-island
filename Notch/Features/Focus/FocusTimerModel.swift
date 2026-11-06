import Foundation
import Combine

@MainActor
final class FocusTimerModel: ObservableObject {
    enum Phase { case idle, running, paused, finished }
    enum Mode: String, CaseIterable { case standard = "Standard", pomodoro = "Pomodoro" }
    enum Stage { case focus, shortBreak, longBreak }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var mode: Mode = .standard
    @Published private(set) var stage: Stage = .focus
    @Published private(set) var completedFocusSessions = 0
    @Published private(set) var remainingSeconds = 0
    @Published private(set) var totalSeconds = 0
    private var remaining: TimeInterval = 0
    private var deadline: ContinuousClock.Instant?
    private var task: Task<Void, Never>?
    private let now: () -> ContinuousClock.Instant
    private let tickInterval: Duration

    init(tickInterval: Duration = .seconds(1), now: @escaping () -> ContinuousClock.Instant = { .now }) {
        self.now = now
        self.tickInterval = tickInterval
    }

    var label: String {
        if phase == .finished { return mode == .pomodoro ? "Stage done" : "Focus done" }
        return String(format: "%02d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }
    var stageLabel: String {
        switch stage {
        case .focus: return "Focus"
        case .shortBreak: return "Short break"
        case .longBreak: return "Long break"
        }
    }
    var nextStageLabel: String {
        guard mode == .pomodoro else { return "" }
        if stage == .focus { return completedFocusSessions.isMultiple(of: 4) ? "Long break" : "Short break" }
        return "Focus"
    }
    func setMode(_ newMode: Mode) {
        guard mode != newMode else { return }
        reset()
        mode = newMode
    }
    func startPomodoro() {
        mode = .pomodoro
        stage = .focus
        completedFocusSessions = 0
        start(seconds: 25 * 60)
    }
    func advancePomodoro() {
        guard mode == .pomodoro, phase == .finished else { return }
        if stage == .focus {
            stage = completedFocusSessions.isMultiple(of: 4) ? .longBreak : .shortBreak
        } else { stage = .focus }
        start(seconds: Double(stage == .focus ? 25 * 60 : stage == .longBreak ? 15 * 60 : 5 * 60))
    }
    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return min(1, max(0, 1 - Double(remainingSeconds) / Double(totalSeconds)))
    }

    func start(seconds: TimeInterval) {
        guard seconds.isFinite, seconds > 0 else { return }
        if mode == .standard { stage = .focus }
        task?.cancel()
        remaining = min(seconds, 10800)
        totalSeconds = Int(ceil(remaining))
        remainingSeconds = Int(ceil(remaining))
        deadline = now().advanced(by: .seconds(remaining))
        phase = .running
        schedule()
    }

    func pause() {
        guard phase == .running else { return }
        refresh()
        guard phase == .running else { return }
        task?.cancel(); task = nil
        deadline = nil
        phase = .paused
    }

    func resume() {
        guard phase == .paused else { return }
        deadline = now().advanced(by: .seconds(remaining))
        phase = .running
        schedule()
    }

    func reset() {
        task?.cancel(); task = nil
        deadline = nil; remaining = 0; remainingSeconds = 0; totalSeconds = 0
        phase = .idle
        stage = .focus
        completedFocusSessions = 0
    }

    // Derive time from a monotonic deadline, not the number of timer callbacks.
    // ContinuousClock includes time spent asleep and ignores wall-clock edits.
    func refresh() {
        guard phase == .running, let deadline else { return }
        let delta = now().duration(to: deadline).components
        remaining = max(0, Double(delta.seconds) + Double(delta.attoseconds) / 1e18)
        remainingSeconds = Int(ceil(remaining))
        if remaining == 0 {
            self.deadline = nil
            if mode == .pomodoro && stage == .focus { completedFocusSessions += 1 }
            phase = .finished
            task?.cancel(); task = nil
        }
    }

    private func schedule() {
        task?.cancel()
        let interval = tickInterval
        task = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: interval) } catch { return }
                guard let self, self.phase == .running else { return }
                self.refresh()
            }
        }
    }
}
