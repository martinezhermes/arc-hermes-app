import AVFAudio
import XCTest
@testable import ARCHermes

@MainActor
final class AudioSessionCoordinatorTests: XCTestCase {
    private let playback = AudioSessionConfiguration(category: .playback, mode: .spokenAudio)
    private let capture = AudioSessionConfiguration(category: .playAndRecord, mode: .measurement)

    func testIdleListenCleanupDoesNotDeactivateAudioOwnedElsewhere() async throws {
        let driver = AudioSessionTestDriver()
        let coordinator = AudioSessionCoordinator(driver: driver, captureChanged: { _ in })
        let listener = ListenAudioSessionController(coordinator: coordinator)
        let owner = UUID()
        try await coordinator.activate(owner: owner, configuration: playback)
        listener.deactivate()
        listener.deactivate()
        try await coordinator.activate(owner: owner, configuration: playback)
        XCTAssertEqual(driver.deactivations, 0)
        let ended = expectation(description: "owner released")
        driver.onDeactivate = { ended.fulfill() }
        coordinator.deactivate(owner: owner)
        await fulfillment(of: [ended], timeout: 2)
    }

    func testStaleReleaseCannotDeactivateNewPlayback() async throws {
        let driver = AudioSessionTestDriver()
        let coordinator = AudioSessionCoordinator(driver: driver, captureChanged: { _ in })
        let first = UUID(), second = UUID(), barrier = UUID()
        try await coordinator.activate(owner: first, configuration: playback)
        try await coordinator.activate(owner: second, configuration: playback)
        coordinator.deactivate(owner: first)
        coordinator.deactivate(owner: first)
        try await coordinator.activate(owner: barrier, configuration: playback)
        XCTAssertEqual(driver.deactivations, 0)
        let ended = expectation(description: "last playback released")
        driver.onDeactivate = { ended.fulfill() }
        coordinator.deactivate(owner: second)
        coordinator.deactivate(owner: barrier)
        await fulfillment(of: [ended], timeout: 2)
        XCTAssertEqual(driver.deactivations, 1)
    }

    func testCaptureKeepsItsCategoryUntilReleasedThenRestoresPlayback() async throws {
        let driver = AudioSessionTestDriver()
        let coordinator = AudioSessionCoordinator(driver: driver) { driver.captureStates.append($0) }
        let player = UUID(), microphone = UUID(), secondPlayer = UUID(), barrier = UUID()
        try await coordinator.activate(owner: player, configuration: playback)
        try await coordinator.activate(owner: microphone, configuration: capture)
        try await coordinator.activate(owner: secondPlayer, configuration: playback)
        XCTAssertEqual(driver.activations.last, capture)
        XCTAssertEqual(driver.captureStates.last, true)
        coordinator.deactivate(owner: microphone)
        try await coordinator.activate(owner: barrier, configuration: playback)
        XCTAssertEqual(driver.activations.last, playback)
        XCTAssertEqual(driver.captureStates.last, false)
        XCTAssertEqual(driver.deactivations, 0)
        let ended = expectation(description: "remaining playback released")
        driver.onDeactivate = { ended.fulfill() }
        for owner in [player, secondPlayer, barrier] { coordinator.deactivate(owner: owner) }
        await fulfillment(of: [ended], timeout: 2)
    }

    func testReleaseWhileActivationIsPendingRejectsLateStartAndFinishesCleanup() async throws {
        try await checkPendingCancellation(releaseExplicitly: true)
    }

    func testCancelledActivationTaskReleasesItsLease() async throws {
        try await checkPendingCancellation(releaseExplicitly: false)
    }

    func testInlinePlaybackCancelledDuringActivationNeverStartsLate() async throws {
        let driver = AudioSessionTestDriver()
        let coordinator = AudioSessionCoordinator(driver: driver, captureChanged: { _ in })
        let model = InlineAudioPlayerModel(audioSession: coordinator)
        await model.loadIfNeeded { Self.silentWAV() }
        XCTAssertEqual(model.phase, .ready)
        let began = expectation(description: "inline activation started")
        let ended = expectation(description: "inline activation released")
        driver.activationStarted = began
        driver.onDeactivate = { ended.fulfill() }
        model.togglePlayPause()
        await fulfillment(of: [began], timeout: 2)
        XCTAssertTrue(model.isStarting)
        model.togglePlayPause()
        driver.resumeActivation()
        await fulfillment(of: [ended], timeout: 2)
        XCTAssertFalse(model.isStarting)
        XCTAssertFalse(model.isPlaying)
        XCTAssertEqual(model.phase, .ready)
        model.teardown()
    }

