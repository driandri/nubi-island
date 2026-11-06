import AppKit
import Combine
import IOKit.ps
import CoreAudio
import Darwin

struct BatterySource: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let percent: Int
    let charging: Bool
}

struct SystemSnapshot: Equatable {
    let cpuPercent: Int
    let memoryPercent: Int
    let memoryUsedGB: Double
    let memoryTotalGB: Double
    let loadAverage: Double
}

@MainActor
final class SystemInfoModel: ObservableObject {
    @Published private(set) var batteryPercent: Int?
    @Published private(set) var volumePercent: Int?
    @Published private(set) var isMuted = false
    @Published private(set) var inputMuted: Bool?
    @Published private(set) var batteryCharging: Bool?
    @Published private(set) var batteries: [BatterySource] = []
    @Published private(set) var stats: SystemSnapshot?
    private var statsTask: Task<Void, Never>?
    private var previousCPU: (UInt64, UInt64)?
    private var audioListeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var audioRefreshTask: Task<Void, Never>?
    private var observedOutputDevice: AudioObjectID?
    private var observedInputDevice: AudioObjectID?
    private var stopped = false
    private var source: CFRunLoopSource?
    init() {
        refresh()
        bindAudio()
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let created = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let model = Unmanaged<SystemInfoModel>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in model.refresh() }
        }, context)?.takeRetainedValue() {
            source = created
            CFRunLoopAddSource(CFRunLoopGetMain(), created, .defaultMode)
        }
    }
    func stop() {
        stopped = true
        statsTask?.cancel(); statsTask = nil
        audioRefreshTask?.cancel(); audioRefreshTask = nil
        removeAudioListeners()
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
        source = nil
    }
    func refresh() {
        batteryPercent = nil
        batteries = []
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            batteryCharging = nil
            return
        }
        var internalCharging: Bool?
        for source in sources {
            guard let details = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let current = details[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = details[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            let percent = min(100, max(0, current * 100 / maximum))
            let kind = details[kIOPSTypeKey] as? String
            let name = details[kIOPSNameKey] as? String ?? (kind == kIOPSInternalBatteryType ? "Mac battery" : "Accessory")
            let charging = details[kIOPSIsChargingKey] as? Bool ?? false
            batteries.append(BatterySource(name: name, percent: percent, charging: charging))
            if kind == kIOPSInternalBatteryType { batteryPercent = percent; internalCharging = charging }
        }
        batteryCharging = internalCharging
    }
    func setStatsVisible(_ visible: Bool) {
        if !visible { statsTask?.cancel(); statsTask = nil; return }
        guard statsTask == nil else { return }
        refreshStats()
        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                self?.refreshStats()
            }
        }
    }
    func refreshStats() {
        var load: [Double] = [0, 0, 0]
        _ = getloadavg(&load, 3)
        var cpu = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let cpuStatus = withUnsafeMutablePointer(to: &cpu) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        var cpuPercent = stats?.cpuPercent ?? 0
        if cpuStatus == KERN_SUCCESS {
            let ticks = cpu.cpu_ticks
            let busy = UInt64(ticks.0) + UInt64(ticks.1) + UInt64(ticks.2)
            let total = busy + UInt64(ticks.3)
            if let previousCPU, total > previousCPU.1, busy >= previousCPU.0 {
                cpuPercent = Int((Double(busy - previousCPU.0) / Double(total - previousCPU.1) * 100).rounded())
            }
            previousCPU = (busy, total)
        }
        var memory = vm_statistics64_data_t()
        count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let memoryStatus = withUnsafeMutablePointer(to: &memory) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        let used: Double
        if memoryStatus == KERN_SUCCESS {
            var pageSize: vm_size_t = 0
            host_page_size(mach_host_self(), &pageSize)
            let free = (Double(memory.free_count) + Double(memory.inactive_count)) * Double(pageSize)
            used = max(0, total - free)
        } else { used = 0 }
        stats = SystemSnapshot(cpuPercent: min(100, max(0, cpuPercent)),
                               memoryPercent: total > 0 ? Int((used / total * 100).rounded()) : 0,
                               memoryUsedGB: used / 1_073_741_824, memoryTotalGB: total / 1_073_741_824,
                               loadAverage: load[0])
    }
    private func removeAudioListeners() {
        for (object, address, block) in audioListeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
        }
        audioListeners.removeAll()
    }
    private func listen(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) {
        var address = address
        guard AudioObjectHasProperty(object, &address) else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.scheduleAudioRefresh() }
        }
        if AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr {
            audioListeners.append((object, address, block))
        }
    }
    private func scheduleAudioRefresh() {
        audioRefreshTask?.cancel()
        audioRefreshTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(40)) } catch { return }
            guard let self else { return }
            self.refreshAudioValues()
        }
    }
    private func bindAudio() {
        guard !stopped else { return }
        removeAudioListeners()
        let system = AudioObjectID(kAudioObjectSystemObject)
        var outputAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                       mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        listen(system, outputAddress)
        let inputAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                      mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        listen(system, inputAddress)
        bindInputMute(system: system)
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &outputAddress, 0, nil, &size, &device) == noErr, device != 0 else {
            observedOutputDevice = nil
            volumePercent = nil
            isMuted = false
            inputMuted = readInputMute(observedInputDevice ?? 0)
            return
        }
        observedOutputDevice = device
        // Prefer the master volume; fall back to the left/right channels for stereo devices.
        for element: UInt32 in [kAudioObjectPropertyElementMain, 1, 2] {
            let address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                                     mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            listen(device, address)
        }
        let muteAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                                     mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        listen(device, muteAddress)
        refreshAudioValues()
    }
    private func bindInputMute(system: AudioObjectID) {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &device) == noErr, device != 0 else {
            observedInputDevice = nil; inputMuted = nil; return
        }
        observedInputDevice = device
        for element: UInt32 in [kAudioObjectPropertyElementMain, 1, 2] {
            listen(device, AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                                      mScope: kAudioDevicePropertyScopeInput, mElement: element))
        }
    }
    private func refreshAudioValues() {
        guard !stopped else { return }
        let system = AudioObjectID(kAudioObjectSystemObject)
        var outputAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                       mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &outputAddress, 0, nil, &size, &device) == noErr,
              device != 0 else {
            bindAudio()
            return
        }
        if observedOutputDevice != device { bindAudio(); return }
        var inputAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                      mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var inputDevice = AudioObjectID(0)
        size = UInt32(MemoryLayout<AudioObjectID>.size)
        if AudioObjectGetPropertyData(system, &inputAddress, 0, nil, &size, &inputDevice) == noErr,
           observedInputDevice != inputDevice { bindAudio(); return }
        var levels: [Float32] = []
        for element: UInt32 in [kAudioObjectPropertyElementMain, 1, 2] {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                                     mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            var value: Float32 = 0
            size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectHasProperty(device, &address),
               AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr, value.isFinite {
                levels.append(value)
                if element == kAudioObjectPropertyElementMain { break }
            }
        }
        let nextVolume = levels.isEmpty ? nil : Int((min(1, max(0, levels.reduce(0, +) / Float32(levels.count))) * 100).rounded())
        if volumePercent != nextVolume { volumePercent = nextVolume }
        var muteAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                                     mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var mute: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectHasProperty(device, &muteAddress),
           AudioObjectGetPropertyData(device, &muteAddress, 0, nil, &size, &mute) == noErr,
           isMuted != (mute != 0) { isMuted = mute != 0 }
        inputMuted = readInputMute(inputDevice)
    }

    private func readInputMute(_ device: AudioObjectID) -> Bool? {
        guard device != 0 else { return nil }
        for element: UInt32 in [kAudioObjectPropertyElementMain, 1, 2] {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                                     mScope: kAudioDevicePropertyScopeInput, mElement: element)
            var mute: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectHasProperty(device, &address),
               AudioObjectGetPropertyData(device, &address, 0, nil, &size, &mute) == noErr { return mute != 0 }
        }
        return nil
    }

}
