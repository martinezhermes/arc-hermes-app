import SwiftUI
import XCTest
@testable import ARCHermes

final class SessionNavigationStateTests: XCTestCase {
    /// A Hermes row (#1046) is known by its lineage root and opens its own id, which on a
    /// legacy compression chain is the tip, in the row's Profile. A webui row opens no Hermes chat.
    func testAHermesRowOpensItsOwnIDInItsProfile() {
        let row = HermesSessionRow(id: "tip", profile: "research", lineageRootID: "root").summary(in: "default")

        XCTAssertEqual(row.id, "root")
        XCTAssertEqual(row.hermesTarget(listedIn: "default"), .session(profile: "research", key: "tip"))
        XCTAssertEqual(HermesSessionRow(id: "plain").summary(in: "default").hermesTarget(listedIn: "default"),
                       .session(profile: "default", key: "plain"))
        XCTAssertNil(SessionSummary(sessionId: "webui", profile: "default").hermesTarget(listedIn: "default"))
    }

    func testPushFallbackStaysOnListInsteadOfRestoringPreviousChat() {
        let previous = SessionSummary(sessionId: "old", title: "Old")
        var state = SessionNavigationState(lastSelectedSessionID: "old")
        state.select(previous)
        let oldRevision = state.rootRevision
        state.openSessionList()
        state.restoreIfNeeded(from: [previous])
        XCTAssertNil(state.destination)
        XCTAssertNil(state.lastSelectedSessionID)
        XCTAssertGreaterThan(state.rootRevision, oldRevision)
    }

    func testSelectingSessionUpdatesDestinationAndRestorationID() {
        let session = SessionSummary(sessionId: "session-1", title: "One")
        var state = SessionNavigationState()

        state.select(session)

        XCTAssertEqual(state.destination, .session(session))
        XCTAssertEqual(state.selectedSessionID, "session-1")
        XCTAssertEqual(state.lastSelectedSessionID, "session-1")
    }

    func testRestoreSelectsStoredSessionWhenItStillExists() {
        let first = SessionSummary(sessionId: "session-1", title: "One")
        let second = SessionSummary(sessionId: "session-2", title: "Two")
        var state = SessionNavigationState(lastSelectedSessionID: "session-2")

        state.restoreIfNeeded(from: [first, second])

        XCTAssertEqual(state.destination, .session(second))
        XCTAssertEqual(state.lastSelectedSessionID, "session-2")
    }

    func testRestoreClearsStoredSelectionWhenSessionNoLongerExists() {
        var state = SessionNavigationState(lastSelectedSessionID: "missing")

        state.restoreIfNeeded(from: [SessionSummary(sessionId: "session-1")])

        XCTAssertNil(state.destination)
        XCTAssertNil(state.lastSelectedSessionID)
    }

    func testRestorePreservesStoredSelectionWhenSessionListIsNotAuthoritative() {
        var state = SessionNavigationState(lastSelectedSessionID: "session-1")

        state.restoreIfNeeded(from: [], clearsMissingSelection: false)

        XCTAssertNil(state.destination)
        XCTAssertEqual(state.lastSelectedSessionID, "session-1")
    }

    func testRestoreSkipsWhileDeepLinkIsPendingAndKeepsStoredSelection() {
        let stored = SessionSummary(sessionId: "stored")
        var state = SessionNavigationState(lastSelectedSessionID: "stored")

        state.restoreIfNeeded(from: [stored], pendingDeepLinkedSessionID: "deep-linked")

        XCTAssertNil(state.destination)
        XCTAssertEqual(state.lastSelectedSessionID, "stored")
    }

    func testRestoreSkipsAfterPendingDeepLinkIsConsumedWhileLoadIsInFlight() {
        let stored = SessionSummary(sessionId: "stored")
        var state = SessionNavigationState(lastSelectedSessionID: "stored")

        let deepLinkedSessionID = state.beginDeepLinkedSessionLoad(id: "deep-linked")
        state.restoreIfNeeded(from: [stored], pendingDeepLinkedSessionID: nil)

        XCTAssertEqual(deepLinkedSessionID, "deep-linked")
        XCTAssertNil(state.destination)
        XCTAssertEqual(state.lastSelectedSessionID, "stored")

        state.finishDeepLinkedSessionLoad(id: deepLinkedSessionID)
        state.restoreIfNeeded(from: [stored], pendingDeepLinkedSessionID: nil)

        XCTAssertEqual(state.destination, .session(stored))
    }

    func testRestoreProceedsWhenPendingDeepLinkIDIsBlank() {
        let stored = SessionSummary(sessionId: "stored")
        var state = SessionNavigationState(lastSelectedSessionID: "stored")

        state.restoreIfNeeded(from: [stored], pendingDeepLinkedSessionID: "   ")

        XCTAssertEqual(state.destination, .session(stored))
    }

    func testInitialRefreshStartsBeforeDelayedDeepLinkFinishes() async {
        let recorder = SessionInitialLoadEventRecorder()

        await SessionListInitialLoad.run(
            resolvePendingDeepLink: {
                await recorder.record(.deepLinkStarted)
                try? await Task.sleep(nanoseconds: 50_000_000)
                await recorder.record(.deepLinkFinished)
            },
            loadSessions: {
                await recorder.record(.refreshStarted)
            },
            restoreSelection: {},
            loadProjects: {},
            loadActiveProfile: {}
        )

        let events = await recorder.snapshot()
        guard let refreshIndex = events.firstIndex(of: .refreshStarted),
              let deepLinkFinishIndex = events.firstIndex(of: .deepLinkFinished)
        else {
            return XCTFail("Expected both refresh and deep-link completion events")
        }

        XCTAssertLessThan(refreshIndex, deepLinkFinishIndex)
    }

