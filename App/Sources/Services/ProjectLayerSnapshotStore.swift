import Foundation

enum ProjectLayerSnapshotStoreError: LocalizedError {
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(version):
            return "지원하지 않는 레이어 스냅샷 버전입니다: \(version)"
        }
    }
}

enum ProjectLayerSnapshotStore {
    static let directoryName = ".tuist-spider"
    static let fileName = "layers.json"

    static func snapshotFileURL(rootURL: URL) -> URL {
        rootURL
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    static func canPersist(_ node: SpiderGraphNode, rootURL: URL) -> Bool {
        snapshotKey(for: node, rootURL: rootURL) != nil
    }

    static func load(rootURL: URL) throws -> ProjectLayerSnapshot? {
        let fileURL = snapshotFileURL(rootURL: rootURL)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        let data = try Data(contentsOf: fileURL)
        let snapshot = try JSONDecoder().decode(ProjectLayerSnapshot.self, from: data)
        guard snapshot.version == 1 else {
            throw ProjectLayerSnapshotStoreError.unsupportedVersion(snapshot.version)
        }
        return snapshot.normalized()
    }

    static func apply(_ snapshot: ProjectLayerSnapshot, to graph: SpiderGraph, rootURL: URL) -> SpiderGraph {
        let entriesByKey = Dictionary(uniqueKeysWithValues: snapshot.targets.map { ($0.key, $0) })
        let updatedNodes = graph.nodes.map { node in
            guard
                let key = snapshotKey(for: node, rootURL: rootURL),
                let entry = entriesByKey[key]
            else {
                return node
            }

            return node.updatingClassification(
                primaryLayer: normalizedLayerName(entry.layer),
                layerSource: .projectSnapshot,
                hasPersistedClassification: true
            )
        }

        return graph.replacingNodes(updatedNodes)
    }

    @discardableResult
    static func syncSnapshot(for graph: SpiderGraph, rootURL: URL) throws -> Bool {
        let snapshot = makeSnapshot(for: graph, rootURL: rootURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(snapshot)
        let fileURL = snapshotFileURL(rootURL: rootURL)
        let directoryURL = fileURL.deletingLastPathComponent()
        let fileManager = FileManager.default

        if let existingData = try? Data(contentsOf: fileURL), existingData == data {
            return false
        }

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        return true
    }

    private static func makeSnapshot(for graph: SpiderGraph, rootURL: URL) -> ProjectLayerSnapshot {
        let targets = graph.nodes.compactMap { node -> ProjectLayerSnapshot.TargetEntry? in
            guard let key = snapshotKey(for: node, rootURL: rootURL) else { return nil }
            return ProjectLayerSnapshot.TargetEntry(
                projectPath: key.projectPath,
                targetName: key.targetName,
                layer: normalizedLayerName(node.primaryLayer)
            )
        }

        return ProjectLayerSnapshot(
            version: 1,
            targets: targets.sorted { lhs, rhs in
                ProjectLayerSnapshot.TargetEntry.sort(lhs: lhs, rhs: rhs)
            }
        )
    }

    private static func snapshotKey(for node: SpiderGraphNode, rootURL: URL) -> SnapshotKey? {
        guard node.isInternalTarget, let projectPath = node.projectPath else { return nil }
        guard let relativeProjectPath = relativeProjectPath(projectPath, rootURL: rootURL) else { return nil }
        return SnapshotKey(projectPath: relativeProjectPath, targetName: node.name)
    }

    private static func relativeProjectPath(_ projectPath: String, rootURL: URL) -> String? {
        let standardizedRootPath = rootURL.standardizedFileURL.path
        let standardizedProjectPath = URL(fileURLWithPath: projectPath).standardizedFileURL.path

        if standardizedProjectPath == standardizedRootPath {
            return "."
        }

        let rootWithSlash = standardizedRootPath.hasSuffix("/") ? standardizedRootPath : standardizedRootPath + "/"
        guard standardizedProjectPath.hasPrefix(rootWithSlash) else { return nil }

        return String(standardizedProjectPath.dropFirst(rootWithSlash.count))
    }

    private static func normalizedLayerName(_ layer: String?) -> String? {
        guard let layer else { return nil }
        let trimmed = layer.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    fileprivate struct SnapshotKey: Hashable {
        let projectPath: String
        let targetName: String
    }

    struct ProjectLayerSnapshot: Codable {
        let version: Int
        let targets: [TargetEntry]

        func normalized() -> ProjectLayerSnapshot {
            ProjectLayerSnapshot(
                version: version,
                targets: targets
                    .map { entry in
                        TargetEntry(
                            projectPath: entry.projectPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "." : entry.projectPath,
                            targetName: entry.targetName.trimmingCharacters(in: .whitespacesAndNewlines),
                            layer: ProjectLayerSnapshotStore.normalizedLayerName(entry.layer)
                        )
                    }
                    .filter { !$0.targetName.isEmpty }
                    .sorted { lhs, rhs in
                        TargetEntry.sort(lhs: lhs, rhs: rhs)
                    }
            )
        }

        struct TargetEntry: Codable, Hashable {
            let projectPath: String
            let targetName: String
            let layer: String?

            fileprivate var key: SnapshotKey {
                SnapshotKey(projectPath: projectPath, targetName: targetName)
            }

            static func sort(lhs: TargetEntry, rhs: TargetEntry) -> Bool {
                if lhs.projectPath != rhs.projectPath {
                    return lhs.projectPath.localizedCaseInsensitiveCompare(rhs.projectPath) == .orderedAscending
                }
                return lhs.targetName.localizedCaseInsensitiveCompare(rhs.targetName) == .orderedAscending
            }
        }
    }
}
