import Foundation

/// Stable semantic versions only. Never compare version strings lexicographically.
public struct AppVersion: Comparable, Equatable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(_ value: String) {
        let text = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.count <= 9,
                  part.utf8.allSatisfy({ (48...57).contains($0) }),
                  part.count == 1 || part.first != "0", let number = Int(part) else { return nil }
            numbers.append(number)
        }
        major = numbers[0]; minor = numbers[1]; patch = numbers[2]
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    public var description: String { "\(major).\(minor).\(patch)" }
}

public enum AppUpdateChannel: Equatable, Sendable {
    case standard, sonoma

    public static var current: AppUpdateChannel {
        #if MANTIS_SONOMA
        .sonoma
        #else
        .standard
        #endif
    }
}

public struct AppRelease: Equatable, Sendable {
    public let version: AppVersion
    public let pageURL: URL

    public init?(tag: String, channel: AppUpdateChannel = .standard) {
        let versionTag: String
        switch channel {
        case .standard: versionTag = tag
        case .sonoma:
            guard tag.hasSuffix("-sonoma") else { return nil }
            versionTag = String(tag.dropLast("-sonoma".count))
        }
        guard let version = AppVersion(versionTag) else { return nil }
        self.version = version
        // Do not trust html_url or asset URLs supplied by remote metadata.
        pageURL = URL(string: "https://github.com/Caracolaracol/mantis/releases/tag/\(tag)")!
    }
}

public enum AppUpdateError: Error {
    case invalidResponse, responseTooLarge, unavailable
}

public struct AppReleaseClient: Sendable {
    public static let endpoint = URL(string: "https://api.github.com/repos/Caracolaracol/mantis/releases/latest")!
    public static let maximumBytes = 262_144

    private let channel: AppUpdateChannel

    public init(channel: AppUpdateChannel = .current) { self.channel = channel }

    public static func endpoint(for channel: AppUpdateChannel) -> URL {
        switch channel {
        case .standard: endpoint
        case .sonoma: URL(string: "https://api.github.com/repos/Caracolaracol/mantis/releases?per_page=20")!
        }
    }

    public static func request(channel: AppUpdateChannel = .current) -> URLRequest {
        var request = URLRequest(url: endpoint(for: channel), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Mantis-Update-Check", forHTTPHeaderField: "User-Agent")
        return request
    }

    public func latest() async throws -> AppRelease? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForResource = 20
        let session = URLSession(configuration: configuration, delegate: UpdateRedirectPolicy(endpoint: Self.endpoint(for: channel)), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: Self.request(channel: channel))
        guard let http = response as? HTTPURLResponse else { throw AppUpdateError.invalidResponse }
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200 else { throw AppUpdateError.unavailable }
        guard response.expectedContentLength <= Int64(Self.maximumBytes) else { throw AppUpdateError.responseTooLarge }
        var data = Data()
        for try await byte in bytes {
            guard data.count < Self.maximumBytes else { throw AppUpdateError.responseTooLarge }
            data.append(byte)
        }
        return try Self.parse(data, channel: channel)
    }

    public static func parse(_ data: Data, channel: AppUpdateChannel = .standard) throws -> AppRelease? {
        guard data.count <= maximumBytes else { throw AppUpdateError.responseTooLarge }
        struct Metadata: Decodable {
            let tag_name: String
            let draft: Bool
            let prerelease: Bool
        }
        if channel == .sonoma {
            // Sonoma is a distinct opt-in compatibility channel, including its test releases.
            // Never offer a standard macOS-15-only installer to a Sonoma user.
            let releases = try JSONDecoder().decode([Metadata].self, from: data)
            return releases.filter { !$0.draft }.compactMap { AppRelease(tag: $0.tag_name, channel: .sonoma) }
                .max { $0.version < $1.version }
        }
        let metadata = try JSONDecoder().decode(Metadata.self, from: data)
        guard !metadata.draft, !metadata.prerelease else { return nil }
        guard let release = AppRelease(tag: metadata.tag_name) else { throw AppUpdateError.invalidResponse }
        return release
    }
}

private final class UpdateRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let endpoint: URL
    init(endpoint: URL) { self.endpoint = endpoint }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // A renamed repository or unexpected redirect must not silently change the destination.
        completionHandler(request.url == endpoint ? request : nil)
    }
}
