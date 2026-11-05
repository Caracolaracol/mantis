import AVFoundation
import CoreMedia
import ScreenCaptureKit
import XCTest
import MeetingCore
@testable import MeetingRecorder

// Fully initialized on the producer, then read only on the capture queue.
private final class ImmutableSample: @unchecked Sendable {
    let value: CMSampleBuffer
    init(_ value: CMSampleBuffer) { self.value = value }
}

final class CaptureOutputTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MeetingCaptureTests-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func silentBuffer(at time: CMTime) throws -> CMSampleBuffer {
        let frames = 24_000
        var asbd = AudioStreamBasicDescription(mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
                                              mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                                              mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
                                              mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
        var description: CMAudioFormatDescription?
        XCTAssertEqual(CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0,
                                                      layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil,
                                                      formatDescriptionOut: &description), noErr)
        var block: CMBlockBuffer?
        XCTAssertEqual(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
                                                         blockLength: frames * 4, blockAllocator: kCFAllocatorDefault,
                                                         customBlockSource: nil, offsetToData: 0, dataLength: frames * 4,
                                                         flags: 0, blockBufferOut: &block), noErr)
        let data = try XCTUnwrap(block)
        XCTAssertEqual(CMBlockBufferFillDataBytes(with: 0, blockBuffer: data, offsetIntoDestination: 0,
                                                 dataLength: frames * 4), noErr)
        var sample: CMSampleBuffer?
        XCTAssertEqual(CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: kCFAllocatorDefault,
                                                                           dataBuffer: data,
                                                                           formatDescription: try XCTUnwrap(description),
                                                                           sampleCount: frames, presentationTimeStamp: time,
                                                                           packetDescriptions: nil, sampleBufferOut: &sample), noErr)
        return try XCTUnwrap(sample)
    }

    private func recording(in directory: URL, includeMicrophone: Bool = true) async throws -> URL {
        let destination = directory.appendingPathComponent("synthetic.mov")
        let output = try CaptureOutput(destination: destination, includeMicrophone: includeMicrophone) { _ in }
        if !includeMicrophone {
            // A stray mic sample must neither create a track nor shift the session start.
            let microphone = ImmutableSample(try silentBuffer(at: CMTime(seconds: 9, preferredTimescale: 48_000)))
            await withCheckedContinuation { continuation in
                output.queue.async {
                    output.append(microphone.value, type: .microphone)
                    continuation.resume()
                }
            }
        }
        // Synthetic host times start at 10 s. With two sources, system audio starts 0.5 s later.
        for index in 0..<4 {
            let buffer = ImmutableSample(try silentBuffer(at: CMTime(value: Int64(480_000 + index * 24_000), timescale: 48_000)))
            await withCheckedContinuation { continuation in
                output.queue.async {
                    if includeMicrophone { output.append(buffer.value, type: .microphone) }
                    if !includeMicrophone || index > 0 { output.append(buffer.value, type: .audio) }
                    continuation.resume()
                }
            }
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        try await output.finish()
        return destination
    }

    func testWriterCreatesTwoAudioTracksAndNoVideo() async throws {
        let url = try await recording(in: directory())
        let asset = AVURLAsset(url: url)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let video = try await asset.loadTracks(withMediaType: .video)
        let duration = try await asset.load(.duration)
        XCTAssertEqual(audio.count, 2)
        XCTAssertTrue(video.isEmpty)
        XCTAssertEqual(duration.seconds, 2, accuracy: 0.1)
    }

    func testApplicationOnlyPlanDisablesMicrophone() {
        let plan = ApplicationCapturePlan(mode: .applicationOnly)
        let configuration = plan.configuration()
        XCTAssertFalse(plan.capturesMicrophone)
        XCTAssertFalse(configuration.captureMicrophone)
        XCTAssertTrue(configuration.capturesAudio)
        XCTAssertFalse(plan.outputTypes.contains(.microphone))
        XCTAssertTrue(plan.outputTypes.contains(.audio))
    }

    func testCombinedPlanEnablesBothSources() {
        let plan = ApplicationCapturePlan(mode: .application)
        XCTAssertTrue(plan.configuration().captureMicrophone)
        XCTAssertTrue(plan.outputTypes.contains(.microphone))
        XCTAssertTrue(plan.outputTypes.contains(.audio))
    }

    func testAudioOnlyModesNeverRequestMicrophonePermission() async {
        for mode in [RecordingMode.applicationOnly, .systemAudio] {
            var requested = false
            let allowed = await CapturePermissions.microphoneAllowed(for: mode) {
                requested = true
                return false
            }
            XCTAssertTrue(allowed)
            XCTAssertFalse(requested)
        }
    }

    func testWholeSystemCapturePlans() {
        for mode in [RecordingMode.systemAudio, .systemAndMicrophone] {
            let plan = ApplicationCapturePlan(mode: mode)
            XCTAssertTrue(plan.configuration().capturesAudio)
            XCTAssertEqual(plan.configuration().captureMicrophone, mode.capturesMicrophone)
            XCTAssertEqual(plan.outputTypes.contains(.microphone), mode.capturesMicrophone)
        }
    }

    func testMicrophoneModesRequirePermission() async {
        for mode in [RecordingMode.microphone, .application, .systemAndMicrophone] {
            var requested = false
            let allowed = await CapturePermissions.microphoneAllowed(for: mode) {
                requested = true
                return false
            }
            XCTAssertTrue(requested)
            XCTAssertFalse(allowed)
        }
    }

    func testApplicationOnlyWriterCreatesOneAudioTrackAndIgnoresMicrophone() async throws {
        let url = try await recording(in: directory(), includeMicrophone: false)
        let asset = AVURLAsset(url: url)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let video = try await asset.loadTracks(withMediaType: .video)
        let duration = try await asset.load(.duration)
        XCTAssertEqual(audio.count, 1)
        XCTAssertTrue(video.isEmpty)
        XCTAssertEqual(duration.seconds, 2, accuracy: 0.1)
    }

    func testTwoTrackCaptureExportsVerifiedAudioOnlyM4A() async throws {
        let root = try directory()
        let source = try await recording(in: root)
        let destination = root.appendingPathComponent("Reunión.m4a")
        let duration = try await AudioNormalizer().exportM4A(source: source, destination: destination)
        let asset = AVURLAsset(url: destination)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let video = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(audio.count, 1)
        XCTAssertTrue(video.isEmpty)
        XCTAssertEqual(duration, 2, accuracy: 0.1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        do {
            _ = try await AudioNormalizer().exportM4A(source: source, destination: destination)
            XCTFail("Must not overwrite")
        } catch {}
    }

    func testWriterReportsMissingAudio() async throws {
        let output = try CaptureOutput(destination: directory().appendingPathComponent("empty.mov"), includeMicrophone: true) { _ in }
        do { try await output.finish(); XCTFail("Expected missing audio error") }
        catch { XCTAssertTrue(error.localizedDescription.contains("muestras")) }
    }

    func testInputRouteSelectsOnlyRequestedChannels() throws {
        let layout = try XCTUnwrap(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | 4))
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, interleaved: false, channelLayout: layout))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 3))
        buffer.frameLength = 3
        let data = try XCTUnwrap(buffer.floatChannelData)
        for channel in 0..<4 {
            for frame in 0..<3 { data[channel][frame] = Float(channel + 1) / 4 }
        }
        XCTAssertEqual(try AudioInputRoute(deviceUID: "test", channels: [1]).monoSamples(buffer), [0.5, 0.5, 0.5])
        XCTAssertEqual(try AudioInputRoute(deviceUID: "test", channels: [0, 2]).monoSamples(buffer), [0.5, 0.5, 0.5])
        for channels in [[], [-1], [4], [0, 0]] {
            XCTAssertThrowsError(try AudioInputRoute(deviceUID: "test", channels: channels).monoSamples(buffer))
        }
    }

    func testRoutedMicrophoneWriterContainsOnlyOneAudioTrack() async throws {
        let outputURL = try directory().appendingPathComponent("routed.mov")
        let output = try CaptureOutput(destination: outputURL, includeMicrophone: true, includeSystem: false) { _ in }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 24_000))
        buffer.frameLength = 24_000
        let data = try XCTUnwrap(buffer.floatChannelData)
        for channel in 0..<2 {
            for frame in 0..<24_000 { data[channel][frame] = 0 }
        }
        for index in 0..<4 {
            let time = AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: 10 + Double(index) / 2))
            output.appendMicrophone(buffer, at: time, route: AudioInputRoute(deviceUID: "synthetic", channels: [1]))
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        try await output.finish()
        let asset = AVURLAsset(url: outputURL)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let video = try await asset.loadTracks(withMediaType: .video)
        let duration = try await asset.load(.duration)
        XCTAssertEqual(audio.count, 1)
        XCTAssertTrue(video.isEmpty)
        XCTAssertEqual(duration.seconds, 2, accuracy: 0.1)
    }

    @MainActor
    func testRequiredPermissionsAreRequestedInOrderAndStopOnDenial() async throws {
        var requested: [String] = []
        do {
            try await CapturePermissions.ensure(for: .systemAndMicrophone, requestMicrophone: {
                requested.append("microphone"); return false
            }, requestSystemAudio: {
                requested.append("system"); return true
            })
            XCTFail("Expected permission denial")
        } catch {
            XCTAssertEqual((error as? CaptureAuthorizationError)?.permission, .microphone)
        }
        XCTAssertEqual(requested, ["microphone"])
        requested = []
        try await CapturePermissions.ensure(for: .systemAudio, requestMicrophone: {
            requested.append("microphone"); return false
        }, requestSystemAudio: {
            requested.append("system"); return true
        })
        XCTAssertEqual(requested, ["system"])
    }

    /// Opt-in: integrated engine + this app's model; no external programs or capture devices.
    func testSyntheticCaptureToNativeEngineIntegration() async throws {
        try await verifyPipeline(includeMicrophone: true)
    }

    func testApplicationOnlySyntheticCaptureToNativeEngineIntegration() async throws {
        try await verifyPipeline(includeMicrophone: false)
    }

    private func verifyPipeline(includeMicrophone: Bool) async throws {
        guard ProcessInfo.processInfo.environment["MEETING_RECORDER_INTEGRATION"] == "1" else {
            throw XCTSkip("Run MEETING_RECORDER_INTEGRATION=1 swift test to exercise installed tools.")
        }
        let models = try ModelStore()
        guard models.isReady else { throw XCTSkip("Import a local GGUF into MeetingRecorder first.") }
        let directory = try directory()
        let source = try await recording(in: directory, includeMicrophone: includeMicrophone)
        let wav = directory.appendingPathComponent("normalized.wav")
        let tracks = try await AVURLAsset(url: source).loadTracks(withMediaType: .audio)
        XCTAssertEqual(tracks.count, includeMicrophone ? 2 : 1)
        _ = try await AudioNormalizer().normalize(source: source, destination: wav)
        let file = try AVAudioFile(forReading: wav)
        XCTAssertEqual(file.fileFormat.sampleRate, 16_000)
        XCTAssertEqual(file.fileFormat.channelCount, 1)
        XCTAssertEqual(Double(file.length) / 16_000, 2, accuracy: 0.1)
        let result = try await NativeTranscriber().transcribe(wav: wav, modelURL: models.modelURL,
                                                             cancellation: TranscriptionCancellation())
        XCTAssertEqual(result.audioSeconds, 2, accuracy: 0.1)
        XCTAssertFalse(result.model.isEmpty)
        XCTAssertFalse(result.engineVersion.isEmpty)
    }
}
