import SwiftUI
import UIKit
import Combine

extension EnvironmentValues {
    @Entry var navigationSurfaceIsActive = true
    @Entry var drawerFocusScope: DrawerFocusScope?
    @Entry var drawerPane: DrawerPane?
}

enum DrawerPane: Equatable { case sidebar, detail }

/// One drawer's current interaction and editing intent. Focus changes do not redraw its panes.
@MainActor final class DrawerFocusScope {
    private(set) var revision = 0
    var sceneIsActive = false
    var presentation: Binding<Bool>?
    var isWide = false
    var isRevealing = false
    private weak var editorScene: UIWindowScene?
    private weak var editorView: UIView?
    private var focusedPane: DrawerPane?

    func invalidateRestoration() {
        revision &+= 1
        focusedPane = nil
    }

    func claimFocus(_ pane: DrawerPane) {
        revision &+= 1
        focusedPane = pane
    }

    func intendsFocus(in pane: DrawerPane?) -> Bool { pane != nil && pane == focusedPane }

    func registerEditor(_ editor: UIView) {
        editorScene = editor.window?.windowScene
        editorView = editor
        claimFocus(.detail)
    }

    func isActive(_ pane: DrawerPane) -> Bool {
        guard sceneIsActive, let presentation else { return false }
        if pane == .detail { return isWide || (!presentation.wrappedValue && !isRevealing) }
        return presentation.wrappedValue && !isRevealing
    }

    func didBeginEditing(_ notification: Notification) {
        guard let view = notification.object as? UIView, let editorScene,
              view.window?.windowScene === editorScene else { return }
        if view === editorView { return }
        invalidateRestoration()
    }
}

/// A drawer blur suspends the existing editor; newer focus and scene actions supersede its return.
struct DrawerFocusRestorationModifier: ViewModifier {
    @Binding var isFocused: Bool
    var allowsRestoration = true
    @Environment(\.navigationSurfaceIsActive) private var surfaceIsActive
    @Environment(\.drawerFocusScope) private var scope
    @Environment(\.drawerPane) private var pane
    @Environment(\.scenePhase) private var scenePhase
    @State private var suspendedRevision: Int?
    @State private var ownsPendingBlur = false
    @State private var restorationTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onChange(of: surfaceIsActive) { _, active in
                restorationTask?.cancel()
                if !active {
                    // Disabling a native editor can clear its binding before this callback.
                    let wasEditing = isFocused || scope?.intendsFocus(in: pane) == true
                    suspendedRevision = wasEditing ? scope?.revision : nil
                    ownsPendingBlur = wasEditing
                    isFocused = false
                } else {
                    restoreIfCurrent()
                }
            }
            .onChange(of: isFocused) { _, focused in
                if !focused, ownsPendingBlur {
                    ownsPendingBlur = false
                } else if focused {
                    ownsPendingBlur = false
                    suspendedRevision = nil
                    restorationTask?.cancel()
                    if let pane { scope?.claimFocus(pane) }
                } else if let pane, scope?.isActive(pane) ?? surfaceIsActive {
                    invalidate()
                }
            }
            .onChange(of: allowsRestoration) { _, allowed in
                if !allowed { invalidate() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { invalidate() }
            }
            .onDisappear { invalidate() }
    }

    private func restoreIfCurrent() {
        let revision = suspendedRevision
        suspendedRevision = nil
        guard allowsRestoration, scenePhase == .active,
              let scope, let pane, let revision, revision == scope.revision else { return }
        restorationTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, scope.isActive(pane), revision == scope.revision else { return }
            isFocused = true
        }
    }

    private func invalidate() {
        restorationTask?.cancel()
        suspendedRevision = nil
        ownsPendingBlur = false
        scope?.invalidateRestoration()
    }
}

/// A mounted pane keeps its draft and stream while only its local interaction pauses.
struct ChatPaneActivity: Equatable {
    let sidebar: Bool
    let detail: Bool

    init(wide: Bool, sidebarPresented: Bool, isRevealing: Bool) {
        sidebar = sidebarPresented && !isRevealing
        detail = wide || (!sidebarPresented && !isRevealing)
    }
}

