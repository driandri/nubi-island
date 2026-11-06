import SwiftUI

struct PrayerPanel: View {
    @ObservedObject var prayer: PrayerTimesModel
    @ObservedObject var weather: WeatherModel
    var openSettings: () -> Void
    @State private var selectedName: String?

    private var selectedIndex: Int {
        prayer.times.firstIndex(where: { $0.name == selectedName })
            ?? prayer.times.firstIndex(where: { $0.id == prayer.nextPrayer?.id }) ?? 0
    }
    private var selected: PrayerTime? { prayer.times.indices.contains(selectedIndex) ? prayer.times[selectedIndex] : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("SHOLAT").font(.system(size: 11, weight: .bold)).tracking(1.2)
                Text(weather.resolvedLocation?.name ?? "Belum ada kota")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                Spacer()
                Circle().stroke(.green, lineWidth: 2.5).frame(width: 12, height: 12)
                Text("5 waktu").font(.system(size: 10)).foregroundStyle(.white.opacity(0.63))
                Button { prayer.refresh(force: true) } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Perbarui jadwal sholat")
            }
            if let selected {
                HStack(spacing: 15) {
                    HStack(spacing: 8) {
                        Button { changeSelection(-1) } label: { Image(systemName: "chevron.left") }
                            .disabled(selectedIndex == 0).accessibilityLabel("Waktu sholat sebelumnya")
                        VStack(alignment: .leading, spacing: 3) {
                            Text(prayer.nextPrayer?.id == selected.id ? "BERIKUTNYA" : "JADWAL")
                                .font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
                            Text(selected.name).font(.system(size: 30, weight: .bold)).lineLimit(1)
                            HStack(spacing: 8) {
                                Text(selected.displayTime).font(.system(size: 14, weight: .semibold)).monospacedDigit()
                                Text(countdown(to: selected.date)).font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.cyan).lineLimit(1)
                            }
                            ProgressView(value: progress(to: selected.date))
                                .tint(.cyan).frame(maxWidth: 180)
                        }
                        Button { changeSelection(1) } label: { Image(systemName: "chevron.right") }
                            .disabled(selectedIndex == prayer.times.count - 1)
                            .accessibilityLabel("Waktu sholat berikutnya")
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Rectangle().fill(.white.opacity(0.16)).frame(width: 1)
                    VStack(spacing: 5) {
                        PrayerDayArc(times: prayer.times, selectedName: selected.name)
                            .frame(height: 79)
                        HStack(alignment: .top, spacing: 1) {
                            ForEach(prayer.times) { item in
                                VStack(spacing: 2) {
                                    Text(item.name).font(.system(size: 8, weight: item.id == selected.id ? .bold : .regular))
                                    Text(item.displayTime).font(.system(size: 7)).monospacedDigit()
                                }
                                .foregroundStyle(item.id == selected.id ? .white : .white.opacity(0.54))
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }.frame(maxWidth: .infinity)
                }.frame(height: 124)
                Text("AlAdhan · metode Kemenag. Jadwal masjid setempat dapat berbeda.")
                    .font(.system(size: 9)).foregroundStyle(.white.opacity(0.54))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(prayer.loading ? "Memuat jadwal sholat…" : prayer.status)
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.75))
                    Button("Atur kota") { openSettings() }.foregroundStyle(.cyan)
                }.frame(maxWidth: .infinity, minHeight: 124, alignment: .leading)
            }
        }
        .foregroundStyle(.white)
        .buttonStyle(.plain)
    }

    private func changeSelection(_ offset: Int) {
        let index = min(max(selectedIndex + offset, 0), prayer.times.count - 1)
        selectedName = prayer.times[index].name
    }
    private func countdown(to date: Date) -> String {
        let seconds = Int(date.timeIntervalSince(prayer.now))
        if seconds <= 0 { return seconds > -90 ? "Saatnya sholat" : "Sudah lewat" }
        let minutes = max(1, Int(ceil(Double(seconds) / 60)))
        return minutes >= 60 ? "dalam \(minutes / 60) j \(minutes % 60) m" : "dalam \(minutes) menit"
    }
    private func progress(to date: Date) -> Double {
        let previous = prayer.times.last(where: { $0.date < date })?.date
            ?? Calendar.current.startOfDay(for: date)
        return min(1, max(0, prayer.now.timeIntervalSince(previous) / max(1, date.timeIntervalSince(previous))))
    }
}

