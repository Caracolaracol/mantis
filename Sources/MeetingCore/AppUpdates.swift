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

public struct AppRelease: Equatable, Sendable {
    public let version: AppVersion
    public let pageURL: URL

    public init?(tag: String) {
        guard let version = AppVersion(tag) else { return nil }
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

    public init() {}

    public static func request() -> URLRequest {
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
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
        let session = URLSession(configuration: configuration, delegate: UpdateRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: Self.request())
        guard let http = response as? HTTPURLResponse else { throw AppUpdateError.invalidResponse }
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200 else { throw AppUpdateError.unavailable }
        guard response.expectedContentLength <= Int64(Self.maximumBytes) else { throw AppUpdateError.responseTooLarge }
        var data = Data()
        for try await byte in bytes {
            guard data.count < Self.maximumBytes else { throw AppUpdateError.responseTooLarge }
            data.append(byte)
        }
        return try Self.parse(data)
    }

    public static func parse(_ data: Data) throws -> AppRelease? {
        guard data.count <= maximumBytes else { throw AppUpdateError.responseTooLarge }
        struct Metadata: Decodable {
            let tag_name: String
            let draft: Bool
            let prerelease: Bool
        }
        let metadata = try JSONDecoder().decode(Metadata.self, from: data)
        guard !metadata.draft, !metadata.prerelease else { return nil }
        guard let release = AppRelease(tag: metadata.tag_name) else { throw AppUpdateError.invalidResponse }
        return release
    }
}

private final class UpdateRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // A renamed repository or unexpected redirect must not silently change the destination.
        completionHandler(request.url == AppReleaseClient.endpoint ? request : nil)
    }
}
