import AppKit
import Combine
import CoreLocation
import Foundation

struct WeatherSnapshot: Equatable {
    let place: String
    let temperature: Int
    let description: String
    let symbol: String
    let fetchedAt: Date
}

struct WeatherLocation: Equatable {
    let latitude: Double
    let longitude: Double
    let name: String
    let timeZoneID: String
}

@MainActor
final class WeatherModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var status = "Choose a city or enable location"
    @Published private(set) var loading = false
    @Published private(set) var manualCity: String
    @Published private(set) var resolvedLocation: WeatherLocation?
    private let defaults: UserDefaults
    private let location = CLLocationManager()
    private var request: Task<Void, Never>?
    private var coordinates: (Double, Double)?
    private static let cityKey = "notch.weather.city"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        manualCity = defaults.string(forKey: Self.cityKey) ?? ""
        super.init()
        location.delegate = self
        if !manualCity.isEmpty { refresh() }
    }
    func setCity(_ value: String) {
        let city = value.trimmingCharacters(in: .whitespacesAndNewlines)
        manualCity = city
        defaults.set(city, forKey: Self.cityKey)
        coordinates = nil; snapshot = nil; resolvedLocation = nil
        refresh()
    }
    func requestLocation() {
        switch location.authorizationStatus {
        case .authorizedAlways: location.requestLocation()
        case .notDetermined: location.requestWhenInUseAuthorization()
        case .denied, .restricted: status = "Location denied. Enter a city instead."
        @unknown default: status = "Location is unavailable"
        }
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let authorization = manager.authorizationStatus
        Task { @MainActor in
            if authorization == .authorizedAlways {
                location.requestLocation()
            } else if authorization == .denied { status = "Location denied. Enter a city instead." }
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let point = locations.last else { return }
        let latitude = point.coordinate.latitude
        let longitude = point.coordinate.longitude
        Task { @MainActor in
            coordinates = (latitude, longitude)
            refresh(force: true)
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in status = "Location unavailable. Enter a city instead." }
    }
    func refresh(force: Bool = false) {
        if !force, let snapshot, Date().timeIntervalSince(snapshot.fetchedAt) < 900 { return }
        guard coordinates != nil || !manualCity.isEmpty else { status = "Choose a city or enable location"; return }
        request?.cancel(); loading = true; status = "Loading Open-Meteo…"
        request = Task { [weak self] in
            guard let self else { return }
            do {
                let point: WeatherLocation
                if let coordinates {
                    point = WeatherLocation(latitude: coordinates.0, longitude: coordinates.1,
                                            name: "Current location", timeZoneID: TimeZone.current.identifier)
                }
                else {
                    var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
                    components.queryItems = [URLQueryItem(name: "name", value: manualCity), URLQueryItem(name: "count", value: "1")]
                    let (data, _) = try await URLSession.shared.data(from: components.url!)
                    let result = try JSONDecoder().decode(GeocodingResponse.self, from: data)
                    guard let city = result.results?.first else { throw WeatherError.cityNotFound }
                    point = WeatherLocation(latitude: city.latitude, longitude: city.longitude,
                                            name: city.name, timeZoneID: city.timezone ?? TimeZone.current.identifier)
                }
                resolvedLocation = point
                var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
                components.queryItems = [URLQueryItem(name: "latitude", value: String(point.latitude)),
                                         URLQueryItem(name: "longitude", value: String(point.longitude)),
                                         URLQueryItem(name: "current", value: "temperature_2m,weather_code")]
                let (data, _) = try await URLSession.shared.data(from: components.url!)
                let result = try JSONDecoder().decode(ForecastResponse.self, from: data)
                guard !Task.isCancelled else { return }
                let code = result.current.weather_code
                let condition: (String, String) = switch code {
                case 0: ("Clear", "sun.max.fill")
                case 1...3: ("Cloudy", "cloud.sun.fill")
                case 45...48: ("Fog", "cloud.fog.fill")
                case 51...67, 80...82: ("Rain", "cloud.rain.fill")
                case 71...77, 85...86: ("Snow", "cloud.snow.fill")
                case 95...99: ("Thunderstorm", "cloud.bolt.rain.fill")
                default: ("Weather", "cloud.fill")
                }
                snapshot = WeatherSnapshot(place: point.name, temperature: Int(result.current.temperature_2m.rounded()),
                                           description: condition.0, symbol: condition.1, fetchedAt: Date())
                status = "Updated · Open-Meteo"; loading = false
            } catch {
                guard !Task.isCancelled else { return }
                status = error is WeatherError ? "City not found" : "Weather unavailable. Try again."
                loading = false
            }
        }
    }
    func stop() { request?.cancel(); location.stopUpdatingLocation() }
}

