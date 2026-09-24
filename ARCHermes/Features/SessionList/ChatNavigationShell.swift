import SwiftUI

/// Layout policy shared by the live container and its regression tests.
enum ChatSidebarLayout {
    static func allowsReveal(startLocation: CGPoint, shellFrame: CGRect, excludedFrame: CGRect) -> Bool {
        let globalStart = CGPoint(x: shellFrame.minX + startLocation.x, y: shellFrame.minY + startLocation.y)
        return !excludedFrame.contains(globalStart)
    }

    static func isWide(available: CGFloat, regularSizeClass: Bool) -> Bool {
        regularSizeClass && available >= 600
    }

    static func width(available: CGFloat, preferred: CGFloat?, wide: Bool) -> CGFloat {
        if wide {
            let maximum = max(0, min(420, available - 320))
            return min(maximum, max(min(280, maximum), preferred ?? available / 3))
        }
        // Leave a tappable portion of the chat visible on narrow windows.
        return max(0, min(available * 0.8, available - 44))
    }

    static func reveal(width: CGFloat, presented: Bool, translation: CGFloat) -> CGFloat {
        min(width, max(0, (presented ? width : 0) + translation))
    }

    static func settlesOpen(width: CGFloat, presented: Bool, projectedTranslation: CGFloat) -> Bool {
        reveal(width: width, presented: presented, translation: projectedTranslation) > width / 2
    }
}

struct SidebarRevealExclusionFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .null

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

/// A drag keeps its original geometry and axis even as the rendered pane moves.
struct ChatSidebarDrag {
    static let activationDistance: CGFloat = 12
    let startWidth: CGFloat
    let startedPresented: Bool
    let direction: CGFloat
    private(set) var isHorizontal: Bool?
    var translation: CGFloat = 0

    init(width: CGFloat, presented: Bool, direction: CGFloat, initialTranslation: CGSize, resizing: Bool = false) {
        startWidth = width
        startedPresented = presented
        self.direction = direction
        isHorizontal = resizing ? true : nil
        update(initialTranslation)
    }

    mutating func update(_ value: CGSize) {
        // The first update can still be zero or touch jitter. Do not lock
        // that sample as vertical and reject the rest of a valid swipe.
        if isHorizontal == nil, max(abs(value.width), abs(value.height)) >= Self.activationDistance {
            isHorizontal = abs(value.width) > abs(value.height)
        }
        if isHorizontal == true { translation = value.width * direction }
    }

    var reveal: CGFloat {
        ChatSidebarLayout.reveal(width: startWidth, presented: startedPresented, translation: translation)
    }

    func settlesOpen(projected: CGSize) -> Bool {
        guard isHorizontal == true else { return startedPresented }
        // Velocity can complete a deliberate swipe, but cannot manufacture
        // one in the opposite direction or from release jitter at the origin.
        let travelTowardTransition = startedPresented ? -translation : translation
        guard travelTowardTransition >= Self.activationDistance else { return startedPresented }
        return ChatSidebarLayout.settlesOpen(width: startWidth, presented: startedPresented,
                                             projectedTranslation: projected.width * direction)
    }
}