    /// Over a tunnel each held request is a round trip, so restore must not
    /// wait for projects or the profile, and neither of those waits for the other.
    @MainActor
    func testInitialLoadRestoresBeforeProjectsAndProfileAndLoadsThemTogether() async {
        let log = InitialLoadLog()
        let projects = HeldInitialLoad()
        let profile = HeldInitialLoad()
        let restoredWithBothLoadsInFlight = expectation(description: "restore while projects and profile are held")
        restoredWithBothLoadsInFlight.expectedFulfillmentCount = 2

        let initialLoad = Task { @MainActor in
            await SessionListInitialLoad.run(
                resolvePendingDeepLink: { log.events.append("deepLink") },
                loadSessions: { log.events.append("sessions") },
                restoreSelection: { log.events.append("restore") },
                loadProjects: {
                    restoredWithBothLoadsInFlight.fulfill()
                    await projects.wait()
                    log.events.append("projects")
                },
                loadActiveProfile: {
                    restoredWithBothLoadsInFlight.fulfill()
                    await profile.wait()
                    log.events.append("profile")
                }
            )
        }

        await fulfillment(of: [restoredWithBothLoadsInFlight], timeout: 5)
        XCTAssertEqual(Set(log.events), ["deepLink", "sessions", "restore"])
        XCTAssertEqual(log.events.last, "restore")

        profile.release()
        projects.release()
        await initialLoad.value
        XCTAssertEqual(Set(log.events.suffix(2)), ["projects", "profile"])
    }

    func testExplicitNewChatRouteOverridesStoredSelection() {
        let route = PendingNewChatRoute(initialDraft: "Shared draft")
        var state = SessionNavigationState(lastSelectedSessionID: "session-1")
        state.select(route)

        state.restoreIfNeeded(from: [SessionSummary(sessionId: "session-1")])

        XCTAssertEqual(state.destination, .newChat(route))
        XCTAssertEqual(state.lastSelectedSessionID, "session-1")
    }

    func testExplicitSessionRouteOverridesStoredSelection() {
        let stored = SessionSummary(sessionId: "stored")
        let deepLinked = SessionSummary(sessionId: "deep-linked")
        var state = SessionNavigationState(lastSelectedSessionID: "stored")
        state.select(deepLinked)

        state.restoreIfNeeded(from: [stored])

        XCTAssertEqual(state.destination, .session(deepLinked))
        XCTAssertEqual(state.lastSelectedSessionID, "deep-linked")
    }

    func testCreatedSessionRemainsSelectedWhileNewChatRouteOwnsItsDraft() {
        let route = PendingNewChatRoute(initialDraft: "Shared draft")
        let created = SessionSummary(sessionId: "created-session")
        var state = SessionNavigationState()
        state.select(route)
        XCTAssertTrue(state.isCreatingNewChat)

        state.remember(created)

        XCTAssertEqual(state.destination, .newChat(route))
        XCTAssertEqual(state.selectedSessionID, "created-session")
        XCTAssertEqual(state.lastSelectedSessionID, "created-session")
        XCTAssertFalse(state.isCreatingNewChat)
    }

    func testSelectingAnotherNewChatRouteStartsFreshCreationState() {
        let firstRoute = PendingNewChatRoute()
        let secondRoute = PendingNewChatRoute()
        var state = SessionNavigationState()
        state.select(firstRoute)
        state.remember(SessionSummary(sessionId: "created-session"))

        state.select(secondRoute)

        XCTAssertEqual(state.destination, .newChat(secondRoute))
        XCTAssertNil(state.selectedSessionID)
        XCTAssertTrue(state.isCreatingNewChat)
    }

    func testReturningFromContentfulNewChatSuppressesPlaceholdersThenRefreshesSessions() {
        let route = PendingNewChatRoute()
        var state = SessionNavigationState()
        state.select(route)
        state.remember(SessionSummary(sessionId: "created-session"))
        let oldDestination = state.destination
        state.clearDestination()
        var events: [DestinationReturnEvent] = []

        SessionListDestinationReturn.run(
            from: oldDestination,
            to: state.destination,
            suppressEmptyPlaceholders: { events.append(.suppressedPlaceholders) },
            refreshSessions: { events.append(.refreshedSessions) }
        )

        XCTAssertEqual(events, [.suppressedPlaceholders, .refreshedSessions])
    }

    func testReturningFromEmptyNewChatSuppressesPlaceholderThenRefreshesSessions() {
        let route = PendingNewChatRoute()
        var state = SessionNavigationState()
        state.select(route)
        let oldDestination = state.destination
        state.clearDestination()
        var events: [DestinationReturnEvent] = []

        SessionListDestinationReturn.run(
            from: oldDestination,
            to: state.destination,
            suppressEmptyPlaceholders: { events.append(.suppressedPlaceholders) },
            refreshSessions: { events.append(.refreshedSessions) }
        )

        XCTAssertEqual(events, [.suppressedPlaceholders, .refreshedSessions])
    }

    func testReplacingNewChatRouteDoesNotRefreshSessions() {
        let firstRoute = PendingNewChatRoute()
        let secondRoute = PendingNewChatRoute()
        var events: [DestinationReturnEvent] = []

        SessionListDestinationReturn.run(
            from: .newChat(firstRoute),
            to: .newChat(secondRoute),
            suppressEmptyPlaceholders: { events.append(.suppressedPlaceholders) },
            refreshSessions: { events.append(.refreshedSessions) }
        )

        XCTAssertTrue(events.isEmpty)
    }

