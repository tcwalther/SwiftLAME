import AVFAudio
import XCTest
@testable import SwiftLAME

final class SwiftLAMETests: XCTestCase {
    func testPublicTransferTypesAreSendable() {
        assertSendable(LameVbrMode.self)
        assertSendable(LameBitrateMode.self)
        assertSendable(LameSampleRate.self)
        assertSendable(LameQuality.self)
        assertSendable(LameConfiguration.self)
        assertSendable(SwiftLameEncoder.self)
    }

    func testInitRejectsMissingSourceFile() {
        let source = temporaryURL(extension: "wav")
        let destination = temporaryURL(extension: "mp3")

        XCTAssertThrowsError(
            try SwiftLameEncoder(
                sourceUrl: source,
                configuration: testConfiguration,
                destinationUrl: destination
            )
        )
    }

    func testEncodeProducesPlayableTelephonyMP3() async throws {
        let source = try makeSourceAudio(duration: 0.1)
        let destination = temporaryURL(extension: "mp3")
        let progress = Progress()
        defer { removeIfPresent(source); removeIfPresent(destination) }

        let encoder = try SwiftLameEncoder(
            sourceUrl: source,
            configuration: testConfiguration,
            destinationUrl: destination,
            progress: progress
        )

        try await encoder.encode()

        let encodedFile = try AVAudioFile(forReading: destination)
        XCTAssertGreaterThan(encodedFile.length, 0)
        XCTAssertEqual(encodedFile.processingFormat.sampleRate, 8_000, accuracy: 1)
        XCTAssertEqual(progress.completedUnitCount, progress.totalUnitCount)
    }

    func testCancelledEncodeRemovesPartialOutput() async throws {
        let source = try makeSourceAudio(duration: 0.25)
        let destination = temporaryURL(extension: "mp3")
        let progress = Progress()
        defer { removeIfPresent(source); removeIfPresent(destination) }

        let encoder = try SwiftLameEncoder(
            sourceUrl: source,
            configuration: testConfiguration,
            destinationUrl: destination,
            progress: progress
        )
        progress.cancel()

        try await encoder.encode()

        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testTimeRangeEncodesOnlyThatPart() async throws {
        let source = try makeSourceAudio(duration: 2, sampleRate: 48_000)
        defer { removeIfPresent(source) }

        // Compared with the whole file, so LAME's encoder delay and padding cancel out.
        let whole = try await encodedDuration(of: source, timeRange: nil)
        let part = try await encodedDuration(of: source, timeRange: 0.5...1.5)

        XCTAssertEqual(whole - part, 1, accuracy: 0.03)
    }

    func testTimeRangeIsClampedToTheFile() async throws {
        let source = try makeSourceAudio(duration: 2, sampleRate: 48_000)
        defer { removeIfPresent(source) }

        let whole = try await encodedDuration(of: source, timeRange: nil)
        let clamped = try await encodedDuration(of: source, timeRange: 1...10)

        XCTAssertEqual(whole - clamped, 1, accuracy: 0.03)
    }

    /// Encodes `source` at 48 kHz, which keeps LAME's padding short, and returns the MP3's duration in seconds.
    private func encodedDuration(of source: URL, timeRange: ClosedRange<TimeInterval>?) async throws -> TimeInterval {
        let destination = temporaryURL(extension: "mp3")
        defer { removeIfPresent(destination) }
        let progress = Progress()

        let encoder = try SwiftLameEncoder(
            sourceUrl: source,
            configuration: LameConfiguration(sampleRate: .default, bitrateMode: .constant(128), quality: .standard),
            destinationUrl: destination,
            timeRange: timeRange,
            progress: progress
        )
        try await encoder.encode()

        XCTAssertEqual(progress.fractionCompleted, 1)
        let file = try AVAudioFile(forReading: destination)
        return Double(file.length) / file.processingFormat.sampleRate
    }

    private var testConfiguration: LameConfiguration {
        LameConfiguration(
            sampleRate: .custom(8_000),
            bitrateMode: .constant(64),
            quality: .best
        )
    }

    private func assertSendable<Value: Sendable>(_: Value.Type) {}

    private func makeSourceAudio(duration: TimeInterval, sampleRate: Double = 8_000) throws -> URL {
        let url = temporaryURL(extension: "wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        let samples = buffer.floatChannelData![0]
        for frame in 0..<Int(frameCount) {
            samples[frame] = sin(Float(frame) * 2 * .pi * 440 / Float(sampleRate)) * 0.25
        }

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    private func temporaryURL(extension pathExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(pathExtension)
    }

    private func removeIfPresent(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
