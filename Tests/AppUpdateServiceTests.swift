import XCTest
@testable import TuistSpider

final class AppUpdateServiceTests: XCTestCase {
    func testNormalizeVersionStringStripsPrefixAndPrereleaseSuffix() {
        XCTAssertEqual(AppUpdateService.normalizeVersionString("v1.2.3"), "1.2.3")
        XCTAssertEqual(AppUpdateService.normalizeVersionString("release-2.0.1-beta.4"), "2.0.1")
        XCTAssertEqual(AppUpdateService.normalizeVersionString("1.0"), "1.0")
    }

    func testCompareVersionsTreatsMissingPatchAsSameVersion() {
        XCTAssertEqual(AppUpdateService.compareVersions("1.0", "1.0.0"), .orderedSame)
        XCTAssertEqual(AppUpdateService.compareVersions("1.0.1", "1.0"), .orderedDescending)
        XCTAssertEqual(AppUpdateService.compareVersions("1.9.9", "2.0.0"), .orderedAscending)
    }

    func testPreferredDownloadURLPrefersDMGThenZip() {
        let fallbackURL = URL(string: "https://github.com/leejungyeob/TuistSpider/releases/tag/v1.0.0")!
        let assets = [
            GitHubReleaseAssetPayload(
                name: "TuistSpider.zip",
                browserDownloadURL: "https://example.com/TuistSpider.zip"
            ),
            GitHubReleaseAssetPayload(
                name: "TuistSpider.dmg",
                browserDownloadURL: "https://example.com/TuistSpider.dmg"
            ),
        ]

        XCTAssertEqual(
            AppUpdateService.preferredDownloadURL(assets: assets, fallbackURL: fallbackURL),
            URL(string: "https://example.com/TuistSpider.dmg")
        )
    }
}