    func testReturningFromSessionRefreshesSessionsWithoutSuppressingPlaceholders() {
        var state = SessionNavigationState()
        state.select(SessionSummary(sessionId: "session-1"))
        let oldDestination = state.destination
        state.clearDestination()
        var events: [DestinationReturnEvent] = []

        SessionListDestinationReturn.run(
            from: oldDestination,
            to: state.destination,
            suppressEmptyPlaceholders: { events.append(.suppressedPlaceholders) },
            refreshSessions: { events.append(.refreshedSessions) }
        )

        XCTAssertEqual(events, [.refreshedSessions])
    }

    func testSwitchingBetweenSessionsRefreshesSessions() {
        var events: [DestinationReturnEvent] = []

        SessionListDestinationReturn.run(
            from: .session(SessionSummary(sessionId: "session-1")),
            to: .session(SessionSummary(sessionId: "session-2")),
            suppressEmptyPlaceholders: { events.append(.suppressedPlaceholders) },
            refreshSessions: { events.append(.refreshedSessions) }
        )

        XCTAssertEqual(events, [.refreshedSessions])
    }

    func testReturningFromUtilityDestinationRefreshesSessions() {
        var state = SessionNavigationState()
        state.select(SessionListUtilityDestination.archived)
        let oldDestination = state.destination
        state.clearDestination()
        var events: [DestinationReturnEvent] = []

        SessionListDestinationReturn.run(
            from: oldDestination,
            to: state.destination,
            suppressEmptyPlaceholders: { events.append(.suppressedPlaceholders) },
            refreshSessions: { events.append(.refreshedSessions) }
        )

        XCTAssertEqual(events, [.refreshedSessions])
    }

    func testOpeningTheFirstDestinationRefreshesNothing() {
        var events: [DestinationReturnEvent] = []

        SessionListDestinationReturn.run(
            from: nil,
            to: .session(SessionSummary(sessionId: "session-1")),
            suppressEmptyPlaceholders: { events.append(.suppressedPlaceholders) },
            refreshSessions: { events.append(.refreshedSessions) }
        )

        XCTAssertTrue(events.isEmpty)
    }

    func testUnchangedDestinationRefreshesNothing() {
        let destination = SessionNavigationDestination.session(SessionSummary(sessionId: "session-1"))
        var events: [DestinationReturnEvent] = []

        SessionListDestinationReturn.run(
            from: destination,
            to: destination,
            suppressEmptyPlaceholders: { events.append(.suppressedPlaceholders) },
            refreshSessions: { events.append(.refreshedSessions) }
        )

        XCTAssertTrue(events.isEmpty)
    }

    func testActiveRowPollPausesWhileChatCoversCompactList() {
        let chat = SessionNavigationDestination.session(SessionSummary(sessionId: "streaming"))

        XCTAssertTrue(activeRowMonitorID(isRegularWidth: false, destination: nil).shouldPoll)
        XCTAssertFalse(activeRowMonitorID(isRegularWidth: false, destination: chat).shouldPoll)
        XCTAssertFalse(
            activeRowMonitorID(isRegularWidth: false, destination: .utility(.archived)).shouldPoll
        )
        // Scheduled sessions renders live rows, so its badges keep updating.
        XCTAssertTrue(
            activeRowMonitorID(isRegularWidth: false, destination: .utility(.scheduled)).shouldPoll
        )
        // On regular width the sidebar stays on screen beside the chat.
        XCTAssertTrue(activeRowMonitorID(isRegularWidth: true, destination: chat).shouldPoll)
    }

    func testActiveRowPollRestartsWhenReturningToCompactList() {
        let chat = SessionNavigationDestination.session(SessionSummary(sessionId: "streaming"))

        // A different task ID is what makes SwiftUI restart the paused poll.
        XCTAssertNotEqual(
            activeRowMonitorID(isRegularWidth: false, destination: chat),
            activeRowMonitorID(isRegularWidth: false, destination: nil)
        )
        // Selecting another chat on regular width keeps the running poll.
        XCTAssertEqual(
            activeRowMonitorID(isRegularWidth: true, destination: chat),
            activeRowMonitorID(isRegularWidth: true, destination: nil)
        )
    }

    func testActiveRowPollStillSkipsIdleAndCachedLists() {
        XCTAssertFalse(activeRowMonitorID(hasActiveRows: false).shouldPoll)
        XCTAssertFalse(activeRowMonitorID(isViewingCachedData: true).shouldPoll)
        XCTAssertEqual(ActiveSessionMonitorTaskID.pollInterval, .seconds(3))
    }

    @MainActor
    func testReturnToCompactListTicksOnceAfterReloadingRows() async {
        var events: [String] = []
        var streamIDs = ["before-reload"]

        await SessionListReturnRefresh.run(
            refreshSessions: {
                events.append("reload")
                streamIDs = ["after-reload"]
            },
            monitorTaskID: {
                ActiveSessionMonitorTaskID(
                    streamIDs: streamIDs,
                    hasActiveRows: true,
                    isViewingCachedData: false,
                    isRegularWidth: false,
                    destination: nil
                )
            },
            refreshActiveRows: { taskID in
                events.append("tick:\(taskID.streamIDs.joined())")
            }
        )

        // The tick runs right away, on the rows the reload found, rather than
        // leaving stale Approval or Input badges up until the poll's first tick.
        XCTAssertEqual(events, ["reload", "tick:after-reload"])
    }