    func testVoiceNoteCancelledDuringActivationDoesNotConstructRecorder() async throws {
        let driver = AudioSessionTestDriver()
        let coordinator = AudioSessionCoordinator(driver: driver, captureChanged: { _ in })
        var recorderCreated = false
        let model = ComposerVoiceNoteRecorder(recorderFactory: { _ in
            recorderCreated = true
            throw CancellationError()
        }, permissionRequester: { true }, audioSession: coordinator)
        let began = expectation(description: "voice note activation started")
        let ended = expectation(description: "voice note activation released")
        driver.activationStarted = began
        driver.onDeactivate = { ended.fulfill() }
        let task = Task { await model.begin() }
        await fulfillment(of: [began], timeout: 2)
        model.cancel()
        driver.resumeActivation()
        await task.value
        await fulfillment(of: [ended], timeout: 2)
        XCTAssertFalse(recorderCreated)
        XCTAssertEqual(model.state, .idle)
        XCTAssertNil(model.errorMessage)
    }

    func testComposerDictationStoppedDuringActivationDoesNotStartLate() async throws {
        let driver = AudioSessionTestDriver()
        var captureStates: [Bool] = []
        let coordinator = AudioSessionCoordinator(driver: driver) { captureStates.append($0) }
        let controller = ComposerVoiceInputController(
            speechRecognizerFactory: { nil },
            microphonePermissionRequester: { true },
            appIsActive: { true },
            audioSession: coordinator
        )
        controller.apiClient = APIClient(baseURL: try XCTUnwrap(URL(string: "https://example.invalid")))

        let began = expectation(description: "composer audio activation started")
        let ended = expectation(description: "cancelled composer audio released")
        driver.activationStarted = began
        driver.onDeactivate = { ended.fulfill() }
        let task = Task { await controller.toggle(currentDraft: "", updateDraft: { _ in }) }
        await fulfillment(of: [began], timeout: 2)

        controller.stopKeepingTranscript()
        driver.resumeActivation()
        await task.value
        await fulfillment(of: [ended], timeout: 2)

        XCTAssertEqual(controller.state, .idle)
        XCTAssertNil(controller.errorMessage)
        XCTAssertEqual(driver.activations, [AudioSessionConfiguration(
            category: ComposerVoiceAudioSessionConfiguration.category,
            mode: ComposerVoiceAudioSessionConfiguration.mode,
            options: ComposerVoiceAudioSessionConfiguration.options
        )])
        XCTAssertEqual(captureStates, [true, false])
        XCTAssertEqual(driver.deactivations, 1)
    }

    private static func silentWAV() -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var value = value.littleEndian
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8); append(UInt32(1_636))
        data.append(contentsOf: "WAVEfmt ".utf8); append(UInt32(16))
        append(UInt16(1)); append(UInt16(1)); append(UInt32(8_000))
        append(UInt32(16_000)); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: "data".utf8); append(UInt32(1_600))
        data.append(Data(repeating: 0, count: 1_600))
        return data
    }

    private func checkPendingCancellation(releaseExplicitly: Bool) async throws {
        let driver = AudioSessionTestDriver()
        let coordinator = AudioSessionCoordinator(driver: driver) { driver.captureStates.append($0) }
        let began = expectation(description: "activation started")
        let ended = expectation(description: "cancelled activation cleaned up")
        driver.activationStarted = began
        driver.onDeactivate = { ended.fulfill() }
        let owner = UUID()
        let task = Task { try await coordinator.activate(owner: owner, configuration: capture) }
        await fulfillment(of: [began], timeout: 2)
        if releaseExplicitly { coordinator.deactivate(owner: owner) }
        else { task.cancel() }
        driver.resumeActivation()
        do {
            try await task.value
            XCTFail("A cancelled/released owner must not start recording")
        } catch { XCTAssertTrue(error is CancellationError) }
        await fulfillment(of: [ended], timeout: 2)
        XCTAssertEqual(driver.captureStates.last, false)
        XCTAssertEqual(driver.deactivations, 1)
    }
}

@MainActor
private final class AudioSessionTestDriver: AudioSessionDriving {
    var activations: [AudioSessionConfiguration] = []
    var captureStates: [Bool] = []
    var deactivations = 0
    var activationStarted: XCTestExpectation?
    var onDeactivate: (() -> Void)?
    private var activationContinuation: CheckedContinuation<Void, Never>?

    func activate(_ configuration: AudioSessionConfiguration) async throws {
        activations.append(configuration)
        if let started = activationStarted {
            activationStarted = nil
            await withCheckedContinuation { continuation in
                activationContinuation = continuation
                started.fulfill()
            }
        }
    }

    func resumeActivation() {
        activationContinuation?.resume()
        activationContinuation = nil
    }

    func deactivate() async {
        deactivations += 1
        onDeactivate?()
    }
}
