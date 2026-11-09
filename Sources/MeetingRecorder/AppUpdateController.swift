import Combine
import Foundation
import MeetingCore

@MainActor
final class AppUpdateController: ObservableObject {
    enum State: Equatable {
        case idle, checking, upToDate, failed
        case available(AppRelease)
    }

    static let automaticKey = "mantisAutomaticUpdateChecks"
    static let lastAttemptKey = "mantisLastUpdateAttempt"
    static let skippedKey = "mantisSkippedUpdateVersion"
    static let interval: TimeInterval = 24 * 60 * 60

    @Published private(set) var state: State = .idle
    @Published private(set) var isChecking = false
    @Published var automaticChecks: Bool {
        didSet { if persists { defaults.set(automaticChecks, forKey: Self.automaticKey) } }
    }
    let installedVersion: String
    private let defaults: UserDefaults
    private let persists: Bool
    private let now: () -> Date
    private let fetch: () async throws -> AppRelease?
    private var lastAttempt: Date?
    private var skippedVersion: String?

    init(defaults: UserDefaults = .standard, persists: Bool = true,
         installedVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0",
         now: @escaping () -> Date = Date.init,
         fetch: @escaping () async throws -> AppRelease? = { try await AppReleaseClient().latest() }) {
        self.defaults = defaults
        self.persists = persists
        self.installedVersion = installedVersion
        self.now = now
        self.fetch = fetch
        automaticChecks = persists && defaults.bool(forKey: Self.automaticKey)
        lastAttempt = persists ? defaults.object(forKey: Self.lastAttemptKey) as? Date : nil
        skippedVersion = persists ? defaults.string(forKey: Self.skippedKey) : nil
    }

    func check(automatically: Bool = false, isBusy: Bool = false) async {
        guard !isBusy, !isChecking, let installed = AppVersion(installedVersion) else { return }
        if automatically {
            guard automaticChecks else { return }
            if let lastAttempt, now().timeIntervalSince(lastAttempt) < Self.interval { return }
        }
        // Rate-limit attempts too, so offline/failed requests cannot hammer GitHub.
        lastAttempt = now()
        if persists { defaults.set(lastAttempt, forKey: Self.lastAttemptKey) }
        isChecking = true
        if !automatically { state = .checking }
        defer { isChecking = false }
        do {
            let release = try await fetch()
            // Turning off automatic checks also suppresses a response already in flight.
            guard !automatically || automaticChecks else { return }
            if let release, release.version > installed {
                if !automatically || release.version.description != skippedVersion {
                    state = .available(release)
                }
            } else { state = automatically ? .idle : .upToDate }
        } catch {
            // Network errors never become recorder errors or interrupt a session.
            if !automatically { state = .failed }
        }
    }

    func dismiss() { state = .idle }

    func skip(_ release: AppRelease) {
        skippedVersion = release.version.description
        if persists { defaults.set(skippedVersion, forKey: Self.skippedKey) }
        dismiss()
    }

    /// Synthetic UI fixture: no preferences, network, downloads, or installation.
    static func preview(release: AppRelease) -> AppUpdateController {
        let controller = AppUpdateController(persists: false, installedVersion: "0.3.0", fetch: { nil })
        controller.state = .available(release)
        return controller
    }
}
