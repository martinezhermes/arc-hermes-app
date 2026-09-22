import AVFAudio
import Foundation

struct AudioSessionConfiguration: Equatable, Sendable {
    let category: AVAudioSession.Category
    let mode: AVAudioSession.Mode
    var options: AVAudioSession.CategoryOptions = []

    var capturesInput: Bool { category == .playAndRecord || category == .record }
}

@MainActor
protocol AudioSessionDriving {
    func activate(_ configuration: AudioSessionConfiguration) async throws
    func deactivate() async
}

@MainActor
private final class SystemAudioSessionDriver: AudioSessionDriving {
    func activate(_ configuration: AudioSessionConfiguration) async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(configuration.category, mode: configuration.mode, options: configuration.options)
        guard try await session.activate(options: []) else {
            throw NSError(domain: NSOSStatusErrorDomain,
                          code: Int(AVAudioSession.ErrorCode.cannotStartPlaying.rawValue))
        }
    }

    func deactivate() async {
        _ = try? await AVAudioSession.sharedInstance().deactivate(options: [.notifyOthersOnDeactivation])
    }
}

/// Serializes the iOS 27 async audio-session transitions. Each capture/playback
/// owns a token, so stale cleanup cannot deactivate another operation's audio.
/// Capture takes precedence; releasing it restores any remaining playback lease.
@MainActor
final class AudioSessionCoordinator {
    static let shared = AudioSessionCoordinator()

    private struct Lease {
        let owner: UUID
        let configuration: AudioSessionConfiguration
    }

    private let driver: any AudioSessionDriving
    private let captureChanged: @MainActor (Bool) -> Void
    private var leases: [Lease] = []
    private var pending: Task<Void, Never>?

    init(driver: (any AudioSessionDriving)? = nil,
         captureChanged: (@MainActor (Bool) -> Void)? = nil) {
        self.driver = driver ?? SystemAudioSessionDriver()
        self.captureChanged = captureChanged ?? { ComposerAudioCaptureState.shared.setCapturing($0) }
    }

    private var configuration: AudioSessionConfiguration? {
        (leases.last { $0.configuration.capturesInput } ?? leases.last)?.configuration
    }

    func activate(owner: UUID, configuration requested: AudioSessionConfiguration) async throws {
        leases.removeAll { $0.owner == owner }
        leases.append(Lease(owner: owner, configuration: requested))
        captureChanged(leases.contains { $0.configuration.capturesInput })
        let previous = pending
        let operation = Task { @MainActor in
            await previous?.value
            guard let effective = self.configuration else { throw CancellationError() }
            try await self.driver.activate(effective)
        }
        pending = Task { _ = await operation.result }
        do {
            try await operation.value
            try Task.checkCancellation()
            guard leases.contains(where: { $0.owner == owner }) else { throw CancellationError() }
        } catch {
            deactivate(owner: owner)
            throw error
        }
    }

    func deactivate(owner: UUID) {
        guard leases.contains(where: { $0.owner == owner }) else { return }
        let previousConfiguration = configuration
        leases.removeAll { $0.owner == owner }
        let nextConfiguration = configuration
        captureChanged(leases.contains { $0.configuration.capturesInput })
        guard nextConfiguration != previousConfiguration else { return }
        let previous = pending
        pending = Task { @MainActor in
            await previous?.value
            if let current = self.configuration {
                try? await self.driver.activate(current)
            } else {
                await self.driver.deactivate()
            }
        }
    }
}
