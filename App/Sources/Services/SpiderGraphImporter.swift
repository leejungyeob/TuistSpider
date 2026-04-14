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
        var warnings = raw["warnings"] as? [String] ?? []
        let nodes = (raw["nodes"] as? [[String: Any]] ?? []).compactMap { parseNode($0, warnings: &warnings) }
        let edges = (raw["edges"] as? [[String: Any]] ?? []).compactMap(parseEdge)
        return SpiderGraph(
            graphName: raw["graphName"] as? String ?? raw["name"] as? String ?? "TuistSpider",
            sourceFormat: raw["sourceFormat"] as? String ?? "normalized",
            rootPath: raw["rootPath"] as? String ?? raw["path"] as? String,
            generatedAt: raw["generatedAt"] as? String,
            warnings: warnings,
            nodes: nodes,
            edges: edges
        )
    }

    private static func parseTuist(_ raw: [String: Any]) throws -> SpiderGraph {
        let projectEntries = try pairProjects(raw["projects"])
        let rootPath = normalizeRootPath(raw["path"] as? String)
        var nodesByID: [String: SpiderGraphNode] = [:]
        var edges: [SpiderGraphEdge] = []
        var warnings: [String] = []

        for (projectPath, project) in projectEntries {
            let normalizedProjectPath = normalizePath(basePath: rootPath ?? projectPath, maybePath: projectPath)
            let isExternalProject = isExternalProjectPath(normalizedProjectPath, rootPath: rootPath)
            let projectName = (project["name"] as? String) ?? URL(fileURLWithPath: projectPath).lastPathComponent
            for target in extractTargets(project) {
                guard let name = target["name"] as? String else { continue }
                let nodeID = targetID(projectPath: normalizedProjectPath, targetName: name)
                let rawTags = ((target["metadata"] as? [String: Any])?["tags"] as? [String]) ?? []
                let layerMetadata = resolveLayerMetadata(
                    from: rawTags,
                    nodeName: name,
                    projectPath: normalizedProjectPath,
                    product: target["product"] as? String,
                    kind: "target",
                    isExternal: isExternalProject
                )
                warnings.append(contentsOf: layerMetadata.warnings)
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
                    primaryLayer: layerMetadata.primaryLayer,
                    layerSource: layerMetadata.layerSource,
                    metadataTags: layerMetadata.metadataTags,
                    suggestedLayer: layerMetadata.primaryLayer,
                    suggestedLayerSource: layerMetadata.layerSource
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
                            primaryLayer: nil,
                            layerSource: nil,
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
            warnings: warnings,
            nodes: Array(nodesByID.values),
            edges: edges
        )
    }

    private static func parseNode(_ raw: [String: Any], warnings: inout [String]) -> SpiderGraphNode? {
        guard
            let id = raw["id"] as? String,
            let name = raw["name"] as? String
        else {
            return nil
        }

        let parsedTags = resolveLayerMetadata(
            from: raw["metadataTags"] as? [String] ?? [],
            nodeName: name,
            projectPath: raw["projectPath"] as? String,
            product: raw["product"] as? String,
            kind: raw["kind"] as? String ?? "target",
            isExternal: raw["isExternal"] as? Bool ?? false
        )
        warnings.append(contentsOf: parsedTags.warnings)
        let explicitPrimaryLayer = normalizedLayerName(raw["primaryLayer"] as? String)
        let explicitLayerSource = (raw["layerSource"] as? String).flatMap(SpiderGraphLayerSource.init(rawValue:))
        let suggestedLayer = parsedTags.primaryLayer ?? explicitPrimaryLayer
        let suggestedLayerSource = parsedTags.layerSource ?? (explicitPrimaryLayer == nil ? nil : (explicitLayerSource ?? .normalizedNode))

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
            primaryLayer: explicitPrimaryLayer ?? parsedTags.primaryLayer,
            layerSource: explicitPrimaryLayer != nil ? (explicitLayerSource ?? .normalizedNode) : parsedTags.layerSource,
            metadataTags: parsedTags.metadataTags,
            suggestedLayer: suggestedLayer,
            suggestedLayerSource: suggestedLayerSource
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

    private static func resolveLayerMetadata(
        from rawTags: [String],
        nodeName: String,
        projectPath: String?,
        product: String?,
        kind: String,
        isExternal: Bool
    ) -> ParsedLayerMetadata {
        let parsedTags = parseLayerMetadata(from: rawTags, nodeName: nodeName)
        guard parsedTags.primaryLayer == nil else {
            return parsedTags
        }

        guard !isExternal, kind.lowercased() == "target" else {
            return parsedTags
        }

        if let inferredByPath = inferLayerFromPath(projectPath) {
            return ParsedLayerMetadata(
                primaryLayer: inferredByPath,
                layerSource: .inferredPath,
                metadataTags: parsedTags.metadataTags,
                warnings: parsedTags.warnings
            )
        }

        if let inferredByName = inferLayerFromName(nodeName) {
            return ParsedLayerMetadata(
                primaryLayer: inferredByName,
                layerSource: .inferredName,
                metadataTags: parsedTags.metadataTags,
                warnings: parsedTags.warnings
            )
        }

        if let inferredByProduct = inferLayerFromProduct(product, kind: kind) {
            return ParsedLayerMetadata(
                primaryLayer: inferredByProduct,
                layerSource: .inferredProduct,
                metadataTags: parsedTags.metadataTags,
                warnings: parsedTags.warnings
            )
        }

        return parsedTags
    }

    private static func parseLayerMetadata(from rawTags: [String], nodeName: String) -> ParsedLayerMetadata {
        var layers: [String] = []
        var metadataTags: [String] = []

        for tag in rawTags {
            if let layer = layerName(from: tag) {
                layers.append(layer)
            } else {
                metadataTags.append(tag)
            }
        }

        let primaryLayer = layers.first
        let warnings: [String]
        if layers.count > 1, let primaryLayer {
            warnings = [
                "\(nodeName)은(는) 여러 layer 태그(\(layers.joined(separator: ", ")))를 가집니다. 첫 번째 값인 \(primaryLayer)만 사용합니다."
            ]
        } else {
            warnings = []
        }

        return ParsedLayerMetadata(
            primaryLayer: primaryLayer,
            layerSource: primaryLayer == nil ? nil : .metadataTag,
            metadataTags: metadataTags,
            warnings: warnings
        )
    }

    private static func layerName(from rawTag: String) -> String? {
        let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "layer:"
        guard tag.lowercased().hasPrefix(prefix) else { return nil }

        let rawLayer = String(tag.dropFirst(prefix.count))
        return normalizedLayerName(rawLayer)
    }

    private static func normalizedLayerName(_ rawLayer: String?) -> String? {
        guard let rawLayer else {
            return nil
        }

        let trimmed = rawLayer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func inferLayerFromPath(_ projectPath: String?) -> String? {
        guard let projectPath else { return nil }
        let normalizedPath = projectPath.lowercased()

        for rule in layerInferenceRules {
            if rule.pathMarkers.contains(where: { normalizedPath.contains($0) }) {
                return rule.layer
            }
        }

        return nil
    }

    private static func inferLayerFromName(_ name: String) -> String? {
        let normalizedName = name.lowercased()

        for rule in layerInferenceRules {
            if rule.nameMarkers.contains(where: { normalizedName.contains($0) }) {
                return rule.layer
            }
        }

        return nil
    }

    private static func inferLayerFromProduct(_ product: String?, kind: String) -> String? {
        let normalizedKind = kind.lowercased()
        if normalizedKind.contains("test") {
            return "testing"
        }

        guard let normalizedProduct = product?.lowercased() else { return nil }
        if normalizedProduct.contains("test") {
            return "testing"
        }
        if normalizedProduct == "app" || normalizedProduct.contains("application") {
            return "app"
        }

        return nil
    }

    private static let layerInferenceRules: [LayerInferenceRule] = [
        LayerInferenceRule(
            layer: "testing",
            pathMarkers: ["tests", "test", "testing", "uitests", "snapshot"],
            nameMarkers: ["tests", "test", "uitest", "snapshot"]
        ),
        LayerInferenceRule(
            layer: "design-system",
            pathMarkers: ["designsystem", "design-system", "design_system"],
            nameMarkers: ["designsystem", "designsystemui", "tokens", "componentcatalog"]
        ),
        LayerInferenceRule(
            layer: "feature",
            pathMarkers: ["features", "feature", "scenes", "scene"],
            nameMarkers: ["feature", "scene"]
        ),
        LayerInferenceRule(
            layer: "domain",
            pathMarkers: ["domains", "domain"],
            nameMarkers: ["domain", "usecase", "usecases"]
        ),
        LayerInferenceRule(
            layer: "data",
            pathMarkers: ["datasources", "datasource", "repositories", "repository", "database", "databases", "storage", "cache", "persistence"],
            nameMarkers: ["datasource", "repository", "database", "storage", "cache", "persistence"]
        ),
        LayerInferenceRule(
            layer: "client",
            pathMarkers: ["clients", "client"],
            nameMarkers: ["client"]
        ),
        LayerInferenceRule(
            layer: "service",
            pathMarkers: ["services", "service"],
            nameMarkers: ["service"]
        ),
        LayerInferenceRule(
            layer: "infrastructure",
            pathMarkers: ["infrastructure", "infra", "networking", "network", "remote", "api"],
            nameMarkers: ["infrastructure", "infra", "network", "remoteapi", "api"]
        ),
        LayerInferenceRule(
            layer: "shared",
            pathMarkers: ["shared", "common"],
            nameMarkers: ["shared", "common"]
        ),
        LayerInferenceRule(
            layer: "core",
            pathMarkers: ["core", "foundation", "base", "kit", "utils", "util"],
            nameMarkers: ["core", "foundation", "base", "kit", "utils", "util"]
        ),
        LayerInferenceRule(
            layer: "app",
            pathMarkers: ["apps", "/app", "application"],
            nameMarkers: ["app"]
        ),
    ]
}

private struct ParsedLayerMetadata {
    let primaryLayer: String?
    let layerSource: SpiderGraphLayerSource?
    let metadataTags: [String]
    let warnings: [String]
}

private struct LayerInferenceRule {
    let layer: String
    let pathMarkers: [String]
    let nameMarkers: [String]
}
