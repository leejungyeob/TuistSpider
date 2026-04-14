import Foundation
import XCTest
@testable import TuistSpider

final class ProjectLayerSnapshotStoreTests: XCTestCase {
    func testSyncSnapshotCreatesFileWithRelativeProjectPaths() throws {
        let rootURL = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let nestedProjectURL = rootURL.appendingPathComponent("Projects/Features/Auth", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedProjectURL, withIntermediateDirectories: true)

        let graph = SpiderGraph(
            graphName: "Fixture",
            sourceFormat: "normalized",
            rootPath: rootURL.path,
            generatedAt: nil,
            nodes: [
                makeNode(id: "app", name: "App", projectPath: rootURL.path, layer: nil),
                makeNode(id: "auth", name: "AuthFeature", projectPath: nestedProjectURL.path, layer: "feature"),
                makeNode(id: "package", name: "Alamofire", projectPath: nil, layer: nil, isExternal: true, kind: "package"),
            ],
            edges: []
        )

        let didWrite = try ProjectLayerSnapshotStore.syncSnapshot(for: graph, rootURL: rootURL)
        XCTAssertTrue(didWrite)

        let snapshot = try XCTUnwrap(ProjectLayerSnapshotStore.load(rootURL: rootURL))
        XCTAssertEqual(
            snapshot.targets,
            [
                .init(projectPath: ".", targetName: "App", layer: nil),
                .init(projectPath: "Projects/Features/Auth", targetName: "AuthFeature", layer: "feature"),
            ]
        )
    }

    func testApplySnapshotOverridesSuggestedLayerAndSupportsExplicitUnclassified() throws {
        let rootURL = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let featureProjectURL = rootURL.appendingPathComponent("Projects/Features/Auth", isDirectory: true)
        let legacyProjectURL = rootURL.appendingPathComponent("Projects/Legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: featureProjectURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: legacyProjectURL, withIntermediateDirectories: true)

        let graph = SpiderGraph(
            graphName: "Fixture",
            sourceFormat: "normalized",
            rootPath: rootURL.path,
            generatedAt: nil,
            nodes: [
                makeNode(
                    id: "auth",
                    name: "AuthFeature",
                    projectPath: featureProjectURL.path,
                    layer: "feature",
                    layerSource: .inferredPath,
                    suggestedLayer: "feature",
                    suggestedLayerSource: .inferredPath
                ),
                makeNode(
                    id: "legacy",
                    name: "LegacyModule",
                    projectPath: legacyProjectURL.path,
                    layer: "core",
                    layerSource: .inferredName,
                    suggestedLayer: "core",
                    suggestedLayerSource: .inferredName
                ),
            ],
            edges: []
        )

        let snapshot = ProjectLayerSnapshotStore.ProjectLayerSnapshot(
            version: 1,
            targets: [
                .init(projectPath: "Projects/Features/Auth", targetName: "AuthFeature", layer: "domain"),
                .init(projectPath: "Projects/Legacy", targetName: "LegacyModule", layer: nil),
            ]
        )

        let applied = ProjectLayerSnapshotStore.apply(snapshot, to: graph, rootURL: rootURL)
        let authNode = try XCTUnwrap(applied.nodeMap["auth"])
        let legacyNode = try XCTUnwrap(applied.nodeMap["legacy"])

        XCTAssertEqual(authNode.primaryLayer, "domain")
        XCTAssertEqual(authNode.layerSource, .projectSnapshot)
        XCTAssertEqual(authNode.suggestedLayer, "feature")
        XCTAssertEqual(authNode.suggestedLayerSource, .inferredPath)
        XCTAssertTrue(authNode.hasPersistedClassification)
        XCTAssertTrue(authNode.hasSavedLayerOverride)

        XCTAssertNil(legacyNode.primaryLayer)
        XCTAssertEqual(legacyNode.layerSource, .projectSnapshot)
        XCTAssertEqual(legacyNode.suggestedLayer, "core")
        XCTAssertTrue(legacyNode.hasPersistedClassification)
        XCTAssertTrue(legacyNode.hasSavedLayerOverride)
    }

    func testSyncSnapshotReturnsFalseWhenUnchangedAndPrunesDeletedTargets() throws {
        let rootURL = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let firstProjectURL = rootURL.appendingPathComponent("Projects/FeatureA", isDirectory: true)
        let secondProjectURL = rootURL.appendingPathComponent("Projects/FeatureB", isDirectory: true)
        try FileManager.default.createDirectory(at: firstProjectURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondProjectURL, withIntermediateDirectories: true)

        let firstGraph = SpiderGraph(
            graphName: "Fixture",
            sourceFormat: "normalized",
            rootPath: rootURL.path,
            generatedAt: nil,
            nodes: [
                makeNode(id: "feature-a", name: "FeatureA", projectPath: firstProjectURL.path, layer: "feature"),
                makeNode(id: "feature-b", name: "FeatureB", projectPath: secondProjectURL.path, layer: "feature"),
            ],
            edges: []
        )

        XCTAssertTrue(try ProjectLayerSnapshotStore.syncSnapshot(for: firstGraph, rootURL: rootURL))
        XCTAssertFalse(try ProjectLayerSnapshotStore.syncSnapshot(for: firstGraph, rootURL: rootURL))

        let nextGraph = SpiderGraph(
            graphName: "Fixture",
            sourceFormat: "normalized",
            rootPath: rootURL.path,
            generatedAt: nil,
            nodes: [
                makeNode(id: "feature-a", name: "FeatureA", projectPath: firstProjectURL.path, layer: "domain"),
                makeNode(id: "feature-c", name: "FeatureC", projectPath: secondProjectURL.path, layer: "feature"),
            ],
            edges: []
        )

        XCTAssertTrue(try ProjectLayerSnapshotStore.syncSnapshot(for: nextGraph, rootURL: rootURL))

        let snapshot = try XCTUnwrap(ProjectLayerSnapshotStore.load(rootURL: rootURL))
        XCTAssertEqual(
            snapshot.targets,
            [
                .init(projectPath: "Projects/FeatureA", targetName: "FeatureA", layer: "domain"),
                .init(projectPath: "Projects/FeatureB", targetName: "FeatureC", layer: "feature"),
            ]
        )
    }

    private func makeTemporaryRoot() throws -> URL {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }

    private func makeNode(
        id: String,
        name: String,
        projectPath: String?,
        layer: String?,
        layerSource: SpiderGraphLayerSource? = .metadataTag,
        suggestedLayer: String? = nil,
        suggestedLayerSource: SpiderGraphLayerSource? = nil,
        isExternal: Bool = false,
        kind: String = "target"
    ) -> SpiderGraphNode {
        SpiderGraphNode(
            id: id,
            name: name,
            displayName: name,
            kind: kind,
            product: isExternal ? nil : "framework",
            bundleId: nil,
            projectName: isExternal ? "External" : "App",
            projectPath: projectPath,
            isExternal: isExternal,
            sourceCount: isExternal ? 0 : 1,
            resourceCount: 0,
            primaryLayer: layer,
            layerSource: layerSource,
            metadataTags: [],
            suggestedLayer: suggestedLayer,
            suggestedLayerSource: suggestedLayerSource,
            hasPersistedClassification: false
        )
    }
}
