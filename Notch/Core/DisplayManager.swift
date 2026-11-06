import AppKit
import Combine

struct DisplayChoice: Identifiable {
    let id: UInt32
    let name: String
}

@MainActor
final class DisplayManager: ObservableObject {
    @Published private(set) var displays: [DisplayChoice] = []
    init() { refresh() }
    func refresh() {
        displays = NSScreen.screens.map { DisplayChoice(id: Self.id(of: $0), name: $0.localizedName) }
    }
    func screen(for id: UInt32) -> NSScreen? {
        NSScreen.screens.first { Self.id(of: $0) == id } ?? NSScreen.screens.first
    }
    func exactScreen(for id: UInt32) -> NSScreen? { NSScreen.screens.first { Self.id(of: $0) == id } }
    static func id(of screen: NSScreen) -> UInt32 {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
