import AppKit
import Foundation

@MainActor
final class TuistSpiderViewModel: ObservableObject {
    static let defaultZoomScale = 1.0
    static let zoomScaleRange: ClosedRange<Double> = 0.5...2.0
    static let zoomStep = 0.15

    @Published private(set) var graph = SampleGraph.make()
    @Published var selectedNodeID: String? {
        didSet { persistPreferences() }
    }
    @Published var direction: GraphDirection = .both {
        didSet { persistPreferences() }
    }
    @Published var depth: GraphDepth = .all {
        didSet { persistPreferences() }
    }
    @Published var presentationMode: GraphPresentationMode = .expanded {
        didSet { persistPreferences() }
    }
    @Published var includeExternal = false {
        didSet { persistPreferences() }
    }
    @Published var searchText = "" {
        didSet { persistPreferences() }
    }
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
    @Published var presentedError: SpiderGraphImportError?

    private let exportService = TuistGraphExportService()
    private let preferences = UserDefaults.standard

    init() {
        restorePreferences()
        selectedNodeID = selectedNodeID ?? graph.preferredRootID
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

    var selectedNode: SpiderGraphNode? {
        guard let selectedNodeID else { return nil }
        return graph.nodeMap[selectedNodeID]
    }

    var visibleSubgraph: SpiderGraphSubgraph {
        guard let selectedNodeID else {
            return SpiderGraphSubgraph(nodes: [], edges: [], levels: [:])
        }
        return graph.subgraph(centeredOn: selectedNodeID, direction: direction, depth: depth, includeExternal: includeExternal)
    }

    var directDependencies: [SpiderGraphNode] {
        guard let selectedNodeID else { return [] }
        return graph.directDependencies(of: selectedNodeID, includeExternal: includeExternal)
    }

    var directDependents: [SpiderGraphNode] {
        guard let selectedNodeID else { return [] }
        return graph.directDependents(of: selectedNodeID, includeExternal: includeExternal)
    }

    var visibleLevelGroups: [SpiderGraphLevelGroup] {
        visibleSubgraph.levelGroups
    }

    var selectedLevelGroup: SpiderGraphLevelGroup? {
        visibleLevelGroups.first(where: { $0.level == selectedLevel })
        ?? visibleLevelGroups.first(where: { $0.level == 0 })
        ?? visibleLevelGroups.first
    }

    var totalNodeCount: Int { graph.nodes.count }
    var totalEdgeCount: Int { graph.edges.count }
    var visibleNodeCount: Int { visibleSubgraph.nodes.count }
    var visibleEdgeCount: Int { visibleSubgraph.edges.count }

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
        graph = SampleGraph.make()
        selectedNodeID = graph.preferredRootID
        selectedLevel = 0
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
        zoomScale = Self.defaultZoomScale
        selectedLevel = 0
        selectedNodeID = graph.preferredRootID
        statusMessage = "뷰를 초기화했습니다."
    }

    func selectNode(_ nodeID: String) {
        selectedNodeID = nodeID
        selectedLevel = 0
    }

    func selectLevel(_ level: Int) {
        selectedLevel = level
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

                apply(graph: graph)
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

                apply(graph: graph)
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

    private func apply(graph: SpiderGraph) {
        self.graph = graph
        if let selectedNodeID, graph.nodeMap[selectedNodeID] != nil {
            self.selectedNodeID = selectedNodeID
        } else {
            self.selectedNodeID = graph.preferredRootID
        }
        self.selectedLevel = 0
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
        preferences.set(includeExternal, forKey: PreferencesKey.includeExternal.rawValue)
        preferences.set(searchText, forKey: PreferencesKey.searchText.rawValue)
        preferences.set(selectedNodeID, forKey: PreferencesKey.selectedNodeID.rawValue)
        preferences.set(selectedLevel, forKey: PreferencesKey.selectedLevel.rawValue)
        preferences.set(zoomScale, forKey: PreferencesKey.zoomScale.rawValue)
    }

    private static func clampZoomScale(_ value: Double) -> Double {
        min(max(value, zoomScaleRange.lowerBound), zoomScaleRange.upperBound)
    }

    private enum PreferencesKey: String {
        case direction
        case depth
        case presentationMode
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
