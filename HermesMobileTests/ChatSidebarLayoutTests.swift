import XCTest
@testable import HermesMobile

final class ChatSidebarLayoutTests: XCTestCase {
    func testComposerToolbarSwipeDoesNotRevealSidebar() {
        let shell = CGRect(x: 20, y: 40, width: 390, height: 800)
        let toolbar = CGRect(x: 36, y: 680, width: 300, height: 44)

        XCTAssertFalse(ChatSidebarLayout.allowsReveal(
            startLocation: CGPoint(x: 100, y: 660), shellFrame: shell, excludedFrame: toolbar
        ))
        XCTAssertTrue(ChatSidebarLayout.allowsReveal(
            startLocation: CGPoint(x: 100, y: 500), shellFrame: shell, excludedFrame: toolbar
        ))
        XCTAssertTrue(ChatSidebarLayout.allowsReveal(
            startLocation: CGPoint(x: 100, y: 660), shellFrame: shell, excludedFrame: .null
        ))
    }

    func testOutwardPullCannotCloseOpenPaneEvenWithReverseReleasePrediction() {
        for direction: CGFloat in [1, -1] {
            var drag = ChatSidebarDrag(width: 300, presented: true, direction: direction,
                                      initialTranslation: CGSize(width: 80 * direction, height: 0))
            XCTAssertTrue(drag.settlesOpen(projected: CGSize(width: -900 * direction, height: 0)))
            drag.update(CGSize(width: -2 * direction, height: 0))
            XCTAssertTrue(drag.settlesOpen(projected: CGSize(width: -900 * direction, height: 0)))
        }
    }

    func testWrongDirectionCannotOpenClosedPaneFromReleasePredictionAlone() {
        let drag = ChatSidebarDrag(width: 300, presented: false, direction: 1,
                                  initialTranslation: CGSize(width: -80, height: 0))
        XCTAssertFalse(drag.settlesOpen(projected: CGSize(width: 900, height: 0)))
    }

    func testNarrowRegularWindowUsesCompactPresentation() {
        XCTAssertFalse(ChatSidebarLayout.isWide(available: 599, regularSizeClass: true))
        XCTAssertTrue(ChatSidebarLayout.isWide(available: 600, regularSizeClass: true))
        XCTAssertFalse(ChatSidebarLayout.isWide(available: 800, regularSizeClass: false))
    }

    func testZeroAndJitterSamplesDoNotRejectACompletedSwipe() {
        var drag = ChatSidebarDrag(width: 300, presented: false, direction: 1,
                                  initialTranslation: .zero)
        drag.update(CGSize(width: 1, height: 3))
        XCTAssertNil(drag.isHorizontal)
        drag.update(CGSize(width: 200, height: 8))
        XCTAssertEqual(drag.reveal, 200)
        XCTAssertTrue(drag.settlesOpen(projected: CGSize(width: 250, height: 10)))
    }

    func testReleaseCanResolveWithoutTransientGestureState() {
        let release = ChatSidebarDrag(width: 300, presented: true, direction: 1,
                                      initialTranslation: CGSize(width: -210, height: 4))
        XCTAssertFalse(release.settlesOpen(projected: CGSize(width: -250, height: 6)))
    }

    func testHorizontalCloseRemainsAcceptedAfterDiagonalMovement() {
        var drag = ChatSidebarDrag(width: 300, presented: true, direction: 1,
                                  initialTranslation: CGSize(width: -20, height: 2))
        drag.update(CGSize(width: -200, height: 250))
        XCTAssertEqual(drag.reveal, 100)
        XCTAssertFalse(drag.settlesOpen(projected: CGSize(width: -200, height: 250)))
    }

    func testVerticalStartCannotBecomeARevealMidGesture() {
        var drag = ChatSidebarDrag(width: 300, presented: false, direction: 1,
                                  initialTranslation: CGSize(width: 2, height: 20))
        drag.update(CGSize(width: 250, height: 25))
        XCTAssertEqual(drag.reveal, 0)
        XCTAssertFalse(drag.settlesOpen(projected: CGSize(width: 500, height: 25)))
    }

    func testResizeUsesOriginalWidthAndLatestTotalTranslation() {
        var drag = ChatSidebarDrag(width: 300, presented: true, direction: 1,
                                  initialTranslation: .zero, resizing: true)
        drag.update(CGSize(width: 40, height: 0))
        drag.update(CGSize(width: 60, height: 0))
        XCTAssertEqual(drag.startWidth + drag.translation, 360)
    }

    func testRightToLeftCloseUsesCapturedDirection() {
        let drag = ChatSidebarDrag(width: 300, presented: true, direction: -1,
                                  initialTranslation: CGSize(width: 200, height: 0))
        XCTAssertEqual(drag.reveal, 100)
        XCTAssertFalse(drag.settlesOpen(projected: CGSize(width: 250, height: 0)))
    }

    func testCompactRevealAlwaysLeavesAnExposedChatTarget() {
        for available: CGFloat in [240, 320, 393, 600] {
            let width = ChatSidebarLayout.width(available: available, preferred: 500, wide: false)
            XCTAssertGreaterThanOrEqual(available - width, 44)
            XCTAssertGreaterThan(width, 0)
        }
    }

    func testResizeClampsWithoutLosingTheChatColumn() {
        XCTAssertEqual(ChatSidebarLayout.width(available: 700, preferred: 800, wide: true), 380)
        XCTAssertEqual(ChatSidebarLayout.width(available: 1000, preferred: 300, wide: true), 300)
        XCTAssertEqual(ChatSidebarLayout.width(available: 1000, preferred: -20, wide: true), 280)
        XCTAssertEqual(ChatSidebarLayout.width(available: 700, preferred: 280, wide: true), 280)
    }

    func testRevealClampsAtBothEdges() {
        XCTAssertEqual(ChatSidebarLayout.reveal(width: 300, presented: false, translation: -50), 0)
        XCTAssertEqual(ChatSidebarLayout.reveal(width: 300, presented: false, translation: 600), 300)
        XCTAssertEqual(ChatSidebarLayout.reveal(width: 300, presented: true, translation: -70), 230)
    }

    func testCompletedAndCancelledGesturesFromBothStates() {
        XCTAssertTrue(ChatSidebarLayout.settlesOpen(width: 300, presented: false, projectedTranslation: 200))
        XCTAssertFalse(ChatSidebarLayout.settlesOpen(width: 300, presented: false, projectedTranslation: 30))
        XCTAssertFalse(ChatSidebarLayout.settlesOpen(width: 300, presented: true, projectedTranslation: -200))
        XCTAssertTrue(ChatSidebarLayout.settlesOpen(width: 300, presented: true, projectedTranslation: -30))
    }
}
