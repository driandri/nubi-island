import AppKit
import Combine
import CoreAudio
import AudioToolbox
import Foundation
import os.lock

struct MixerDevice: Identifiable, Equatable {
    let id: AudioObjectID
    let name: String
}

struct MixerApplication: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: NSImage?
    let processCount: Int
    let available: Bool
    let detail: String?
    var gain: Int
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.processCount == rhs.processCount &&
        lhs.available == rhs.available && lhs.detail == rhs.detail && lhs.gain == rhs.gain
    }
}

private final class MixerRoute: @unchecked Sendable {
    let tap: AudioObjectID
    let aggregate: AudioObjectID
    private var gainLock = os_unfair_lock_s()
    private var gainValue: Float
    private var lastRealtimeGain: Float
    private var callbackCount: UInt64 = 0
    private var audibleSamples = false
    let startedAt = Date()
    var ioProc: AudioDeviceIOProcID?
    var context: UnsafeMutableRawPointer?
    init(tap: AudioObjectID, aggregate: AudioObjectID, gain: Float) {
        self.tap = tap; self.aggregate = aggregate
        self.gainValue = gain; self.lastRealtimeGain = gain
    }
    func setGain(_ value: Float) {
        os_unfair_lock_lock(&gainLock)
        gainValue = value
        os_unfair_lock_unlock(&gainLock)
    }
    func realtimeGain() -> Float {
        if os_unfair_lock_trylock(&gainLock) {
            lastRealtimeGain = gainValue
            callbackCount &+= 1
            os_unfair_lock_unlock(&gainLock)
        }
        return lastRealtimeGain
    }
    var hasRendered: Bool {
        os_unfair_lock_lock(&gainLock)
        let result = callbackCount > 0
        os_unfair_lock_unlock(&gainLock)
        return result
    }
    var hasAudibleSamples: Bool {
        os_unfair_lock_lock(&gainLock)
        let result = audibleSamples
        os_unfair_lock_unlock(&gainLock)
        return result
    }
    func markAudible() {
        if os_unfair_lock_trylock(&gainLock) {
            audibleSamples = true
            os_unfair_lock_unlock(&gainLock)
        }
    }
    func stop() {
        if let ioProc {
            AudioDeviceStop(aggregate, ioProc)
            AudioDeviceDestroyIOProcID(aggregate, ioProc)
            self.ioProc = nil
        }
        if let context { Unmanaged<MixerRoute>.fromOpaque(context).release(); self.context = nil }
        AudioHardwareDestroyAggregateDevice(aggregate)
        if #available(macOS 14.2, *) { AudioHardwareDestroyProcessTap(tap) }
    }
}

// A muted-when-tapped process returns to macOS output as soon as its IOProc stops.
private let mixerIOProc: AudioDeviceIOProc = { _, _, inputData, _, outputData, _, clientData in
    guard let clientData else { return noErr }
    let route = Unmanaged<MixerRoute>.fromOpaque(clientData).takeUnretainedValue()
    let input = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
    let output = UnsafeMutableAudioBufferListPointer(outputData)
    let gain = route.realtimeGain()
    var audible = false
    for index in output.indices {
        guard let dst = output[index].mData else { continue }
        let outputBytes = Int(output[index].mDataByteSize)
        memset(dst, 0, outputBytes)
        guard index < input.count, let src = input[index].mData else { continue }
        let sampleCount = min(Int(input[index].mDataByteSize), outputBytes) / MemoryLayout<Float>.size
        let source = src.assumingMemoryBound(to: Float.self)
        let destination = dst.assumingMemoryBound(to: Float.self)
        for sample in 0..<sampleCount {
            let value = source[sample]
            if abs(value) > 0.0001 { audible = true }
            destination[sample] = MixerDSP.apply(value, gain: gain)
        }
    }
    if audible { route.markAudible() }
    return noErr
}

