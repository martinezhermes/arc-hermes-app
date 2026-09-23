import SwiftUI
import UIKit
import XCTest
@testable import HermesMobile

/// Only transcript rows born in the last few seconds earn an entrance; cached
/// history, reloads, and reattached transcripts must render in place.
final class ChatTranscriptRowEntryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testRowCreatedMomentsAgoIsFresh() {
        XCTAssertTrue(ChatTranscriptRowFreshness.isFresh(timestamp: now.timeIntervalSince1970, now: now))
        XCTAssertTrue(ChatTranscriptRowFreshness.isFresh(timestamp: now.timeIntervalSince1970 - 2.9, now: now))
    }

    func testRowOlderThanWindowIsNotFresh() {
        XCTAssertFalse(ChatTranscriptRowFreshness.isFresh(timestamp: now.timeIntervalSince1970 - 3, now: now))
        XCTAssertFalse(ChatTranscriptRowFreshness.isFresh(timestamp: now.timeIntervalSince1970 - 3_600, now: now))
    }

    func testServerClockRunningAheadDoesNotMakeHistoryFresh() {
        XCTAssertFalse(ChatTranscriptRowFreshness.isFresh(timestamp: now.timeIntervalSince1970 + 60, now: now))
    }

    func testMissingOrNonFiniteTimestampIsNeverFresh() {
        XCTAssertFalse(ChatTranscriptRowFreshness.isFresh(timestamp: nil, now: now))
        XCTAssertFalse(ChatTranscriptRowFreshness.isFresh(timestamp: .nan, now: now))
        XCTAssertFalse(ChatTranscriptRowFreshness.isFresh(timestamp: .infinity, now: now))
    }
}

@MainActor
final class ChatTranscriptMaterializationTests: XCTestCase {
    func testLongTranscriptMountsOnlyNearbyResponseViews() {
        let messages = (0..<120).map { index in
            ChatMessage(role: "assistant", content: "Response \(index)",
                        timestamp: 1_700_000_000 + Double(index), messageId: "message-\(index)")
        }
        let displayed = messages.enumerated().map { index, message in
            TranscriptMessage(loadedIndex: index, renderID: "transcript:\(index)",
                              anchorID: "message-\(index)", message: message)
        }
        let transcript = ChatTranscriptView(
            isLoading: false,
            errorMessage: nil,
            messages: messages,
            displayedTranscriptMessages: displayed,
            compressionReferenceCard: nil,
            reasoningGroups: [],
            completedToolCallGroupsForAnchor: { _ in [] },
            liveReasoningText: "",
            reasoningAnchorMessageID: nil,
            liveToolCalls: [],
            toolCallAnchorMessageID: nil,
            streamingAssistantMessageID: nil,
            liveTokensPerSecond: nil,
            activeStreamRecoveryState: .idle,
            clarificationPromptID: nil,
            hidesRunStatusAccessibility: false,
            showsThinkingAndToolCards: false,
            workingRowStartedAt: nil,
            showsScrollToBottomButton: false,
            shouldFollowLatestMessage: true,
            isDisclosureSettling: false,
            latestTranscriptMessageRole: "assistant",
            isScrolledNearBottom: true,
            activeStreamID: nil,
            streamingScrollTrigger: 0,
            transcriptRelayoutScrollToken: 0,
            bottomAnchorID: "bottom",
            transcriptSpacing: 8,
            transcriptBottomInsetHeight: 0,
            scrollToBottomButtonBottomPadding: 0,
            localAttachmentPreviews: [:],
            listeningMessageID: nil,
            isViewingCachedData: false,
            hasOlderMessages: false,
            isLoadingOlderMessages: false,
            isRegeneratingMessage: false,
            isEditingMessage: false,
            isForkingMessage: false,
            loadAttachmentImage: { _ in nil },
            loadAttachmentData: { _ in nil },
            loadTranscriptMediaImage: { _ in nil },
            loadTranscriptMediaData: { _ in nil },
            transcriptMediaCacheNamespace: "",
            actionContext: { _, _ in nil },
            shouldRenderMessageRow: { _ in true },
            onLoadMessages: {},
            onLoadOlderMessages: { false },
            onUpdateScrollMetrics: { _ in },
            onFollowEvent: { _ in },
            onDisclosureToggle: {},
            turnFolds: .none,
            terminalReplyRenderIDs: [],
            expandedTurnKeys: [],
            onToggleTurnFold: { _ in },
            onDismissKeyboard: {},
            onScrollToBottom: { _ in },
            onScrollToLatestTranscriptMessage: { _ in },
            onScrollToLatestContent: { _, _ in },
            onPreviewAttachment: { _, _ in },
            onPreviewTranscriptMedia: { _ in },
            onAskHermex: { _ in },
            onToggleListening: { _ in },
            onRegenerate: { _ in },
            onEdit: { _ in },
            onFork: { _ in },
            onCopy: { _ in }
        )
        let host = UIHostingController(rootView: transcript)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()

        func responseInputCount(in view: UIView) -> Int {
            (view is ResponseSelectionInput ? 1 : 0)
                + view.subviews.reduce(0) { $0 + responseInputCount(in: $1) }
        }

        let mountedResponses = responseInputCount(in: host.view)
        XCTAssertGreaterThan(mountedResponses, 0)
        XCTAssertLessThan(mountedResponses, messages.count / 2)
    }
}
