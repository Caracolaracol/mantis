import AVFoundation
import CoreMedia
import MeetingCore
import ScreenCaptureKit

enum CapturePermissions {
    @MainActor
    static func ensure(for mode: RecordingMode,
                       requestMicrophone: () async -> Bool = { await PermissionService.request(.microphone) },
                       requestSystemAudio: () async -> Bool = { await PermissionService.request(.systemAudio) }) async throws {
        if mode.capturesMicrophone, !(await requestMicrophone()) { throw CaptureAuthorizationError(.microphone) }
        if mode.capturesScreenAudio, !(await requestSystemAudio()) { throw CaptureAuthorizationError(.systemAudio) }
    }

    static func microphoneAllowed(for mode: RecordingMode,
                                  requestAccess: () async -> Bool = { await AVCaptureDevice.requestAccess(for: .audio) }) async -> Bool {
        guard mode.capturesMicrophone else { return true }
        return await requestAccess()
    }
}

/// A testable description of the actual stream configuration and registered outputs.
struct ApplicationCapturePlan {
    let capturesMicrophone: Bool

    init(mode: RecordingMode) {
        precondition(mode.capturesScreenAudio, "Use AVAudioRecorder for microphone-only capture")
        capturesMicrophone = mode.capturesMicrophone
    }

    var outputTypes: [SCStreamOutputType] {
        var types: [SCStreamOutputType] = [.audio]
        if capturesMicrophone { types.append(.microphone) }
        // Frames maintain the capture stream but are discarded, never written to disk.
        types.append(.screen)
        return types
    }

    func configuration() -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.queueDepth = 3
        configuration.showsCursor = false
        configuration.capturesAudio = true
        configuration.captureMicrophone = capturesMicrophone
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 1
        return configuration
    }
}
