import AppKit
import Combine
import IOKit
import IOKit.graphics

@MainActor
final class BrightnessModel: ObservableObject {
    @Published private(set) var percentByDisplay: [UInt32: Int] = [:]
    var percent: Int? {
        let id = configuration.values.displayID == 0 ? CGMainDisplayID() : CGDirectDisplayID(configuration.values.displayID)
        return percentByDisplay[id]
    }
    private var timer: Timer?
    private let configuration: NotchConfiguration
    init(configuration: NotchConfiguration) {
        self.configuration = configuration
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }
    private func refresh() {
        var values: [UInt32: Int] = [:]
        for screen in NSScreen.screens {
            let id = DisplayManager.id(of: screen)
            if let value = readPercent(displayID: id) { values[id] = value }
        }
        if values != percentByDisplay { percentByDisplay = values }
    }
    private func readPercent(displayID id: UInt32) -> Int? {
        let vendor = Int(CGDisplayVendorNumber(id))
        let product = Int(CGDisplayModelNumber(id))
        let serial = Int(CGDisplaySerialNumber(id))
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("IODisplayConnect"),
              IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }
        var matches: [Int] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let dictionary = IODisplayCreateInfoDictionary(service, IOOptionBits(kIODisplayMatchingInfo))?.takeRetainedValue() as? [String: Any],
                  dictionary["DisplayVendorID"] as? Int == vendor,
                  dictionary["DisplayProductID"] as? Int == product else { continue }
            if serial != 0, let serviceSerial = dictionary["DisplaySerialNumber"] as? Int, serviceSerial != serial { continue }
            var value: Float = 0
            if IODisplayGetFloatParameter(service, 0, "brightness" as CFString, &value) == kIOReturnSuccess, value.isFinite {
                matches.append(Int((min(1, max(0, value)) * 100).rounded()))
            }
        }
        return matches.count == 1 ? matches[0] : nil
    }
    func stop() { timer?.invalidate(); timer = nil }
}
