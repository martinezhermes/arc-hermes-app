import AVFoundation
import XCTest
@testable import ARCHermes

final class ComposerVoiceNoteRecorderTests: XCTestCase {
    @MainActor
    func testPermissionResultFromCancelledRecordingCannotOverwriteNewRequest() async {
        let first = expectation(description: "first permission request")
        let second = expectation(description: "second permission request")
        let permission = VoiceNotePermissionGate(started: [first, second])
        let recorder = ComposerVoiceNoteRecorder(
            recorderFactory: { _ in
                XCTFail("Denied or cancelled permission must never construct a recorder")
                throw ComposerVoiceNoteRecorderError.couldNotStart
            },
            permissionRequester: { await permission.request() }
        )
        let firstTask = Task { await recorder.begin() }
        await fulfillment(of: [first], timeout: 2)
        recorder.cancel()
        let secondTask = Task { await recorder.begin() }
        await fulfillment(of: [second], timeout: 2)
        permission.resolve(index: 0, granted: false)
        await firstTask.value
        XCTAssertEqual(recorder.state, .requestingPermission)
        XCTAssertNil(recorder.errorMessage)
        permission.resolve(index: 1, granted: false)
        await secondTask.value
        XCTAssertEqual(recorder.state, .idle)
        XCTAssertNotNil(recorder.errorMessage)
    }

    @MainActor
    func testCancelledPermissionTaskReturnsToIdleWithoutAnError() async {
        let started = expectation(description: "permission request")
        let permission = VoiceNotePermissionGate(started: [started])
        let recorder = ComposerVoiceNoteRecorder(permissionRequester: { await permission.request() })
        let task = Task { await recorder.begin() }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        permission.resolve(index: 0, granted: true)
        await task.value
        XCTAssertEqual(recorder.state, .idle)
        XCTAssertNil(recorder.errorMessage)
    }

    // MARK: - Filename

    func testGenerateFilenameIsM4AVoiceNote() {
        let uuid = UUID(uuidString: "ABCDEF01-2345-6789-ABCD-EF0123456789")!
        let name = VoiceNoteFilename.generate(uuid: uuid)

        XCTAssertTrue(name.hasPrefix("voice-note-"))
        XCTAssertTrue(name.hasSuffix(".m4a"))
        XCTAssertEqual(name, "voice-note-abcdef01.m4a")
        XCTAssertTrue(VoiceNoteFilename.isVoiceNote(name))
    }

    func testTwoGeneratedFilenamesDiffer() {
        XCTAssertNotEqual(VoiceNoteFilename.generate(), VoiceNoteFilename.generate())
    }

    func testIsVoiceNoteRejectsOtherFiles() {
        XCTAssertFalse(VoiceNoteFilename.isVoiceNote("photo.jpg"))
        XCTAssertFalse(VoiceNoteFilename.isVoiceNote("voice-note-123.wav"))
        XCTAssertFalse(VoiceNoteFilename.isVoiceNote("note.m4a"))
    }

    // MARK: - Gesture

    func testCancelArmsOnlyWhenSlidUpPastThreshold() {
        let threshold = ComposerVoiceNoteGesture.cancelTranslationThreshold

        XCTAssertFalse(ComposerVoiceNoteGesture.isCancelArmed(dragTranslationHeight: 0))
        XCTAssertFalse(ComposerVoiceNoteGesture.isCancelArmed(dragTranslationHeight: -10))
        // Sliding down (positive height) never cancels.
        XCTAssertFalse(ComposerVoiceNoteGesture.isCancelArmed(dragTranslationHeight: 200))
        XCTAssertTrue(ComposerVoiceNoteGesture.isCancelArmed(dragTranslationHeight: -threshold))
        XCTAssertTrue(ComposerVoiceNoteGesture.isCancelArmed(dragTranslationHeight: -200))
    }

    // MARK: - Policy

    func testMaximumDurationStaysWellUnderUploadCap() {
        XCTAssertEqual(ComposerVoiceNoteRecorder.maximumDuration, 300)
        XCTAssertLessThan(ComposerVoiceNoteRecorder.minimumDuration, 1)

        // AAC mono at ~32 kbps over 5 minutes is roughly 1.2 MB — far below the
        // 20 MB attachment ceiling, so the duration cap (not size) bounds the UX.
        let approxBytesAt32kbps = 32_000 / 8 * Int(ComposerVoiceNoteRecorder.maximumDuration)
        XCTAssertLessThan(approxBytesAt32kbps, PendingAttachment.maximumUploadBytes)
    }

    func testRecordingSettingsAreMonoAAC() {
        let settings = ComposerVoiceNoteRecorder.recordingSettings
        XCTAssertEqual(settings[AVFormatIDKey] as? Int, Int(kAudioFormatMPEG4AAC))
        XCTAssertEqual(settings[AVNumberOfChannelsKey] as? Int, 1)
    }
}

@MainActor
private final class VoiceNotePermissionGate {
    let started: [XCTestExpectation]
    private var continuations: [CheckedContinuation<Bool, Never>] = []

    init(started: [XCTestExpectation]) { self.started = started }

    func request() async -> Bool {
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
            started[continuations.count - 1].fulfill()
        }
    }

    func resolve(index: Int, granted: Bool) { continuations[index].resume(returning: granted) }
}
