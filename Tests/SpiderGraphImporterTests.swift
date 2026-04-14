import XCTest
@testable import TuistSpider

final class SpiderGraphImporterTests: XCTestCase {
    func testMetadataLayerTagBecomesPrimaryLayerAndLeavesOtherTags() throws {
        let graph = try SpiderGraphImporter.load(from: makeTuistGraphData(
            tags: ["layer:feature", "ios"],
            targetName: "FeatureA",
            projectPath: "/repo/App",
            product: "framework"
        ))

        let node = try XCTUnwrap(graph.nodes.first(where: { $0.name == "FeatureA" }))
        XCTAssertEqual(node.primaryLayer, "feature")
        XCTAssertEqual(node.layerSource, .metadataTag)
        XCTAssertEqual(node.metadataTags, ["ios"])
        XCTAssertTrue(graph.warnings.isEmpty)
    }

    func testMissingLayerTagFallsBackToPathInference() throws {
        let graph = try SpiderGraphImporter.load(from: makeTuistGraphData(
            tags: ["ui", "shared"],
            targetName: "Legacy",
            projectPath: "/repo/Projects/Features/Auth",
            product: "framework"
        ))

        let node = try XCTUnwrap(graph.nodes.first(where: { $0.name == "Legacy" }))
        XCTAssertEqual(node.primaryLayer, "feature")
        XCTAssertEqual(node.layerSource, .inferredPath)
        XCTAssertEqual(node.metadataTags, ["ui", "shared"])
        XCTAssertTrue(graph.warnings.isEmpty)
    }

    func testMultipleLayerTagsKeepFirstAndEmitWarning() throws {
        let graph = try SpiderGraphImporter.load(from: makeTuistGraphData(
            tags: ["layer:feature", "layer:domain", "ios"],
            targetName: "FeatureA",
            projectPath: "/repo/App",
            product: "framework"
        ))

        let node = try XCTUnwrap(graph.nodes.first(where: { $0.name == "FeatureA" }))
        XCTAssertEqual(node.primaryLayer, "feature")
        XCTAssertEqual(node.metadataTags, ["ios"])
        XCTAssertEqual(graph.warnings.count, 1)
        XCTAssertTrue(graph.warnings[0].contains("FeatureA"))
    }

    func testNameInferenceFallsBackWhenPathHasNoSignal() throws {
        let graph = try SpiderGraphImporter.load(from: makeTuistGraphData(
            tags: [],
            targetName: "BillingDomain",
            projectPath: "/repo/Modules/Billing",
            product: "framework"
        ))

        let node = try XCTUnwrap(graph.nodes.first(where: { $0.name == "BillingDomain" }))
        XCTAssertEqual(node.primaryLayer, "domain")
        XCTAssertEqual(node.layerSource, .inferredName)
    }

    func testProductInferenceFallsBackForAppTargets() throws {
        let graph = try SpiderGraphImporter.load(from: makeTuistGraphData(
            tags: [],
            targetName: "RootModule",
            projectPath: "/repo/Modules/Root",
            product: "app"
        ))

        let node = try XCTUnwrap(graph.nodes.first(where: { $0.name == "RootModule" }))
        XCTAssertEqual(node.primaryLayer, "app")
        XCTAssertEqual(node.layerSource, .inferredProduct)
    }

    func testMissingAllSignalsLeavesNodeUnclassified() throws {
        let graph = try SpiderGraphImporter.load(from: makeTuistGraphData(
            tags: ["ui", "shared"],
            targetName: "LegacyModule",
            projectPath: "/repo/Modules/Legacy",
            product: "framework"
        ))

        let node = try XCTUnwrap(graph.nodes.first(where: { $0.name == "LegacyModule" }))
        XCTAssertNil(node.primaryLayer)
        XCTAssertNil(node.layerSource)
        XCTAssertEqual(node.metadataTags, ["ui", "shared"])
    }

    private func makeTuistGraphData(
        tags: [String],
        targetName: String,
        projectPath: String,
        product: String
    ) throws -> Data {
        let payload: [String: Any] = [
            "name": "Fixture",
            "path": "/repo",
            "projects": [
                projectPath: [
                    "name": "App",
                    "targets": [
                        [
                            "name": targetName,
                            "product": product,
                            "bundleId": "com.example.featureA",
                            "metadata": [
                                "tags": tags,
                            ],
                            "dependencies": [],
                        ],
                    ],
                ],
            ],
        ]

        return try JSONSerialization.data(withJSONObject: payload)
    }
}
