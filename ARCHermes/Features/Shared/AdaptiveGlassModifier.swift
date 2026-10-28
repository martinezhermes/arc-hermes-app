import SwiftUI

enum AdaptiveReadableContentWidth {
    static let secondaryDestination: CGFloat = 800
    static let workspace: CGFloat = 1_000
}

private struct AdaptiveReadableContentModifier: ViewModifier {
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}

private struct AdaptiveReadableScrollContentModifier: ViewModifier {
    let maxWidth: CGFloat
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { width = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, newWidth in
                            width = newWidth
                        }
                }
            }
            .contentMargins(
                .horizontal,
                max((width - maxWidth) / 2, 0),
                for: .scrollContent
            )
    }
}

enum AdaptiveKeyboardDismissMode {
    case never
    case interactively
}

extension View {
    /// Scrolling dismisses the touch keyboard on iOS; visionOS owns its spatial keyboard.
    @ViewBuilder
    func adaptiveScrollDismissesKeyboard(_ mode: AdaptiveKeyboardDismissMode) -> some View {
        #if os(visionOS)
        self
        #else
        switch mode {
        case .never: scrollDismissesKeyboard(.never)
        case .interactively: scrollDismissesKeyboard(.interactively)
        }
        #endif
    }

    /// Preserves the native edge treatment on newer systems without changing view
    /// identity when accessibility preferences change. Older systems draw their normal edge.
    @ViewBuilder
    func nativeSoftScrollEdges(_ edges: Edge.Set) -> some View {
        #if os(visionOS)
        self
        #else
        if #available(iOS 26, *) {
            scrollEdgeEffectStyle(.soft, for: edges)
        } else {
            self
        }
        #endif
    }

    /// Pins session chrome using the native bar on newer systems and an inset on iOS 18.
    @ViewBuilder
    func adaptiveTopBar<Bar: View>(@ViewBuilder content: () -> Bar) -> some View {
        if #available(iOS 26, *) {
            safeAreaBar(edge: .top, spacing: 0, content: content)
        } else {
            modifier(InsetTopBarModifier(bar: content()))
        }
    }

    func adaptiveReadableContent(maxWidth: CGFloat) -> some View {
        modifier(AdaptiveReadableContentModifier(maxWidth: maxWidth))
    }

    func adaptiveReadableScrollContent(maxWidth: CGFloat) -> some View {
        modifier(AdaptiveReadableScrollContentModifier(maxWidth: maxWidth))
    }

    func adaptiveFormPresentation() -> some View {
        presentationSizing(.form)
    }

    func adaptivePagePresentation() -> some View {
        presentationSizing(.page)
    }

    func adaptiveSecondaryNavigationTitle() -> some View {
        modifier(AdaptiveSecondaryNavigationTitleModifier())
    }
}

/// Older systems reserve the header's measured height above the scroll content.
struct InsetTopBarModifier<Bar: View>: ViewModifier {
    let bar: Bar

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            bar.background(.bar)
        }
    }
}

private struct AdaptiveSecondaryNavigationTitleModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        content.navigationBarTitleDisplayMode(horizontalSizeClass == .regular ? .inline : .automatic)
    }
}

enum GlassPreference {
    static let isEnabledKey = "adaptiveGlass.isEnabled"
    static let defaultIsEnabled = true

    static var isLiquidGlassSupported: Bool {
        #if os(visionOS)
        // The native window provides spatial glass; these are inset content surfaces.
        return false
        #else
        if #available(iOS 26, *) {
            return true
        }

        return false
        #endif
    }

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: isEnabledKey) != nil else {
            return defaultIsEnabled
        }

        return defaults.bool(forKey: isEnabledKey)
    }
}

enum AdaptiveGlassStyle: Equatable {
    case regular
}

enum AdaptiveGlassSurface: Equatable {
    case liquidGlass
    case material
    case opaque

    static func resolve(
        liquidGlassAvailable: Bool,
        isGlassEnabled: Bool,
        reduceTransparency: Bool
    ) -> AdaptiveGlassSurface {
        if reduceTransparency {
            return .opaque
        }

        guard liquidGlassAvailable, isGlassEnabled else {
            return .material
        }

        return .liquidGlass
    }
}

enum AdaptiveScrollEdgeTreatment: Equatable {
    case soft
    case disabled

    static func resolve(
        softScrollEdgesAvailable: Bool,
        reduceTransparency: Bool
    ) -> AdaptiveScrollEdgeTreatment {
        guard softScrollEdgesAvailable, !reduceTransparency else {
            return .disabled
        }

        return .soft
    }
}

private struct AdaptiveGlassModifier<S: Shape>: ViewModifier {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(GlassPreference.isEnabledKey) private var isGlassEnabled = GlassPreference.defaultIsEnabled