@MainActor
final class SoundMixerModel: ObservableObject {
    private nonisolated static let routeQueue = DispatchQueue(label: "com.personal.notch.mixer.routes")
    @Published private(set) var outputDevices: [MixerDevice] = []
    @Published private(set) var inputDevices: [MixerDevice] = []
    @Published private(set) var selectedOutput: AudioObjectID = 0
    @Published private(set) var selectedInput: AudioObjectID = 0
    @Published private(set) var systemVolume: Int?
    @Published private(set) var inputGain: Int?
    @Published private(set) var applications: [MixerApplication] = []
    @Published private(set) var status = "Enable per-app mixing to control each application's volume."
    @Published private(set) var enabled: Bool
    @Published private(set) var sessionActive = false
    private let defaults: UserDefaults
    private var gains: [String: Int]
    private var routes: [AudioObjectID: MixerRoute] = [:]
    private var pendingRoutes: Set<AudioObjectID> = []
    private var routeGeneration: UInt64 = 0
    private var routeSetupInFlight = false
    private var routeSetupStartedAt: Date?
    private var processToBundle: [AudioObjectID: String] = [:]
    private var failedProcesses: [AudioObjectID: String] = [:]
    private var timer: Timer?
    private var activeOutput: AudioObjectID = 0
    private var sessionVerified = false
    private var sessionIssue: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.enabled = defaults.bool(forKey: "notch.mixer.enabled.v1")
        self.gains = defaults.dictionary(forKey: "notch.mixer.gains.v1") as? [String: Int] ?? [:]
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
    func setEnabled(_ value: Bool) {
        enabled = value
        defaults.set(value, forKey: "notch.mixer.enabled.v1")
        if value { startSession() }
        else { sessionActive = false; sessionVerified = false; sessionIssue = nil; stopRoutes(); failedProcesses.removeAll(); status = "Per-app mixing is off." }
        refresh()
    }
    func retry() { guard enabled else { return }; startSession(); refresh() }
    private func startSession() {
        sessionActive = true
        sessionVerified = false
        sessionIssue = nil
        stopRoutes()
        failedProcesses.removeAll()
    }
    func setGain(_ value: Int, for bundleID: String) {
        let gain = min(100, max(0, value))
        gains[bundleID] = gain
        defaults.set(gains, forKey: "notch.mixer.gains.v1")
        for app in applications.indices where applications[app].id == bundleID { applications[app].gain = gain }
        for (process, route) in routes where processToBundle[process] == bundleID {
            route.setGain(Float(gain) / 100)
        }
    }
    func resetGains() {
        for app in applications { setGain(100, for: app.id) }
        gains.removeAll(); defaults.removeObject(forKey: "notch.mixer.gains.v1")
    }
    func selectOutput(_ id: AudioObjectID) { setDefaultDevice(id, selector: kAudioHardwarePropertyDefaultOutputDevice); refresh() }
    func selectInput(_ id: AudioObjectID) { setDefaultDevice(id, selector: kAudioHardwarePropertyDefaultInputDevice); refresh() }
    func setSystemVolume(_ percent: Int) {
        guard selectedOutput != 0 else { return }
        let value = min(100, max(0, percent))
        if setVolume(Float(value) / 100, device: selectedOutput, scope: kAudioDevicePropertyScopeOutput) {
            systemVolume = value
        }
    }
    func setInputGain(_ percent: Int) {
        guard selectedInput != 0 else { return }
        let value = min(100, max(0, percent))
        if setVolume(Float(value) / 100, device: selectedInput, scope: kAudioDevicePropertyScopeInput) {
            inputGain = value
        }
    }
    func stop() { timer?.invalidate(); timer = nil; sessionActive = false; stopRoutes() }

    func refresh() {
        let system = AudioObjectID(kAudioObjectSystemObject)
        let devices = objectIDs(system, selector: kAudioHardwarePropertyDevices)
        outputDevices = devices.filter { hasStreams($0, scope: kAudioDevicePropertyScopeOutput)
            && !deviceName($0).hasPrefix("Nubi Mixer") && !deviceName($0).hasPrefix("Nōtch Mixer") }
            .map { MixerDevice(id: $0, name: deviceName($0)) }
        inputDevices = devices.filter { hasStreams($0, scope: kAudioDevicePropertyScopeInput)
            && !deviceName($0).hasPrefix("Nubi Mixer") && !deviceName($0).hasPrefix("Nōtch Mixer") }
            .map { MixerDevice(id: $0, name: deviceName($0)) }
        selectedOutput = readScalar(system, selector: kAudioHardwarePropertyDefaultOutputDevice) ?? 0
        selectedInput = readScalar(system, selector: kAudioHardwarePropertyDefaultInputDevice) ?? 0
        systemVolume = readVolume(selectedOutput, scope: kAudioDevicePropertyScopeOutput)
        inputGain = readVolume(selectedInput, scope: kAudioDevicePropertyScopeInput)
        if activeOutput != selectedOutput {
            if sessionActive { sessionActive = false; sessionIssue = "Perangkat output berubah. Tekan Mulai untuk melanjutkan mixer." }
            stopRoutes(); failedProcesses.removeAll(); sessionVerified = false; activeOutput = selectedOutput
        }
        refreshProcesses()
    }

