import AppKit
import Foundation

@MainActor
final class TuistSpiderViewModel: ObservableObject {
    static let defaultZoomScale = 1.0
    static let zoomScaleRange: ClosedRange<Double> = 0.5...2.0
    static let zoomStep = 0.15
    static let defaultConnectionPathLimit = 12
    static let connectionPathLimitStep = 12
    static let connectionPathExtraHops = 3

    @Published private(set) var graph = SampleGraph.make()
    @Published var selectedNodeID: String? {
        didSet { persistPreferences() }
    }
    @Published var graphSelectedNodeID: String?
    @Published private var selectedConnectionPathIDs: Set<String>? = nil
    @Published var showOnlyActivePaths = false {
        didSet {
            refreshDisplayedSubgraph()
            persistPreferences()
        }
    }
    @Published var direction: GraphDirection = .both {
        didSet {
            resetConnectionPathState()
            alignDepthSelectionWithCurrentGraph()
            refreshDerivedState()
            persistPreferences()
        }
    }
    @Published var depth: GraphDepth = .all {
        didSet {
            resetConnectionPathState()
            refreshDerivedState()
            persistPreferences()
        }
    }
    @Published var presentationMode: GraphPresentationMode = .expanded {
        didSet {
            resetConnectionPathState()
            persistPreferences()
        }
    }
    @Published var includeExternal = false {
        didSet {
            resetConnectionPathState()
            alignDepthSelectionWithCurrentGraph()
            refreshDerivedState()
            persistPreferences()
        }
    }
    @Published var searchText = "" {
        didSet { persistPreferences() }
    }
    @Published var relatedNodeSearchText = ""
    @Published var zoomScale = TuistSpiderViewModel.defaultZoomScale {
        didSet {
            let clamped = Self.clampZoomScale(zoomScale)
            if abs(clamped - zoomScale) > .ulpOfOne {
                zoomScale = clamped
                return
            }
            persistPreferences()
        }
    }
    @Published var selectedLevel = 0 {
        didSet { persistPreferences() }
    }
    @Published private(set) var isLoading = false
    @Published private(set) var statusMessage = "샘플 그래프를 불러왔습니다."
    @Published private(set) var sourceLabel = "Sample graph / normalized-sample"
    @Published private(set) var currentProjectURL: URL?
    @Published private(set) var currentJSONURL: URL?
    @Published private(set) var viewportCenterRequestID = 0
    @Published var presentedError: SpiderGraphImportError?
    @Published private(set) var visibleSubgraph = SpiderGraphSubgraph.empty
    @Published private(set) var directDependencies: [SpiderGraphNode] = []
    @Published private(set) var directDependents: [SpiderGraphNode] = []
    @Published private(set) var connectionPaths: [SpiderGraphConnectionPath] = []
    @Published private(set) var connectionPathLimit = TuistSpiderViewModel.defaultConnectionPathLimit
    @Published private(set) var hasTruncatedConnectionPaths = false
    @Published private(set) var connectionDirection: SpiderGraphRelationshipDirection?
    @Published private(set) var displayedSubgraph = SpiderGraphSubgraph.empty

    private let exportService = TuistGraphExportService()
    private let preferences = UserDefaults.standard

    init() {
        restorePreferences()
        selectedNodeID = selectedNodeID ?? graph.preferredRootID
        alignDepthSelectionWithCurrentGraph()
        refreshDerivedState()
        requestViewportCentering()
    }

    var filteredNodes: [SpiderGraphNode] {
        graph.nodes.filter { node in
            if !includeExternal && node.isExternal {
                return false
            }
            if searchText.isEmpty {
                return true
            }
            let query = searchText.lowercased()
            return node.name.lowercased().contains(query) || node.projectLabel.lowercased().contains(query)
        }
    }

    var availableDepthOptions: [GraphDepth] {
        availableDepthOptions(for: selectedNodeID)
    }

    var filteredRelatedNodes: [SpiderGraphNode] {
        guard let selectedNodeID else { return [] }
        let query = relatedNodeSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }

