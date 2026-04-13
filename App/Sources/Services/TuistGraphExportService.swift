import Foundation

struct TuistGraphExportService: Sendable {
    func loadFromProject(at projectURL: URL) throws -> SpiderGraph {
        let fileManager = FileManager.default
        let tuistExecutable = try resolveTuistExecutable()
        let tempDirectory = fileManager.temporaryDirectory.appendingPathComponent("tuist-spider-\(UUID().uuidString)", isDirectory: true)
        let clangCache = URL(fileURLWithPath: "/tmp/clang-modules", isDirectory: true)
        let swiftCache = URL(fileURLWithPath: "/tmp/swift-modules", isDirectory: true)

        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: clangCache, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: swiftCache, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDirectory) }

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: tuistExecutable)
        process.arguments = [
            "graph",
            "--format", "json",
            "--no-open",
            "--path", projectURL.path,
            "--output-path", tempDirectory.path,
        ]
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.environment = ProcessInfo.processInfo.environment.merging(
            [
                "PATH": resolvedPathEnvironment(for: tuistExecutable),
                "TUIST_XDG_STATE_HOME": "/tmp",
                "CLANG_MODULE_CACHE_PATH": clangCache.path,
                "SWIFT_MODULECACHE_PATH": swiftCache.path,
            ],
            uniquingKeysWith: { _, new in new }
        )

        do {
            try process.run()
        } catch {
            throw SpiderGraphImportError.processFailed(
                "tuist 실행에 실패했습니다. 사용 중인 경로: \(tuistExecutable)\n\(error.localizedDescription)"
            )
        }
        process.waitUntilExit()

        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let message = [stderr, stdout]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            throw SpiderGraphImportError.processFailed(
                message.isEmpty ? "tuist graph 실행에 실패했습니다." : message
            )
        }

        let graphURL = tempDirectory.appendingPathComponent("graph.json")
        guard fileManager.fileExists(atPath: graphURL.path) else {
            throw SpiderGraphImportError.fileNotFound(graphURL.path)
        }

        let data = try Data(contentsOf: graphURL)
        return try SpiderGraphImporter.load(from: data)
    }

    func loadFromJSONFile(at fileURL: URL) throws -> SpiderGraph {
        let data = try Data(contentsOf: fileURL)
        return try SpiderGraphImporter.load(from: data)
    }

    private func resolveTuistExecutable() throws -> String {
        let fileManager = FileManager.default
        let environment = ProcessInfo.processInfo.environment
        let homeDirectory = environment["HOME"] ?? NSHomeDirectory()
        var candidates: [String] = []

        if let configuredPath = environment["TUIST_EXECUTABLE"]?.trimmingCharacters(in: .whitespacesAndNewlines), !configuredPath.isEmpty {
            candidates.append(configuredPath)
        }

        if let path = environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map { "\($0)/tuist" })
        }

        candidates.append(contentsOf: [
            "\(homeDirectory)/.local/bin/tuist",
            "\(homeDirectory)/bin/tuist",
            "/opt/homebrew/bin/tuist",
            "/usr/local/bin/tuist",
            "/opt/homebrew/opt/tuist/bin/tuist",
            "/usr/local/opt/tuist/bin/tuist",
        ])

        candidates.append(contentsOf: brewOptCandidates(in: "/opt/homebrew/opt"))
        candidates.append(contentsOf: brewOptCandidates(in: "/usr/local/opt"))

        var seen = Set<String>()
        for candidate in candidates where seen.insert(candidate).inserted {
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        throw SpiderGraphImportError.processFailed(
            """
            tuist 실행 파일을 찾지 못했습니다.
            기본 경로(/opt/homebrew/bin/tuist, /usr/local/bin/tuist)를 확인하거나 `TUIST_EXECUTABLE` 환경변수로 직접 지정해주세요.
            """
        )
    }

    private func brewOptCandidates(in rootPath: String) -> [String] {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: rootPath) else {
            return []
        }

        return contents
            .filter { $0 == "tuist" || $0.hasPrefix("tuist@") }
            .map { "\(rootPath)/\($0)/bin/tuist" }
    }

    private func resolvedPathEnvironment(for executablePath: String) -> String {
        let existing = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let executableDirectory = URL(fileURLWithPath: executablePath).deletingLastPathComponent().path
        let preferredDirectories = [executableDirectory, "/opt/homebrew/bin", "/usr/local/bin"]

        var seen = Set<String>()
        let merged = (preferredDirectories + existing.split(separator: ":").map(String.init))
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }

        return merged.joined(separator: ":")
    }
}