    @MainActor
    func testReturnSkipsTheTickWhenThePollNeverPaused() async {
        for monitorID in [
            activeRowMonitorID(isRegularWidth: true),
            activeRowMonitorID(hasActiveRows: false),
            activeRowMonitorID(isViewingCachedData: true),
        ] {
            var ticks = 0
            await SessionListReturnRefresh.run(
                refreshSessions: {},
                monitorTaskID: { monitorID },
                refreshActiveRows: { _ in ticks += 1 }
            )
            XCTAssertEqual(ticks, 0)
        }
    }

    private func activeRowMonitorID(
        hasActiveRows: Bool = true,
        isViewingCachedData: Bool = false,
        isRegularWidth: Bool = false,
        destination: SessionNavigationDestination? = nil
    ) -> ActiveSessionMonitorTaskID {
        ActiveSessionMonitorTaskID(
            streamIDs: ["stream-1"],
            hasActiveRows: hasActiveRows,
            isViewingCachedData: isViewingCachedData,
            isRegularWidth: isRegularWidth,
            destination: destination
        )
    }

    func testRemovingSelectedSessionClearsDestinationAndRestorationID() {
        let session = SessionSummary(sessionId: "session-1")
        var state = SessionNavigationState()
        state.select(session)

        state.remove(sessionID: "session-1")

        XCTAssertNil(state.destination)
        XCTAssertNil(state.lastSelectedSessionID)
    }

    func testRemovingRememberedSessionPreservesDifferentVisibleDestination() {
        var state = SessionNavigationState(lastSelectedSessionID: "session-1")
        state.select(SessionListUtilityDestination.tasks)

        state.remove(sessionID: "session-1")

        XCTAssertEqual(state.destination, .utility(.tasks))
        XCTAssertNil(state.lastSelectedSessionID)
    }

    func testUtilityDestinationRemainsSelectedAcrossLayoutReevaluation() {
        var state = SessionNavigationState()
        state.select(SessionListUtilityDestination.tasks)

        let reevaluatedState = state

        XCTAssertEqual(reevaluatedState.destination, .utility(.tasks))
        XCTAssertNil(reevaluatedState.selectedSessionID)
    }

    func testKanbanIsSelectableAsAUtilityDestination() {
        var state = SessionNavigationState()

        state.select(SessionListUtilityDestination.kanban)

        XCTAssertEqual(state.destination, .utility(.kanban))
        XCTAssertNil(state.selectedSessionID)
    }

    func testReselectingRootDestinationAdvancesNavigationRevision() {
        var state = SessionNavigationState()
        state.select(SessionListUtilityDestination.skills)
        let firstRevision = state.rootRevision

        state.select(SessionListUtilityDestination.skills)

        XCTAssertEqual(state.destination, .utility(.skills))
        XCTAssertGreaterThan(state.rootRevision, firstRevision)
    }

    func testReadableContentWidthsKeepSecondaryAndWorkspaceSurfacesDistinct() {
        XCTAssertEqual(AdaptiveReadableContentWidth.secondaryDestination, 800)
        XCTAssertEqual(AdaptiveReadableContentWidth.workspace, 1_000)
        XCTAssertLessThan(
            AdaptiveReadableContentWidth.secondaryDestination,
            AdaptiveReadableContentWidth.workspace
        )
    }

    func testPersistenceUsesIndependentKeysPerServer() throws {
        let suiteName = "SessionNavigationStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstServer = try XCTUnwrap(URL(string: "https://first.example.com"))
        let secondServer = try XCTUnwrap(URL(string: "https://second.example.com"))

        SessionNavigationPersistence.save("first-session", for: firstServer, defaults: defaults)
        SessionNavigationPersistence.save("second-session", for: secondServer, defaults: defaults)

        XCTAssertEqual(
            SessionNavigationPersistence.load(for: firstServer, defaults: defaults),
            "first-session"
        )
        XCTAssertEqual(
            SessionNavigationPersistence.load(for: secondServer, defaults: defaults),
            "second-session"
        )
    }

    func testForegroundReturnRefreshesAtOnceWhenNothingIsLoading() {
        var refresh = SessionListForegroundRefresh()

        XCTAssertTrue(refresh.appReturned(didCompleteInitialLoad: true, isLoading: false))
        XCTAssertFalse(refresh.isPending)
        XCTAssertFalse(refresh.consumeIfReady(didCompleteInitialLoad: true, isLoading: false))
    }

    func testForegroundReturnDuringTheInitialLoadRefreshesOnceItCompletes() {
        var refresh = SessionListForegroundRefresh()

        XCTAssertFalse(refresh.appReturned(didCompleteInitialLoad: false, isLoading: true))
        XCTAssertFalse(refresh.consumeIfReady(didCompleteInitialLoad: false, isLoading: false))
        XCTAssertTrue(refresh.consumeIfReady(didCompleteInitialLoad: true, isLoading: false))
        XCTAssertFalse(refresh.consumeIfReady(didCompleteInitialLoad: true, isLoading: false))
    }

    func testForegroundReturnDuringALoadRefreshesOnceWhenItSettles() {
        var refresh = SessionListForegroundRefresh()

        XCTAssertFalse(refresh.appReturned(didCompleteInitialLoad: true, isLoading: true))
        XCTAssertFalse(refresh.consumeIfReady(didCompleteInitialLoad: true, isLoading: true))
        XCTAssertTrue(refresh.consumeIfReady(didCompleteInitialLoad: true, isLoading: false))
        XCTAssertFalse(
            refresh.consumeIfReady(didCompleteInitialLoad: true, isLoading: false),
            "the deferred refresh runs once, and its own load must not trigger another"
        )
    }