    private func refreshProcesses() {
        let system = AudioObjectID(kAudioObjectSystemObject)
        let processes = objectIDs(system, selector: kAudioHardwarePropertyProcessObjectList)
        var grouped: [String: (name: String, icon: NSImage?, ids: [AudioObjectID], available: Bool)] = [:]
        processToBundle.removeAll()
        for id in processes {
            guard let running: UInt32 = readScalar(id, selector: kAudioProcessPropertyIsRunningOutput), running != 0,
                  let pid: pid_t = readScalar(id, selector: kAudioProcessPropertyPID), pid != getpid() else { continue }
            let runningApp = NSRunningApplication(processIdentifier: pid)
            let bundle = runningApp?.bundleIdentifier ?? processBundleID(id) ?? "process.\(pid)"
            processToBundle[id] = bundle
            let name = runningApp?.localizedName ?? bundle.components(separatedBy: ".").last ?? "Audio app"
            let devices = objectIDs(id, selector: kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeOutput)
            let supported = selectedOutput != 0 && (devices.isEmpty || devices.contains(selectedOutput))
            var entry = grouped[bundle] ?? (name, runningApp?.icon, [], true)
            entry.ids.append(id); entry.available = entry.available && supported
            grouped[bundle] = entry
        }
        if enabled && sessionActive, #available(macOS 14.2, *) {
            let eligible = Set(grouped.values.flatMap { $0.available ? $0.ids : [] })
            if routes.values.contains(where: { !$0.hasRendered && Date().timeIntervalSince($0.startedAt) > 3 }) {
                sessionActive = false
                sessionIssue = "Tidak ada buffer audio. Periksa izin System Audio Recording, lalu tekan Mulai lagi."
            }
            for id in routes.keys.filter({ !eligible.contains($0) }) {
                if let route = routes.removeValue(forKey: id) { Self.routeQueue.async { route.stop() } }
            }
            failedProcesses = failedProcesses.filter { eligible.contains($0.key) }
            if !sessionVerified && routes.values.contains(where: \.hasAudibleSamples) { sessionVerified = true }
            if !sessionVerified && routes.values.contains(where: { Date().timeIntervalSince($0.startedAt) > 6 }) {
                sessionActive = false
                sessionIssue = "Tidak ada audio tertangkap. Periksa izin System Audio Recording, lalu tekan Mulai lagi."
            }
            if !sessionActive { stopRoutes() }
            let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            let preferred = ["com.apple.Music", "com.spotify.client", "com.google.Chrome"]
            let candidates = grouped.sorted { lhs, rhs in
                let left = lhs.key == frontmost ? 0 : (preferred.contains(lhs.key) ? 1 : 2)
                let right = rhs.key == frontmost ? 0 : (preferred.contains(rhs.key) ? 1 : 2)
                return left == right ? lhs.value.name.localizedStandardCompare(rhs.value.name) == .orderedAscending : left < right
            }
            routeSetup: for (bundle, entry) in candidates where entry.available && sessionActive {
                for id in entry.ids where routes[id] == nil && pendingRoutes.contains(id) == false && failedProcesses[id] == nil {
                    if routeSetupInFlight || (!sessionVerified && !routes.isEmpty) { break routeSetup }
                    pendingRoutes.insert(id)
                    routeSetupInFlight = true
                    routeSetupStartedAt = Date()
                    let generation = routeGeneration
                    let output = selectedOutput
                    let gain = Float(gains[bundle] ?? 100) / 100
                    Self.routeQueue.async { [weak self] in
                        let result = Result { try Self.makeRoute(process: id, output: output, gain: gain) }
                        Task { @MainActor [weak self] in
                            self?.finishRoute(result, process: id, output: output, generation: generation)
                        }
                    }
                    break routeSetup
                }
            }
            if !sessionActive { status = sessionIssue ?? "Pencampuran dijeda. Tekan Mulai untuk mencoba lagi." }
            else if routeSetupInFlight {
                status = routeSetupStartedAt.map { Date().timeIntervalSince($0) > 10 } == true
                    ? "Core Audio belum merespons. Tutup dan buka Nubi untuk mencoba lagi."
                    : "Menyiapkan rute audio. Nubi tetap dapat digunakan."
            }
            else if !sessionVerified && !routes.isEmpty {
                let name = routes.keys.compactMap { id in grouped.values.first(where: { $0.ids.contains(id) })?.name }.first ?? "aplikasi yang tampil"
                status = "Memeriksa izin audio. Putar suara dari \(name)."
            }
            else if !failedProcesses.isEmpty { status = "Some apps unavailable: \(failedProcesses.values.first ?? "Check audio permission"). Retry after granting access." }
            else if routes.isEmpty && !grouped.isEmpty { status = "Allow System Audio Recording when macOS prompts, then retry Mixer." }
            else if routes.isEmpty { status = "Mixer aktif. Putar audio di aplikasi untuk mulai mencampur." }
            else if !routes.isEmpty { status = "Mixing \(routes.count) audio process\(routes.count == 1 ? "" : "es")." }
        } else {
            stopRoutes()
            if enabled { status = sessionActive ? "Per-app mixing requires macOS 14.2 or later." : (sessionIssue ?? "Mixer siap. Tekan Mulai untuk sesi ini; izin audio hanya diminta saat itu.") }
        }
        applications = grouped.map { bundle, entry in
            let available = entry.available && (!enabled || entry.ids.allSatisfy { routes[$0] != nil })
            return MixerApplication(id: bundle, name: entry.name, icon: entry.icon, processCount: entry.ids.count,
                                    available: available, detail: entry.available ? entry.ids.compactMap { failedProcesses[$0] }.first : "Uses another output device",
                                    gain: gains[bundle] ?? 100)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    @available(macOS 14.2, *)
    private nonisolated static func makeRoute(process: AudioObjectID, output: AudioObjectID, gain: Float) throws -> MixerRoute {
        guard let outputUID = routeObjectString(output, selector: kAudioDevicePropertyDeviceUID) else {
            throw MixerError("Audio device is unavailable")
        }
        // Bind the tap to the chosen device so its sample rate matches the output stream.
        let description = CATapDescription(processes: [process], deviceUID: outputUID, stream: 0)
        description.name = "Nubi · \(process)"
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped
        var tap: AudioObjectID = 0
        guard AudioHardwareCreateProcessTap(description, &tap) == noErr else { throw MixerError("Could not create process tap") }
        var aggregate: AudioObjectID = 0
        do {
            guard let tapUID = routeObjectString(tap, selector: kAudioTapPropertyUID) else { throw MixerError("Audio tap is unavailable") }
            let config: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Nubi Mixer \(process)",
                kAudioAggregateDeviceUIDKey: "com.personal.notch.mixer.\(UUID().uuidString)",
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceMainSubDeviceKey: outputUID,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUID]],
                kAudioAggregateDeviceTapAutoStartKey: true
            ]
            guard AudioHardwareCreateAggregateDevice(config as CFDictionary, &aggregate) == noErr else { throw MixerError("Could not create audio route") }
            let route = MixerRoute(tap: tap, aggregate: aggregate, gain: gain)
            guard let inputFormat = streamFormat(aggregate, scope: kAudioDevicePropertyScopeInput),
                  let outputFormat = streamFormat(aggregate, scope: kAudioDevicePropertyScopeOutput),
                  MixerDSP.canPassThrough(input: inputFormat, output: outputFormat) else {
                route.stop(); throw MixerError("Unsupported audio stream format")
            }
            let context = Unmanaged.passRetained(route).toOpaque()
            route.context = context
            var ioProc: AudioDeviceIOProcID?
            guard AudioDeviceCreateIOProcID(aggregate, mixerIOProc, context, &ioProc) == noErr, let ioProc else {
                route.stop(); throw MixerError("Could not prepare audio output")
            }
            route.ioProc = ioProc
            guard AudioDeviceStart(aggregate, ioProc) == noErr else {
                route.stop(); throw MixerError("Audio capture permission or output start failed", pauseSession: true)
            }
            return route
        } catch {
            if aggregate == 0 { AudioHardwareDestroyProcessTap(tap) }
            throw error
        }
    }
    private func finishRoute(_ result: Result<MixerRoute, Error>, process: AudioObjectID, output: AudioObjectID, generation: UInt64) {
        routeSetupInFlight = false
        routeSetupStartedAt = nil
        pendingRoutes.remove(process)
        guard generation == routeGeneration, enabled, sessionActive, output == selectedOutput,
              processToBundle[process] != nil else {
            if case .success(let route) = result { Self.routeQueue.async { route.stop() } }
            refresh()
            return
        }
        switch result {
        case .success(let route):
            let bundle = processToBundle[process]!
            route.setGain(Float(gains[bundle] ?? 100) / 100)
            routes[process] = route
        case .failure(let error):
            failedProcesses[process] = error.localizedDescription
            if (error as? MixerError)?.pauseSession == true {
                sessionActive = false
                sessionIssue = "Routing audio gagal. Periksa izin System Audio Recording, lalu tekan Mulai lagi."
                stopRoutes()
            }
        }
        refresh()
    }
    private func stopRoutes() {
        routeGeneration &+= 1
        pendingRoutes.removeAll()
        for route in routes.values { Self.routeQueue.async { route.stop() } }
        routes.removeAll()
    }
    private nonisolated static func streamFormat(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> AudioStreamBasicDescription? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamFormat, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &format) == noErr else { return nil }
        return format
    }
    private nonisolated static func routeObjectString(_ id: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
    private func setDefaultDevice(_ id: AudioObjectID, selector: AudioObjectPropertySelector) {
        guard id != 0 else { return }
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value = id
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                                UInt32(MemoryLayout<AudioObjectID>.size), &value)
        if status != noErr { self.status = "Could not select audio device (\(status))." }
    }
    @discardableResult
    private func setVolume(_ value: Float32, device: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool {
        var changed = false
        for element: AudioObjectPropertyElement in [kAudioObjectPropertyElementMain, 1, 2] {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: scope, mElement: element)
            var writable = DarwinBoolean(false)
            guard AudioObjectHasProperty(device, &address), AudioObjectIsPropertySettable(device, &address, &writable) == noErr,
                  writable.boolValue else { continue }
            var level = value
            if AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &level) == noErr {
                changed = true
                if element == kAudioObjectPropertyElementMain { return true }
            }
        }
        if !changed { status = "Volume control is unavailable for this device." }
        return changed
    }
    private func readVolume(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Int? {
        guard device != 0 else { return nil }
        for element: AudioObjectPropertyElement in [kAudioObjectPropertyElementMain, 1, 2] {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: scope, mElement: element)
            var writable = DarwinBoolean(false)
            guard AudioObjectIsPropertySettable(device, &address, &writable) == noErr, writable.boolValue,
                  let value: Float32 = readScalar(device, selector: kAudioDevicePropertyVolumeScalar, scope: scope, element: element), value.isFinite else { continue }
            return Int((min(1, max(0, value)) * 100).rounded())
        }
        return nil
    }
    private func hasStreams(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool {
        !objectIDs(device, selector: kAudioDevicePropertyStreams, scope: scope).isEmpty
    }
    private func deviceName(_ id: AudioObjectID) -> String { objectString(id, selector: kAudioObjectPropertyName) ?? "Audio device \(id)" }
    private func processBundleID(_ id: AudioObjectID) -> String? { objectString(id, selector: kAudioProcessPropertyBundleID) }
    private func objectString(_ id: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
    private func objectIDs(_ id: AudioObjectID, selector: AudioObjectPropertySelector,
                           scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var values = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let result = values.withUnsafeMutableBufferPointer { buffer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, buffer.baseAddress!)
        }
        guard result == noErr else { return [] }
        return values
    }
    private func readScalar<T>(_ id: AudioObjectID, selector: AudioObjectPropertySelector,
                               scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                               element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> T? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        var value = [UInt8](repeating: 0, count: MemoryLayout<T>.size)
        var size = UInt32(MemoryLayout<T>.size)
        let result = value.withUnsafeMutableBytes { bytes in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, bytes.baseAddress!)
        }
        guard result == noErr, size == MemoryLayout<T>.size else { return nil }
        return value.withUnsafeBytes { $0.loadUnaligned(as: T.self) }
    }
}

enum MixerDSP {
    static func apply(_ sample: Float, gain: Float) -> Float { sample * gain }
    static func canPassThrough(input: AudioStreamBasicDescription, output: AudioStreamBasicDescription) -> Bool {
        let floatPCM = { (format: AudioStreamBasicDescription) in
            format.mFormatID == kAudioFormatLinearPCM && format.mBitsPerChannel == 32 &&
            (format.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        }
        return floatPCM(input) && floatPCM(output) && input.mSampleRate == output.mSampleRate &&
            input.mChannelsPerFrame == output.mChannelsPerFrame &&
            (input.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == (output.mFormatFlags & kAudioFormatFlagIsNonInterleaved)
    }
}

private struct MixerError: LocalizedError {
    let message: String
    let pauseSession: Bool
    init(_ message: String, pauseSession: Bool = false) { self.message = message; self.pauseSession = pauseSession }
    var errorDescription: String? { message }
}
