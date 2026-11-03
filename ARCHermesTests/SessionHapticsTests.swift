import XCTest
import CoreGraphics
@testable import ARCHermes

final class SessionHapticsTests: XCTestCase {
    @MainActor
    func testHapticsRespectEnabledSetting() {
        var feedback: [SessionHapticFeedback] = []

        SessionHaptics.sessionCreated(isEnabled: false) { feedback.append($0) }
        SessionHaptics.pinStateChanged(isEnabled: false) { feedback.append($0) }
        SessionHaptics.archiveStateChanged(isEnabled: false) { feedback.append($0) }
        SessionHaptics.sessionDeleted(isEnabled: false) { feedback.append($0) }
        SessionHaptics.sessionRenamed(isEnabled: false) { feedback.append($0) }
        SessionHaptics.sidebarSlideCompleted(from: false, to: true, isEnabled: false) { feedback.append($0) }

        XCTAssertTrue(feedback.isEmpty)
    }

    @MainActor
    func testCompletedSidebarSwipesEmitOneSelectionInBothDirections() {
        for direction: CGFloat in [1, -1] {
            for presented in [false, true] {
                let travel: CGFloat = presented ? -220 : 220
                var drag = ChatSidebarDrag(width: 300, presented: presented, direction: direction,
                    initialTranslation: CGSize(width: 20 * direction, height: 0))
                drag.update(CGSize(width: travel * direction, height: 0))
                let settled = drag.settlesOpen(projected: CGSize(width: travel * direction, height: 0))
                var feedback: [SessionHapticFeedback] = []

                SessionHaptics.sidebarSlideCompleted(from: presented, to: settled, isEnabled: true) {
                    feedback.append($0)
                }

                XCTAssertEqual(settled, !presented)
                XCTAssertEqual(feedback, [.selection])
            }
        }
    }

    @MainActor
    func testUncommittedSidebarSwipesStayQuiet() {
        for direction: CGFloat in [1, -1] {
            for presented in [false, true] {
                let sign: CGFloat = presented ? -1 : 1
                for translation in [CGSize(width: 35 * sign, height: 0),
                                    CGSize(width: -220 * sign, height: 0),
                                    CGSize(width: 5, height: 120)] {
                    let sample = CGSize(width: translation.width * direction, height: translation.height)
                    let drag = ChatSidebarDrag(width: 300, presented: presented, direction: direction,
                        initialTranslation: sample)
                    let settled = drag.settlesOpen(projected: sample)
                    var feedback: [SessionHapticFeedback] = []

                    SessionHaptics.sidebarSlideCompleted(from: presented, to: settled, isEnabled: true) {
                        feedback.append($0)
                    }

                    XCTAssertEqual(settled, presented)
                    XCTAssertTrue(feedback.isEmpty)
                }
            }
        }
    }

    @MainActor
    func testCompletedSidebarSwipesRespectDisabledHaptics() {
        for presented in [false, true] {
            var feedback: [SessionHapticFeedback] = []
            SessionHaptics.sidebarSlideCompleted(from: presented, to: !presented, isEnabled: false) {
                feedback.append($0)
            }
            XCTAssertTrue(feedback.isEmpty)
        }
    }
}