/// Layout policy shared by the live container and its regression tests.
enum ChatSidebarLayout {
    static func allowsReveal(at globalStart: CGPoint, excluding frames: [CGRect]?) -> Bool {
        frames?.contains { $0.contains(globalStart) } != true
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

    /// GestureState may be gone at release; commit the final total translation from the saved base.
    static func completedResizeWidth(drag: ChatSidebarDrag?, baseWidth: CGFloat,
                                     translation: CGFloat, direction: CGFloat, available: CGFloat) -> CGFloat {
        width(available: available,
              preferred: (drag?.startWidth ?? baseWidth) + translation * (drag?.direction ?? direction),
              wide: true)
    }

    static func reveal(width: CGFloat, presented: Bool, translation: CGFloat) -> CGFloat {
        min(width, max(0, (presented ? width : 0) + translation))
    }

    /// Compact chat covers an anchored sidebar; wide layouts still reclaim its column.
    static func sidebarOffset(width: CGFloat, reveal: CGFloat, wide: Bool) -> CGFloat {
        wide ? reveal - width : 0
    }

    /// A restrained fade follows coverage, so reversing a drag has no separate animation to unwind.
    static func sidebarOpacity(separation: CGFloat, wide: Bool, reduceMotion: Bool) -> Double {
        guard !wide, !reduceMotion else { return 1 }
        return 0.88 + 0.12 * Double(min(1, max(0, separation)))
    }

    /// A small uniform scale makes the covered pane recede without a sideways translation.
    static func sidebarScale(separation: CGFloat, wide: Bool, reduceMotion: Bool) -> CGFloat {
        guard !wide, !reduceMotion else { return 1 }
        return 0.97 + 0.03 * min(1, max(0, separation))
    }

    static func settlesOpen(width: CGFloat, presented: Bool, projectedTranslation: CGFloat) -> Bool {
        reveal(width: width, presented: presented, translation: projectedTranslation) > width / 2
    }
}

struct SidebarRevealExclusionFrameKey: PreferenceKey {
    static let defaultValue: [CGRect] = []

    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue().filter { !$0.isNull && !$0.isEmpty })
    }
}

/// Gesture-only geometry: updating it while content scrolls must not invalidate the shell.
@MainActor final class SidebarRevealExclusions {
    var frames: [CGRect] = []
}

extension View {
    /// A horizontal surface owns its gestures even when its content currently fits.
    func sidebarRevealGestureExcluded() -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(key: SidebarRevealExclusionFrameKey.self,
                                       value: [geometry.frame(in: .global)])
            }
        }
    }
}

