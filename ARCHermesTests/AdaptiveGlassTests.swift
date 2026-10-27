import SwiftUI
import XCTest
@testable import ARCHermes

final class AdaptiveGlassTests: XCTestCase {
    func testSurfaceResolutionPrefersOpaqueWhenReduceTransparencyIsEnabled() {
        let surface = AdaptiveGlassSurface.resolve(
            liquidGlassAvailable: true,
            isGlassEnabled: true,
            reduceTransparency: true
        )

        XCTAssertEqual(surface, .opaque)
    }

    func testSurfaceResolutionFallsBackToMaterialWhenGlassIsDisabled() {
        let surface = AdaptiveGlassSurface.resolve(
            liquidGlassAvailable: true,
            isGlassEnabled: false,
            reduceTransparency: false
        )

        XCTAssertEqual(surface, .material)
    }

    func testScrollEdgeTreatmentDisablesWhenReduceTransparencyIsEnabled() {
        let treatment = AdaptiveScrollEdgeTreatment.resolve(
            softScrollEdgesAvailable: true,
            reduceTransparency: true
        )

        XCTAssertEqual(treatment, .disabled)
    }
}

@MainActor
final class InsetTopBarTests: XCTestCase {
    func testHeaderReservesSpaceAboveScrollContent() async throws {
        try await checkHeaderLayout(typeSize: .large)
    }

    func testHeaderReservesSpaceAboveScrollContentAtAccessibilitySize() async throws {
        try await checkHeaderLayout(typeSize: .accessibility3)
    }

    private func checkHeaderLayout(typeSize: DynamicTypeSize) async throws {
        let appeared = expectation(description: "Inset header appeared")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let headerMarker = UIView()
        let contentMarker = UIView()
        let host = UIHostingController(rootView:
            ScrollView {
                TopBarLayoutMarker(view: contentMarker).frame(height: 100)
            }
            .modifier(InsetTopBarModifier(bar:
                Text("Sessions")
                    .font(.largeTitle)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(TopBarLayoutMarker(view: headerMarker))
            ))
            .environment(\.dynamicTypeSize, typeSize)
            .background(NavigationAppearanceCompletionObserver { appeared.fulfill() })
        )
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        await fulfillment(of: [appeared], timeout: 5)
        window.layoutIfNeeded()

        let header = headerMarker.convert(headerMarker.bounds, to: window)
        let firstContent = contentMarker.convert(contentMarker.bounds, to: window)
        XCTAssertGreaterThan(header.height, 0)
        XCTAssertEqual(firstContent.height, 100, accuracy: 1)
        XCTAssertEqual(firstContent.minY, header.maxY, accuracy: 1,
                       "The fallback must reserve the header's actual height without covering the first row")
    }
}

private struct TopBarLayoutMarker: UIViewRepresentable {
    let view: UIView
    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

@MainActor
final class ChatNavigationBackgroundTests: XCTestCase {
    func testChatNavigationKeepsToolbarBackgroundTransparent() async throws {
        try await checkBackground(reduceTransparency: false)
    }

    func testChatNavigationKeepsToolbarBackgroundTransparentWhenTransparencyIsReduced() async throws {
        try await checkBackground(reduceTransparency: true)
    }

    private func checkBackground(reduceTransparency: Bool) async throws {
        let appeared = expectation(description: "Chat navigation appeared")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: NavigationStack {
            ChatView(
                session: SessionSummary(title: "Synthetic chat", workspace: "/workspace"),
                server: URL(string: "https://chat-header.invalid")!,
                onAPIError: { _ in },
                loadsInitialMessages: false
            )
            // SwiftUI's public accessibility value is read-only; the test-only
            // backing setter exercises ChatView without changing simulator settings.
            .environment(\._accessibilityReduceTransparency, reduceTransparency)
            .background(NavigationAppearanceCompletionObserver { appeared.fulfill() })
        })
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        await fulfillment(of: [appeared], timeout: 5)
        window.layoutIfNeeded()
        let navigation = try XCTUnwrap(findNavigation(in: host))
        let item = try XCTUnwrap(navigation.topViewController?.navigationItem)
        let appearances = [
            navigation.navigationBar.standardAppearance,
            item.scrollEdgeAppearance ?? navigation.navigationBar.scrollEdgeAppearance
                ?? navigation.navigationBar.standardAppearance
        ]
        for appearance in appearances {
            XCTAssertNil(appearance.backgroundEffect,
                         "The chat header must not request a full-width material plane")
            XCTAssertEqual(appearance.backgroundColor?.resolvedColor(with: host.traitCollection).cgColor.alpha ?? 0, 0,
                           "A transparent toolbar must leave the transcript's native scroll-edge treatment visible")
            XCTAssertEqual(appearance.shadowColor?.resolvedColor(with: host.traitCollection).cgColor.alpha ?? 0, 0,
                           "The chat header must not add a rectangular separator")
        }
    }

    private func findNavigation(in controller: UIViewController) -> UINavigationController? {
        if let navigation = controller as? UINavigationController { return navigation }
        return controller.children.lazy.compactMap { self.findNavigation(in: $0) }.first
    }
}
