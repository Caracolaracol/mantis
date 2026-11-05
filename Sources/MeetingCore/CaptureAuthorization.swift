import Foundation

public enum CapturePermissionKind: String, CaseIterable, Identifiable, Sendable {
    case microphone, systemAudio
    public var id: String { rawValue }
    public var title: String {
        self == .microphone ? "Entrada de audio (permiso Micrófono)" : "Audio del computador"
    }
    public var settingsURL: URL {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?\(self == .microphone ? "Privacy_Microphone" : "Privacy_ScreenCapture")")!
    }
    public var settingsSection: String {
        self == .microphone ? "Micrófono" : "Grabación de pantalla y audio del sistema"
    }
    public var recoveryMessage: String {
        "macOS no autorizó el acceso \(self == .microphone ? "a tu micrófono" : "al audio del computador"). Revisa Ajustes del Sistema → Privacidad y seguridad → \(settingsSection). Si Mantis ya está activado, sal completamente desde su menú y vuelve a abrirlo; cerrar la ventana no termina la app. Tras recompilar, el permiso puede corresponder a una versión anterior y necesitar volver a autorizarse."
    }
}

public enum CaptureAuthorizationState: String, Sendable {
    case allowed, notRequested, denied, restricted, unverified
    public var title: String {
        switch self {
        case .allowed: return "Autorizado"
        case .notRequested: return "Por autorizar"
        case .denied: return "Sin acceso"
        case .restricted: return "Restringido por el sistema"
        case .unverified: return "No confirmado para esta versión"
        }
    }

    /// A false preflight is not proof that the user left the Settings toggle off.
    public static func screenCapturePreflight(_ allowed: Bool) -> Self {
        allowed ? .allowed : .unverified
    }
}

public struct CaptureAuthorizationSnapshot: Equatable, Sendable {
    public let microphone: CaptureAuthorizationState
    public let systemAudio: CaptureAuthorizationState
    public init(microphone: CaptureAuthorizationState, systemAudio: CaptureAuthorizationState) {
        self.microphone = microphone
        self.systemAudio = systemAudio
    }
    public subscript(_ kind: CapturePermissionKind) -> CaptureAuthorizationState {
        kind == .microphone ? microphone : systemAudio
    }
    public func required(for mode: RecordingMode) -> [CapturePermissionKind] {
        var kinds: [CapturePermissionKind] = []
        if mode.capturesMicrophone { kinds.append(.microphone) }
        if mode.capturesScreenAudio { kinds.append(.systemAudio) }
        return kinds
    }
}

public struct CaptureAuthorizationError: LocalizedError, Sendable {
    public let permission: CapturePermissionKind
    public init(_ permission: CapturePermissionKind) { self.permission = permission }
    public var errorDescription: String? { permission.recoveryMessage }
}

public enum CaptureErrorPresentation {
    public static func permission(for error: Error) -> CapturePermissionKind? {
        if let error = error as? CaptureAuthorizationError { return error.permission }
        var current = error as NSError
        for _ in 0..<5 {
            if current.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain", current.code == -3801 {
                return .systemAudio
            }
            guard let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError else { break }
            current = underlying
        }
        return permission(in: error.localizedDescription)
    }

    /// Includes legacy persisted errors; old meetings do not need a schema migration.
    public static func permission(in message: String) -> CapturePermissionKind? {
        let lower = message.lowercased()
        if lower.contains("tcc"), lower.contains("captur") || lower.contains("screen") { return .systemAudio }
        if lower.contains("macos no autorizó el acceso al audio del computador") { return .systemAudio }
        if lower.contains("autoriza el micrófono") || lower.contains("macos no autorizó el acceso a tu micrófono") { return .microphone }
        return nil
    }

    public static func message(for error: Error) -> String {
        permission(for: error)?.recoveryMessage ?? error.localizedDescription
    }
    public static func message(for text: String) -> String {
        permission(in: text)?.recoveryMessage ?? text
    }
}
