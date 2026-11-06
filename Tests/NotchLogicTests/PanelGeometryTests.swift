import XCTest
@testable import NotchLogic

final class PanelGeometryTests: XCTestCase {
    func testCenteredAtTopOnPrimary() {
        let result = PanelGeometry.frame(screen: CGRect(x: 0, y: 0, width: 1920, height: 1080), top: 1080,
                                         requestedSize: CGSize(width: 180, height: 32))
        XCTAssertEqual(result, CGRect(x: 870, y: 1048, width: 180, height: 32))
    }
    func testNegativeOriginAndMenuBarOffset() {
        let screen = CGRect(x: -2560, y: -200, width: 2560, height: 1440)
        let result = PanelGeometry.frame(screen: screen, top: 1215, requestedSize: CGSize(width: 360, height: 242))
        XCTAssertEqual(result.midX, screen.midX)
        XCTAssertEqual(result.maxY, 1215)
    }
    func testOversizedPanelClampsToDisplay() {
        let screen = CGRect(x: 200, y: 300, width: 200, height: 100)
        let result = PanelGeometry.frame(screen: screen, top: 400, requestedSize: CGSize(width: 360, height: 242))
        XCTAssertEqual(result, screen)
    }

    func testLockScreenCardStaysBetweenClockAndSignInBands() throws {
        for screen in [CGRect(x: 0, y: 0, width: 1512, height: 982),
                       CGRect(x: -420, y: -150, width: 420, height: 480)] {
            let card = try XCTUnwrap(LockScreenLayout.cardFrame(on: screen))
            XCTAssertEqual(card.midX, screen.midX)
            XCTAssertGreaterThanOrEqual(card.minX, screen.minX + 16)
            XCTAssertLessThanOrEqual(card.maxY, screen.maxY - screen.height * 0.30)
            XCTAssertGreaterThanOrEqual(card.minY, screen.maxY - screen.height * 0.60)
        }
        XCTAssertNil(LockScreenLayout.cardFrame(on: CGRect(x: 0, y: 0, width: 640, height: 350)))
    }

    func testLockScreenPillReservesRoomBelowTheCameraHousing() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let pill = LockScreenLayout.pillFrame(on: screen, safeTop: 32, cameraWidth: 200)
        XCTAssertEqual(pill.maxY, screen.maxY)
        XCTAssertEqual(pill.midX, screen.midX)
        XCTAssertEqual(pill.width, 224)
        XCTAssertEqual(pill.height, 64)
    }
}
