import XCTest
import SwiftUI
import UIKit
@testable import ARCHermes

final class ChatSidebarLayoutTests: XCTestCase {
    @MainActor
    func testFullHeightCardKeepsOneBackgroundAndSafeNativeControls() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for (direction, additionalRail) in [LayoutDirection.leftToRight, .rightToLeft].flatMap({ direction in
            [false, true].map { (direction, $0) }
        }) {
            let pane = SidebarCoverFixtureState()
            pane.shown = false
            let window = UIWindow(windowScene: scene)
            window.frame = scene.coordinateSpace.bounds
            window.overrideUserInterfaceStyle = .light
            window.traitOverrides.horizontalSizeClass = .compact
            let host = UIHostingController(rootView: FullHeightCardFixture(pane: pane)
                .environment(\.layoutDirection, direction)
                .environment(\.colorScheme, .light)
                .transaction { $0.disablesAnimations = true })
            host.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: additionalRail ? 17 : 0,
                bottom: 0, right: additionalRail ? 72 : 0)
            window.rootViewController = host
            defer { pane.rendered = nil; window.isHidden = true; window.rootViewController = nil }
            let appeared = expectation(description: "native card appeared")
            pane.rendered = { appeared.fulfill() }
            window.makeKeyAndVisible()
            await fulfillment(of: [appeared], timeout: 10)
            pane.rendered = nil
            window.layoutIfNeeded()
            let toolbar = try XCTUnwrap(pane.toolbar)
            let composer = try XCTUnwrap(pane.composer)
            let originalToolbar = toolbar.convert(toolbar.bounds, to: window)
            let originalComposer = composer.convert(composer.bounds, to: window)
            XCTAssertGreaterThanOrEqual(originalToolbar.minY, window.safeAreaInsets.top - 1)
            XCTAssertLessThanOrEqual(originalComposer.maxY, window.bounds.maxY - window.safeAreaInsets.bottom + 1)
            let closedImage = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            for x in [CGFloat(2), window.bounds.width - 2] {
                let rail = try cardPixel(closedImage, at: CGPoint(x: x, y: window.bounds.height / 2), bounds: window.bounds)
                XCTAssertTrue(rail.prefix(3).allSatisfy { $0 > 0.95 },
                              "The closed card must cover the side safe-area rails; got \(rail)")
            }