    let style: AdaptiveGlassStyle
    let isInteractive: Bool
    let tint: Color?
    let fallbackMaterial: Material
    let inheritsClipping: Bool
    let shape: S

    @ViewBuilder
    func body(content: Content) -> some View {
        switch resolvedSurface {
        case .liquidGlass:
            #if os(visionOS)
            materialContent(content)
            #else
            if #available(iOS 26, *) {
                liquidGlassContent(content)
            } else {
                materialContent(content)
            }
            #endif
        case .material:
            materialContent(content)
        case .opaque:
            opaqueContent(content)
        }
    }

    private var resolvedSurface: AdaptiveGlassSurface {
        AdaptiveGlassSurface.resolve(
            liquidGlassAvailable: GlassPreference.isLiquidGlassSupported && !inheritsClipping,
            isGlassEnabled: isGlassEnabled,
            reduceTransparency: reduceTransparency
        )
    }

    private var showsContrastStroke: Bool {
        reduceTransparency || colorSchemeContrast == .increased
    }

    private var contrastStrokeOpacity: Double {
        colorSchemeContrast == .increased ? 0.22 : 0.14
    }

    #if !os(visionOS)
    @available(iOS 26, *)
    private var resolvedGlass: Glass {
        switch style {
        case .regular:
            var glass = Glass.regular
            if let tint {
                glass = glass.tint(tint)
            }
            if isInteractive {
                glass = glass.interactive()
            }
            return glass
        }
    }

    @available(iOS 26, *)
    private func liquidGlassContent(_ content: Content) -> some View {
        content
            .glassEffect(resolvedGlass, in: shape)
            .adaptiveGlassAccessibilityStroke(
                shape: shape,
                isVisible: showsContrastStroke,
                opacity: contrastStrokeOpacity
            )
    }

    #endif

    private func materialContent(_ content: Content) -> some View {
        content
            .background(fallbackMaterial, in: shape)
            .adaptiveGlassAccessibilityStroke(
                shape: shape,
                isVisible: showsContrastStroke,
                opacity: contrastStrokeOpacity
            )
    }

    private func opaqueContent(_ content: Content) -> some View {
        content
            .background(Color(.secondarySystemBackground), in: shape)
            .adaptiveGlassAccessibilityStroke(
                shape: shape,
                isVisible: true,
                opacity: contrastStrokeOpacity
            )
    }
}

private struct AdaptiveSoftScrollEdgeModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let edges: Edge.Set

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(visionOS)
        content
        #else
        if #available(iOS 26, *),
           AdaptiveScrollEdgeTreatment.resolve(
               softScrollEdgesAvailable: true,
               reduceTransparency: reduceTransparency
           ) == .soft {
            content.scrollEdgeEffectStyle(.soft, for: edges)
        } else {
            content
        }
        #endif
    }
}

struct AdaptiveGlassContainer<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(GlassPreference.isEnabledKey) private var isGlassEnabled = GlassPreference.defaultIsEnabled

    let spacing: CGFloat
    private let content: () -> Content

    init(spacing: CGFloat = 16, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        #if os(visionOS)
        content()
        #else
        if #available(iOS 26, *), isGlassEnabled, !reduceTransparency {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
        #endif
    }
}

private extension View {
    @ViewBuilder
    func adaptiveGlassAccessibilityStroke<S: Shape>(
        shape: S,
        isVisible: Bool,
        opacity: Double
    ) -> some View {
        if isVisible {
            overlay(
                shape
                    .stroke(Color.primary.opacity(opacity), lineWidth: 1)
                    .allowsHitTesting(false)
            )
        } else {
            self
        }
    }
}

extension View {
    /// `inheritsClipping` keeps the surface on the material path even when
    /// Liquid Glass is available. Glass is composited outside the SwiftUI
    /// layer tree, so it ignores an ancestor's clip or mask and draws over
    /// neighbouring views; controls inside a masked scroller need this.
    func adaptiveGlass(
        _ style: AdaptiveGlassStyle = .regular,
        isInteractive: Bool = false,
        tint: Color? = nil,
        fallbackMaterial: Material = .regularMaterial,
        inheritsClipping: Bool = false,
        in shape: some Shape
    ) -> some View {
        modifier(AdaptiveGlassModifier(
            style: style,
            isInteractive: isInteractive,
            tint: tint,
            fallbackMaterial: fallbackMaterial,
            inheritsClipping: inheritsClipping,
            shape: shape
        ))
    }

    func adaptiveSoftScrollEdges(_ edges: Edge.Set = [.top, .bottom]) -> some View {
        modifier(AdaptiveSoftScrollEdgeModifier(edges: edges))
    }
}
