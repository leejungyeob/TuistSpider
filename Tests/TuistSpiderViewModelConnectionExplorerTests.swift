import XCTest
@testable import TuistSpider

final class TuistSpiderViewModelConnectionExplorerTests: XCTestCase {
    @MainActor
    func testSelectedNodePopulatesRelatedConnectionItemsWithoutPinnedTarget() {
        let viewModel = TuistSpiderViewModel()
        viewModel.loadSample()
        viewModel.resetView()

        XCTAssertNil(viewModel.graphSelectedNode)

        let relatedModuleNames = Set(
            viewModel.relatedConnectionItems.map(\.node.name)
        )

        XCTAssertTrue(relatedModuleNames.contains("FeatureA"))
        XCTAssertTrue(relatedModuleNames.contains("FeatureB"))
        XCTAssertTrue(relatedModuleNames.contains("Core"))
        XCTAssertTrue(viewModel.availableConnectionPaths.isEmpty)
        XCTAssertFalse(viewModel.hasConnectionPathContext)
    }

    @MainActor
    func testIndirectFilterKeepsOnlyIndirectConnectionItemsUntilTargetSelected() {
        let viewModel = TuistSpiderViewModel()
        viewModel.loadSample()
        viewModel.resetView()

        viewModel.selectedConnectionPathFilter = .indirectOnly

        let relatedModuleNames = Set(
            viewModel.relatedConnectionItems.map(\.node.name)
        )

        XCTAssertEqual(relatedModuleNames, Set(["Core"]))
        XCTAssertTrue(viewModel.availableConnectionPaths.isEmpty)

        viewModel.selectRelatedNode("target::examples/TuistFixture::Core")

        XCTAssertTrue(viewModel.availableConnectionPaths.allSatisfy { !$0.isDirectConnection })
        XCTAssertTrue(viewModel.hasConnectionPathContext)
    }

    @MainActor
    func testSelectingRelatedNodeDoesNotMoveItToTopOfOverviewList() {
        let viewModel = TuistSpiderViewModel()
        viewModel.loadSample()
        viewModel.resetView()

        viewModel.selectRelatedNode("target::examples/TuistFixture::FeatureB")

        XCTAssertEqual(viewModel.relatedConnectionItems.map(\.node.name), ["FeatureA", "FeatureB", "Core"])
    }

    @MainActor
    func testRelatedConnectionSearchFiltersOverviewItems() {
        let viewModel = TuistSpiderViewModel()
        viewModel.loadSample()
        viewModel.resetView()

        viewModel.relatedNodeSearchText = "featureb"

        XCTAssertEqual(viewModel.filteredRelatedConnectionItems.map(\.node.name), ["FeatureB"])
    }

    @MainActor
    func testIndirectTargetCanExposeMultipleDistinctPathCells() throws {
        let viewModel = TuistSpiderViewModel()
        viewModel.loadSample()
        viewModel.resetView()

        let coreItem = try XCTUnwrap(
            viewModel.relatedConnectionItems.first(where: { $0.node.name == "Core" })
        )

        let cells = viewModel.connectionPathCellItems(for: coreItem)

        XCTAssertEqual(cells.count, 2)
        XCTAssertEqual(
            Set(cells.map(\.previewText)),
            Set([
                "FixtureApp -> FeatureA -> Core",
                "FixtureApp -> FeatureB -> Core"
            ])
        )
    }

    @MainActor
    func testDirectOnlyFilterShowsMismatchNoticeWhenOnlyIndirectPathExists() {
        let viewModel = TuistSpiderViewModel()
        viewModel.loadSample()
        viewModel.resetView()

        viewModel.selectRelatedNode("target::examples/TuistFixture::Core")
        viewModel.selectedConnectionPathFilter = .directOnly

        XCTAssertEqual(viewModel.connectionPathFilterMismatchNotice?.suggestedFilter, .indirectOnly)
    }

    @MainActor
    func testIndirectOnlyFilterShowsMismatchNoticeWhenOnlyDirectPathExists() {
        let viewModel = TuistSpiderViewModel()
        viewModel.loadSample()
        viewModel.resetView()

        viewModel.selectRelatedNode("target::examples/TuistFixture::FeatureA")
        viewModel.selectedConnectionPathFilter = .indirectOnly

        XCTAssertEqual(viewModel.connectionPathFilterMismatchNotice?.suggestedFilter, .directOnly)
    }
}
