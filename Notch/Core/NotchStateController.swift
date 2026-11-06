import AppKit
import Combine

@MainActor
final class NotchStateController: ObservableObject {
    @Published private(set) var interaction = InteractionState()
    @Published private(set) var attachesToScreenEdge: Bool
    private var pending: Task<Void, Never>?
    private var openedAt: Date?
    private let configuration: NotchConfiguration
    var isExpanded: Bool { interaction.isExpanded }
    var isPeek: Bool { interaction.phase == .peek }
    var isOpen: Bool { interaction.isOpen }
    var isHidden: Bool { interaction.isHidden }
    var isPinned: Bool { interaction.phase == .pinned }
    init(configuration: NotchConfiguration) {
        self.configuration = configuration
        attachesToScreenEdge = !configuration.values.belowMenuBar
    }

    func setAttachesToScreenEdge(_ attached: Bool) {
        if attached != attachesToScreenEdge { attachesToScreenEdge = attached }
    }

    func pointerChanged(inside: Bool, opensPeek: Bool = true) {
        guard interaction.pointerInside != inside else { return }
        interaction.pointerChanged(inside: inside)
        pending?.cancel()
        let grace = openedAt.map { max(0, 2 - Date().timeIntervalSince($0)) } ?? 0
        let delay = inside ? configuration.values.expandDelay : max(configuration.values.collapseDelay, grace)
        pending = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self else { return }
            if inside {
                if opensPeek { self.interaction.peekIfHovered() }
            } else { self.interaction.collapseIfOutside() }
        }
    }
    func activityChanged(_ active: Bool) {
        guard interaction.hasActivity != active else { return }
        interaction.activityChanged(active: active)
    }
    func setHidden(_ hidden: Bool) {
        guard interaction.isHidden != hidden else { return }
        if hidden { openedAt = nil }
        pending?.cancel(); interaction.setHidden(hidden)
    }
    func open() { pending?.cancel(); openedAt = .now; interaction.open() }
    func navigationChanged() {
        guard isExpanded && !isPinned else { return }
        pending?.cancel()
        openedAt = .now
        if !interaction.pointerInside {
            pending = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                self?.interaction.collapseIfOutside()
            }
        }
    }
    func togglePin() { pending?.cancel(); interaction.togglePin() }
    func dismiss() { pending?.cancel(); openedAt = nil; interaction.dismiss() }
}
