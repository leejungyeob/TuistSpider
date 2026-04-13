import Foundation

enum SpiderGraphImportError: LocalizedError, Identifiable, Sendable {
    case invalidRootObject
    case unsupportedFormat
    case malformedProjectList
    case processFailed(String)
    case fileNotFound(String)

    var id: String { errorDescription ?? UUID().uuidString }

    var errorDescription: String? {
        switch self {
        case .invalidRootObject:
            return "JSON 루트 형식을 읽지 못했습니다."
        case .unsupportedFormat:
            return "지원하지 않는 그래프 JSON 형식입니다."
        case .malformedProjectList:
            return "Tuist projects 배열 형식이 올바르지 않습니다."
        case let .processFailed(message):
            return message
        case let .fileNotFound(path):
            return "그래프 파일을 찾지 못했습니다: \(path)"
        }
    }
}

enum SpiderGraphImporter {
    static func load(from data: Data) throws -> SpiderGraph {
        let raw = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = raw as? [String: Any] else {
            throw SpiderGraphImportError.invalidRootObject
        }

        if dictionary["nodes"] is [[String: Any]], dictionary["edges"] is [[String: Any]] {
            return try parseNormalized(dictionary)
        }

        if dictionary["projects"] != nil {
            return try parseTuist(dictionary)
        }

        throw SpiderGraphImportError.unsupportedFormat
    }

    private static func parseNormalized(_ raw: [String: Any]) throws -> SpiderGraph {
        let nodes = (raw["nodes"] as? [[String: Any]] ?? []).compactMap(parseNode)
        let edges = (raw["edges"] as? [[String: Any]] ?? []).compactMap(parseEdge)
        return SpiderGraph(
            graphName: raw["graphName"] as? String ?? raw["name"] as? String ?? "TuistSpider",
            sourceFormat: raw["sourceFormat"] as? String ?? "normalized",
            rootPath: raw["rootPath"] as? String ?? raw["path"] as? String,
            generatedAt: raw["generatedAt"] as? String,
            nodes: nodes,
            edges: edges
        )
    }

    private static func parseTuist(_ raw: [String: Any]) throws -> SpiderGraph {
        let projectEntries = try pairProjects(raw["projects"])
        let rootPath = normalizeRootPath(raw["path"] as? String)
        var nodesByID: [String: SpiderGraphNode] = [:]
        var edges: [SpiderGraphEdge] = []

        for (projectPath, project) in projectEntries {
            let normalizedProjectPath = normalizePath(basePath: rootPath ?? projectPath, maybePath: projectPath)
            let isExternalProject = isExternalProjectPath(normalizedProjectPath, rootPath: rootPath)
            let projectName = (project["name"] as? String) ?? URL(fileURLWithPath: projectPath).lastPathComponent
            for target in extractTargets(project) {
                guard let name = target["name"] as? String else { continue }
                let nodeID = targetID(projectPath: normalizedProjectPath, targetName: name)
                nodesByID[nodeID] = SpiderGraphNode(
                    id: nodeID,
                    name: name,
                    displayName: name,
                    kind: "target",
                    product: target["product"] as? String,
                    bundleId: target["bundleId"] as? String,
                    projectName: isExternalProject ? "External" : projectName,
                    projectPath: normalizedProjectPath,
                    isExternal: isExternalProject,
                    sourceCount: countItems(target["sources"]),
                    resourceCount: countItems(target["resources"]),
                    metadataTags: ((target["metadata"] as? [String: Any])?["tags"] as? [String]) ?? []
                )
            }
        }

        for (projectPath, project) in projectEntries {
            let normalizedProjectPath = normalizePath(basePath: rootPath ?? projectPath, maybePath: projectPath)
            for target in extractTargets(project) {
                guard let sourceName = target["name"] as? String else { continue }
                let sourceID = targetID(projectPath: normalizedProjectPath, targetName: sourceName)
                let dependencies = target["dependencies"] as? [[String: Any]] ?? []

                for dependency in dependencies {
                    guard let descriptor = dependencyDescriptor(
                        from: dependency,
                        currentProjectPath: normalizedProjectPath,
                        rootPath: rootPath
                    ) else { continue }

                    if nodesByID[descriptor.id] == nil {
                        nodesByID[descriptor.id] = SpiderGraphNode(
                            id: descriptor.id,
                            name: descriptor.name,
                            displayName: descriptor.displayName,
                            kind: descriptor.kind,
                            product: nil,
                            bundleId: nil,
                            projectName: descriptor.isExternal ? "External" : nil,
                            projectPath: descriptor.projectPath,
                            isExternal: descriptor.isExternal,
                            sourceCount: 0,
                            resourceCount: 0,
                            metadataTags: []
                        )
                    }

                    edges.append(
                        SpiderGraphEdge(
                            from: sourceID,
                            to: descriptor.id,
                            kind: descriptor.kind,
                            status: descriptor.status
                        )
                    )
                }
            }
        }

        return SpiderGraph(
            graphName: raw["name"] as? String ?? "Tuist graph",
            sourceFormat: raw["projects"] is [Any] ? "tuist-json" : "tuist-legacy-json",
            rootPath: rootPath,
            generatedAt: nil,
            nodes: Array(nodesByID.values),
            edges: edges
        )
    }

    private static func parseNode(_ raw: [String: Any]) -> SpiderGraphNode? {
        guard
            let id = raw["id"] as? String,
            let name = raw["name"] as? String
        else {
            return nil
        }

        return SpiderGraphNode(
            id: id,
            name: name,
            displayName: raw["displayName"] as? String ?? name,
            kind: raw["kind"] as? String ?? "target",
            product: raw["product"] as? String,
            bundleId: raw["bundleId"] as? String,
            projectName: raw["projectName"] as? String,
            projectPath: raw["projectPath"] as? String,
            isExternal: raw["isExternal"] as? Bool ?? false,
            sourceCount: raw["sourceCount"] as? Int ?? 0,
            resourceCount: raw["resourceCount"] as? Int ?? 0,
            metadataTags: raw["metadataTags"] as? [String] ?? []
        )
    }

