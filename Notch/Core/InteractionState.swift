import Foundation

/// Pure transition logic; delayed transitions are scheduled by NotchStateController.
public struct InteractionState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case hidden, collapsed, activityCompact, peek, expanded, pinned }
    public private(set) var phase: Phase = .collapsed
    public private(set) var pointerInside = false
    public private(set) var hasActivity = false
    public var isExpanded: Bool { phase == .expanded || phase == .pinned }
    public var isOpen: Bool { isExpanded || phase == .peek }
    public var isHidden: Bool { phase == .hidden }
    public init() {}
    public mutating func pointerChanged(inside: Bool) { pointerInside = inside }
    public mutating func activityChanged(active: Bool) {
        hasActivity = active
        if phase == .collapsed || phase == .activityCompact { phase = restingPhase }
    }
    public mutating func setHidden(_ hidden: Bool) {
        if hidden { phase = .hidden; pointerInside = false }
        else if phase == .hidden { phase = restingPhase }
    }
    public mutating func peekIfHovered() {
        if pointerInside && (phase == .collapsed || phase == .activityCompact) { phase = .peek }
    }
    public mutating func expandIfHovered() { peekIfHovered() }
    public mutating func open() { if phase != .hidden { phase = .expanded } }
    public mutating func collapseIfOutside() {
        if !pointerInside && phase != .pinned && phase != .hidden { phase = restingPhase }
    }
    public mutating func togglePin() {
        guard phase != .hidden else { return }
        phase = phase == .pinned ? (pointerInside ? .expanded : restingPhase) : .pinned
    }
    public mutating func dismiss() { phase = phase == .hidden ? .hidden : restingPhase; pointerInside = false }
    private var restingPhase: Phase { hasActivity ? .activityCompact : .collapsed }
}

/// AppKit coordinates: the display origin may be negative or above the primary display.
public enum PanelGeometry {
    public static func frame(screen: CGRect, top: CGFloat, requestedSize: CGSize) -> CGRect {
        let width = min(max(requestedSize.width, 1), screen.width)
        let height = min(max(requestedSize.height, 1), screen.height)
        return CGRect(x: screen.midX - width / 2,
                      y: max(screen.minY, min(top, screen.maxY) - height),
                      width: width, height: height)
    }
}

public enum PanelVisibility {
    public static func hidden(excluded: Bool, fullscreen: Bool, hoverReveal: Bool,
                              notificationsOnly: Bool, internalAlert: Bool) -> Bool {
        excluded || (fullscreen && !hoverReveal) || (notificationsOnly && !internalAlert)
    }

    public static func fullscreenHoverZone(screen: CGRect, pillWidth: CGFloat) -> CGRect {
        CGRect(x: screen.midX - min(pillWidth, screen.width) / 2,
               y: screen.maxY - 42, width: min(pillWidth, screen.width), height: 42)
    }

    // WindowServer rectangles use a top-left origin. A fullscreen app can leave the notch band empty.
    public static func fillsDisplay(_ window: CGRect, display: CGRect, safeTop: CGFloat) -> Bool {
        let tolerance: CGFloat = 4
        let topInset = window.minY - display.minY
        return abs(window.minX - display.minX) <= tolerance
            && abs(window.maxX - display.maxX) <= tolerance
            && abs(window.maxY - display.maxY) <= tolerance
            && (abs(topInset) <= tolerance || (safeTop > 0 && abs(topInset - safeTop) <= tolerance))
    }
}

enum LockScreenLayout {
    static let cardSize = CGSize(width: 440, height: 112)

    static func pillFrame(on screen: CGRect, safeTop: CGFloat, cameraWidth: CGFloat) -> CGRect {
        PanelGeometry.frame(screen: screen, top: screen.maxY,
                            requestedSize: CGSize(width: max(184, cameraWidth + 24), height: 32 + safeTop))
    }

    static func cardFrame(on screen: CGRect) -> CGRect? {
        // Reserve the upper band for the system clock and the lower band for sign-in.
        guard screen.width >= 360, screen.height * 0.30 >= cardSize.height else { return nil }
        let top = screen.maxY - screen.height * 0.45 + cardSize.height / 2
        return PanelGeometry.frame(screen: screen.insetBy(dx: 16, dy: 0), top: top, requestedSize: cardSize)
    }
}
