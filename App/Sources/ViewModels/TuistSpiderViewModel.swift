import AppKit
import Foundation

struct SpiderGraphLayerCatalogEntry: Identifiable, Hashable, Sendable {
    let name: String
    let nodeCount: Int

    var id: String { name }
}

struct SpiderGraphLayerFilterOption: Identifiable, Hashable, Sendable {
    let filter: SpiderGraphLayerFilter
    let count: Int

    var id: String { filter.id }
}

@MainActor
final class TuistSpiderViewModel: ObservableObject {
    static let defaultZoomScale = 1.0
    static let zoomScaleRange: ClosedRange<Double> = 0.5...2.0
    static let zoomStep = 0.15
    static let defaultConnectionPathLimit = 12
    static let connectionPathLimitStep = 12
    static let connectionPathExtraHops = 3
    static let unclassifiedLayerTitle = "Unclassified"
    static let automaticUpdateCheckInterval: TimeInterval = 60 * 60 * 12

    @Published private(set) var graph = SampleGraph.make()
    @Published var selectedNodeID: String? {
        didSet {
            guard !isRestoringPreferences else { return }
            persistPreferences()
        }
    }
    @Published var graphSelectedNodeID: String?
    @Published private var selectedConnectionPathIDs: Set<String>? = nil
    @Published var showOnlyActivePaths = false {
        didSet {
            guard !isRestoringPreferences else { return }
            refreshDisplayedSubgraph()
            persistPreferences()
        }
    }
    @Published var direction: GraphDirection = .both {
        didSet {
            guard !isRestoringPreferences else { return }
            resetConnectionPathState()
            alignDepthSelectionWithCurrentGraph()
            refreshDerivedState()
            persistPreferences()
        }
    }
    @Published var depth: GraphDepth = .all {
        didSet {
            guard !isRestoringPreferences else { return }
            resetConnectionPathState()
            refreshDerivedState()
            persistPreferences()
        }
    }
    @Published var presentationMode: GraphPresentationMode = .expanded {
        didSet {
            guard !isRestoringPreferences else { return }
            resetConnectionPathState()
            persistPreferences()
        }
    }
    @Published var includeExternal = false {
        didSet {
            guard !isRestoringPreferences else { return }
            ensureSelectedNodeMatchesFilters()
            resetConnectionPathState()
            alignDepthSelectionWithCurrentGraph()
            refreshDerivedState()
            persistPreferences()
        }
    }
    @Published var selectedLayerFilter: SpiderGraphLayerFilter = .all {
        didSet {
            guard !isRestoringPreferences else { return }
            ensureSelectedLayerFilterIsAvailable()
            ensureSelectedNodeMatchesFilters()
            graphSelectedNodeID = nil
            resetConnectionPathState()
            alignDepthSelectionWithCurrentGraph()
            refreshDerivedState()
            persistPreferences()
        }
    }
    @Published var searchText = "" {
        didSet {
            guard !isRestoringPreferences else { return }
            persistPreferences()
        }
    }
    @Published var relatedNodeSearchText = ""
    @Published var zoomScale = TuistSpiderViewModel.defaultZoomScale {
        didSet {
            guard !isRestoringPreferences else { return }
            let clamped = Self.clampZoomScale(zoomScale)
            if abs(clamped - zoomScale) > .ulpOfOne {
                zoomScale = clamped
                return
            }
            persistPreferences()
        }
    }
    @Published var selectedLevel = 0 {
        didSet {
            guard !isRestoringPreferences else { return }
            persistPreferences()
        }
    }
    @Published private(set) var isLoading = false
    @Published private(set) var statusMessage = "샘플 그래프를 불러왔습니다."
    @Published private(set) var sourceLabel = "Sample graph / normalized-sample"
    @Published private(set) var currentProjectURL: URL?
    @Published private(set) var currentJSONURL: URL?
    @Published private(set) var viewportCenterRequestID = 0
    @Published var presentedError: SpiderGraphImportError?
    @Published private(set) var availableAppUpdate: AppUpdateRelease?
    @Published private(set) var isCheckingForUpdates = false
    @Published private(set) var visibleSubgraph = SpiderGraphSubgraph.empty
    @Published private(set) var directDependencies: [SpiderGraphNode] = []
    @Published private(set) var directDependents: [SpiderGraphNode] = []
    @Published private(set) var connectionPaths: [SpiderGraphConnectionPath] = []
    @Published private(set) var connectionPathLimit = TuistSpiderViewModel.defaultConnectionPathLimit
    @Published private(set) var hasTruncatedConnectionPaths = false
    @Published private(set) var connectionDirection: SpiderGraphRelationshipDirection?
    @Published private(set) var displayedSubgraph = SpiderGraphSubgraph.empty