private enum WeatherError: Error { case cityNotFound }
private struct GeocodingResponse: Decodable {
    struct City: Decodable { let name: String; let latitude: Double; let longitude: Double; let timezone: String? }
    let results: [City]?
}
private struct ForecastResponse: Decodable {
    struct Current: Decodable { let temperature_2m: Double; let weather_code: Int }
    let current: Current
}

struct PrayerTime: Equatable, Identifiable {
    let name: String
    let date: Date
    let displayTime: String
    var id: String { name }
}

enum PrayerTimeParser {
    static func sunrise(_ values: [String: String], day: String, timeZone: TimeZone) -> PrayerTime? {
        guard let raw = values["Sunrise"] else { return nil }
        let time = DateFormatter()
        time.timeZone = timeZone; time.locale = Locale(identifier: "en_US_POSIX")
        time.dateFormat = "dd-MM-yyyy HH:mm"
        guard let date = time.date(from: "\(day) \(raw.prefix(5))") else { return nil }
        return PrayerTime(name: "Terbit", date: date, displayTime: String(raw.prefix(5)))
    }

    static func times(_ values: [String: String], day: String, timeZone: TimeZone) -> [PrayerTime] {
        let time = DateFormatter()
        time.timeZone = timeZone; time.locale = Locale(identifier: "en_US_POSIX")
        time.dateFormat = "dd-MM-yyyy HH:mm"
        return [("Subuh", "Fajr"), ("Zuhur", "Dhuhr"), ("Asar", "Asr"),
                ("Magrib", "Maghrib"), ("Isya", "Isha")].compactMap { name, key in
            guard let raw = values[key], let date = time.date(from: "\(day) \(raw.prefix(5))") else { return nil }
            return PrayerTime(name: name, date: date, displayTime: String(raw.prefix(5)))
        }.sorted { $0.date < $1.date }
    }
}

@MainActor
final class PrayerTimesModel: ObservableObject {
    @Published private(set) var times: [PrayerTime] = []
    @Published private(set) var sunrise: PrayerTime?
    @Published private(set) var status = "Set a city or enable location in Weather settings"
    @Published private(set) var loading = false
    @Published private(set) var now = Date()
    private let weather: WeatherModel
    private let session: URLSession
    private var subscriptions = Set<AnyCancellable>()
    private var request: Task<Void, Never>?
    private var timer: Timer?
    private var cachedDay: String?
    private var cachedLocation: WeatherLocation?