private struct PrayerDayArc: View {
    let times: [PrayerTime]
    let selectedName: String
    private let levels: [CGFloat] = [0.78, 0.43, 0.48, 0.16, 0.75]
    var body: some View {
        GeometryReader { geometry in
            let count = max(1, times.count - 1)
            let points = times.indices.map { index in
                CGPoint(x: 9 + (geometry.size.width - 18) * CGFloat(index) / CGFloat(count),
                        y: 8 + (geometry.size.height - 16) * levels[min(index, levels.count - 1)])
            }
            Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                for index in 1..<points.count {
                    let before = points[index - 1], after = points[index]
                    let middle = (before.x + after.x) / 2
                    path.addCurve(to: after, control1: CGPoint(x: middle, y: before.y),
                                  control2: CGPoint(x: middle, y: after.y))
                }
            }
            .stroke(LinearGradient(colors: [.cyan, .blue, .purple], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            ForEach(Array(times.enumerated()), id: \.element.id) { index, item in
                Circle().fill(item.name == selectedName ? .white : Color.white.opacity(0.75))
                    .frame(width: item.name == selectedName ? 10 : 5,
                           height: item.name == selectedName ? 10 : 5)
                    .shadow(color: item.name == selectedName ? .yellow : .clear, radius: 7)
                    .position(points[index])
            }
        }
        .accessibilityLabel("Ilustrasi urutan lima waktu sholat")
    }
}

struct WaterPanel: View {
    @ObservedObject var water: WaterReminderModel
    private var liters: String { WaterAmount.liters(water.todayML) }
    private var goalLiters: String { WaterAmount.liters(water.snapshot.goalML) }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label("WATER REMINDER", systemImage: "drop.fill")
                    .font(.system(size: 10, weight: .bold)).tracking(1)
                    .foregroundStyle(.cyan)
                Spacer()
                Toggle("Pengingat", isOn: Binding(get: { water.snapshot.enabled },
                                                  set: { water.setEnabled($0) }))
                    .toggleStyle(.switch).controlSize(.small)
            }
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(liters).font(.system(size: 31, weight: .bold)).monospacedDigit()
                        Text("/ \(goalLiters) L").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                    }
                    Text(water.goalReached ? "Hari ini · 100% · Target tercapai" : "Hari ini · \(Int((water.progress * 100).rounded()))% dari target")
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.66)).lineLimit(1)
                    ProgressView(value: water.progress).tint(.blue)
                    HStack(spacing: 5) {
                        Button { water.drink() } label: {
                            Label("Minum +\(water.snapshot.servingML) mL", systemImage: "drop.fill")
                        }.buttonStyle(.borderedProminent).tint(.blue)
                        Button { water.showingSettings.toggle() } label: {
                            Label("Pengaturan", systemImage: "slider.horizontal.3")
                        }.buttonStyle(.bordered)
                    }.controlSize(.small)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(.white.opacity(0.16)).frame(width: 1, height: 126)
                WaterHoursChart(drinks: water.todayDrinks)
                    .frame(maxWidth: .infinity, minHeight: 124)
            }
            if water.showingSettings {
                HStack(spacing: 9) {
                    Picker("Target", selection: Binding(get: { water.snapshot.goalML }, set: { water.setGoal($0) })) {
                        ForEach([1000, 1500, 2000, 2500, 3000], id: \.self) { value in Text("\(value) mL").tag(value) }
                    }
                    Picker("Sekali minum", selection: Binding(get: { water.snapshot.servingML }, set: { water.setServing($0) })) {
                        ForEach([100, 150, 200, 250, 300, 500], id: \.self) { value in Text("\(value) mL").tag(value) }
                    }
                    Picker("Interval", selection: Binding(get: { water.snapshot.intervalMinutes }, set: { water.setInterval($0) })) {
                        ForEach([30, 45, 60, 90, 120, 180], id: \.self) { value in Text("\(value) menit").tag(value) }
                    }
                }.font(.system(size: 9))
                HStack {
                    Text("Pengingat island aktif pukul 08.00–21.00 selama Nubi berjalan.")
                        .font(.system(size: 9)).foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Button("Urungkan minum terakhir") { water.undoLastDrink() }
                        .disabled(water.todayDrinks.isEmpty).font(.system(size: 9))
                }
            } else {
                Text(water.snapshot.enabled ? "Pengingat berikutnya: \(water.nextReminder?.formatted(.dateTime.hour().minute()) ?? "—")" : "Aktifkan pengingat bila ingin diingatkan minum.")
                    .font(.system(size: 9)).foregroundStyle(.white.opacity(0.56))
            }
        }
        .foregroundStyle(.white)
    }
}

private struct WaterHoursChart: View {
    let drinks: [WaterDrink]
    private let hours = Array(stride(from: 0, through: 21, by: 3))
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("HARI INI").font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(hours, id: \.self) { hour in
                    let amount = drinks.filter { (hour..<(hour + 3)).contains(Calendar.current.component(.hour, from: $0.date)) }
                        .reduce(0) { $0 + $1.milliliters }
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(amount > 0 ? Color.blue : Color.white.opacity(0.11))
                            .frame(height: CGFloat(max(5, min(58, amount / 10))))
                            .frame(height: 62, alignment: .bottom)
                        Text(String(format: "%02d", hour))
                            .font(.system(size: 8)).foregroundStyle(.white.opacity(0.5))
                    }.frame(maxWidth: .infinity)
                }
            }
            Text(drinks.isEmpty ? "Belum ada minum tercatat" : "\(drinks.count) kali minum tercatat")
                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.55))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Grafik minum hari ini, \(drinks.count) catatan")
    }
}