    private let exportService = TuistGraphExportService()
    private let updateService = AppUpdateService()
    private let preferences = UserDefaults.standard
    private var isRestoringPreferences = false
    private var hasPerformedInitialUpdateCheck = false

    init() {
        restorePreferences(for: graph)
        requestViewportCentering()
    }

    var filteredNodes: [SpiderGraphNode] {
        graph.nodes.filter { node in
            guard matchesNodeListFilters(node) else { return false }
            if searchText.isEmpty {
                return true
            }
            let query = searchText.lowercased()
            return node.name.lowercased().contains(query)
                || node.projectLabel.lowercased().contains(query)
                || node.layerLabel.lowercased().contains(query)
        }
    }

    var availableDepthOptions: [GraphDepth] {
        availableDepthOptions(for: selectedNodeID)
    }

    var layerCatalog: [SpiderGraphLayerCatalogEntry] {
        let internalNodes = graph.nodes.filter { !$0.isExternal }
        let counts = Dictionary(grouping: internalNodes.compactMap(\.primaryLayer), by: { $0 })
            .mapValues(\.count)

        return counts.keys.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }.map { name in
            SpiderGraphLayerCatalogEntry(name: name, nodeCount: counts[name] ?? 0)
        }
    }

    var layerFilterOptions: [SpiderGraphLayerFilterOption] {
        let internalNodes = graph.nodes.filter { !$0.isExternal }
        let unclassifiedCount = internalNodes.filter { $0.primaryLayer == nil }.count
        var options = [SpiderGraphLayerFilterOption(filter: .all, count: internalNodes.count)]
        options.append(contentsOf: layerCatalog.map { entry in
            SpiderGraphLayerFilterOption(filter: .layer(entry.name), count: entry.nodeCount)
        })
        if unclassifiedCount > 0 {
            options.append(SpiderGraphLayerFilterOption(filter: .unclassified, count: unclassifiedCount))
        }
        return options
    }

    var filteredRelatedNodes: [SpiderGraphNode] {
        guard let selectedNodeID else { return [] }
        let query = relatedNodeSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }

        return visibleSubgraph.nodes
            .filter { node in
                guard node.id != selectedNodeID else { return false }
                return node.name.lowercased().contains(query)
                    || node.projectLabel.lowercased().contains(query)
                    || node.layerLabel.lowercased().contains(query)
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

    var canExportCurrentGraphAsPNG: Bool {
        !displayedSubgraph.nodes.isEmpty
    }

    var suggestedPNGDirectoryURL: URL? {
        if let currentProjectURL {
            return currentProjectURL
        }
        if let currentJSONURL {
            return currentJSONURL.deletingLastPathComponent()
        }
        if let rootPath = graph.rootPath {
            return URL(fileURLWithPath: rootPath, isDirectory: true)
        }
        return nil
    }

    var suggestedPNGFileName: String {
        let baseName = sanitizeFileNameComponent(graph.graphName)
        let modeName = presentationMode == .grouped ? "grouped" : "expanded"
        if let selectedNode {
            return "\(baseName)-\(modeName)-\(sanitizeFileNameComponent(selectedNode.name)).png"
        }
        return "\(baseName)-\(modeName).png"
    }

    var currentAppVersion: String {
        if let marketingVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !marketingVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return marketingVersion
        }

        if let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
           !buildVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return buildVersion
        }

        return "0"
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
        statusMessage = loadStatusMessage(base: "샘플 그래프를 불러왔습니다.", for: graph)
    }

    func resetView() {
        direction = .both
        depth = .all
        presentationMode = .expanded
        includeExternal = false
        selectedLayerFilter = .all
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

    func canEditLayerClassification(for node: SpiderGraphNode) -> Bool {
        guard let rootURL = snapshotRootURL(for: graph) else { return false }
        return ProjectLayerSnapshotStore.canPersist(node, rootURL: rootURL)
    }

    func availableLayerOptions(for node: SpiderGraphNode) -> [String] {
        let names = Set(
            graph.nodes.compactMap(\.primaryLayer)
            + graph.nodes.compactMap(\.suggestedLayer)
            + [node.primaryLayer, node.suggestedLayer].compactMap { $0 }
        )

        return names.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    func applyLayerClassification(for nodeID: String, layerName: String?) {
        guard
            let node = graph.nodeMap[nodeID],
            let rootURL = snapshotRootURL(for: graph),
            ProjectLayerSnapshotStore.canPersist(node, rootURL: rootURL)
        else {
            return
        }

        let normalizedLayer = normalizedLayerName(layerName)
        let updatedNode = node.updatingClassification(
            primaryLayer: normalizedLayer,
            layerSource: .projectSnapshot,
            hasPersistedClassification: true
        )
        let updatedGraph = graph.replacingNodes(
            graph.nodes.map { $0.id == nodeID ? updatedNode : $0 }
        )

        do {
            try ProjectLayerSnapshotStore.syncSnapshot(for: updatedGraph, rootURL: rootURL)
            applyUpdatedGraph(updatedGraph)
            statusMessage = "레이어 분류를 저장했습니다."
        } catch {
            presentedError = .processFailed("레이어 분류를 저장하지 못했습니다. \(error.localizedDescription)")
            statusMessage = "레이어 분류 저장에 실패했습니다."
        }
    }

    func resetLayerClassificationToSuggested(for nodeID: String) {
        guard let node = graph.nodeMap[nodeID] else { return }
        applyLayerClassification(for: nodeID, layerName: node.suggestedLayer)
    }

    func handlePNGExportSuccess(fileURL: URL) {
        statusMessage = "PNG를 저장했습니다: \(fileURL.lastPathComponent)"
    }

    func handlePNGExportFailure(_ error: Error) {
        presentedError = .processFailed("PNG 저장에 실패했습니다. \(error.localizedDescription)")
        statusMessage = "PNG 저장에 실패했습니다."
    }

    func checkForUpdatesIfNeeded() async {
        guard !hasPerformedInitialUpdateCheck else { return }
        hasPerformedInitialUpdateCheck = true
        guard shouldPerformAutomaticUpdateCheck() else { return }
        await performUpdateCheck(userInitiated: false, ignoreSkippedVersion: false)
    }

    func checkForUpdatesManually() {
        Task {
            await performUpdateCheck(userInitiated: true, ignoreSkippedVersion: true)
        }
    }

    func dismissAvailableUpdate() {
        availableAppUpdate = nil
    }

    func skipAvailableUpdate() {
        guard let availableAppUpdate else { return }
        preferences.set(availableAppUpdate.version, forKey: PreferencesKey.skippedAppUpdateVersion.rawValue)
        self.availableAppUpdate = nil
        statusMessage = "\(availableAppUpdate.displayVersion) 업데이트 알림을 숨겼습니다."
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

                let resolvedGraph = prepareGraphForPresentation(
                    graph,
                    projectURL: targetURL,
                    jsonURL: nil
                )
                apply(graph: resolvedGraph, resetViewport: true)
                currentProjectURL = targetURL
                currentJSONURL = nil
                sourceLabel = "Tuist project / \(resolvedGraph.sourceFormat)"
                statusMessage = loadStatusMessage(base: "프로젝트 그래프를 불러왔습니다.", for: resolvedGraph)
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

                let resolvedGraph = prepareGraphForPresentation(
                    graph,
                    projectURL: nil,
                    jsonURL: targetURL
                )
                apply(graph: resolvedGraph, resetViewport: true)
                currentProjectURL = nil
                currentJSONURL = targetURL
                sourceLabel = "JSON file / \(resolvedGraph.sourceFormat)"
                statusMessage = loadStatusMessage(base: "JSON 그래프를 불러왔습니다.", for: resolvedGraph)
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
        restorePreferences(for: graph)
        self.graphSelectedNodeID = nil
        self.relatedNodeSearchText = ""
        resetConnectionPathState()
        refreshDerivedState()
        requestViewportCentering()

        if resetViewport && !hasScopedPreference(for: .zoomScale, scopeID: preferenceScopeID(for: graph)) {
            self.zoomScale = Self.defaultZoomScale
        }

        persistPreferences()
    }

    private func applyUpdatedGraph(_ updatedGraph: SpiderGraph) {
        graph = updatedGraph
        ensureSelectedLayerFilterIsAvailable()
        ensureSelectedNodeMatchesFilters()
        resetConnectionPathState()
        alignDepthSelectionWithCurrentGraph()
        refreshDerivedState()
        persistPreferences()
    }

    private func prepareGraphForPresentation(
        _ graph: SpiderGraph,
        projectURL: URL?,
        jsonURL: URL?
    ) -> SpiderGraph {
        guard let rootURL = snapshotRootURL(for: graph, projectURL: projectURL, jsonURL: jsonURL) else {
            return graph
        }

        var preparedGraph = graph
        var warnings: [String] = []
        var didFailLoadingSnapshot = false

        do {
            if let snapshot = try ProjectLayerSnapshotStore.load(rootURL: rootURL) {
                preparedGraph = ProjectLayerSnapshotStore.apply(snapshot, to: preparedGraph, rootURL: rootURL)
            }
        } catch {
            didFailLoadingSnapshot = true
            warnings.append("레이어 스냅샷을 읽지 못해 자동 분류 결과를 사용합니다. \(error.localizedDescription)")
        }

        if !didFailLoadingSnapshot {
            do {
                _ = try ProjectLayerSnapshotStore.syncSnapshot(for: preparedGraph, rootURL: rootURL)
            } catch {
                warnings.append("레이어 스냅샷을 저장하지 못했습니다. \(error.localizedDescription)")
            }
        }

        return preparedGraph.appendingWarnings(warnings)
    }

    private func restorePreferences(for graph: SpiderGraph) {
        let scopeID = preferenceScopeID(for: graph)
        isRestoringPreferences = true
        defer { isRestoringPreferences = false }

        if let rawDirection = preferences.string(forKey: scopedPreferenceKey(.direction, scopeID: scopeID)),
           let direction = GraphDirection(rawValue: rawDirection) {
            self.direction = direction
        } else {
            self.direction = .both
        }
        if let rawDepth = preferences.string(forKey: scopedPreferenceKey(.depth, scopeID: scopeID)),
           let depth = GraphDepth(rawValue: rawDepth) {
            self.depth = depth
        } else {
            self.depth = .all
        }
        if let rawPresentationMode = preferences.string(forKey: scopedPreferenceKey(.presentationMode, scopeID: scopeID)),
           let presentationMode = GraphPresentationMode(rawValue: rawPresentationMode) {
            self.presentationMode = presentationMode
        } else {
            self.presentationMode = .expanded
        }

        self.showOnlyActivePaths = hasScopedPreference(for: .showOnlyActivePaths, scopeID: scopeID)
            ? preferences.bool(forKey: scopedPreferenceKey(.showOnlyActivePaths, scopeID: scopeID))
            : false
        self.includeExternal = hasScopedPreference(for: .includeExternal, scopeID: scopeID)
            ? preferences.bool(forKey: scopedPreferenceKey(.includeExternal, scopeID: scopeID))
            : false
        self.searchText = preferences.string(forKey: scopedPreferenceKey(.searchText, scopeID: scopeID)) ?? ""
        self.selectedLayerFilter = preferences.string(forKey: scopedPreferenceKey(.selectedLayerFilter, scopeID: scopeID))
            .flatMap(SpiderGraphLayerFilter.init(persistedValue:))
            ?? .all
        self.selectedNodeID = preferences.string(forKey: scopedPreferenceKey(.selectedNodeID, scopeID: scopeID))
        self.selectedLevel = hasScopedPreference(for: .selectedLevel, scopeID: scopeID)
            ? preferences.integer(forKey: scopedPreferenceKey(.selectedLevel, scopeID: scopeID))
            : 0
        self.zoomScale = hasScopedPreference(for: .zoomScale, scopeID: scopeID)
            ? Self.clampZoomScale(preferences.double(forKey: scopedPreferenceKey(.zoomScale, scopeID: scopeID)))
            : Self.defaultZoomScale

        ensureSelectedLayerFilterIsAvailable()
        ensureSelectedNodeMatchesFilters()
        alignDepthSelectionWithCurrentGraph()
    }

    private func persistPreferences() {
        let scopeID = preferenceScopeID(for: graph)
        preferences.set(direction.rawValue, forKey: scopedPreferenceKey(.direction, scopeID: scopeID))
        preferences.set(depth.rawValue, forKey: scopedPreferenceKey(.depth, scopeID: scopeID))
        preferences.set(presentationMode.rawValue, forKey: scopedPreferenceKey(.presentationMode, scopeID: scopeID))
        preferences.set(showOnlyActivePaths, forKey: scopedPreferenceKey(.showOnlyActivePaths, scopeID: scopeID))
        preferences.set(includeExternal, forKey: scopedPreferenceKey(.includeExternal, scopeID: scopeID))
        preferences.set(searchText, forKey: scopedPreferenceKey(.searchText, scopeID: scopeID))
        preferences.set(selectedLayerFilter.persistedValue, forKey: scopedPreferenceKey(.selectedLayerFilter, scopeID: scopeID))
        preferences.set(selectedNodeID, forKey: scopedPreferenceKey(.selectedNodeID, scopeID: scopeID))
        preferences.set(selectedLevel, forKey: scopedPreferenceKey(.selectedLevel, scopeID: scopeID))
        preferences.set(zoomScale, forKey: scopedPreferenceKey(.zoomScale, scopeID: scopeID))
    }

    private static func clampZoomScale(_ value: Double) -> Double {
        min(max(value, zoomScaleRange.lowerBound), zoomScaleRange.upperBound)
    }

    private func sanitizeFileNameComponent(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "\\/:*?\"<>|")
        let cleaned = value.components(separatedBy: invalidCharacters).joined(separator: "-")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "TuistSpider" : trimmed
    }

    private func loadStatusMessage(base: String, for graph: SpiderGraph) -> String {
        guard !graph.warnings.isEmpty else { return base }
        return "\(base) 레이어 경고 \(graph.warnings.count)건이 있습니다."
    }

    private func snapshotRootURL(for graph: SpiderGraph) -> URL? {
        snapshotRootURL(for: graph, projectURL: currentProjectURL, jsonURL: currentJSONURL)
    }

    private func snapshotRootURL(
        for graph: SpiderGraph,
        projectURL: URL?,
        jsonURL: URL?
    ) -> URL? {
        if let projectURL {
            return projectURL.standardizedFileURL
        }

        if let rootPath = graph.rootPath {
            let candidateURL: URL
            if let jsonURL {
                candidateURL = URL(fileURLWithPath: rootPath, relativeTo: jsonURL.deletingLastPathComponent()).standardizedFileURL
            } else {
                candidateURL = URL(fileURLWithPath: rootPath).standardizedFileURL
            }

            if FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        if let jsonURL {
            return jsonURL.deletingLastPathComponent().standardizedFileURL
        }

        return nil
    }

    private func normalizedLayerName(_ layerName: String?) -> String? {
        guard let layerName else { return nil }
        let trimmed = layerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func performUpdateCheck(userInitiated: Bool, ignoreSkippedVersion: Bool) async {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }

        do {
            let skippedVersion = ignoreSkippedVersion
                ? nil
                : preferences.string(forKey: PreferencesKey.skippedAppUpdateVersion.rawValue)
            let result = try await updateService.checkForUpdates(
                currentVersion: currentAppVersion,
                skippedVersion: skippedVersion
            )
            preferences.set(Date(), forKey: PreferencesKey.lastAppUpdateCheckAt.rawValue)

            switch result {
            case let .updateAvailable(release):
                availableAppUpdate = release
                statusMessage = "새 버전 \(release.displayVersion)이 있습니다."
            case let .upToDate(latestVersion):
                if ignoreSkippedVersion || availableAppUpdate?.version == latestVersion {
                    availableAppUpdate = nil
                }
                if userInitiated {
                    statusMessage = "최신 버전입니다. (\(AppUpdateService.normalizeVersionString(latestVersion)))"
                }
            }
        } catch {
            if userInitiated {
                presentedError = .processFailed("업데이트 확인에 실패했습니다. \(error.localizedDescription)")
                statusMessage = "업데이트 확인에 실패했습니다."
            }
        }
    }

    private func shouldPerformAutomaticUpdateCheck(now: Date = Date()) -> Bool {
        guard let lastCheckedAt = preferences.object(forKey: PreferencesKey.lastAppUpdateCheckAt.rawValue) as? Date else {
            return true
        }
        return now.timeIntervalSince(lastCheckedAt) >= Self.automaticUpdateCheckInterval
    }

    private func preferenceScopeID(for graph: SpiderGraph) -> String {
        graph.rootPath ?? "graph::\(graph.sourceFormat)::\(graph.graphName)"
    }

    private func scopedPreferenceKey(_ key: PreferencesKey, scopeID: String) -> String {
        "graphPreferences::\(scopeID)::\(key.rawValue)"
    }

    private func hasScopedPreference(for key: PreferencesKey, scopeID: String) -> Bool {
        preferences.object(forKey: scopedPreferenceKey(key, scopeID: scopeID)) != nil
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
            includeExternal: includeExternal,
            layerFilter: selectedLayerFilter
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
            includeExternal: includeExternal,
            layerFilter: selectedLayerFilter
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
            directDependencies = graph.directDependencies(
                of: inspectedNodeID,
                includeExternal: includeExternal,
                layerFilter: selectedLayerFilter
            )
            directDependents = graph.directDependents(
                of: inspectedNodeID,
                includeExternal: includeExternal,
                layerFilter: selectedLayerFilter
            )
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

    private func matchesNodeListFilters(_ node: SpiderGraphNode) -> Bool {
        guard includeExternal || !node.isExternal else { return false }
        return selectedLayerFilter.matches(node)
    }

    private func ensureSelectedLayerFilterIsAvailable() {
        guard layerFilterOptions.contains(where: { $0.filter == selectedLayerFilter }) else {
            selectedLayerFilter = .all
            return
        }
    }

    private func ensureSelectedNodeMatchesFilters() {
        if let selectedNodeID,
           let node = graph.nodeMap[selectedNodeID],
           matchesNodeListFilters(node) {
            return
        }

        selectedNodeID = graph.nodes.first(where: matchesNodeListFilters)?.id
            ?? graph.preferredRootID
            ?? graph.nodes.first?.id
    }

    private enum PreferencesKey: String {
        case direction
        case depth
        case presentationMode
        case showOnlyActivePaths
        case includeExternal
        case searchText
        case selectedLayerFilter
        case selectedNodeID
        case selectedLevel
        case lastProjectPath
        case zoomScale
        case skippedAppUpdateVersion
        case lastAppUpdateCheckAt
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
                    primaryLayer: nil,
                    layerSource: nil,
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
                    primaryLayer: "feature",
                    layerSource: .metadataTag,
                    metadataTags: [],
                    suggestedLayer: "feature",
                    suggestedLayerSource: .metadataTag
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
                    primaryLayer: "feature",
                    layerSource: .metadataTag,
                    metadataTags: [],
                    suggestedLayer: "feature",
                    suggestedLayerSource: .metadataTag
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
                    primaryLayer: "foundation",
                    layerSource: .metadataTag,
                    metadataTags: [],
                    suggestedLayer: "foundation",
                    suggestedLayerSource: .metadataTag
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
                    primaryLayer: nil,
                    layerSource: nil,
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
