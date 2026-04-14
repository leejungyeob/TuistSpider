import XCTest
@testable import TuistSpider

final class SpiderGraphLayerFilterTests: XCTestCase {
    func testLayerFilterKeepsOnlyMatchingInternalNodes() {
        let graph = makeGraph()

        let subgraph = graph.subgraph(
            centeredOn: "feature",
            direction: .both,
            depth: .all,
            includeExternal: true,
            layerFilter: .layer("feature")
        )

        XCTAssertEqual(Set(subgraph.nodes.map(\.id)), ["feature"])
    }

    func testUnclassifiedFilterDoesNotIncludeExternalNodes() {
        let graph = makeGraph()

        let subgraph = graph.subgraph(
            centeredOn: "unclassified",
            direction: .both,
            depth: .all,
            includeExternal: true,
            layerFilter: .unclassified
        )

        XCTAssertEqual(Set(subgraph.nodes.map(\.id)), ["unclassified"])
    }

    func testDirectDependenciesRespectLayerFilter() {
        let graph = makeGraph()

        let dependencies = graph.directDependencies(
            of: "feature",
            includeExternal: true,
            layerFilter: .layer("core")
        )

        XCTAssertEqual(dependencies.map(\.id), ["core"])
    }

    private func makeGraph() -> SpiderGraph {
        SpiderGraph(
            graphName: "Fixture",
            sourceFormat: "normalized",
            rootPath: "/repo",
            generatedAt: nil,
            nodes: [
                SpiderGraphNode(
                    id: "feature",
                    name: "Feature",
                    displayName: "Feature",
                    kind: "target",
                    product: "framework",
                    bundleId: nil,
                    projectName: "App",
                    projectPath: "/repo/App",
                    isExternal: false,
                    sourceCount: 1,
                    resourceCount: 0,
                    primaryLayer: "feature",
                    layerSource: .metadataTag,
                    metadataTags: []
                ),
                SpiderGraphNode(
                    id: "core",
                    name: "Core",
                    displayName: "Core",
                    kind: "target",
                    product: "framework",
                    bundleId: nil,
                    projectName: "App",
                    projectPath: "/repo/App",
                    isExternal: false,
                    sourceCount: 1,
                    resourceCount: 0,
                    primaryLayer: "core",
                    layerSource: .metadataTag,
                    metadataTags: []
                ),
                SpiderGraphNode(
                    id: "unclassified",
                    name: "Legacy",
                    displayName: "Legacy",
                    kind: "target",
                    product: "framework",
                    bundleId: nil,
                    projectName: "App",
                    projectPath: "/repo/App",
                    isExternal: false,
                    sourceCount: 1,
                    resourceCount: 0,
                    primaryLayer: nil,
                    layerSource: nil,
                    metadataTags: []
                ),
                SpiderGraphNode(
                    id: "package",
                    name: "NetworkingKit",
                    displayName: "NetworkingKit",
                    kind: "package",
                    product: nil,
                    bundleId: nil,
                    projectName: "External",
                    projectPath: nil,
                    isExternal: true,
                    sourceCount: 0,
                    resourceCount: 0,
                    primaryLayer: nil,
                    layerSource: nil,
                    metadataTags: []
                ),
            ],
            edges: [
                SpiderGraphEdge(from: "feature", to: "core", kind: "target", status: nil),
                SpiderGraphEdge(from: "feature", to: "package", kind: "package", status: nil),
                SpiderGraphEdge(from: "unclassified", to: "feature", kind: "target", status: nil),
                SpiderGraphEdge(from: "unclassified", to: "package", kind: "package", status: nil),
            ]
        )
    }
}
