import AppKit
import Combine
import Foundation

struct WaterDrink: Codable, Equatable, Identifiable {
    let id: UUID
    let date: Date
    let milliliters: Int
}

struct WaterSnapshot: Codable {
    var goalML = 1500
    var servingML = 250
    var intervalMinutes = 60
    var enabled = false
    var drinks: [WaterDrink] = []
}

enum WaterAmount {
    static func liters(_ milliliters: Int) -> String {
        let whole = milliliters / 1000
        let remainder = milliliters % 1000
        guard remainder != 0 else { return String(whole) }
        let fraction = String(format: "%03d", remainder)
            .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
        return "\(whole).\(fraction)"
    }
}

@MainActor
final class WaterReminderModel: ObservableObject {
    @Published private(set) var snapshot: WaterSnapshot
    @Published private(set) var now: Date
    @Published private(set) var nextReminder: Date? = nil
    @Published var showingSettings = false
    var onReminder: (() -> Void)?

    private let defaults: UserDefaults
    private let nowSource: () -> Date
    private let key = "nubi.water.v1"
    private var timer: Timer?

    init(defaults: UserDefaults = .standard, nowSource: @escaping () -> Date = Date.init,
         running: Bool = true) {
        self.defaults = defaults
        self.nowSource = nowSource
        now = nowSource()
        snapshot = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(WaterSnapshot.self, from: $0) }
            ?? WaterSnapshot()
        snapshot.goalML = min(5000, max(500, snapshot.goalML))
        snapshot.servingML = min(1000, max(100, snapshot.servingML))
        snapshot.intervalMinutes = min(180, max(30, snapshot.intervalMinutes))
        prune()
        if snapshot.enabled { nextReminder = now.addingTimeInterval(Double(snapshot.intervalMinutes * 60)) }
        if running {
            timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.tick() }
            }
        }
    }

    var todayDrinks: [WaterDrink] { snapshot.drinks.filter { Calendar.current.isDate($0.date, inSameDayAs: now) } }
    var todayML: Int { todayDrinks.reduce(0) { $0 + $1.milliliters } }
    var progress: Double { min(1, Double(todayML) / Double(snapshot.goalML)) }
    var goalReached: Bool { todayML >= snapshot.goalML }

    func drink(_ amount: Int? = nil) {
        let value = min(1000, max(100, amount ?? snapshot.servingML))
        now = nowSource()
        snapshot.drinks.append(WaterDrink(id: UUID(), date: now, milliliters: value))
        nextReminder = snapshot.enabled ? now.addingTimeInterval(Double(snapshot.intervalMinutes * 60)) : nil
        save()
    }
    func undoLastDrink() {
        guard let last = todayDrinks.last,
              let index = snapshot.drinks.firstIndex(where: { $0.id == last.id }) else { return }
        snapshot.drinks.remove(at: index)
        save()
    }
    func setGoal(_ value: Int) { snapshot.goalML = min(5000, max(500, value)); save() }
    func setServing(_ value: Int) { snapshot.servingML = min(1000, max(100, value)); save() }
    func setInterval(_ value: Int) {
        snapshot.intervalMinutes = min(180, max(30, value))
        nextReminder = snapshot.enabled ? nowSource().addingTimeInterval(Double(snapshot.intervalMinutes * 60)) : nil
        save()
    }
    func setEnabled(_ enabled: Bool) {
        snapshot.enabled = enabled
        nextReminder = enabled ? nowSource().addingTimeInterval(Double(snapshot.intervalMinutes * 60)) : nil
        save()
    }
    func tick(at date: Date? = nil) {
        now = date ?? nowSource()
        prune()
        guard snapshot.enabled, let nextReminder, now >= nextReminder else { return }
        let hour = Calendar.current.component(.hour, from: now)
        guard (8..<21).contains(hour) else { return }
        self.nextReminder = now.addingTimeInterval(Double(snapshot.intervalMinutes * 60))
        guard !goalReached else { return }
        onReminder?()
    }
    func stop() { timer?.invalidate(); timer = nil; onReminder = nil }

    private func prune() {
        let oldest = Calendar.current.date(byAdding: .day, value: -6,
                                           to: Calendar.current.startOfDay(for: now)) ?? now
        let count = snapshot.drinks.count
        snapshot.drinks.removeAll { $0.date < oldest }
        if snapshot.drinks.count != count { save() }
    }
    private func save() { defaults.set(try? JSONEncoder().encode(snapshot), forKey: key) }
}