        return visibleSubgraph.nodes
            .filter { node in
                guard node.id != selectedNodeID else { return false }
                return node.name.lowercased().contains(query) || node.projectLabel.lowercased().contains(query)
            }
            .sorted { lhs, rhs in
                if lhs.name != rhs.name { return lhs.name < rhs.name }
                return lhs.id < rhs.id
            }
    }

    var filteredRelatedNodesPreview: [SpiderGraphNode] {
        Array(filteredRelatedNodes.prefix(8))
    }

    var selectedNode: SpiderGraphNode? {
        guard let selectedNodeID else { return nil }
        return graph.nodeMap[selectedNodeID]
    }

    var graphSelectedNode: SpiderGraphNode? {
        guard let visibleGraphSelectedNodeID else { return nil }
        return graph.nodeMap[visibleGraphSelectedNodeID]
    }

    var visibleGraphSelectedNodeID: String? {
        guard let graphSelectedNodeID else { return nil }
        return visibleSubgraph.nodeIDs.contains(graphSelectedNodeID) ? graphSelectedNodeID : nil
    }

    var inspectedNode: SpiderGraphNode? {
        if let visibleGraphSelectedNodeID {
            return graph.nodeMap[visibleGraphSelectedNodeID]
        }
        return selectedNode
    }

    var activeConnectionPathIDs: Set<String> {
        let availablePathIDs = Set(connectionPaths.map(\.id))
        guard !availablePathIDs.isEmpty else { return [] }

        guard let selectedConnectionPathIDs else {
            return availablePathIDs
        }

        if selectedConnectionPathIDs.isEmpty {
            return []
        }

        let intersected = selectedConnectionPathIDs.intersection(availablePathIDs)
        return intersected.isEmpty ? availablePathIDs : intersected
    }

    var activeConnectionPaths: [SpiderGraphConnectionPath] {
        connectionPaths.filter { activeConnectionPathIDs.contains($0.id) }
    }

    var activeConnectionPathNodeIDs: Set<String> {
        Set(activeConnectionPaths.flatMap(\.nodeIDs))
    }

    var activeConnectionPathEdgeIDs: Set<String> {
        Set(activeConnectionPaths.flatMap(\.edgeIDs))
    }

    var activeConnectionPathCount: Int {
        activeConnectionPaths.count
    }

    var isUsingExpandedConnectionPathLimit: Bool {
        connectionPathLimit > Self.defaultConnectionPathLimit
    }

    func isConnectionPathVisible(_ pathID: String) -> Bool {
        activeConnectionPathIDs.contains(pathID)
    }

    var visibleLevelGroups: [SpiderGraphLevelGroup] {
        displayedSubgraph.levelGroups
    }

    var selectedLevelGroup: SpiderGraphLevelGroup? {
        visibleLevelGroups.first(where: { $0.level == selectedLevel })
        ?? visibleLevelGroups.first(where: { $0.level == 0 })
        ?? visibleLevelGroups.first
    }

    var totalNodeCount: Int { graph.nodes.count }
    var totalEdgeCount: Int { graph.edges.count }
    var visibleNodeCount: Int { displayedSubgraph.nodes.count }
    var visibleEdgeCount: Int { displayedSubgraph.edges.count }

    var currentPathLabel: String {
        currentProjectURL?.path ?? currentJSONURL?.path ?? graph.rootPath ?? "샘플 그래프"
    }

    var zoomPercentageLabel: String {
        "\(Int((zoomScale * 100).rounded()))%"
    }

    var lastProjectPath: String? {
        preferences.string(forKey: PreferencesKey.lastProjectPath.rawValue)
    }

    func chooseTuistProject() {
        let panel = NSOpenPanel()
        panel.title = "Tuist 프로젝트 폴더 선택"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "열기"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadProject(at: url)
    }

    func chooseJSONFile() {
        let panel = NSOpenPanel()
        panel.title = "그래프 JSON 파일 선택"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.prompt = "열기"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadJSONFile(at: url)
    }

    func reloadCurrentProject() {
        if let currentProjectURL {
            loadProject(at: currentProjectURL)
            return
        }

        guard let lastProjectPath else { return }
        loadProject(at: URL(fileURLWithPath: lastProjectPath))
    }

    func loadSample() {
        apply(graph: SampleGraph.make(), resetViewport: true)
        currentProjectURL = nil
        currentJSONURL = nil
        sourceLabel = "Sample graph / normalized-sample"
        statusMessage = "샘플 그래프를 불러왔습니다."
    }

    func resetView() {
        direction = .both
        depth = .all
        presentationMode = .expanded
        includeExternal = false
        searchText = ""
        relatedNodeSearchText = ""
        zoomScale = Self.defaultZoomScale
        graphSelectedNodeID = nil
        resetConnectionPathState()
        selectedLevel = 0
        selectedNodeID = graph.preferredRootID
        refreshDerivedState()
        requestViewportCentering()
        statusMessage = "뷰를 초기화했습니다."
    }

    func selectNode(_ nodeID: String) {
        selectedNodeID = nodeID
        graphSelectedNodeID = nil
        relatedNodeSearchText = ""
        resetConnectionPathState()
        selectedLevel = 0
        alignDepthSelectionWithCurrentGraph()
        refreshDerivedState()
        requestViewportCentering()
    }

    func selectGraphNode(_ nodeID: String) {
        guard nodeID != selectedNodeID else {
            graphSelectedNodeID = nil
            resetConnectionPathState()
            refreshDerivedState()
            return
        }
        graphSelectedNodeID = graphSelectedNodeID == nodeID ? nil : nodeID
        resetConnectionPathState()
        refreshDerivedState()
    }

    func selectLevel(_ level: Int) {
        selectedLevel = level
    }

    func selectRelatedNode(_ nodeID: String) {
        guard nodeID != selectedNodeID else { return }
        graphSelectedNodeID = nodeID
        resetConnectionPathState()
        refreshDerivedState()
    }

    func clearRelatedNodeSelection() {
        guard graphSelectedNodeID != nil else { return }
        graphSelectedNodeID = nil
        resetConnectionPathState()
        refreshDerivedState()
    }

    func selectFirstMatchingRelatedNode() {
        guard let nodeID = filteredRelatedNodes.first?.id else { return }
        selectRelatedNode(nodeID)
    }

    func showAllConnectionPaths() {
        selectedConnectionPathIDs = nil
        refreshDisplayedSubgraph()
    }

    func hideAllConnectionPaths() {
        selectedConnectionPathIDs = []
        if showOnlyActivePaths {
            showOnlyActivePaths = false
        } else {
            refreshDisplayedSubgraph()
        }
    }

    func increaseConnectionPathLimit() {
        connectionPathLimit += Self.connectionPathLimitStep
        refreshDerivedState()
    }

    func resetConnectionPathLimit() {
        guard connectionPathLimit != Self.defaultConnectionPathLimit else { return }
        connectionPathLimit = Self.defaultConnectionPathLimit
        refreshDerivedState()
    }

    func toggleConnectionPath(_ pathID: String, additiveSelection: Bool = false) {
        let availablePathIDs = Set(connectionPaths.map(\.id))
        guard availablePathIDs.contains(pathID) else { return }

        if showOnlyActivePaths {
            if additiveSelection {
                var nextSelection = selectedConnectionPathIDs ?? availablePathIDs
                if nextSelection.contains(pathID) {
                    nextSelection.remove(pathID)
                } else {
                    nextSelection.insert(pathID)
                }

                selectedConnectionPathIDs = nextSelection == availablePathIDs ? nil : nextSelection
                if selectedConnectionPathIDs?.isEmpty == true {
                    showOnlyActivePaths = false
                } else {
                    refreshDisplayedSubgraph()
                }
            } else {
                selectedConnectionPathIDs = [pathID]
                refreshDisplayedSubgraph()
            }
            return
        }

        var nextSelection = selectedConnectionPathIDs ?? availablePathIDs
        if nextSelection.contains(pathID) {
            nextSelection.remove(pathID)
        } else {
            nextSelection.insert(pathID)
        }

        selectedConnectionPathIDs = nextSelection == availablePathIDs ? nil : nextSelection
        if selectedConnectionPathIDs?.isEmpty == true, showOnlyActivePaths {
            showOnlyActivePaths = false
        } else {
            refreshDisplayedSubgraph()
        }
    }

    func setZoomScale(_ value: Double) {
        zoomScale = Self.clampZoomScale(value)
    }

    func zoomIn() {
        setZoomScale(zoomScale + Self.zoomStep)
    }

    func zoomOut() {
        setZoomScale(zoomScale - Self.zoomStep)
    }

    func resetZoom() {
        setZoomScale(Self.defaultZoomScale)
    }

    private func loadProject(at url: URL) {
        isLoading = true
        statusMessage = "Tuist 그래프를 생성하는 중입니다..."
        let service = exportService
        let targetURL = url

        Task {
            do {
                let graph = try await Task.detached(priority: .userInitiated) {
                    try service.loadFromProject(at: targetURL)
                }.value

                apply(graph: graph, resetViewport: true)
                currentProjectURL = targetURL
                currentJSONURL = nil
                sourceLabel = "Tuist project / \(graph.sourceFormat)"
                statusMessage = "프로젝트 그래프를 불러왔습니다."
                preferences.set(targetURL.path, forKey: PreferencesKey.lastProjectPath.rawValue)
            } catch let error as SpiderGraphImportError {
                presentedError = error
                statusMessage = error.errorDescription ?? "그래프 생성에 실패했습니다."
            } catch {
                presentedError = .processFailed(error.localizedDescription)
                statusMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func loadJSONFile(at url: URL) {
        isLoading = true
        statusMessage = "그래프 JSON을 읽는 중입니다..."
        let service = exportService
        let targetURL = url

        Task {
            do {
                let graph = try await Task.detached(priority: .userInitiated) {
                    try service.loadFromJSONFile(at: targetURL)
                }.value

                apply(graph: graph, resetViewport: true)
                currentProjectURL = nil
                currentJSONURL = targetURL
                sourceLabel = "JSON file / \(graph.sourceFormat)"
                statusMessage = "JSON 그래프를 불러왔습니다."
            } catch let error as SpiderGraphImportError {
                presentedError = error
                statusMessage = error.errorDescription ?? "그래프 로드에 실패했습니다."
            } catch {
                presentedError = .processFailed(error.localizedDescription)
                statusMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func apply(graph: SpiderGraph, resetViewport: Bool = false) {
        self.graph = graph
        self.selectedNodeID = graph.preferredRootID
        self.graphSelectedNodeID = nil
        self.relatedNodeSearchText = ""
        resetConnectionPathState()
        self.selectedLevel = 0
        alignDepthSelectionWithCurrentGraph()
        refreshDerivedState()
        requestViewportCentering()

        if resetViewport {
            self.zoomScale = Self.defaultZoomScale
        }
    }

    private func restorePreferences() {
        if let rawDirection = preferences.string(forKey: PreferencesKey.direction.rawValue),
           let direction = GraphDirection(rawValue: rawDirection) {
            self.direction = direction
        }
        if let rawDepth = preferences.string(forKey: PreferencesKey.depth.rawValue),
           let depth = GraphDepth(rawValue: rawDepth) {
            self.depth = depth
        }
        if let rawPresentationMode = preferences.string(forKey: PreferencesKey.presentationMode.rawValue),
           let presentationMode = GraphPresentationMode(rawValue: rawPresentationMode) {
            self.presentationMode = presentationMode
        }
        if preferences.object(forKey: PreferencesKey.showOnlyActivePaths.rawValue) != nil {
            self.showOnlyActivePaths = preferences.bool(forKey: PreferencesKey.showOnlyActivePaths.rawValue)
        }
        self.includeExternal = preferences.bool(forKey: PreferencesKey.includeExternal.rawValue)
        self.searchText = preferences.string(forKey: PreferencesKey.searchText.rawValue) ?? ""
        self.selectedNodeID = preferences.string(forKey: PreferencesKey.selectedNodeID.rawValue)
        if preferences.object(forKey: PreferencesKey.selectedLevel.rawValue) != nil {
            self.selectedLevel = preferences.integer(forKey: PreferencesKey.selectedLevel.rawValue)
        }
        if preferences.object(forKey: PreferencesKey.zoomScale.rawValue) != nil {
            self.zoomScale = Self.clampZoomScale(preferences.double(forKey: PreferencesKey.zoomScale.rawValue))
        }
    }

    private func persistPreferences() {
        preferences.set(direction.rawValue, forKey: PreferencesKey.direction.rawValue)
        preferences.set(depth.rawValue, forKey: PreferencesKey.depth.rawValue)
        preferences.set(presentationMode.rawValue, forKey: PreferencesKey.presentationMode.rawValue)
        preferences.set(showOnlyActivePaths, forKey: PreferencesKey.showOnlyActivePaths.rawValue)
        preferences.set(includeExternal, forKey: PreferencesKey.includeExternal.rawValue)
        preferences.set(searchText, forKey: PreferencesKey.searchText.rawValue)
        preferences.set(selectedNodeID, forKey: PreferencesKey.selectedNodeID.rawValue)
        preferences.set(selectedLevel, forKey: PreferencesKey.selectedLevel.rawValue)
        preferences.set(zoomScale, forKey: PreferencesKey.zoomScale.rawValue)
    }

    private static func clampZoomScale(_ value: Double) -> Double {
        min(max(value, zoomScaleRange.lowerBound), zoomScaleRange.upperBound)
    }

    private func resetConnectionPathState() {
        selectedConnectionPathIDs = nil
        connectionPathLimit = Self.defaultConnectionPathLimit
    }

    private func refreshDerivedState() {
        refreshVisibleSubgraph()
        refreshInspectorState()
        refreshDisplayedSubgraph()
    }

    private func refreshVisibleSubgraph() {
        guard let selectedNodeID else {
            visibleSubgraph = .empty
            return
        }

        visibleSubgraph = graph.subgraph(
            centeredOn: selectedNodeID,
            direction: direction,
            depth: depth,
            includeExternal: includeExternal
        )

        if let graphSelectedNodeID, !visibleSubgraph.nodeIDs.contains(graphSelectedNodeID) {
            self.graphSelectedNodeID = nil
        }

        if visibleSubgraph.levelGroups.contains(where: { $0.level == selectedLevel }) == false {
            selectedLevel = visibleSubgraph.levelGroups.first(where: { $0.level == 0 })?.level
                ?? visibleSubgraph.levelGroups.first?.level
                ?? 0
        }
    }

    private func availableDepthOptions(for nodeID: String?) -> [GraphDepth] {
        guard let nodeID else { return [.all] }
        let maxDepth = graph.maxReachableDepth(
            centeredOn: nodeID,
            direction: direction,
            includeExternal: includeExternal
        )
        guard maxDepth > 0 else { return [.all] }
        return (1...maxDepth).map { GraphDepth(maxDepth: $0) } + [.all]
    }

    private func alignDepthSelectionWithCurrentGraph() {
        let options = availableDepthOptions(for: selectedNodeID)
        guard !options.contains(depth) else { return }

        if let currentDepth = depth.maxDepth,
           let maxAvailableDepth = options.compactMap(\.maxDepth).max() {
            depth = GraphDepth(maxDepth: min(currentDepth, maxAvailableDepth))
        } else {
            depth = .all
        }
    }

    private func refreshInspectorState() {
        if let inspectedNodeID = inspectedNode?.id {
            directDependencies = graph.directDependencies(of: inspectedNodeID, includeExternal: includeExternal)
            directDependents = graph.directDependents(of: inspectedNodeID, includeExternal: includeExternal)
        } else {
            directDependencies = []
            directDependents = []
        }

        guard
            let focusedNodeID = selectedNodeID,
            let graphSelectedNodeID = visibleGraphSelectedNodeID
        else {
            connectionPaths = []
            hasTruncatedConnectionPaths = false
            connectionDirection = nil
            return
        }

        let connectionPathResult = visibleSubgraph.connectionPaths(
            from: focusedNodeID,
            to: graphSelectedNodeID,
            maxPaths: connectionPathLimit,
            maxExtraHops: Self.connectionPathExtraHops
        )

        connectionPaths = connectionPathResult?.paths ?? []
        hasTruncatedConnectionPaths = connectionPathResult?.isTruncated == true
        connectionDirection = graph.relationshipDirection(
            from: focusedNodeID,
            to: graphSelectedNodeID,
            restrictedTo: visibleSubgraph.nodeIDs
        )
    }

    private func refreshDisplayedSubgraph() {
        if showOnlyActivePaths && !activeConnectionPaths.isEmpty {
            displayedSubgraph = visibleSubgraph.filtered(
                toNodeIDs: activeConnectionPathNodeIDs,
                edgeIDs: activeConnectionPathEdgeIDs
            )
        } else {
            displayedSubgraph = visibleSubgraph
        }

        if displayedSubgraph.levelGroups.contains(where: { $0.level == selectedLevel }) == false {
            selectedLevel = displayedSubgraph.levelGroups.first(where: { $0.level == 0 })?.level
                ?? displayedSubgraph.levelGroups.first?.level
                ?? 0
        }
    }

    private func requestViewportCentering() {
        viewportCenterRequestID &+= 1
    }

    private enum PreferencesKey: String {
        case direction
        case depth
        case presentationMode
        case showOnlyActivePaths
        case includeExternal
        case searchText
        case selectedNodeID
        case selectedLevel
        case lastProjectPath
        case zoomScale
    }
}

private enum SampleGraph {
    static func make() -> SpiderGraph {
        SpiderGraph(
            graphName: "FixtureApp",
            sourceFormat: "normalized-sample",
            rootPath: "examples/TuistFixture",
            generatedAt: nil,
            nodes: [
                SpiderGraphNode(
                    id: "target::examples/TuistFixture::FixtureApp",
                    name: "FixtureApp",
                    displayName: "FixtureApp",
                    kind: "target",
                    product: "app",
                    bundleId: "com.example.fixture",
                    projectName: "FixtureApp",
                    projectPath: "examples/TuistFixture",
                    isExternal: false,
                    sourceCount: 1,
                    resourceCount: 0,
                    metadataTags: []
                ),
                SpiderGraphNode(
                    id: "target::examples/TuistFixture::FeatureA",
                    name: "FeatureA",
                    displayName: "FeatureA",
                    kind: "target",
                    product: "framework",
                    bundleId: "com.example.featureA",
                    projectName: "FixtureApp",
                    projectPath: "examples/TuistFixture",
                    isExternal: false,
                    sourceCount: 1,
                    resourceCount: 0,
                    metadataTags: ["feature"]
                ),
                SpiderGraphNode(
                    id: "target::examples/TuistFixture::FeatureB",
                    name: "FeatureB",
                    displayName: "FeatureB",
                    kind: "target",
                    product: "framework",
                    bundleId: "com.example.featureB",
                    projectName: "FixtureApp",
                    projectPath: "examples/TuistFixture",
                    isExternal: false,
                    sourceCount: 1,
                    resourceCount: 0,
                    metadataTags: ["feature"]
                ),
                SpiderGraphNode(
                    id: "target::examples/TuistFixture::Core",
                    name: "Core",
                    displayName: "Core",
                    kind: "target",
                    product: "framework",
                    bundleId: "com.example.core",
                    projectName: "FixtureApp",
                    projectPath: "examples/TuistFixture",
                    isExternal: false,
                    sourceCount: 1,
                    resourceCount: 0,
                    metadataTags: ["foundation"]
                ),
                SpiderGraphNode(
                    id: "package::NetworkingKit",
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
                    metadataTags: []
                ),
            ],
            edges: [
                SpiderGraphEdge(
                    from: "target::examples/TuistFixture::FixtureApp",
                    to: "target::examples/TuistFixture::FeatureA",
                    kind: "target",
                    status: "required"
                ),
                SpiderGraphEdge(
                    from: "target::examples/TuistFixture::FixtureApp",
                    to: "target::examples/TuistFixture::FeatureB",
                    kind: "target",
                    status: "required"
                ),
                SpiderGraphEdge(
                    from: "target::examples/TuistFixture::FeatureA",
                    to: "target::examples/TuistFixture::Core",
                    kind: "target",
                    status: "required"
                ),
                SpiderGraphEdge(
                    from: "target::examples/TuistFixture::FeatureB",
                    to: "target::examples/TuistFixture::Core",
                    kind: "target",
                    status: "required"
                ),
                SpiderGraphEdge(
                    from: "target::examples/TuistFixture::FeatureB",
                    to: "package::NetworkingKit",
                    kind: "package",
                    status: nil
                ),
            ]
        )
    }
}
