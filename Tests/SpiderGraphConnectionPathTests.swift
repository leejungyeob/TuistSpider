import XCTest
@testable import TuistSpider

final class SpiderGraphConnectionPathTests: XCTestCase {
    func testDirectedPathDistinguishesDirectAndIndirectDependencies() {
        let directPath = SpiderGraphConnectionPath(
            primaryNodeIDs: ["feature", "core"],
            secondaryNodeIDs: nil,
            edgeIDs: ["feature->core"],
            paletteIndex: 0,
            kind: .directedForward
        )
        let indirectPath = SpiderGraphConnectionPath(
            primaryNodeIDs: ["feature", "shared", "core"],
            secondaryNodeIDs: nil,
            edgeIDs: ["feature->shared", "shared->core"],
            paletteIndex: 1,
            kind: .directedForward
        )

        XCTAssertEqual(directPath.dependencyScopeLabel, "직접 의존")
        XCTAssertTrue(directPath.isDirectConnection)
        XCTAssertEqual(indirectPath.dependencyScopeLabel, "간접 의존")
        XCTAssertFalse(indirectPath.isDirectConnection)
    }

    func testReverseAndBridgePathsExposeExpectedScopeLabels() {
        let directReversePath = SpiderGraphConnectionPath(
            primaryNodeIDs: ["feature", "app"],
            secondaryNodeIDs: nil,
            edgeIDs: ["feature->app"],
            paletteIndex: 0,
            kind: .directedReverse
        )
        let bridgePath = SpiderGraphConnectionPath(
            primaryNodeIDs: ["feature", "shared"],
            secondaryNodeIDs: ["app", "shared"],
            edgeIDs: ["feature->shared", "app->shared"],
            paletteIndex: 1,
            kind: .commonDependency
        )

        XCTAssertEqual(directReversePath.dependencyScopeLabel, "나에게 직접 의존")
        XCTAssertTrue(directReversePath.isDirectConnection)
        XCTAssertEqual(bridgePath.dependencyScopeLabel, "같이 의존하는 모듈 경유")
        XCTAssertFalse(bridgePath.isDirectConnection)
    }

    func testConnectionPathFilterSeparatesDirectAndIndirectPaths() {
        let directPath = SpiderGraphConnectionPath(
            primaryNodeIDs: ["feature", "core"],
            secondaryNodeIDs: nil,
            edgeIDs: ["feature->core"],
            paletteIndex: 0,
            kind: .directedForward
        )
        let indirectPath = SpiderGraphConnectionPath(
            primaryNodeIDs: ["feature", "shared", "core"],
            secondaryNodeIDs: nil,
            edgeIDs: ["feature->shared", "shared->core"],
            paletteIndex: 1,
            kind: .directedForward
        )

        XCTAssertTrue(SpiderGraphConnectionPathFilter.all.includes(directPath))
        XCTAssertTrue(SpiderGraphConnectionPathFilter.all.includes(indirectPath))
        XCTAssertTrue(SpiderGraphConnectionPathFilter.directOnly.includes(directPath))
        XCTAssertFalse(SpiderGraphConnectionPathFilter.directOnly.includes(indirectPath))
        XCTAssertFalse(SpiderGraphConnectionPathFilter.indirectOnly.includes(directPath))
        XCTAssertTrue(SpiderGraphConnectionPathFilter.indirectOnly.includes(indirectPath))
    }
}
