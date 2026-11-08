import SwiftUI

struct PrayerPanel: View {
    @ObservedObject var prayer: PrayerTimesModel
    @ObservedObject var weather: WeatherModel
    var openSettings: () -> Void
    @State private var selectedName: String?
    private let gold = Color(red: 0.96, green: 0.77, blue: 0.38)
    private let surface = Color(red: 0.10, green: 0.11, blue: 0.14)

    private var selectedIndex: Int {
        schedule.firstIndex(where: { $0.name == selectedName })
            ?? schedule.firstIndex(where: { $0.id == prayer.nextPrayer?.id }) ?? 0
    }
    private var selected: PrayerTime? { schedule.indices.contains(selectedIndex) ? schedule[selectedIndex] : nil }
    private var schedule: [PrayerTime] {
        (prayer.times + (prayer.sunrise.map { [$0] } ?? [])).sorted { $0.date < $1.date }
    }
    private var timeZone: TimeZone {
        TimeZone(identifier: weather.resolvedLocation?.timeZoneID ?? "") ?? .current
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "moon.stars.fill")
                    .foregroundStyle(gold)
                    .frame(width: 28, height: 28)
                    .background(gold.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Waktu sholat").font(.system(size: 14, weight: .semibold))
                    Text(weather.resolvedLocation?.name ?? "Pilih kota")
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.72)).lineLimit(1)
                }
                Spacer()
                Button { prayer.refresh(force: true) } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 26, height: 26)
                }
                    .accessibilityLabel("Perbarui jadwal sholat")
            }
            if let selected {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(dateLabel(for: selected.date))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.78))
                            Label(weather.resolvedLocation?.name ?? "", systemImage: "location.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.92))
                        }
                        Spacer()
                        Button { openSettings() } label: {
                            Label("Pengaturan", systemImage: "gearshape")
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(.white.opacity(0.12), in: Capsule())
                        }
                    }
                    if let sunrise = prayer.sunrise,
                       let sunset = prayer.times.first(where: { $0.name == "Magrib" }) {
                        PrayerSunArc(progress: sunProgress(from: sunrise.date, to: sunset.date), gold: gold)
                            .frame(height: 100)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Lintasan matahari dari Terbit \(sunrise.displayTime) sampai Magrib \(sunset.displayTime)")
                    }
                    VStack(spacing: 3) {
                        Text(prayer.nextPrayer?.id == selected.id ? "BERIKUTNYA  \(selected.name)" : "JADWAL  \(selected.name)")
                            .font(.system(size: 10, weight: .bold)).tracking(0.6)
                            .foregroundStyle(gold)
                        Text(selected.displayTime)
                            .font(.system(size: 35, weight: .medium, design: .rounded))
                            .monospacedDigit()
                        Text(countdown(to: selected.date, name: selected.name))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.76))
                    }
                    .frame(maxWidth: .infinity)
                    Rectangle().fill(.white.opacity(0.22)).frame(height: 1)
                    HStack(spacing: 5) {
                        ForEach(schedule) { item in
                            Button { selectedName = item.name } label: {
                                timeTile(item, selected: item.id == selected.id)
                            }
                            .accessibilityLabel("\(item.name), \(item.displayTime)")
                            .accessibilityAddTraits(item.id == selected.id ? .isSelected : [])
                        }
                    }
                    Text("AlAdhan · metode Kemenag. Waktu masjid setempat dapat berbeda.")
                        .font(.system(size: 9)).foregroundStyle(.white.opacity(0.72))
                }
                .padding(12)
                .background(surface, in: RoundedRectangle(cornerRadius: 18))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(prayer.loading ? "Memuat jadwal sholat…" :
                         weather.resolvedLocation == nil ? "Pilih kota untuk melihat jadwal sholat." : "Jadwal belum tersedia. Coba perbarui.")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.75))
                    Button("Atur kota") { openSettings() }.foregroundStyle(.cyan)
                    if weather.resolvedLocation != nil {
                        Button("Coba lagi") { prayer.refresh(force: true) }.foregroundStyle(gold)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
                .padding(12)
                .background(surface, in: RoundedRectangle(cornerRadius: 18))
            }
        }
        .foregroundStyle(.white)
        .buttonStyle(.plain)
    }

    private func timeTile(_ item: PrayerTime, selected: Bool) -> some View {
        VStack(spacing: 5) {
            Text(item.displayTime).font(.system(size: 10, weight: .semibold)).monospacedDigit()
            Image(systemName: symbol(for: item.name)).font(.system(size: 16))
                .foregroundStyle(selected ? gold : .white.opacity(0.78))
            Text(item.name).font(.system(size: 10, weight: selected ? .semibold : .medium))
        }
        .frame(maxWidth: .infinity, minHeight: 62)
        .foregroundStyle(selected ? .white : .white.opacity(0.78))
        .background(selected ? gold.opacity(0.16) : .white.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(selected ? gold : .white.opacity(0.35), lineWidth: 1))
    }
    private func symbol(for name: String) -> String {
        switch name {
        case "Subuh": "sunrise.fill"
        case "Terbit": "sun.horizon.fill"
        case "Zuhur": "sun.max.fill"
        case "Asar": "cloud.sun.fill"
        case "Magrib": "sunset.fill"
        default: "moon.stars.fill"
        }
    }
    private func dateLabel(for date: Date) -> String {
        let gregorian = DateFormatter()
        gregorian.locale = Locale(identifier: "id_ID")
        gregorian.timeZone = timeZone
        gregorian.dateFormat = "EEEE, d MMMM"
        let hijri = DateFormatter()
        hijri.calendar = Calendar(identifier: .islamicUmmAlQura)
        hijri.locale = Locale(identifier: "id_ID")
        hijri.timeZone = timeZone
        hijri.dateFormat = "d MMMM yyyy"
        return "\(gregorian.string(from: date)) · \(hijri.string(from: date)) H"
    }
    private func sunProgress(from sunrise: Date, to sunset: Date) -> Double {
        min(1, max(0, prayer.now.timeIntervalSince(sunrise) / max(1, sunset.timeIntervalSince(sunrise))))
    }
    private func countdown(to date: Date, name: String) -> String {
        let seconds = Int(date.timeIntervalSince(prayer.now))
        if seconds <= 0 { return seconds > -90 ? (name == "Terbit" ? "Waktu terbit" : "Saatnya sholat") : "Sudah lewat" }
        let minutes = max(1, Int(ceil(Double(seconds) / 60)))
        return minutes >= 60 ? "dalam \(minutes / 60) j \(minutes % 60) m" : "dalam \(minutes) menit"
    }
}

private struct PrayerSunArc: View {
    let progress: Double
    let gold: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let t = CGFloat(progress)
            let point = CGPoint(x: 20 + (width - 40) * t,
                                y: 75 - 264 * t * (1 - t))
            let arc = Path { path in
                path.move(to: CGPoint(x: 20, y: 75))
                path.addQuadCurve(to: CGPoint(x: width - 20, y: 75),
                                  control: CGPoint(x: width / 2, y: -57))
            }
            arc.stroke(.white.opacity(0.48), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            arc.trimmedPath(from: 0, to: progress)
                .stroke(gold, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            Image(systemName: "sun.max.fill")
                .font(.system(size: 23))
                .foregroundStyle(gold)
                .shadow(color: gold.opacity(0.8), radius: 10)
                .position(point)
            Text("Terbit").position(x: 37, y: 92)
            Text("Magrib").position(x: width - 37, y: 92)
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(.white.opacity(0.75))
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
