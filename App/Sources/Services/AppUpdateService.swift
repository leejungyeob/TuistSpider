import Foundation

struct AppUpdateRelease: Identifiable, Equatable, Sendable {
    let version: String
    let title: String
    let notes: String
    let htmlURL: URL
    let downloadURL: URL
    let publishedAt: Date?

    var id: String { version }

    var displayVersion: String {
        "v\(version)"
    }

    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? displayVersion : title
    }
}

enum AppUpdateCheckResult: Equatable, Sendable {
    case upToDate(latestVersion: String)
    case updateAvailable(AppUpdateRelease)
}

enum AppUpdateServiceError: LocalizedError {
    case invalidResponse
    case unsupportedReleasePayload

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "릴리즈 정보를 불러오지 못했습니다."
        case .unsupportedReleasePayload:
            return "릴리즈 응답 형식이 올바르지 않습니다."
        }
    }
}

struct AppUpdateService {
    private let session: URLSession
    private let latestReleaseURL: URL

    init(
        session: URLSession = .shared,
        latestReleaseURL: URL = URL(string: "https://api.github.com/repos/leejungyeob/TuistSpider/releases/latest")!
    ) {
        self.session = session
        self.latestReleaseURL = latestReleaseURL
    }

    func checkForUpdates(
        currentVersion: String,
        skippedVersion: String? = nil
    ) async throws -> AppUpdateCheckResult {
        let latestRelease = try await fetchLatestRelease()
        let current = Self.normalizeVersionString(currentVersion)
        let latest = latestRelease.version

        if
            let skippedVersion,
            Self.compareVersions(Self.normalizeVersionString(skippedVersion), latest) == .orderedSame
        {
            return .upToDate(latestVersion: latest)
        }

        if Self.compareVersions(current, latest) == .orderedAscending {
            return .updateAvailable(latestRelease)
        }

        return .upToDate(latestVersion: latest)
    }

    func fetchLatestRelease() async throws -> AppUpdateRelease {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("TuistSpider", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw AppUpdateServiceError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let release = try decoder.decode(GitHubReleasePayload.self, from: data)
        guard let htmlURL = URL(string: release.htmlURL) else {
            throw AppUpdateServiceError.unsupportedReleasePayload
        }

        return AppUpdateRelease(
            version: Self.normalizeVersionString(release.tagName),
            title: release.name ?? "",
            notes: release.body ?? "",
            htmlURL: htmlURL,
            downloadURL: Self.preferredDownloadURL(assets: release.assets, fallbackURL: htmlURL),
            publishedAt: release.publishedAt
        )
    }

    static func normalizeVersionString(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: #"\d+(?:\.\d+)*"#, options: .regularExpression) else {
            return "0"
        }
        return String(trimmed[range])
    }

    static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsComponents = normalizedVersionComponents(lhs)
        let rhsComponents = normalizedVersionComponents(rhs)
        let maxCount = max(lhsComponents.count, rhsComponents.count)

        for index in 0..<maxCount {
            let lhsValue = index < lhsComponents.count ? lhsComponents[index] : 0
            let rhsValue = index < rhsComponents.count ? rhsComponents[index] : 0
            if lhsValue < rhsValue { return .orderedAscending }
            if lhsValue > rhsValue { return .orderedDescending }
        }

        return .orderedSame
    }

    static func preferredDownloadURL(
        assets: [GitHubReleaseAssetPayload],
        fallbackURL: URL
    ) -> URL {
        let preferredExtensions = ["dmg", "zip", "pkg"]
        for preferredExtension in preferredExtensions {
            if let assetURL = assets.firstURL(matchingExtension: preferredExtension) {
                return assetURL
            }
        }
        return fallbackURL
    }

    private static func normalizedVersionComponents(_ value: String) -> [Int] {
        normalizeVersionString(value)
            .split(separator: ".")
            .compactMap { Int($0) }
    }
}

struct GitHubReleaseAssetPayload: Decodable, Sendable {
    let name: String
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

private struct GitHubReleasePayload: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: String
    let publishedAt: Date?
    let assets: [GitHubReleaseAssetPayload]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case assets
    }
}

private extension Array where Element == GitHubReleaseAssetPayload {
    func firstURL(matchingExtension fileExtension: String) -> URL? {
        first(where: { $0.name.lowercased().hasSuffix(".\(fileExtension)") })
            .flatMap { URL(string: $0.browserDownloadURL) }
    }
}
