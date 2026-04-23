import Foundation
import XCTest
@testable import TuistSpider

final class ProjectLayerSnapshotStoreTests: XCTestCase {
    func testReconcileWithoutSnapshotKeepsSuggestedClassificationAndSeedsSnapshotOnSync() throws {
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

        let reconciliation = ProjectLayerSnapshotStore.reconcile(graph, with: nil, rootURL: rootURL)
        XCTAssertFalse(reconciliation.hasExistingSnapshot)
        XCTAssertTrue(reconciliation.newlyDiscoveredNodes.isEmpty)

        let authNode = try XCTUnwrap(reconciliation.graph.nodeMap["auth"])
        XCTAssertEqual(authNode.primaryLayer, "feature")
        XCTAssertFalse(authNode.hasPersistedClassification)
        XCTAssertFalse(authNode.isNewlyDiscovered)

        let didWrite = try ProjectLayerSnapshotStore.syncSnapshot(for: reconciliation.graph, rootURL: rootURL)
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

    func testReconcileWithSnapshotMarksNewTargetsPendingAndSkipsPersistingThem() throws {
        let rootURL = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let featureProjectURL = rootURL.appendingPathComponent("Projects/Features/Auth", isDirectory: true)
        let legacyProjectURL = rootURL.appendingPathComponent("Projects/Legacy", isDirectory: true)
        let paymentsProjectURL = rootURL.appendingPathComponent("Projects/Payments", isDirectory: true)
        try FileManager.default.createDirectory(at: featureProjectURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: legacyProjectURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paymentsProjectURL, withIntermediateDirectories: true)

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
                makeNode(
                    id: "payments",
                    name: "PaymentsFeature",
                    projectPath: paymentsProjectURL.path,
                    layer: "feature",
                    layerSource: .inferredPath,
                    suggestedLayer: "feature",
                    suggestedLayerSource: .inferredPath
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

        let reconciliation = ProjectLayerSnapshotStore.reconcile(graph, with: snapshot, rootURL: rootURL)
        let applied = reconciliation.graph
        let authNode = try XCTUnwrap(applied.nodeMap["auth"])
        let legacyNode = try XCTUnwrap(applied.nodeMap["legacy"])
        let paymentsNode = try XCTUnwrap(applied.nodeMap["payments"])

        XCTAssertEqual(authNode.primaryLayer, "domain")
        XCTAssertEqual(authNode.layerSource, .projectSnapshot)
        XCTAssertEqual(authNode.suggestedLayer, "feature")
        XCTAssertEqual(authNode.suggestedLayerSource, .inferredPath)
        XCTAssertTrue(authNode.hasPersistedClassification)
        XCTAssertTrue(authNode.hasSavedLayerOverride)
        XCTAssertFalse(authNode.isNewlyDiscovered)

        XCTAssertNil(legacyNode.primaryLayer)
        XCTAssertEqual(legacyNode.layerSource, .projectSnapshot)
        XCTAssertEqual(legacyNode.suggestedLayer, "core")
        XCTAssertTrue(legacyNode.hasPersistedClassification)
        XCTAssertTrue(legacyNode.hasSavedLayerOverride)
        XCTAssertFalse(legacyNode.isNewlyDiscovered)

        XCTAssertNil(paymentsNode.primaryLayer)
        XCTAssertNil(paymentsNode.layerSource)
        XCTAssertEqual(paymentsNode.suggestedLayer, "feature")
        XCTAssertFalse(paymentsNode.hasPersistedClassification)
        XCTAssertFalse(paymentsNode.hasSavedLayerOverride)
        XCTAssertTrue(paymentsNode.isNewlyDiscovered)
        XCTAssertEqual(reconciliation.newlyDiscoveredNodes.map(\.id), ["payments"])

        XCTAssertTrue(try ProjectLayerSnapshotStore.syncSnapshot(for: applied, rootURL: rootURL))

        let persistedSnapshot = try XCTUnwrap(ProjectLayerSnapshotStore.load(rootURL: rootURL))
        XCTAssertEqual(
            persistedSnapshot.targets,
            [
                .init(projectPath: "Projects/Features/Auth", targetName: "AuthFeature", layer: "domain"),
                .init(projectPath: "Projects/Legacy", targetName: "LegacyModule", layer: nil),
            ]
        )
    }

    func testSyncSnapshotReturnsFalseWhenUnchangedAndPrunesDeletedTargetsWhileKeepingPendingTargetsOut() throws {
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
                makeNode(
                    id: "feature-d",
                    name: "FeatureD",
                    projectPath: secondProjectURL.path,
                    layer: nil,
                    layerSource: nil,
                    suggestedLayer: "feature",
                    suggestedLayerSource: .inferredName,
                    isNewlyDiscovered: true
                ),
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

    func testSavingPendingTargetAddsItToSnapshotAndClearsPendingState() throws {
        let rootURL = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let projectURL = rootURL.appendingPathComponent("Projects/Features/Auth", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let initialGraph = SpiderGraph(
            graphName: "Fixture",
            sourceFormat: "normalized",
            rootPath: rootURL.path,
            generatedAt: nil,
            nodes: [
                makeNode(
                    id: "auth",
                    name: "AuthFeature",
                    projectPath: projectURL.path,
                    layer: nil,
                    layerSource: nil,
                    suggestedLayer: "feature",
                    suggestedLayerSource: .inferredPath,
                    isNewlyDiscovered: true
                ),
            ],
            edges: []
        )

        XCTAssertTrue(try ProjectLayerSnapshotStore.syncSnapshot(for: initialGraph, rootURL: rootURL))
        let emptySnapshot = try XCTUnwrap(ProjectLayerSnapshotStore.load(rootURL: rootURL))
        XCTAssertTrue(emptySnapshot.targets.isEmpty)

        let pendingNode = try XCTUnwrap(initialGraph.nodeMap["auth"])
        let acceptedNode = pendingNode.updatingClassification(
            primaryLayer: pendingNode.suggestedLayer,
            layerSource: .projectSnapshot,
            hasPersistedClassification: true
        )
        let acceptedGraph = initialGraph.replacingNodes([acceptedNode])

        XCTAssertFalse(acceptedNode.isNewlyDiscovered)
        XCTAssertTrue(try ProjectLayerSnapshotStore.syncSnapshot(for: acceptedGraph, rootURL: rootURL))

        let snapshot = try XCTUnwrap(ProjectLayerSnapshotStore.load(rootURL: rootURL))
        XCTAssertEqual(
            snapshot.targets,
            [
                .init(projectPath: "Projects/Features/Auth", targetName: "AuthFeature", layer: "feature"),
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
        isNewlyDiscovered: Bool = false,
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
            hasPersistedClassification: false,
            isNewlyDiscovered: isNewlyDiscovered
        )
    }
}
