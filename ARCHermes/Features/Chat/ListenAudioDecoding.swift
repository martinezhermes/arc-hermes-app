import AVFoundation
import Foundation

/// Prepares downloaded Ogg speech for AudioQueue without changing its samples or voice.
/// AVAudioPlayer recognizes Opus metadata but cannot prepare that compressed file for playback.
enum ListenAudioDecoding {
    enum Failure: Error, Equatable {
        case invalidAudio
        case tooLarge
    }

    static func prepare(_ data: Data, maximumDecodedBytes: Int = 64 * 1024 * 1024) async throws -> Data {
        try Task.checkCancellation()
        guard data.starts(with: [0x4f, 0x67, 0x67, 0x53]) else { return data }
        let preparation = Task.detached(priority: .userInitiated) {
            try decodeOgg(data, maximumDecodedBytes: maximumDecodedBytes)
        }
        return try await withTaskCancellationHandler {
            let playable = try await preparation.value
            try Task.checkCancellation()
            return playable
        } onCancel: {
            preparation.cancel()
        }
    }

    private static func decodeOgg(_ data: Data, maximumDecodedBytes: Int) throws -> Data {
        try Task.checkCancellation()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("listen-audio-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("speech.ogg")
        let destination = folder.appendingPathComponent("playback.caf")
        try data.write(to: source, options: .atomic)
        try writePCM(source: source, destination: destination, maximumBytes: maximumDecodedBytes)
        try Task.checkCancellation()
        return try Data(contentsOf: destination)
    }

    /// This scope closes the writer before its completed CAF is read into the player.
    private static func writePCM(source: URL, destination: URL, maximumBytes: Int) throws {
        let reader = try AVAudioFile(forReading: source, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = reader.processingFormat
        let bytesPerFrame = Int(format.channelCount) * MemoryLayout<Float>.size
        guard bytesPerFrame > 0, maximumBytes >= bytesPerFrame else { throw Failure.tooLarge }
        let capacity = AVAudioFrameCount(min(8192, maximumBytes / bytesPerFrame))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { throw Failure.invalidAudio }
        let writer = try AVAudioFile(forWriting: destination, settings: format.settings)
        var framesWritten = 0
        let maximumFrames = maximumBytes / bytesPerFrame
        while reader.framePosition < reader.length {
            try Task.checkCancellation()
            let remaining = reader.length - reader.framePosition
            try reader.read(into: buffer, frameCount: AVAudioFrameCount(min(remaining, Int64(capacity))))
            let frames = Int(buffer.frameLength)
            guard frames > 0 else { break }
            guard frames <= maximumFrames - framesWritten else { throw Failure.tooLarge }
            try writer.write(from: buffer)
            framesWritten += frames
        }
        guard framesWritten > 0 else { throw Failure.invalidAudio }
    }
}