    private static func parseEdge(_ raw: [String: Any]) -> SpiderGraphEdge? {
        guard
            let from = raw["from"] as? String,
            let to = raw["to"] as? String,
            let kind = raw["kind"] as? String
        else {
            return nil
        }
        return SpiderGraphEdge(from: from, to: to, kind: kind, status: raw["status"] as? String)
    }

    private static func pairProjects(_ rawProjects: Any?) throws -> [(String, [String: Any])] {
        if let dictionary = rawProjects as? [String: Any] {
            return dictionary.compactMap { key, value in
                guard let project = value as? [String: Any] else { return nil }
                return (key, project)
            }
        }

        if let list = rawProjects as? [Any] {
            guard list.count.isMultiple(of: 2) else {
                throw SpiderGraphImportError.malformedProjectList
            }

            var pairs: [(String, [String: Any])] = []
            for index in stride(from: 0, to: list.count, by: 2) {
                guard
                    let path = list[index] as? String,
                    let project = list[index + 1] as? [String: Any]
                else {
                    throw SpiderGraphImportError.malformedProjectList
                }
                pairs.append((path, project))
            }
            return pairs
        }

        throw SpiderGraphImportError.unsupportedFormat
    }

    private static func extractTargets(_ project: [String: Any]) -> [[String: Any]] {
        if let targets = project["targets"] as? [[String: Any]] {
            return targets
        }
        if let targets = project["targets"] as? [String: Any] {
            return targets.values.compactMap { $0 as? [String: Any] }
        }
        return []
    }

    private static func dependencyDescriptor(
        from dependency: [String: Any],
        currentProjectPath: String,
        rootPath: String?
    ) -> (id: String, kind: String, name: String, displayName: String, projectPath: String?, isExternal: Bool, status: String?)? {
        if let payload = dependency["target"] as? [String: Any], let name = payload["name"] as? String {
            let projectPath = normalizePath(basePath: currentProjectPath, maybePath: payload["path"] as? String)
            let isExternal = isExternalProjectPath(projectPath, rootPath: rootPath)
            return (
                id: targetID(projectPath: projectPath, targetName: name),
                kind: "target",
                name: name,
                displayName: name,
                projectPath: projectPath,
                isExternal: isExternal,
                status: payload["status"] as? String
            )
        }

        if let payload = dependency["project"] as? [String: Any] {
            let name = payload["target"] as? String ?? payload["name"] as? String
            if let name {
                let projectPath = normalizePath(basePath: currentProjectPath, maybePath: payload["path"] as? String)
                let isExternal = isExternalProjectPath(projectPath, rootPath: rootPath)
                return (
                    id: targetID(projectPath: projectPath, targetName: name),
                    kind: "target",
                    name: name,
                    displayName: name,
                    projectPath: projectPath,
                    isExternal: isExternal,
                    status: payload["status"] as? String
                )
            }
        }

        for kind in ["package", "packageProduct", "external", "sdk", "framework", "xcframework", "library", "xctest", "macro", "plugin"] {
            guard let payload = dependency[kind] else { continue }
            guard let name = dependencyName(from: payload) else { continue }
            return (
                id: "\(kind)::\(name)",
                kind: kind,
                name: name,
                displayName: name,
                projectPath: nil,
                isExternal: true,
                status: nil
            )
        }

        return nil
    }

    private static func dependencyName(from raw: Any) -> String? {
        if let string = raw as? String { return string }
        guard let dictionary = raw as? [String: Any] else { return nil }
        if let name = dictionary["name"] as? String { return name }
        if let product = dictionary["product"] as? String { return product }
        if let target = dictionary["target"] as? String { return target }
        if let path = dictionary["path"] as? String {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        return nil
    }

    private static func targetID(projectPath: String, targetName: String) -> String {
        "target::\(projectPath)::\(targetName)"
    }

    private static func normalizePath(basePath: String, maybePath: String?) -> String {
        guard let maybePath, !maybePath.isEmpty else { return basePath }
        if maybePath.hasPrefix("/") { return maybePath }
        return URL(fileURLWithPath: basePath).appendingPathComponent(maybePath).path
    }

    private static func normalizeRootPath(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func isExternalProjectPath(_ projectPath: String, rootPath: String?) -> Bool {
        let standardizedPath = URL(fileURLWithPath: projectPath).standardizedFileURL.path
        let pathComponents = URL(fileURLWithPath: standardizedPath).pathComponents.map { $0.lowercased() }
        let externalMarkers = [
            "checkouts",
            "sourcepackages",
            "swiftpackagemanager",
            ".build",
            ".cache",
            "cocoapods",
            "carthage",
        ]

        if externalMarkers.contains(where: { pathComponents.contains($0) }) {
            return true
        }

        guard let rootPath else { return false }
        let standardizedRoot = URL(fileURLWithPath: rootPath).standardizedFileURL.path
        if standardizedPath == standardizedRoot {
            return false
        }

        let rootWithSlash = standardizedRoot.hasSuffix("/") ? standardizedRoot : standardizedRoot + "/"
        return !standardizedPath.hasPrefix(rootWithSlash)
    }

    private static func countItems(_ raw: Any?) -> Int {
        if let array = raw as? [Any] { return array.count }
        if let dictionary = raw as? [String: Any] { return dictionary.count }
        return 0
    }
}
