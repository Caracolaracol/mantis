import AppKit
import AVFoundation
import CoreGraphics
import MeetingCore

@MainActor
enum PermissionService {
    static func snapshot() -> CaptureAuthorizationSnapshot {
        let microphone: CaptureAuthorizationState
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: microphone = .allowed
        case .notDetermined: microphone = .notRequested
        case .denied: microphone = .denied
        case .restricted: microphone = .restricted
        @unknown default: microphone = .denied
        }
        // CoreGraphics cannot distinguish missing grants from a stale code
        // requirement after an ad hoc rebuild. Never call this "not requested".
        // Never trigger a prompt just to draw UI; explicit buttons handle authorization.
        return CaptureAuthorizationSnapshot(microphone: microphone,
                                             systemAudio: .screenCapturePreflight(CGPreflightScreenCaptureAccess()))
    }

    static func request(_ kind: CapturePermissionKind) async -> Bool {
        switch kind {
        case .microphone: return await AVCaptureDevice.requestAccess(for: .audio)
        case .systemAudio: return CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess()
        }
    }

    static func openSettings(_ kind: CapturePermissionKind) {
        NSWorkspace.shared.open(kind.settingsURL)
    }
}