    func testRepeatedForegroundReturnsDuringALoadCoalesce() {
        var refresh = SessionListForegroundRefresh()

        XCTAssertFalse(refresh.appReturned(didCompleteInitialLoad: true, isLoading: true))
        XCTAssertFalse(refresh.appReturned(didCompleteInitialLoad: true, isLoading: true))
        XCTAssertTrue(refresh.consumeIfReady(didCompleteInitialLoad: true, isLoading: false))
        XCTAssertFalse(refresh.consumeIfReady(didCompleteInitialLoad: true, isLoading: false))
    }

    func testLoadsWithoutAForegroundReturnDoNotRefresh() {
        var refresh = SessionListForegroundRefresh()

        XCTAssertFalse(refresh.consumeIfReady(didCompleteInitialLoad: true, isLoading: false))
    }

    func testArchiveToastShowsOnTheScreenTheRowWasSwipedOn() {
        var route = SessionListArchiveToastRoute()
        let scheduledArchive = route.archiveStarted()
        XCTAssertEqual(
            route.archiveConfirmed(
                scheduledArchive, swipedOn: .scheduled, destination: .utility(.scheduled), isRegularWidth: false
            ),
            .scheduled
        )
        XCTAssertEqual(route.host, .scheduled)

        // iPad: the sidebar keeps its own toast while Scheduled fills the detail column.
        let sidebarArchive = route.archiveStarted()
        XCTAssertEqual(
            route.archiveConfirmed(
                sidebarArchive, swipedOn: .list, destination: .utility(.scheduled), isRegularWidth: true
            ),
            .list
        )
        XCTAssertEqual(route.host, .list)
    }

    func testArchiveToastFollowsTheUserToTheOtherSessionScreen() {
        var route = SessionListArchiveToastRoute()

        // iPhone: swiped on Scheduled, then tapped Back before the reply.
        let leftScheduled = route.archiveStarted()
        XCTAssertEqual(
            route.archiveConfirmed(leftScheduled, swipedOn: .scheduled, destination: nil, isRegularWidth: false),
            .list
        )

        // iPhone: swiped on the list, then opened Scheduled before the reply.
        let openedScheduled = route.archiveStarted()
        XCTAssertEqual(
            route.archiveConfirmed(
                openedScheduled, swipedOn: .list, destination: .utility(.scheduled), isRegularWidth: false
            ),
            .scheduled
        )
    }

    func testArchiveToastIsSkippedWhileAnotherScreenCoversBothHosts() {
        var route = SessionListArchiveToastRoute()
        let older = route.archiveStarted()
        let newer = route.archiveStarted()
        let chat = SessionNavigationDestination.session(SessionSummary(sessionId: "open-chat"))

        XCTAssertNil(route.archiveConfirmed(newer, swipedOn: .scheduled, destination: chat, isRegularWidth: false))
        XCTAssertEqual(
            route.archiveConfirmed(older, swipedOn: .list, destination: nil, isRegularWidth: false),
            .list,
            "a skipped toast must not block an older archive that lands where the user can see it"
        )
    }

    func testOlderArchiveNeverReplacesTheNewerArchivesToast() {
        var route = SessionListArchiveToastRoute()
        let first = route.archiveStarted()
        let second = route.archiveStarted()

        XCTAssertEqual(route.archiveConfirmed(second, swipedOn: .list, destination: nil, isRegularWidth: false), .list)
        XCTAssertNil(
            route.archiveConfirmed(first, swipedOn: .list, destination: nil, isRegularWidth: false),
            "the first archive's reply landed last"
        )
    }

    func testChatShortcutPositionPicksNthChatOrNothing() {
        let chats = ["a", "b", "c"].map { SessionSummary(sessionId: $0) }

        XCTAssertEqual(ChatShortcutNavigation.chat(atPosition: 1, in: chats)?.sessionId, "a")
        XCTAssertEqual(ChatShortcutNavigation.chat(atPosition: 3, in: chats)?.sessionId, "c")
        XCTAssertNil(ChatShortcutNavigation.chat(atPosition: 4, in: chats))
        XCTAssertNil(ChatShortcutNavigation.chat(atPosition: 9, in: chats))
        XCTAssertNil(ChatShortcutNavigation.chat(atPosition: 0, in: chats))
        XCTAssertNil(ChatShortcutNavigation.chat(atPosition: 1, in: []))
    }

    func testNextAndPreviousChatWrapAndStartFromTheEndsWithoutSelection() {
        let chats = ["a", "b", "c"].map { SessionSummary(sessionId: $0) }
        func adjacent(_ offset: Int, from selectedSessionID: String?) -> String? {
            ChatShortcutNavigation.adjacentChat(offset: offset, from: selectedSessionID, in: chats)?.sessionId
        }

        XCTAssertEqual(adjacent(1, from: "a"), "b")
        XCTAssertEqual(adjacent(-1, from: "b"), "a")
        XCTAssertEqual(adjacent(1, from: "c"), "a", "next wraps from the last chat to the first")
        XCTAssertEqual(adjacent(-1, from: "a"), "c", "previous wraps from the first chat to the last")
        XCTAssertEqual(adjacent(1, from: nil), "a")
        XCTAssertEqual(adjacent(-1, from: nil), "c")
        XCTAssertEqual(adjacent(1, from: "filtered-out"), "a")
        XCTAssertEqual(adjacent(-1, from: "filtered-out"), "c")
        XCTAssertNil(ChatShortcutNavigation.adjacentChat(offset: 1, from: "a", in: []))
    }
}

