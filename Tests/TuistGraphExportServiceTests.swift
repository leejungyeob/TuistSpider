import XCTest
@testable import TuistSpider

final class TuistGraphExportServiceTests: XCTestCase {
    func testResolveTuistExecutablePrefersExplicitEnvironmentPath() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let explicitTuist = try makeExecutable(named: "explicit-tuist", in: rootURL)
        let miseTuist = try makeExecutable(named: "mise-tuist", in: rootURL)
        _ = try makeMiseExecutable(in: rootURL, tuistPath: miseTuist.path)

        let service = TuistGraphExportService(
            environment: [
                "HOME": rootURL.path,
                "PATH": rootURL.path,
                "TUIST_EXECUTABLE": explicitTuist.path,
            ]
        )

        XCTAssertEqual(
            try service.resolveTuistExecutable(for: rootURL),
            explicitTuist.path
        )
    }

    func testResolveTuistExecutableUsesProjectMiseBeforePathTuist() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let miseTuist = try makeExecutable(named: "mise-tuist", in: rootURL)
        _ = try makeMiseExecutable(in: rootURL, tuistPath: miseTuist.path)
        _ = try makeExecutable(named: "tuist", in: rootURL)

        let service = TuistGraphExportService(
            environment: [
                "HOME": rootURL.path,
                "PATH": rootURL.path,
            ]
        )

        XCTAssertEqual(
            try service.resolveTuistExecutable(for: rootURL),
            miseTuist.path
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tuist-spider-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeExecutable(named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try "#!/bin/sh\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func makeMiseExecutable(in directory: URL, tuistPath: String) throws -> URL {
        let url = directory.appendingPathComponent("mise")
        let script = """
        #!/bin/sh
        if [ "$1" = "which" ] && [ "$2" = "tuist" ]; then
          printf '%s\\n' "\(tuistPath)"
          exit 0
        fi
        exit 1
        """
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}
