import XCTest
@testable import TuistSpider

final class SpiderGraphCanvasLayoutTests: XCTestCase {
    func testCanvasLayoutAlignsSameLayerAcrossLevels() throws {
        let nodes = [
            makeNode(id: "feature-a", name: "FeatureA", layer: "feature"),
            makeNode(id: "core-a", name: "CoreA", layer: "core"),
            makeNode(id: "feature-b", name: "FeatureB", layer: "feature"),
        ]
        let levels = [
            "feature-a": 0,
            "core-a": 0,
            "feature-b": 1,
        ]

        let layout = SpiderGraphCanvasLayout.make(for: nodes, levels: levels)

        let coreRegion = try XCTUnwrap(layout.layerRegions.first(where: { $0.kind == .layer("core") }))
        let featureRegion = try XCTUnwrap(layout.layerRegions.first(where: { $0.kind == .layer("feature") }))
        let featureAFrame = try XCTUnwrap(layout.nodeFrames["feature-a"])
        let featureBFrame = try XCTUnwrap(layout.nodeFrames["feature-b"])
        let coreFrame = try XCTUnwrap(layout.nodeFrames["core-a"])

        XCTAssertLessThan(coreRegion.frame.midY, featureRegion.frame.midY)
        XCTAssertGreaterThan(featureAFrame.midY, coreFrame.midY)
        XCTAssertEqual(featureAFrame.midY, featureBFrame.midY, accuracy: 0.1)
        XCTAssertTrue(featureRegion.frame.contains(featureAFrame))
        XCTAssertTrue(featureRegion.frame.contains(featureBFrame))
    }

    func testCanvasLayoutAddsNewModulesUnclassifiedAndExternalBands() {
        let nodes = [
            makeNode(id: "feature", name: "Feature", layer: "feature"),
            makeNode(id: "new-module", name: "PaymentsFeature", layer: nil, isNewlyDiscovered: true),
            makeNode(id: "legacy", name: "Legacy", layer: nil),
            makeNode(id: "package", name: "Alamofire", layer: nil, isExternal: true, kind: "package"),
        ]
        let levels = [
            "feature": 0,
            "new-module": 0,
            "legacy": 0,
            "package": 1,
        ]

        let layout = SpiderGraphCanvasLayout.make(for: nodes, levels: levels)

        XCTAssertEqual(
            layout.layerRegions.map(\.kind),
            [.layer("feature"), .newModules, .unclassified, .external]
        )
    }

    func testExpandedEdgeLaneOccupancyPenalizesOverlappingVerticalSegments() {
        var occupancy = ExpandedEdgeLaneOccupancy()
        occupancy.record(
            points: [
                CGPoint(x: 100, y: 40),
                CGPoint(x: 100, y: 220)
            ]
        )

        let overlappingPenalty = occupancy.overlapPenalty(
            for: [
                CGPoint(x: 100, y: 80),
                CGPoint(x: 100, y: 260)
            ]
        )
        let separatedPenalty = occupancy.overlapPenalty(
            for: [
                CGPoint(x: 116, y: 80),
                CGPoint(x: 116, y: 260)
            ]
        )

        XCTAssertGreaterThan(overlappingPenalty, 0)
        XCTAssertEqual(separatedPenalty, 0, accuracy: 0.1)
    }

    private func makeNode(
        id: String,
        name: String,
        layer: String?,
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
            projectPath: isExternal ? nil : "/repo/App",
            isExternal: isExternal,
            sourceCount: isExternal ? 0 : 1,
            resourceCount: 0,
            primaryLayer: layer,
            layerSource: layer == nil ? nil : .metadataTag,
            metadataTags: [],
            isNewlyDiscovered: isNewlyDiscovered
        )
    }
}