private enum DestinationReturnEvent: Equatable {
    case suppressedPlaceholders
    case refreshedSessions
}

@MainActor
private final class InitialLoadLog {
    var events: [String] = []
}

/// Holds a scripted load open until the test releases it.
@MainActor
private final class HeldInitialLoad {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isReleased = false

    func wait() async {
        guard !isReleased else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        isReleased = true
        continuation?.resume()
        continuation = nil
    }
}

private actor SessionInitialLoadEventRecorder {
    enum Event: Equatable {
        case deepLinkStarted
        case refreshStarted
        case deepLinkFinished
    }

    private var events: [Event] = []

    func record(_ event: Event) {
        events.append(event)
    }

    func snapshot() -> [Event] {
        events
    }
}

/// Hosts the native ARC sidebar shell in a real window. Creation counts show which
/// column a root selection re-identifies; the detail column's navigation stack
/// shows what it pops and keeps; probe views entering and leaving the window mark
/// when the sidebar and pushed screens actually change, so tests wait on those
/// events rather than on a number of main-queue turns.
@MainActor
final class HermesHomeIdentityTests: XCTestCase {
    func testRootSelectionRebuildsOnlyTheDetailColumn() throws {
        let log = SplitColumnCreationLog()
        let (host, window) = try hostSplitView(log: log, size: CGSize(width: 1_194, height: 834))
        defer { tearDown(window) }
        XCTAssertEqual(log.sidebar, 1)
        XCTAssertEqual(log.detail, 1)

        host.rootView = splitView(rootRevision: 1, log: log)
        host.view.layoutIfNeeded()

        XCTAssertEqual(log.sidebar, 1, "A root selection must not rebuild the sidebar")
        XCTAssertEqual(log.detail, 2, "A root selection must reset the detail stack")
    }

    func testSelectionClosesOnlyACompactSidebarAndReturnToSessionsOpensIt() {
        var compact = HermesHomeNavigation()
        compact.select(.bots)
        XCTAssertFalse(compact.isSidebarPresented)
        compact.showSessions()
        XCTAssertNil(compact.destination)
        XCTAssertTrue(compact.isSidebarPresented)
        var wide = HermesHomeNavigation(isCompact: false)
        wide.select(.kanban)
        XCTAssertTrue(wide.isSidebarPresented)
        wide.isSidebarPresented = false
        wide.select(.bots)
        XCTAssertFalse(wide.isSidebarPresented)
    }

    func testReopeningTheSameSessionKeepsItsIdentityButOtherProfilesAndConnectionsDoNot() throws {
        let server = try XCTUnwrap(URL(string: "https://native.test"))
        let connection = BotConnection(id: UUID(), name: "Test", address: server, username: "fixture", password: "fixture")
        let first = HermesSessionChat(server: server, connection: connection, target: .session(profile: "default", key: "one"))
        var navigation = HermesHomeNavigation()
        navigation.openChat(first)
        navigation.isSidebarPresented = true
        navigation.openChat(HermesSessionChat(server: server, connection: connection, target: first.target))
        XCTAssertEqual(navigation.destination?.chat?.id, first.id)
        XCTAssertFalse(navigation.isSidebarPresented)
        let anotherProfile = HermesSessionChat(server: server, connection: connection, target: .session(profile: "research", key: "one"))
        navigation.openChat(anotherProfile)
        XCTAssertEqual(navigation.destination?.chat?.id, anotherProfile.id)
        let replacement = BotConnection(id: UUID(), name: "Test", address: server, username: "fixture", password: "fixture")
        let replaced = HermesSessionChat(server: server, connection: replacement, target: anotherProfile.target)
        navigation.openChat(replaced)
        XCTAssertEqual(navigation.destination?.chat?.id, replaced.id)
        var anotherHome = HermesHomeNavigation()
        anotherHome.select(.bots)
        XCTAssertEqual(navigation.destination?.chat?.id, replaced.id, "Another server's navigation owns separate value state")
    }

    func testCompressionTipChangesKeepChatIdentityWhenTheListStillShowsTheOldTip() throws {
        let server = try XCTUnwrap(URL(string: "https://native.test"))
        let connection = BotConnection(id: UUID(), name: "Test", address: server, username: "fixture", password: "fixture")
        let chat = HermesSessionChat(server: server, connection: connection, target: .session(profile: "default", key: "old-tip"))
        var navigation = HermesHomeNavigation()
        navigation.openChat(chat, lineageRootID: "root")
        navigation.identify(.session(profile: "default", key: "new-tip"), chatID: chat.id)
        let staleRow = HermesSessionChat(server: server, connection: connection, target: chat.target)
        navigation.openChat(staleRow, lineageRootID: "root")
        XCTAssertEqual(navigation.destination?.chat?.id, chat.id)
        XCTAssertEqual(navigation.activeTarget, .session(profile: "default", key: "new-tip"))
        let unrelated = HermesSessionChat(server: server, connection: connection, target: .session(profile: "default", key: "different-tip"))
        navigation.openChat(unrelated, lineageRootID: "different-root")
        XCTAssertEqual(navigation.destination?.chat?.id, unrelated.id)
    }