            let revealed = expectation(description: "card revealed")
            pane.rendered = { revealed.fulfill() }
            pane.shown = true
            await fulfillment(of: [revealed], timeout: 10)
            pane.rendered = nil
            window.layoutIfNeeded()
            XCTAssertTrue(pane.toolbar === toolbar)
            XCTAssertTrue(pane.composer === composer)
            XCTAssertEqual(toolbar.convert(toolbar.bounds, to: window).minY, originalToolbar.minY, accuracy: 1)
            XCTAssertEqual(composer.convert(composer.bounds, to: window).maxY, originalComposer.maxY, accuracy: 1)

            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let available = window.bounds.width - host.view.safeAreaInsets.left - host.view.safeAreaInsets.right
            let width = ChatSidebarLayout.width(available: available, preferred: nil, wide: false)
            let sign: CGFloat = direction == .rightToLeft ? -1 : 1
            let edge = direction == .rightToLeft ? window.bounds.width - width : width
            for y in [CGFloat(2), window.bounds.height / 2, window.bounds.height - 2] {
                let inside = try cardPixel(image, at: CGPoint(x: edge + sign * 40, y: y), bounds: window.bounds)
                XCTAssertTrue(inside.prefix(3).allSatisfy { $0 > 0.95 },
                              "The card must stay white through its safe areas; got \(inside) at y=\(y)")
            }
            for y in [CGFloat(2), window.bounds.height - 2] {
                let corner = try cardPixel(image, at: CGPoint(x: edge + sign * 2, y: y), bounds: window.bounds)
                XCTAssertGreaterThan(corner[0] - corner[1], 0.45,
                                     "Rounded safe-area corners must reveal the red fixture behind the card")
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "full-height-card-\(direction)-\(additionalRail ? "side-rail" : "standard")"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    private func cardPixel(_ image: UIImage, at point: CGPoint, bounds: CGRect) throws -> [Double] {
        let pixels = try XCTUnwrap(image.cgImage)
        let crop = try XCTUnwrap(pixels.cropping(to: CGRect(
            x: floor(point.x * CGFloat(pixels.width) / bounds.width),
            y: floor(point.y * CGFloat(pixels.height) / bounds.height), width: 1, height: 1)))
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8,
            bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return bytes.map { Double($0) / 255 }
    }

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

    func testSidebarDepthTracksCoverageAndReversalWithinASubtleRange() {
        let closing = [1.0, 0.75, 0.5, 0.25, 0.0].map {
            ChatSidebarLayout.sidebarScale(separation: $0, wide: false, reduceMotion: false)
        }
        XCTAssertEqual(closing.first, 1)
        XCTAssertEqual(closing.last, 0.97)
        XCTAssertTrue(zip(closing, closing.dropFirst()).allSatisfy { $0 > $1 })
        XCTAssertEqual(ChatSidebarLayout.sidebarScale(separation: 0.5, wide: false, reduceMotion: false),
                       closing[2], "Reversed swipes share the same scale rather than starting another animation")
        XCTAssertEqual(ChatSidebarLayout.sidebarScale(separation: -1, wide: false, reduceMotion: false), 0.97)
        XCTAssertEqual(ChatSidebarLayout.sidebarScale(separation: 2, wide: false, reduceMotion: false), 1)
    }

    func testWideColumnsAndReduceMotionDoNotFadeTheSidebar() {
        for reveal: CGFloat in [0, 150, 300] {
            XCTAssertEqual(ChatSidebarLayout.sidebarOffset(width: 300, reveal: reveal, wide: true), reveal - 300)
            XCTAssertEqual(ChatSidebarLayout.sidebarOpacity(separation: reveal / 300, wide: true, reduceMotion: false), 1)
            XCTAssertEqual(ChatSidebarLayout.sidebarOpacity(separation: reveal / 300, wide: false, reduceMotion: true), 1)
            XCTAssertEqual(ChatSidebarLayout.sidebarScale(separation: reveal / 300, wide: true, reduceMotion: false), 1)
            XCTAssertEqual(ChatSidebarLayout.sidebarScale(separation: reveal / 300, wide: false, reduceMotion: true), 1)
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
                let renderedSidebar = sidebar.convert(sidebar.bounds, to: window)
                let leadingEdge = direction == .rightToLeft ? renderedSidebar.maxX : renderedSidebar.minX
                let originalLeadingEdge = direction == .rightToLeft ? anchor.maxX : anchor.minX
                XCTAssertEqual(leadingEdge,
                               wide && !shown ? originalLeadingEdge - sign * anchor.width : originalLeadingEdge, accuracy: 1)
                let expectedScale: CGFloat = wide || shown ? 1 : 0.97
                XCTAssertEqual(renderedSidebar.width, sidebar.bounds.width * expectedScale, accuracy: 1)
                XCTAssertEqual(renderedSidebar.height, sidebar.bounds.height * expectedScale, accuracy: 1)
                XCTAssertEqual(renderedSidebar.midY, anchor.midY, accuracy: 1)
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
            XCTAssertEqual(sidebar.convert(sidebar.bounds, to: window).width, sidebar.bounds.width * (shown ? 1 : 0.97), accuracy: 1)
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

    func testEveryHorizontalSurfaceKeepsItsGestureEvenWhenItsContentFits() {
        let toolbar = CGRect(x: 36, y: 680, width: 300, height: 44)
        let attachments = CGRect(x: 36, y: 600, width: 300, height: 60)
        var frames: [CGRect] = []
        SidebarRevealExclusionFrameKey.reduce(value: &frames) { [toolbar] }
        SidebarRevealExclusionFrameKey.reduce(value: &frames) { [attachments, .null] }
        XCTAssertFalse(ChatSidebarLayout.allowsReveal(at: CGPoint(x: 100, y: 700), excluding: frames))
        XCTAssertFalse(ChatSidebarLayout.allowsReveal(at: CGPoint(x: 100, y: 620), excluding: frames))
        XCTAssertTrue(ChatSidebarLayout.allowsReveal(at: CGPoint(x: 100, y: 500), excluding: frames))
        XCTAssertEqual(frames, [toolbar, attachments], "One child cannot replace another child's ownership")
    }

    func testFinalPanSampleCompletesASwipeThatBeganBelowTheActivationDistance() {
        var drag = ChatSidebarDrag(width: 300, presented: false, direction: 1,
                                  initialTranslation: CGSize(width: 8, height: 1))
        XCTAssertNil(drag.isHorizontal)
        drag.update(CGSize(width: 180, height: 2))
        XCTAssertTrue(drag.settlesOpen(projected: CGSize(width: 180, height: 2)))
    }

    func testCoveredChatCanCloseSessionsOverAnInactiveHorizontalSurface() {
        let table = CGRect(x: 330, y: 180, width: 390, height: 120)
        let start = CGPoint(x: 370, y: 220)
        XCTAssertFalse(ChatSidebarLayout.allowsReveal(at: start, excluding: [table]))
        XCTAssertTrue(ChatSidebarLayout.allowsReveal(at: start, excluding: nil),
                      "The closing scrim owns its touch even over disabled horizontal content")
    }

    func testSidebarClosingSwipeIgnoresChatContentMovingAcrossItsStart() {
        let start = CGPoint(x: 200, y: 220)
        let table = CGRect(x: 330, y: 180, width: 390, height: 120)
        XCTAssertTrue(ChatSidebarLayout.allowsReveal(at: start, excluding: [table]))
        XCTAssertFalse(ChatSidebarLayout.allowsReveal(at: start, excluding: [table.offsetBy(dx: -200, dy: 0)]))
        XCTAssertTrue(ChatSidebarLayout.allowsReveal(at: start, excluding: nil),
                      "A sidebar closing gesture must not inherit the moving chat's exclusions")
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
        XCTAssertFalse(drag.hasAcceptedTransition, "A clamped outward pull must not suspend typing")
    }

    func testAcceptedRevealKeepsTypingSuspendedUntilAReversedGestureEnds() {
        var drag = ChatSidebarDrag(width: 300, presented: false, direction: 1,
                                  initialTranslation: CGSize(width: 20, height: 2))
        XCTAssertTrue(drag.hasAcceptedTransition)
        drag.update(.zero)
        XCTAssertTrue(drag.hasAcceptedTransition, "Returning to the origin while still dragging is not a focus return")
        XCTAssertFalse(drag.settlesOpen(projected: .zero))
    }

    func testFocusSuspensionRequiresTravelTowardTransitionInBothDirections() {
        for direction: CGFloat in [1, -1] {
            for presented in [false, true] {
                let openingSign: CGFloat = presented ? -1 : 1
                var drag = ChatSidebarDrag(width: 300, presented: presented, direction: direction,
                    initialTranslation: CGSize(width: -60 * openingSign * direction, height: 1))
                XCTAssertFalse(drag.hasAcceptedTransition)
                drag.update(CGSize(width: 30 * openingSign * direction, height: 1))
                XCTAssertTrue(drag.hasAcceptedTransition)
            }
        }
    }

    @MainActor
    func testFocusReturnReadsPresentationIntentBeforeTheViewRefreshes() {
        var presented = false
        let scope = DrawerFocusScope()
        scope.sceneIsActive = true
        scope.presentation = Binding(get: { presented }, set: { presented = $0 })
        XCTAssertTrue(scope.isActive(.detail))
        presented = true
        XCTAssertFalse(scope.isActive(.detail), "A stale active frame cannot authorize a queued keyboard return")
        XCTAssertTrue(scope.isActive(.sidebar))
    }

    @MainActor
    func testFocusReturnRejectsNewGestureAndSceneInterruption() {
        let scope = DrawerFocusScope()
        scope.sceneIsActive = true
        scope.presentation = .constant(false)
        XCTAssertTrue(scope.isActive(.detail))
        scope.isRevealing = true
        XCTAssertFalse(scope.isActive(.detail))
        scope.isRevealing = false
        scope.sceneIsActive = false
        XCTAssertFalse(scope.isActive(.detail))
        XCTAssertFalse(scope.isActive(.sidebar))
    }

    @MainActor
    func testWideDrawerKeepsDetailFocusAvailableAlongsideSidebar() {
        let scope = DrawerFocusScope()
        scope.sceneIsActive = true
        scope.isWide = true
        scope.presentation = .constant(true)
        XCTAssertTrue(scope.isActive(.detail))
        XCTAssertTrue(scope.isActive(.sidebar))
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
    @ObservationIgnored var toolbar: UIView?
    @ObservationIgnored var composer: UIView?
    @ObservationIgnored var rendered: (() -> Void)?
}

private struct FullHeightCardFixture: View {
    @Bindable var pane: SidebarCoverFixtureState

    var body: some View {
        ChatNavigationShell(isPresented: $pane.shown, isCompact: $pane.compact) {
            Color.red
        } detail: {
            NavigationStack {
                Color.white
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        SidebarCoverMarker { pane.composer = $0 }.frame(height: 44)
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            SidebarCoverMarker { pane.toolbar = $0 }.frame(width: 44, height: 44)
                        }
                    }
            }
        }
        .background(Color.red.ignoresSafeArea())
        .onChange(of: pane.shown, initial: true) {
            DispatchQueue.main.async { pane.rendered?() }
        }
    }
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