    init(weather: WeatherModel, session: URLSession = .shared) {
        self.weather = weather; self.session = session
        weather.$resolvedLocation.removeDuplicates().sink { [weak self] location in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if location != self.cachedLocation { self.times = []; self.sunrise = nil; self.cachedDay = nil }
                self.refresh()
            }
        }.store(in: &subscriptions)
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.now = Date()
                self.refresh()
            }
        }
    }
    var nextPrayer: PrayerTime? { times.first { $0.date > now } }
    func refresh(force: Bool = false) {
        guard let location = weather.resolvedLocation else {
            request?.cancel(); times = []; sunrise = nil; status = "Set a city or enable location in Weather settings"; loading = false
            return
        }
        let zone = TimeZone(identifier: location.timeZoneID) ?? .current
        let formatter = DateFormatter()
        formatter.timeZone = zone; formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd-MM-yyyy"
        let day = formatter.string(from: now)
        if !force, cachedDay == day, cachedLocation == location, nextPrayer != nil { return }
        if loading && !force { return }
        request?.cancel(); loading = true; status = "Loading prayer times…"
        request = Task { [weak self] in
            guard let self else { return }
            do {
                var fetched = try await self.fetch(day: day, location: location, zone: zone)
                if fetched.times.allSatisfy({ $0.date <= self.now }) {
                    let tomorrow = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: self.now) ?? self.now.addingTimeInterval(86_400)
                    fetched = try await self.fetch(day: formatter.string(from: tomorrow), location: location, zone: zone)
                }
                guard !Task.isCancelled else { return }
                self.times = fetched.times
                self.sunrise = fetched.sunrise
                self.cachedDay = day; self.cachedLocation = location
                self.status = "AlAdhan · Kemenag calculation (method 20)"
                self.loading = false
            } catch {
                guard !Task.isCancelled else { return }
                self.status = "Prayer times unavailable. Try again."
                self.loading = false
            }
        }
    }
    private func fetch(day: String, location: WeatherLocation, zone: TimeZone) async throws -> (times: [PrayerTime], sunrise: PrayerTime?) {
        var components = URLComponents(string: "https://api.aladhan.com/v1/timings/\(day)")!
        components.queryItems = [URLQueryItem(name: "latitude", value: String(location.latitude)),
                                 URLQueryItem(name: "longitude", value: String(location.longitude)),
                                 URLQueryItem(name: "method", value: "20")]
        let (data, response) = try await session.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw WeatherError.cityNotFound }
        let payload = try JSONDecoder().decode(PrayerAPIResponse.self, from: data)
        let responseZone = TimeZone(identifier: payload.data.meta.timezone) ?? zone
        let parsed = PrayerTimeParser.times(payload.data.timings, day: day, timeZone: responseZone)
        guard parsed.count == 5 else { throw WeatherError.cityNotFound }
        return (parsed, PrayerTimeParser.sunrise(payload.data.timings, day: day, timeZone: responseZone))
    }
    func stop() { request?.cancel(); timer?.invalidate(); timer = nil; subscriptions.removeAll() }
}

private struct PrayerAPIResponse: Decodable {
    struct DataValue: Decodable {
        struct Meta: Decodable { let timezone: String }
        let timings: [String: String]
        let meta: Meta
    }
    let data: DataValue
}

struct PrayerReminderEvent: Equatable {
    let prayer: PrayerTime
    let isDue: Bool
    let progress: Double
    var key: String { "\(prayer.name)-\(Int(prayer.date.timeIntervalSince1970))-\(isDue ? "due" : "soon")" }
}

enum PrayerReminderSchedule {
    static func events(times: [PrayerTime], now: Date, leadMinutes: Int) -> [PrayerReminderEvent] {
        times.flatMap { prayer -> [PrayerReminderEvent] in
            let remaining = prayer.date.timeIntervalSince(now)
            if remaining <= 0 && remaining > -90 { return [PrayerReminderEvent(prayer: prayer, isDue: true, progress: 1)] }
            if remaining > 0 && remaining <= Double(leadMinutes * 60) {
                return [PrayerReminderEvent(prayer: prayer, isDue: false,
                                            progress: 1 - remaining / Double(leadMinutes * 60))]
            }
            return []
        }
    }
}

@MainActor
final class PrayerReminderCoordinator {
    var onReminder: ((PrayerReminderEvent) -> Void)?
    private var seen = Set<String>()
    private var subscriptions = Set<AnyCancellable>()
    private let prayer: PrayerTimesModel
    private let leadMinutes: () -> Int
    private let enabled: () -> Bool

    init(prayer: PrayerTimesModel, leadMinutes: @escaping () -> Int, enabled: @escaping () -> Bool) {
        self.prayer = prayer; self.leadMinutes = leadMinutes; self.enabled = enabled
        prayer.$now.combineLatest(prayer.$times).sink { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.check() }
        }.store(in: &subscriptions)
    }
    func check() {
        guard enabled() else { return }
        for event in PrayerReminderSchedule.events(times: prayer.times, now: prayer.now,
                                                    leadMinutes: leadMinutes()) where seen.insert(event.key).inserted {
            onReminder?(event)
        }
    }
    func stop() { subscriptions.removeAll(); onReminder = nil }
}