/// Both children stay at the same structural positions while only their frames
/// and offsets change. Folding or revealing never tears down the active chat.
struct ChatNavigationShell<Sidebar: View, Detail: View>: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.layoutDirection) private var direction
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @AppStorage(AppHaptics.isEnabledKey) private var hapticsEnabled = true
    @Binding var isPresented: Bool
    @Binding var isCompact: Bool
    @State private var preferredWidth: CGFloat?
    @State private var revealExclusionFrame: CGRect = .null
    @Namespace private var gestureSpace
    @GestureState private var revealDrag: ChatSidebarDrag?
    @GestureState private var resizeDrag: ChatSidebarDrag?
    let sidebar: Sidebar
    let detail: Detail

    init(isPresented: Binding<Bool>, isCompact: Binding<Bool>, @ViewBuilder sidebar: () -> Sidebar, @ViewBuilder detail: () -> Detail) {
        _isPresented = isPresented
        _isCompact = isCompact
        self.sidebar = sidebar()
        self.detail = detail()
    }

    private var sign: CGFloat { direction == .rightToLeft ? -1 : 1 }
    private var motion: Animation? { reduceMotion ? nil : .easeOut(duration: 0.22) }

    var body: some View {
        GeometryReader { geometry in
            let available = geometry.size.width
            let wide = ChatSidebarLayout.isWide(available: available, regularSizeClass: sizeClass == .regular)
            let baseWidth = ChatSidebarLayout.width(available: available, preferred: preferredWidth, wide: wide)
            let width = ChatSidebarLayout.width(available: available,
                preferred: resizeDrag.map { $0.startWidth + $0.translation } ?? baseWidth, wide: wide)
            let reveal = !wide ? (revealDrag?.reveal ?? (isPresented ? width : 0)) : (isPresented ? width : 0)
            let separation = width > 0 ? min(1, max(0, reveal / width)) : 0
            let chatSurface = UnevenRoundedRectangle(
                topLeadingRadius: 24 * separation,
                bottomLeadingRadius: 24 * separation,
                style: .continuous
            )

            ZStack(alignment: .leading) {
                sidebar
                    .frame(width: width)
                    .frame(maxHeight: .infinity)
                    .offset(x: sign * (reveal - width))
                    .allowsHitTesting(isPresented)
                    .accessibilityHidden(!isPresented)
                    .simultaneousGesture(revealGesture(width: width, shellFrame: geometry.frame(in: .global)), isEnabled: !wide && isPresented)

                detail
                    .frame(width: wide ? max(0, available - reveal) : available)
                    .frame(maxHeight: .infinity)
                    .background(.background)
                    .background {
                        chatSurface.fill(.background)
                            .shadow(color: .black.opacity(0.12 * separation), radius: 6, x: -2 * sign)
                    }
                    // A compact reveal leaves only a slice of chat visible;
                    // don't let its native indicator cling to the window edge.
                    .scrollIndicators(!wide && (isPresented || reveal > 0) ? .hidden : .automatic, axes: .vertical)
                    // Recognize horizontal reveals across the chat while its
                    // child scroll views continue handling vertical movement.
                    .simultaneousGesture(revealGesture(width: width, shellFrame: geometry.frame(in: .global)), isEnabled: !wide && !isPresented)
                    .accessibilityHidden(!wide && isPresented)
                    .overlay {
                        if !wide && isPresented {
                            Color.black.opacity(0.15)
                                .contentShape(Rectangle())
                                .onTapGesture { isPresented = false }
                                .gesture(revealGesture(width: width, shellFrame: geometry.frame(in: .global)))
                                .accessibilityLabel("Hide Sessions")
                                .accessibilityAddTraits(.isButton)
                        }
                    }
                    // A quiet surface edge, not a mask: native toolbar items
                    // remain free to render in the window's safe-area rail.
                    .overlay {
                        chatSurface.fill(.primary.opacity(0.025 * separation))
                            .overlay {
                                chatSurface.strokeBorder(.primary.opacity(0.10 * separation), lineWidth: 1 / displayScale)
                            }
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    .offset(x: sign * reveal)

                if wide && isPresented {
                    Rectangle()
                        .fill(.separator)
                        .frame(width: 1)
                        .frame(width: 20)
                        .contentShape(Rectangle())
                        .offset(x: sign * (width - 10))
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named(gestureSpace))
                                .updating($resizeDrag) { value, state, transaction in
                                    transaction.disablesAnimations = true
                                    if state == nil {
                                        state = ChatSidebarDrag(width: baseWidth, presented: true,
                                            direction: sign, initialTranslation: value.translation, resizing: true)
                                    }
                                    state?.update(value.translation)
                                }
                                .onEnded { value in
                                    guard let drag = resizeDrag else { return }
                                    preferredWidth = ChatSidebarLayout.width(
                                        available: available,
                                        preferred: drag.startWidth + value.translation.width * drag.direction,
                                        wide: true
                                    )
                                }
                        )
                        .accessibilityLabel("Sidebar width")
                        .accessibilityValue(Text("\(Int(width))"))
                        .accessibilityAdjustableAction { adjustment in
                            preferredWidth = ChatSidebarLayout.width(
                                available: available,
                                preferred: width + (adjustment == .increment ? 20 : -20),
                                wide: true
                            )
                        }
                }
            }
            .frame(width: available, height: geometry.size.height, alignment: .leading)
            .coordinateSpace(name: gestureSpace)
            .onPreferenceChange(SidebarRevealExclusionFrameKey.self) { revealExclusionFrame = $0 }
            .onChange(of: wide, initial: true) { _, wide in
                isCompact = !wide
            }
            // Do not clip here: native navigation controls can occupy the
            // window's safe-area rail outside this content rectangle on Duo.
            .animation(motion, value: isPresented)
            .animation(motion, value: revealDrag == nil)
        }
        .sensoryFeedback(.selection, trigger: isPresented) { old, new in
            hapticsEnabled && old != new
        }
    }

    private func revealGesture(width: CGFloat, shellFrame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: ChatSidebarDrag.activationDistance, coordinateSpace: .named(gestureSpace))
            .updating($revealDrag) { value, state, transaction in
                guard ChatSidebarLayout.allowsReveal(startLocation: value.startLocation,
                    shellFrame: shellFrame, excludedFrame: revealExclusionFrame) else { return }
                // Track the finger directly, including the first drag update.
                // Only settling after release is animated, without a spring.
                transaction.disablesAnimations = true
                if state == nil {
                    state = ChatSidebarDrag(width: width, presented: isPresented,
                        direction: sign, initialTranslation: value.translation)
                }
                state?.update(value.translation)
            }
            .onEnded { value in
                guard ChatSidebarLayout.allowsReveal(startLocation: value.startLocation,
                    shellFrame: shellFrame, excludedFrame: revealExclusionFrame) else { return }
                // GestureState is transient: release must still commit if
                // SwiftUI has already reset it before this callback reads it.
                let drag = revealDrag ?? ChatSidebarDrag(width: width, presented: isPresented,
                    direction: sign, initialTranslation: value.translation)
                isPresented = drag.settlesOpen(projected: value.predictedEndTranslation)
            }
    }
}