    func testConfirmedRemovalClearsOnlyTheMatchingNativeSessionScope() throws {
        let server = try XCTUnwrap(URL(string: "https://native.test"))
        let otherServer = try XCTUnwrap(URL(string: "https://other.test"))
        let connection = BotConnection(id: UUID(), name: "Test", address: server, username: "fixture", password: "fixture")
        let chat = HermesSessionChat(server: server, connection: connection, target: .new(profile: "default"))
        var navigation = HermesHomeNavigation()
        navigation.select(.chat(chat))
        navigation.identify(.session(profile: "default", key: "created"), chatID: chat.id)
        let row = HermesSessionRow(id: "created", profile: "default").summary(in: "default")
        navigation.remove(row, server: otherServer, connectionID: connection.id, listedIn: "default")
        navigation.remove(row, server: server, connectionID: UUID(), listedIn: "default")
        navigation.remove(HermesSessionRow(id: "created", profile: "research").summary(in: "research"),
                          server: server, connectionID: connection.id, listedIn: "research")
        navigation.remove(HermesSessionRow(id: "other", profile: "default").summary(in: "default"),
                          server: server, connectionID: connection.id, listedIn: "default")
        XCTAssertEqual(navigation.destination?.chat?.id, chat.id)
        navigation.remove(row, server: server, connectionID: connection.id, listedIn: "default")
        XCTAssertNil(navigation.destination)
        XCTAssertNil(navigation.activeTarget)
        XCTAssertTrue(navigation.isSidebarPresented)
    }

    func testRemovedCompressionLineageClosesItsChatAndStaleIdentificationCannotSelectAnother() throws {
        let server = try XCTUnwrap(URL(string: "https://native.test"))
        let connection = BotConnection(id: UUID(), name: "Test", address: server, username: "fixture", password: "fixture")
        let chat = HermesSessionChat(server: server, connection: connection, target: .session(profile: "default", key: "old-tip"))
        var navigation = HermesHomeNavigation()
        navigation.openChat(chat, lineageRootID: "root")
        let removed = HermesSessionRow(id: "new-tip", profile: "default", lineageRootID: "root").summary(in: "default")
        navigation.remove(removed, server: server, connectionID: connection.id, listedIn: "default")
        XCTAssertNil(navigation.destination)
        let another = HermesSessionChat(server: server, connection: connection, target: .session(profile: "default", key: "another"))
        navigation.openChat(another)
        navigation.identify(.session(profile: "default", key: "old-tip"), chatID: chat.id)
        navigation.remove(removed, server: server, connectionID: connection.id, listedIn: "default")
        XCTAssertEqual(navigation.destination?.chat?.id, another.id)
        XCTAssertEqual(navigation.activeTarget, another.target)
    }

    func testSidebarRevealAndWindowResizeKeepTheActiveDetailMounted() throws {
        let log = SplitColumnCreationLog()
        let (host, window) = try hostSplitView(log: log, size: CGSize(width: 1_194, height: 834))
        defer { tearDown(window) }
        host.rootView = splitView(rootRevision: 0, log: log, presented: false)
        host.view.layoutIfNeeded()
        window.frame = CGRect(x: 0, y: 0, width: 500, height: 834)
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        host.rootView = splitView(rootRevision: 0, log: log, presented: true)
        host.view.layoutIfNeeded()
        XCTAssertEqual(log.sidebar, 1)
        XCTAssertEqual(log.detail, 1, "Reveal, collapse and resizing must keep the active chat mounted")
    }

    /// Settings subpages (`NavigationLink`) and file or fork screens
    /// (`navigationDestination`) push inside the detail column; a root selection
    /// must pop them along with the old root (#116), and the new root can push again.
    func testRootSelectionPopsAScreenPushedInsideTheDetail() throws {
        let log = DetailPushLog()
        let host = UIHostingController(rootView: pushingSplitView(rootRevision: 0, log: log))
        let window = try hostWindow(host, size: CGSize(width: 1_194, height: 834))
        defer { tearDown(window) }
        let detailStack = try waitForPushedScreen(log: log) { try push(from: log, in: host) }
        XCTAssertEqual(detailStack.viewControllers.count, 2)

        log.oldPushedScreen = log.pushedScreen
        let oldScreenLeft = expectation(description: "old root's screen left the window")
        oldScreenLeft.assertForOverFulfill = false
        log.pushedScreenMoved = { isOnScreen in
            if !isOnScreen { oldScreenLeft.fulfill() }
        }
        let newRootAppeared = expectation(description: "new root appeared")
        newRootAppeared.assertForOverFulfill = false
        log.rootDidAppear = { newRootAppeared.fulfill() }
        host.rootView = pushingSplitView(rootRevision: 1, log: log)
        host.view.layoutIfNeeded()
        wait(for: [oldScreenLeft, newRootAppeared], timeout: 2)
        log.pushedScreenMoved = { _ in }
        log.rootDidAppear = {}

        XCTAssertNil(log.oldPushedScreen?.window, "A root selection must remove the old pushed screen")
        XCTAssertEqual(log.roots, 2, "A root selection must reset the detail stack")
        XCTAssertEqual(log.sidebar, 1, "A root selection must not rebuild the sidebar")

        let replacementStack = try waitForPushedScreen(log: log) { try push(from: log, in: host) }
        XCTAssertEqual(replacementStack.viewControllers.count, 2, "The new root must still push")
    }

