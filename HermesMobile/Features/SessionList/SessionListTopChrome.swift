import SwiftUI

/// Production-owned mutation model for the search chrome (#21): expand,
/// filter, and close all operate on one query. `SessionListView` owns an
/// instance and derives its `@State` flags from it, so the open/type/clear/
/// close lifecycle has one definition shared by the view and its tests.
struct SessionListSearchChrome: Equatable {
    var isExpanded = false
    var isVisible = false
    var query = ""

    var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var showsClearButton: Bool {
        isExpanded && !query.isEmpty
    }

    /// Focused derivation used by the chrome presentation: the clear button
    /// appears only while expanded with a non-empty query.
    static func showsClearButton(isExpanded: Bool, query: String) -> Bool {
        isExpanded && !query.isEmpty
    }

    static func applyOpen(to state: inout SessionListSearchChrome, preserving query: String? = nil) {
        if let query { state.query = query }
        state.isVisible = true
        state.isExpanded = true
    }

    /// Close collapses the chrome and clears the query — the single
    /// definition both the view's close action and tests exercise.
    static func applyClose(to state: inout SessionListSearchChrome) {
        state.isExpanded = false
        state.isVisible = false
        state.query = ""
    }

    mutating func clearQuery() {
        query = ""
    }
}

/// Controls for the session list's native safe-area bar. The enclosing bar
/// supplies the scroll-edge treatment; this view supplies no backdrop.
struct SessionListTopChrome: View {
    static let headerAccessibilityIdentifier = "session-list-top-chrome"
    static let searchFieldAccessibilityIdentifier = "session-list-search-field"
    static let searchToggleAccessibilityIdentifier = "session-list-search-toggle"
    static let searchCloseAccessibilityIdentifier = "session-list-search-close"

    /// Optical size of the SF Symbol glyphs (22pt font in a 36pt box keeps
    /// the magnifier/xmark visually balanced against the 160pt wordmark).
    private static let iconVisualSize: CGFloat = 36
    /// HIG minimum touch target; the visual box is centered inside it.
    private static let iconHitTarget: CGFloat = 44

    let headerLogoColor: Color
    let headerLogoText: String
    @Binding var searchText: String
    @Binding var searchChromeIsExpanded: Bool
    var searchFieldIsFocused: FocusState<Bool>.Binding
    let showsSearchClearButton: Bool
    let reduceMotion: Bool
    let onOpenSearch: () -> Void
    let onCloseSearch: () -> Void
    let onSearchFocusChange: (Bool) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: searchChromeIsExpanded ? 0 : 16) {
            HermesHeaderLogo(selectedColor: headerLogoColor, text: headerLogoText)
                .frame(width: searchChromeIsExpanded ? 0 : 160, alignment: .leading)
                .opacity(searchChromeIsExpanded ? 0 : 1)
                .clipped()
                .accessibilityHidden(searchChromeIsExpanded)

            searchChrome
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        // Match the sidebar's bottom controls horizontally; the bar derives
        // its height from its content and standard vertical padding.
        .padding(.horizontal, 24)
        .padding(.vertical)
        .accessibilityIdentifier(Self.headerAccessibilityIdentifier)
        .animation(SessionListMotion.searchChromeAnimation(reduceMotion: reduceMotion), value: searchChromeIsExpanded)
        .animation(SessionListMotion.searchFocusAnimation(reduceMotion: reduceMotion), value: showsSearchClearButton)
        .onChange(of: searchFieldIsFocused.wrappedValue) { _, newValue in
            onSearchFocusChange(newValue)
        }
    }

    private var searchChrome: some View {
        HStack(spacing: searchChromeIsExpanded ? 8 : 0) {
            HapticButton {
                if searchChromeIsExpanded {
                    searchFieldIsFocused.wrappedValue = true
                } else {
                    onOpenSearch()
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(searchChromeIsExpanded ? .secondary : .primary)
                    .frame(width: Self.iconVisualSize, height: Self.iconVisualSize)
                    .frame(width: 48, height: 48)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(searchChromeIsExpanded ? "Focus session search" : "Search sessions")
            .accessibilityHint("Shows the session search field.")
            .accessibilityIdentifier(Self.searchToggleAccessibilityIdentifier)
            .accessibilityHidden(searchChromeIsExpanded)

            searchTextField

            if showsSearchClearButton {
                searchClearButton
                    .transition(.scale.combined(with: .opacity))
            }

            if searchChromeIsExpanded {
                searchCloseButton
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: searchChromeIsExpanded ? .infinity : nil, alignment: .trailing)
        .sessionsChromeGlass(
            isInteractive: true,
            in: Capsule()
        )
        .clipShape(Capsule())
        .contentShape(Capsule())
    }

    private var searchTextField: some View {
        TextField("Search sessions", text: $searchText)
            .font(AppFont.subheadline())
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused(searchFieldIsFocused)
            .submitLabel(.done)
            .lineLimit(1)
            .layoutPriority(1)
            .frame(maxWidth: searchChromeIsExpanded ? .infinity : 0)
            .opacity(searchChromeIsExpanded ? 1 : 0)
            .clipped()
            .accessibilityIdentifier(Self.searchFieldAccessibilityIdentifier)
            .accessibilityHidden(!searchChromeIsExpanded)
    }

    private var searchClearButton: some View {
        Button {
            searchText = ""
            searchFieldIsFocused.wrappedValue = true
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(AppFont.subheadline())
                .foregroundStyle(.secondary)
                .frame(width: Self.iconVisualSize, height: Self.iconVisualSize)
                .frame(width: Self.iconHitTarget, height: Self.iconHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear search")
    }

    private var searchCloseButton: some View {
        HapticButton(feedbackStyle: .medium, action: onCloseSearch) {
            Image(systemName: "xmark")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: Self.iconHitTarget, height: Self.iconHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close search")
        .accessibilityHint("Closes search and clears the current query.")
        .accessibilityIdentifier(Self.searchCloseAccessibilityIdentifier)
    }
}
