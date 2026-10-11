import XCTest
import SwiftUI
import UIKit
@testable import ARCHermes

final class ChatSidebarLayoutTests: XCTestCase {
    func testCompactSidebarRemainsAnchoredDuringCoverRevealAndReversal() {
        for direction: CGFloat in [1, -1] {
            for presented in [true, false] {
                var drag = ChatSidebarDrag(width: 312, presented: presented, direction: direction,
                                          initialTranslation: .zero)
                for translation: CGFloat in [20, 160, 90, 0, -90, -160, -20] {
                    drag.update(CGSize(width: translation * direction, height: 0))
                    XCTAssertEqual(direction * ChatSidebarLayout.sidebarOffset(
                        width: drag.startWidth, reveal: drag.reveal, wide: false), 0,
                        "Only the chat should move, including a reversed or cancelled swipe")
                }
            }
        }
    }

    func testSidebarFadeTracksCoverageAndRecoversWithoutHidingTheExposedList() {
        let closing = [1.0, 0.75, 0.5, 0.25, 0.0].map {
            ChatSidebarLayout.sidebarOpacity(separation: $0, wide: false, reduceMotion: false)
        }
        XCTAssertEqual(closing.first, 1)
        XCTAssertEqual(closing.last, 0.88)
        XCTAssertTrue(zip(closing, closing.dropFirst()).allSatisfy { $0 > $1 })
        XCTAssertEqual(ChatSidebarLayout.sidebarOpacity(separation: 0.5, wide: false, reduceMotion: false),
                       closing[2], "Reversal uses the same progress rather than a delayed fade")
        XCTAssertEqual(ChatSidebarLayout.sidebarOpacity(separation: -1, wide: false, reduceMotion: false), 0.88)
        XCTAssertEqual(ChatSidebarLayout.sidebarOpacity(separation: 2, wide: false, reduceMotion: false), 1)
    }

    func testWideColumnsAndReduceMotionDoNotFadeTheSidebar() {
        for reveal: CGFloat in [0, 150, 300] {
            XCTAssertEqual(ChatSidebarLayout.sidebarOffset(width: 300, reveal: reveal, wide: true), reveal - 300)
            XCTAssertEqual(ChatSidebarLayout.sidebarOpacity(separation: reveal / 300, wide: true, reduceMotion: false), 1)
            XCTAssertEqual(ChatSidebarLayout.sidebarOpacity(separation: reveal / 300, wide: false, reduceMotion: true), 1)
        }
    }

    @MainActor
    func testMountedPanesPreserveIdentityAndUseCorrectCompactAndWideGeometry() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for (wide, direction) in [false, true].flatMap({ wide in
            [LayoutDirection.leftToRight, .rightToLeft].map { (wide, $0) }
        }) {
            let pane = SidebarCoverFixtureState()
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: wide ? 1000 : 390, height: 844)
            window.traitOverrides.horizontalSizeClass = wide ? .regular : .compact
            window.rootViewController = UIHostingController(rootView: SidebarCoverFixture(pane: pane)
                .environment(\.layoutDirection, direction)
                .transaction { $0.disablesAnimations = true })
            defer { pane.rendered = nil; window.isHidden = true; window.rootViewController = nil }

            let appeared = expectation(description: "sidebar fixture appeared")
            pane.rendered = { appeared.fulfill() }
            window.makeKeyAndVisible()
            await fulfillment(of: [appeared], timeout: 5)
            pane.rendered = nil
            window.layoutIfNeeded()
            let sidebar = try XCTUnwrap(pane.sidebar)
            let detail = try XCTUnwrap(pane.detail)
            let anchor = sidebar.convert(sidebar.bounds, to: window)
            let sign: CGFloat = direction == .rightToLeft ? -1 : 1
            let openDetailOrigin = wide && direction == .rightToLeft ? 0 : sign * anchor.width
            XCTAssertEqual(pane.compact, !wide)
            XCTAssertEqual(detail.convert(detail.bounds, to: window).minX, openDetailOrigin, accuracy: 1)

            for shown in [false, true] {
                let rendered = expectation(description: "sidebar visibility updated")
                pane.rendered = { rendered.fulfill() }
                pane.shown = shown
                await fulfillment(of: [rendered], timeout: 5)
                pane.rendered = nil
                window.layoutIfNeeded()
                XCTAssertTrue(pane.sidebar === sidebar)
                XCTAssertTrue(pane.detail === detail)
                XCTAssertEqual(sidebar.convert(sidebar.bounds, to: window).minX,
                               wide && !shown ? anchor.minX - sign * anchor.width : anchor.minX, accuracy: 1)
                XCTAssertEqual(detail.convert(detail.bounds, to: window).minX, shown ? openDetailOrigin : 0, accuracy: 1)
                XCTAssertEqual(detail.bounds.width, wide && shown ? window.bounds.width - anchor.width : window.bounds.width, accuracy: 1)
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "sidebar-cover-\(wide ? "wide" : "compact")-\(direction)-\(shown ? "revealed" : "covered")"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    @MainActor
    func testAnimatedCompactCoverAndRevealKeepTheSidebarAnchored() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let pane = SidebarCoverFixtureState()
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.traitOverrides.horizontalSizeClass = .compact
        window.rootViewController = UIHostingController(rootView: SidebarCoverFixture(pane: pane))
        defer { pane.rendered = nil; window.isHidden = true; window.rootViewController = nil }
        let appeared = expectation(description: "animated pane appeared")
        pane.rendered = { appeared.fulfill() }
        window.makeKeyAndVisible()
        await fulfillment(of: [appeared], timeout: 5)
        pane.rendered = nil
        window.layoutIfNeeded()
        let sidebar = try XCTUnwrap(pane.sidebar)
        let detail = try XCTUnwrap(pane.detail)
        let anchor = sidebar.convert(sidebar.bounds, to: window)
        for shown in [false, true, false, true] {
            let completed = expectation(description: "native cover animation completed")
            withAnimation(.easeOut(duration: 0.22), completionCriteria: .removed) {
                pane.shown = shown
            } completion: {
                completed.fulfill()
            }
            await fulfillment(of: [completed], timeout: 5)
            window.layoutIfNeeded()
            XCTAssertTrue(pane.sidebar === sidebar)
            XCTAssertTrue(pane.detail === detail)
            XCTAssertEqual(sidebar.convert(sidebar.bounds, to: window).minX, anchor.minX, accuracy: 1)
            XCTAssertEqual(detail.convert(detail.bounds, to: window).minX, shown ? anchor.width : 0, accuracy: 1)
        }
    }