    /// A deep link can select a root that pushes as soon as it appears, even while the
    /// old root's screen still covers it. The selection pops only the old screen.
    func testRootSelectionKeepsAScreenTheNewRootPushes() throws {
        let log = DetailPushLog()
        let host = UIHostingController(rootView: pushingSplitView(rootRevision: 0, log: log))
        let window = try hostWindow(host, size: CGSize(width: 1_194, height: 834))
        defer { tearDown(window) }
        let detailStack = try waitForPushedScreen(log: log) { try push(from: log, in: host) }
        let oldScreen = try XCTUnwrap(detailStack.topViewController)

        let replacementStack = try waitForPushedScreen(log: log) {
            host.rootView = pushingSplitView(rootRevision: 1, log: log, pushesOnAppear: true)
            host.view.layoutIfNeeded()
        }
        // Main-queue work the selection deferred ran before this turn.
        let deferredWorkRan = expectation(description: "deferred work ran")
        DispatchQueue.main.async { deferredWorkRan.fulfill() }
        wait(for: [deferredWorkRan], timeout: 1)

        XCTAssertFalse(replacementStack.viewControllers.contains(oldScreen), "A root selection must pop the old root's screen")
        XCTAssertEqual(replacementStack.viewControllers.count, 2, "A root selection must keep the new root's own push")
    }

    /// Runs `change` and returns the detail column's navigation controller once the
    /// screen it pushes is on screen.
    private func waitForPushedScreen(
        log: DetailPushLog,
        after change: () throws -> Void
    ) throws -> UINavigationController {
        let pushed = expectation(description: "screen pushed")
        pushed.assertForOverFulfill = false
        log.pushedScreenMoved = { isOnScreen in
            if isOnScreen { pushed.fulfill() }
        }
        try change()
        wait(for: [pushed], timeout: 2)
        log.pushedScreenMoved = { _ in }
        return try XCTUnwrap(log.pushedScreen.flatMap(owningNavigationController))
    }

    private func push(from log: DetailPushLog, in host: UIViewController) throws {
        let push = try XCTUnwrap(log.push)
        push()
        host.view.layoutIfNeeded()
    }

    private func owningNavigationController(of view: UIView) -> UINavigationController? {
        var responder: UIResponder? = view
        while let next = responder?.next {
            if let controller = next as? UIViewController { return controller.navigationController }
            responder = next
        }
        return nil
    }

    private func pushingSplitView(
        rootRevision: Int,
        log: DetailPushLog,
        pushesOnAppear: Bool = false
    ) -> PushingSplitView {
        HermesHomeShell(navigation: .constant(HermesHomeNavigation(destination: .archived(String(rootRevision)), isCompact: false))) {
            SplitColumnProbe { log.sidebar += 1 }
        } detail: {
            PushingDetailProbe(log: log, pushesOnAppear: pushesOnAppear)
        }
    }

    private func hostWindow(_ host: UIViewController, size: CGSize) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.traitOverrides.horizontalSizeClass = .regular
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        return window
    }

    private func hostSplitView(
        log: SplitColumnCreationLog,
        size: CGSize
    ) throws -> (UIHostingController<ProbeSplitView>, UIWindow) {
        let host = UIHostingController(rootView: splitView(rootRevision: 0, log: log))
        return (host, try hostWindow(host, size: size))
    }

    private func tearDown(_ window: UIWindow) {
        window.isHidden = true
        window.rootViewController = nil
    }

    private func splitView(rootRevision: Int, log: SplitColumnCreationLog, presented: Bool = true) -> ProbeSplitView {
        HermesHomeShell(navigation: .constant(HermesHomeNavigation(destination: .archived(String(rootRevision)), isSidebarPresented: presented, isCompact: false))) {
            SplitColumnProbe(onCreate: { log.sidebar += 1 })
        } detail: {
            SplitColumnProbe { log.detail += 1 }
        }
    }
}

private typealias ProbeSplitView = HermesHomeShell<SplitColumnProbe, SplitColumnProbe>
private typealias PushingSplitView = HermesHomeShell<SplitColumnProbe, PushingDetailProbe>

@MainActor
private final class DetailPushLog {
    var sidebar = 0
    var roots = 0
    /// Pushes a screen from the detail root that appeared last.
    var push: (() -> Void)?
    var rootDidAppear: () -> Void = {}
    weak var pushedScreen: UIView?
    weak var oldPushedScreen: UIView?
    var pushedScreenMoved: (Bool) -> Void = { _ in }
}

/// A detail root that pushes a screen the way Settings and the file browser do.
private struct PushingDetailProbe: View {
    let log: DetailPushLog
    let pushesOnAppear: Bool
    @State private var isPushed = false

    var body: some View {
        SplitColumnProbe { log.roots += 1 }
            .onAppear {
                log.push = { isPushed = true }
                if pushesOnAppear { isPushed = true }
                log.rootDidAppear()
            }
            .navigationDestination(isPresented: $isPushed) {
                SplitColumnProbe(
                    onCreate: {},
                    onWindowChange: { log.pushedScreenMoved($0) },
                    onMake: { log.pushedScreen = $0 }
                )
            }
    }
}

@MainActor
private final class SplitColumnCreationLog {
    var sidebar = 0
    var detail = 0
}

/// Reports when SwiftUI creates it and when its view enters or leaves the window.
private struct SplitColumnProbe: UIViewRepresentable {
    let onCreate: @MainActor () -> Void
    var onWindowChange: @MainActor (Bool) -> Void = { _ in }
    var onMake: @MainActor (UIView) -> Void = { _ in }

    func makeUIView(context: Context) -> WindowReportingView {
        onCreate()
        let view = WindowReportingView()
        view.onWindowChange = onWindowChange
        onMake(view)
        return view
    }

    func updateUIView(_ view: WindowReportingView, context: Context) {
        view.onWindowChange = onWindowChange
    }
}

private final class WindowReportingView: UIView {
    var onWindowChange: @MainActor (Bool) -> Void = { _ in }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChange(window != nil)
    }
}
