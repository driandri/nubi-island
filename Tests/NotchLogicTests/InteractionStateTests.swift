import XCTest
@testable import NotchLogic

final class InteractionStateTests: XCTestCase {
    func testFullscreenGeometryRecognizesNotchSafeAreaWithoutMatchingNormalWindow() {
        let display = CGRect(x: -1920, y: -100, width: 1920, height: 1080)
        let inset = CGRect(x: -1920, y: -68, width: 1920, height: 1048)
        XCTAssertTrue(PanelVisibility.fillsDisplay(display, display: display, safeTop: 32))
        XCTAssertTrue(PanelVisibility.fillsDisplay(inset, display: display, safeTop: 32))
        XCTAssertFalse(PanelVisibility.fillsDisplay(inset, display: display, safeTop: 0))
        XCTAssertFalse(PanelVisibility.fillsDisplay(inset.insetBy(dx: 0, dy: 12), display: display, safeTop: 32))
    }

    func testFullscreenHoverVisibilityAndTopZone() {
        let screen = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let zone = PanelVisibility.fullscreenHoverZone(screen: screen, pillWidth: 340)
        XCTAssertEqual(zone.midX, screen.midX)
        XCTAssertEqual(zone.maxY, screen.maxY)
        XCTAssertTrue(PanelVisibility.hidden(excluded: false, fullscreen: true, hoverReveal: false,
                                            notificationsOnly: false, internalAlert: false))
        XCTAssertFalse(PanelVisibility.hidden(excluded: false, fullscreen: true, hoverReveal: true,
                                             notificationsOnly: false, internalAlert: false))
        XCTAssertFalse(PanelVisibility.hidden(excluded: false, fullscreen: false, hoverReveal: false,
                                             notificationsOnly: false, internalAlert: false))
        XCTAssertTrue(PanelVisibility.hidden(excluded: true, fullscreen: true, hoverReveal: true,
                                            notificationsOnly: false, internalAlert: false))
        XCTAssertTrue(PanelVisibility.hidden(excluded: false, fullscreen: true, hoverReveal: true,
                                            notificationsOnly: true, internalAlert: false))
    }
    func testHoverThenLeave() {
        var state = InteractionState()
        state.pointerChanged(inside: true)
        state.expandIfHovered()
        XCTAssertEqual(state.phase, .peek)
        state.pointerChanged(inside: false)
        state.collapseIfOutside()
        XCTAssertEqual(state.phase, .collapsed)
    }
    func testStaleExpansionDoesNotOpenAfterLeave() {
        var state = InteractionState()
        state.pointerChanged(inside: true)
        state.pointerChanged(inside: false)
        state.expandIfHovered()
        XCTAssertFalse(state.isExpanded)
    }
    func testPinSurvivesPointerExit() {
        var state = InteractionState()
        state.togglePin()
        state.pointerChanged(inside: false)
        state.collapseIfOutside()
        XCTAssertEqual(state.phase, .pinned)
        state.togglePin()
        XCTAssertEqual(state.phase, .collapsed)
    }
    func testUnpinWhileHoveredStaysExpanded() {
        var state = InteractionState()
        state.pointerChanged(inside: true)
        state.togglePin()
        state.togglePin()
        XCTAssertEqual(state.phase, .expanded)
    }
    func testReentryInvalidatesCollapse() {
        var state = InteractionState()
        state.pointerChanged(inside: true)
        state.expandIfHovered()
        state.pointerChanged(inside: false)
        state.pointerChanged(inside: true)
        state.collapseIfOutside()
        XCTAssertEqual(state.phase, .peek)
    }
    func testDismissResetsPinAndHover() {
        var state = InteractionState()
        state.pointerChanged(inside: true)
        state.togglePin()
        state.dismiss()
        XCTAssertEqual(state, InteractionState())
    }
    func testActivityCompactPeekAndHidden() {
        var state = InteractionState()
        state.activityChanged(active: true)
        XCTAssertEqual(state.phase, .activityCompact)
        state.pointerChanged(inside: true)
        state.peekIfHovered()
        XCTAssertEqual(state.phase, .peek)
        state.open()
        XCTAssertEqual(state.phase, .expanded)
        state.setHidden(true)
        XCTAssertEqual(state.phase, .hidden)
        state.open()
        XCTAssertEqual(state.phase, .hidden)
        state.setHidden(false)
        XCTAssertEqual(state.phase, .activityCompact)
        state.activityChanged(active: false)
        XCTAssertEqual(state.phase, .collapsed)
    }
}