    func testPaneActivityPausesCompactTransitionsAndPreservesWideInteraction() {
        XCTAssertEqual(ChatPaneActivity(wide: false, sidebarPresented: false, isRevealing: false),
                       ChatPaneActivity(wide: true, sidebarPresented: false, isRevealing: false))
        let shown = ChatPaneActivity(wide: false, sidebarPresented: true, isRevealing: false)
        XCTAssertTrue(shown.sidebar)
        XCTAssertFalse(shown.detail)
        for presented in [true, false] {
            let moving = ChatPaneActivity(wide: false, sidebarPresented: presented, isRevealing: true)
            XCTAssertFalse(moving.sidebar)
            XCTAssertFalse(moving.detail)
        }
        let wide = ChatPaneActivity(wide: true, sidebarPresented: true, isRevealing: false)
        XCTAssertTrue(wide.sidebar)
        XCTAssertTrue(wide.detail)
        let canceled = ChatPaneActivity(wide: false, sidebarPresented: false, isRevealing: false)
        XCTAssertFalse(canceled.sidebar)
        XCTAssertTrue(canceled.detail)
    }

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

    func testResizeReleaseCommitsEvenAfterTransientStateHasReset() {
        let saved = ChatSidebarLayout.completedResizeWidth(drag: nil, baseWidth: 330,
            translation: 45, direction: 1, available: 1000)
        XCTAssertEqual(saved, 375)
        XCTAssertEqual(ChatSidebarLayout.width(available: 1000, preferred: saved, wide: true), 375)
        let next = ChatSidebarLayout.completedResizeWidth(drag: nil, baseWidth: saved,
            translation: -60, direction: 1, available: 1000)
        XCTAssertEqual(next, 315, "The next gesture starts at the committed width")
    }

    func testResizeReleaseMatchesLastRenderedWidthWithoutDoubleCountingTranslation() {
        var drag = ChatSidebarDrag(width: 300, presented: true, direction: 1,
                                   initialTranslation: .zero, resizing: true)
        drag.update(CGSize(width: 50, height: 0))
        XCTAssertEqual(ChatSidebarLayout.completedResizeWidth(drag: drag, baseWidth: 300,
            translation: 50, direction: 1, available: 1000), drag.startWidth + drag.translation)
        XCTAssertEqual(ChatSidebarLayout.completedResizeWidth(drag: nil, baseWidth: 300,
            translation: 50, direction: 1, available: 1000), 350)
        XCTAssertEqual(ChatSidebarLayout.completedResizeWidth(drag: nil, baseWidth: 300,
            translation: -50, direction: -1, available: 1000), 350)
    }

    func testSavedSidebarWidthSurvivesTemporaryWindowClamping() {
        let preferred = ChatSidebarLayout.completedResizeWidth(drag: nil, baseWidth: 350,
            translation: 50, direction: 1, available: 1100)
        XCTAssertEqual(ChatSidebarLayout.width(available: 700, preferred: preferred, wide: true), 380)
        XCTAssertEqual(ChatSidebarLayout.width(available: 1100, preferred: preferred, wide: true), 400)
        XCTAssertEqual(ChatSidebarLayout.completedResizeWidth(drag: nil, baseWidth: 350,
            translation: 500, direction: 1, available: 700), 380)
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

@MainActor @Observable
private final class SidebarCoverFixtureState {
    var shown = true
    var compact = true
    @ObservationIgnored var sidebar: UIView?
    @ObservationIgnored var detail: UIView?
    @ObservationIgnored var rendered: (() -> Void)?
}

private struct SidebarCoverFixture: View {
    @Bindable var pane: SidebarCoverFixtureState
    var body: some View {
        ChatNavigationShell(isPresented: $pane.shown, isCompact: $pane.compact) {
            VStack(alignment: .leading) {
                Text("ARC Hermes").font(.title.bold())
                Text("Selected session")
                Text("Sessions stay in place")
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SidebarCoverMarker { pane.sidebar = $0 })
        } detail: {
            VStack {
                Text("Selected session").font(.title)
                Spacer()
                Text("Chat covers Sessions")
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SidebarCoverMarker { pane.detail = $0 })
        }
        .onChange(of: pane.shown, initial: true) {
            DispatchQueue.main.async { pane.rendered?() }
        }
    }
}

private struct SidebarCoverMarker: UIViewRepresentable {
    let mounted: (UIView) -> Void
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        mounted(view)
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