/// A drag keeps its original geometry and axis even as the rendered pane moves.
struct ChatSidebarDrag {
    static let activationDistance: CGFloat = 12
    let startWidth: CGFloat
    let startedPresented: Bool
    let direction: CGFloat
    private(set) var isHorizontal: Bool?
    private(set) var hasAcceptedTransition = false
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
        if isHorizontal == true {
            translation = value.width * direction
            let travel = startedPresented ? -translation : translation
            if travel >= Self.activationDistance { hasAcceptedTransition = true }
        }
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
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppHaptics.isEnabledKey) private var hapticsEnabled = true
    @Binding var isPresented: Bool
    @Binding var isCompact: Bool
    @State private var preferredWidth: CGFloat?
    @State private var revealExclusions = SidebarRevealExclusions()
    @State private var focusScope = DrawerFocusScope()
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
            let activity = ChatPaneActivity(wide: wide, sidebarPresented: isPresented,
                                            isRevealing: revealDrag?.hasAcceptedTransition == true)
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
                    .environment(\.navigationSurfaceIsActive, activity.sidebar)
                    .environment(\.drawerPane, .sidebar)
                    .disabled(!activity.sidebar)
                    .scrollDisabled(!activity.sidebar)
                    .frame(width: width)
                    .frame(maxHeight: .infinity)
                    .scaleEffect(ChatSidebarLayout.sidebarScale(separation: separation, wide: wide, reduceMotion: reduceMotion), anchor: .leading)
                    .offset(x: ChatSidebarLayout.sidebarOffset(width: width, reveal: reveal, wide: wide))
                    .opacity(ChatSidebarLayout.sidebarOpacity(separation: separation, wide: wide, reduceMotion: reduceMotion))
                    .allowsHitTesting(isPresented)
                    .accessibilityHidden(!isPresented)
                    .simultaneousGesture(revealGesture(width: width, excludesContent: false), isEnabled: !wide && isPresented)

                detail
                    .environment(\.navigationSurfaceIsActive, activity.detail)
                    .environment(\.drawerPane, .detail)
                    .disabled(!activity.detail)
                    .scrollDisabled(!activity.detail)
                    .frame(width: wide ? max(0, available - reveal) : available)
                    .frame(maxHeight: .infinity)
                    // Extend only the painted card into the window's safe areas.
                    // Matching negative padding below keeps native content in place.
                    .padding(.top, geometry.safeAreaInsets.top)
                    .padding(.bottom, geometry.safeAreaInsets.bottom)
                    .padding(.leading, geometry.safeAreaInsets.leading)
                    .padding(.trailing, geometry.safeAreaInsets.trailing)
                    .background(.background, ignoresSafeAreaEdges: [])
                    .clipShape(chatSurface)
                    .background {
                        chatSurface.fill(.background)
                            .shadow(color: .black.opacity(0.12 * separation), radius: 6, x: -2 * sign)
                    }
                    // A compact reveal leaves only a slice of chat visible;
                    // don't let its native indicator cling to the window edge.
                    .scrollIndicators(!wide && (isPresented || reveal > 0) ? .hidden : .automatic, axes: .vertical)
                    // Recognize horizontal reveals across the chat while its
                    // child scroll views continue handling vertical movement.
                    .simultaneousGesture(revealGesture(width: width), isEnabled: !wide && !isPresented)
                    .accessibilityHidden(!wide && isPresented)
                    .overlay {
                        if !wide && isPresented {
                            chatSurface.fill(Color.clear)
                                .contentShape(chatSurface)
                                .onTapGesture { isPresented = false }
                                .gesture(revealGesture(width: width, excludesContent: false))
                                .accessibilityLabel("Hide Sessions")
                                .accessibilityAddTraits(.isButton)
                        }
                    }
                    // The edge follows the same full-height card without tinting its content.
                    .overlay {
                        chatSurface.strokeBorder(Color(uiColor: .separator), lineWidth: 1)
                            .opacity(separation)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    .padding(.top, -geometry.safeAreaInsets.top)
                    .padding(.bottom, -geometry.safeAreaInsets.bottom)
                    .padding(.leading, -geometry.safeAreaInsets.leading)
                    .padding(.trailing, -geometry.safeAreaInsets.trailing)
                    // SwiftUI offsets already run from leading to trailing, including RTL.
                    .offset(x: reveal)

                if wide && isPresented {
                    Rectangle()
                        .fill(.separator)
                        .frame(width: 1)
                        .frame(width: 20)
                        .contentShape(Rectangle())
                        .offset(x: width - 10)
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
                                    preferredWidth = ChatSidebarLayout.completedResizeWidth(
                                        drag: resizeDrag, baseWidth: baseWidth,
                                        translation: value.translation.width, direction: sign, available: available
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
            .environment(\.drawerFocusScope, focusScope)
            .onAppear {
                focusScope.presentation = _isPresented
                focusScope.sceneIsActive = scenePhase == .active
                focusScope.isWide = wide
            }
            .onDisappear {
                focusScope.presentation = nil
                focusScope.sceneIsActive = false
                focusScope.invalidateRestoration()
            }
            .onChange(of: revealDrag?.hasAcceptedTransition == true) { _, revealing in
                focusScope.isRevealing = revealing
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                focusScope.sceneIsActive = phase == .active
                if phase != .active { focusScope.invalidateRestoration() }
            }
            .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)
                .merge(with: NotificationCenter.default.publisher(for: UITextView.textDidBeginEditingNotification))) {
                focusScope.didBeginEditing($0)
            }
            .onPreferenceChange(SidebarRevealExclusionFrameKey.self) { revealExclusions.frames = $0 }
            .onChange(of: wide, initial: true) { _, wide in
                focusScope.isWide = wide
                isCompact = !wide
            }
            // Keep the shell unmasked; only the expanded detail card is clipped.
            .animation(motion, value: isPresented)
            .animation(motion, value: revealDrag == nil)
        }
        .sensoryFeedback(.selection, trigger: isPresented) { old, new in
            hapticsEnabled && old != new
        }
    }

    private func revealGesture(width: CGFloat, excludesContent: Bool = true) -> some Gesture {
        DragGesture(minimumDistance: ChatSidebarDrag.activationDistance, coordinateSpace: .global)
            .updating($revealDrag) { value, state, transaction in
                guard ChatSidebarLayout.allowsReveal(at: value.startLocation,
                    excluding: excludesContent ? revealExclusions.frames : nil) else { return }
                // Excluded horizontal controls never change pane activity or keyboard focus.
                transaction.disablesAnimations = true
                if state == nil {
                    state = ChatSidebarDrag(width: width, presented: isPresented,
                        direction: sign, initialTranslation: value.translation)
                }
                state?.update(value.translation)
                focusScope.isRevealing = state?.hasAcceptedTransition == true
            }
            .onEnded { value in
                guard ChatSidebarLayout.allowsReveal(at: value.startLocation,
                    excluding: excludesContent ? revealExclusions.frames : nil) else { return }
                // GestureState can reset before release; always apply the final sample.
                var drag = revealDrag ?? ChatSidebarDrag(width: width, presented: isPresented,
                    direction: sign, initialTranslation: value.translation)
                drag.update(value.translation)
                isPresented = drag.settlesOpen(projected: value.predictedEndTranslation)
            }
    }
}
