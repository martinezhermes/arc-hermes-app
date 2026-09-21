import XCTest
@testable import HermesMobile

/// Focused unit tests for #21 covering only behavior production code
/// consumes: the `SessionListSearchChrome` open/type/clear/close lifecycle
/// that `SessionListView.openSearch`/`closeSearch` drive.
@MainActor
final class SessionListTopChromeTests: XCTestCase {
    func testOpenExpandsWhilePreservingQuery() {
        var state = SessionListSearchChrome()
        XCTAssertFalse(state.isExpanded)
        XCTAssertFalse(state.isVisible)

        SessionListSearchChrome.applyOpen(to: &state, preserving: "  Planning ")
        XCTAssertTrue(state.isExpanded)
        XCTAssertTrue(state.isVisible)
        XCTAssertEqual(state.query, "  Planning ")
        XCTAssertEqual(state.normalizedQuery, "planning")
    }

    func testClearButtonAppearsOnlyWhenExpandedWithQuery() {
        XCTAssertFalse(SessionListSearchChrome.showsClearButton(isExpanded: false, query: "planning"))
        XCTAssertFalse(SessionListSearchChrome.showsClearButton(isExpanded: true, query: ""))
        // Whitespace-only input still counts as a query for the button (the
        // list filters on the normalized form); production shows the clear
        // control so the user can escape the state.
        XCTAssertTrue(SessionListSearchChrome.showsClearButton(isExpanded: true, query: "   "))
        XCTAssertTrue(SessionListSearchChrome.showsClearButton(isExpanded: true, query: "planning"))

        // The instance derivation matches the static one production uses.
        var state = SessionListSearchChrome()
        SessionListSearchChrome.applyOpen(to: &state, preserving: "planning")
        XCTAssertEqual(state.showsClearButton, SessionListSearchChrome.showsClearButton(isExpanded: true, query: "planning"))
        state.clearQuery()
        XCTAssertFalse(state.showsClearButton)
    }

    func testCloseCollapsesAndClearsQuery() {
        var state = SessionListSearchChrome()
        SessionListSearchChrome.applyOpen(to: &state, preserving: "planning")
        state.query = "triage inbox"
        XCTAssertTrue(state.isExpanded)

        SessionListSearchChrome.applyClose(to: &state)
        XCTAssertFalse(state.isExpanded)
        XCTAssertFalse(state.isVisible)
        XCTAssertEqual(state.query, "")
        XCTAssertFalse(state.showsClearButton)
    }

}
