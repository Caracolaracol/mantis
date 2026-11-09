import XCTest
import MeetingCore

final class AppUpdatesTests: XCTestCase {
    func testStableVersionsCompareNumerically() throws {
        XCTAssertLessThan(try XCTUnwrap(AppVersion("0.9.0")), try XCTUnwrap(AppVersion("0.10.0")))
        XCTAssertLessThan(try XCTUnwrap(AppVersion("1.0.9")), try XCTUnwrap(AppVersion("1.0.10")))
        XCTAssertEqual(AppVersion("v0.3.0"), AppVersion("0.3.0"))
        for value in ["", "1.2", "1.2.3.4", "01.2.3", "1.2.-1", "1.2.3-beta", "1.2.3+build", "1.2.3/path", "1.2. 3", "9999999999.0.0"] {
            XCTAssertNil(AppVersion(value), value)
            XCTAssertNil(AppRelease(tag: value), value)
        }
    }

    func testStableReleaseIgnoresRemoteDownloadURLs() throws {
        let data = Data(#"{"tag_name":"v0.4.0","draft":false,"prerelease":false,"html_url":"https://malicious.example","assets":[{"browser_download_url":"file:///Applications/Mantis.app"}]}"#.utf8)
        let release = try XCTUnwrap(AppReleaseClient.parse(data))
        XCTAssertEqual(release.version, AppVersion("0.4.0"))
        XCTAssertEqual(release.pageURL.absoluteString, "https://github.com/Caracolaracol/mantis/releases/tag/v0.4.0")
    }

    func testDraftsAndPrereleasesAreNotOffered() throws {
        for flags in [(true, false), (false, true)] {
            let data = Data("{\"tag_name\":\"v0.4.0\",\"draft\":\(flags.0),\"prerelease\":\(flags.1)}".utf8)
            XCTAssertNil(try AppReleaseClient.parse(data))
        }
    }

    func testMalformedUnstableAndOversizedResponsesFailClosed() {
        for text in ["{}", "not JSON", #"{"tag_name":"v0.4.0-rc1","draft":false,"prerelease":false}"#,
                     #"{"tag_name":"https://example.com","draft":false,"prerelease":false}"#] {
            XCTAssertThrowsError(try AppReleaseClient.parse(Data(text.utf8)))
        }
        XCTAssertThrowsError(try AppReleaseClient.parse(Data(repeating: 32, count: AppReleaseClient.maximumBytes + 1)))
    }

    func testRequestHasOnlyTrustedMetadataDestinationAndNoCredentialsOrPayload() {
        let request = AppReleaseClient.request()
        XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/repos/Caracolaracol/mantis/releases/latest")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertEqual(request.timeoutInterval, 15)
    }
}
