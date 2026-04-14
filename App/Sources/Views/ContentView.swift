import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = TuistSpiderViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

            Divider()

            HSplitView {
                sidebar
                    .frame(minWidth: 280, idealWidth: 320)

                graphPane
                    .frame(minWidth: 620, idealWidth: 860)

                inspector
                    .frame(minWidth: 300, idealWidth: 340)
            }
        }
        .frame(minWidth: 1260, minHeight: 780)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .center) {
            if viewModel.isLoading {
                loadingOverlay
            }
        }
        .alert(item: $viewModel.presentedError) { error in
            Alert(
                title: Text("작업 실패"),
                message: Text(error.errorDescription ?? "알 수 없는 오류입니다.")
            )
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("TuistSpider")
                    .font(.system(size: 24, weight: .bold))
                Text(viewModel.statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 20)

            Button("프로젝트 열기") {
                viewModel.chooseTuistProject()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Button("JSON 열기") {
                viewModel.chooseJSONFile()
            }
            .keyboardShortcut("o")

            Button("새로고침") {
                viewModel.reloadCurrentProject()
            }
            .disabled(viewModel.currentProjectURL == nil && viewModel.lastProjectPath == nil)

            Button("샘플") {
                viewModel.loadSample()
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("모듈 검색", text: $viewModel.searchText)
                        .textFieldStyle(.roundedBorder)

                    Picker("방향", selection: $viewModel.direction) {
                        ForEach(GraphDirection.allCases) { direction in
                            Text(direction.title).tag(direction)
                        }
                    }

                    Picker("깊이", selection: $viewModel.depth) {
                        ForEach(viewModel.availableDepthOptions) { depth in
                            Text(depth.title).tag(depth)
                        }
                    }

                    Picker("레이어", selection: $viewModel.selectedLayerFilter) {
                        ForEach(viewModel.layerFilterOptions) { option in
                            Text("\(option.filter.title) (\(option.count))")
                                .tag(option.filter)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("표현 방식")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Picker("표현 방식", selection: $viewModel.presentationMode) {
                            ForEach(GraphPresentationMode.allCases) { mode in
                                Text(mode.shortTitle).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    Toggle("외부 의존성 포함", isOn: $viewModel.includeExternal)

                    if !viewModel.graph.warnings.isEmpty {
                        Label("레이어 경고 \(viewModel.graph.warnings.count)건", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .help(viewModel.graph.warnings.joined(separator: "\n"))
                    }

                    Button("뷰 초기화") {
                        viewModel.resetView()
                    }
                }
            } label: {
                Text("필터")
            }

            HStack(spacing: 10) {
                statCard(title: "전체 노드", value: "\(viewModel.totalNodeCount)")
                statCard(title: "현재 노드", value: "\(viewModel.visibleNodeCount)")
            }
            HStack(spacing: 10) {
                statCard(title: "전체 간선", value: "\(viewModel.totalEdgeCount)")
                statCard(title: "현재 간선", value: "\(viewModel.visibleEdgeCount)")
            }

            List(selection: Binding(get: {
                viewModel.selectedNodeID
            }, set: { newValue in
                if let newValue {
                    viewModel.selectNode(newValue)
                }
            })) {
                ForEach(viewModel.filteredNodes) { node in
                    SidebarNodeRow(node: node)
                        .tag(node.id)
                }
            }
            .listStyle(.sidebar)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.25))
    }

    private var graphPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.graph.graphName)
                    .font(.title2.weight(.bold))
                Text(viewModel.sourceLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(viewModel.currentPathLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            GraphCanvasView(
                subgraph: viewModel.displayedSubgraph,
                presentationMode: viewModel.presentationMode,
                focusedNodeID: viewModel.selectedNodeID,
                graphSelectedNodeID: viewModel.visibleGraphSelectedNodeID,
                selectedLevel: viewModel.selectedLevel,
                connectionPaths: viewModel.activeConnectionPaths,
                hasConnectionPathContext: viewModel.graphSelectedNode != nil && !viewModel.connectionPaths.isEmpty,
                focusRequestID: viewModel.viewportCenterRequestID,
                zoomScale: $viewModel.zoomScale,
                onSelect: { nodeID in
                    viewModel.selectGraphNode(nodeID)
                },
                onSelectLevel: { level in
                    viewModel.selectLevel(level)
                }
            )
        }
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if viewModel.presentationMode == .grouped, let levelGroup = viewModel.selectedLevelGroup {
                    groupedInspector(levelGroup: levelGroup)
                } else if let node = viewModel.inspectedNode {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(node.name)
                            .font(.title3.weight(.bold))
                        Text(node.kindLabel.uppercased())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        LayerBadge(layerName: node.primaryLayer)
                        Text(node.projectPath ?? "External dependency")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    if let focusedNode = viewModel.selectedNode {
                        relatedNodeSearchSection(focusedNode: focusedNode)
                    }

                    if let focusedNode = viewModel.selectedNode,
                       let targetNode = viewModel.graphSelectedNode,
                       !viewModel.connectionPaths.isEmpty {
                        connectionPathsSection(focusedNode: focusedNode, targetNode: targetNode)
                    }

                    HStack(spacing: 10) {
                        statCard(title: "직접 의존", value: "\(viewModel.directDependencies.count)")
                        statCard(title: "직접 역의존", value: "\(viewModel.directDependents.count)")
                    }

                    dependencySection(title: "직접 의존성", nodes: viewModel.directDependencies)
                    dependencySection(title: "직접 역의존성", nodes: viewModel.directDependents)
                    if viewModel.canEditLayerClassification(for: node) {
                        layerEditorSection(node: node)
                    }
                    metadataSection(node: node)
                } else {
                    ContentUnavailableView(
                        "모듈을 선택하세요",
                        systemImage: "sidebar.leading",
                        description: Text("왼쪽 목록이나 중앙 그래프에서 모듈을 고르면 상세 정보가 나타납니다.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.18))
    }

    private var loadingOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.08))
                .ignoresSafeArea()

            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.large)
                Text(viewModel.statusMessage)
                    .font(.headline)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func groupedInspector(levelGroup: SpiderGraphLevelGroup) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(levelGroup.title)
                    .font(.title3.weight(.bold))
                Text("기준 모듈: \(viewModel.selectedNode?.name ?? "-")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(levelDescription(levelGroup.level))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                statCard(title: "포함 모듈", value: "\(levelGroup.nodes.count)")
                statCard(title: "내부 연결", value: "\(levelGroup.internalEdgeCount)")
            }

            levelLayerSummarySection(levelGroup: levelGroup)
            levelNodesSection(levelGroup: levelGroup)
        }
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func dependencySection(title: String, nodes: [SpiderGraphNode]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            if nodes.isEmpty {
                Text("없음")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                ForEach(nodes) { node in
                    Button {
                        viewModel.selectNode(node.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(node.name)
                                    .foregroundStyle(.primary)
                                HStack(spacing: 6) {
                                    Text(node.projectLabel)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    LayerBadge(layerName: node.primaryLayer, font: .caption2)
                                }
                            }
                            Spacer()
                            Text(node.kindLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func connectionPathsSection(focusedNode: SpiderGraphNode, targetNode: SpiderGraphNode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("연결 경로")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.activeConnectionPathCount) / \(viewModel.connectionPaths.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text("\(focusedNode.name) -> \(targetNode.name)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let relationship = viewModel.connectionDirection {
                VStack(alignment: .leading, spacing: 8) {
                    Text("의존성 방향")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(alignment: .center, spacing: 10) {
                        Text(relationship.badgeText)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(directionColor(for: relationship))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(directionColor(for: relationship).opacity(0.14), in: Capsule())

                        Text(relationship.description(focusedName: focusedNode.name, selectedName: targetNode.name))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            HStack(spacing: 8) {
                Button("전체 보기") {
                    viewModel.showAllConnectionPaths()
                }
                .buttonStyle(.bordered)

                Button("모두 숨김") {
                    viewModel.hideAllConnectionPaths()
                }
                .buttonStyle(.bordered)
            }

            Toggle("선택 경로만 보기", isOn: $viewModel.showOnlyActivePaths)
                .toggleStyle(.switch)
                .disabled(viewModel.connectionPaths.isEmpty)

            if viewModel.showOnlyActivePaths {
                Text("활성화된 경로에 포함된 노드와 간선만 그래프에 남깁니다. Shift + 클릭으로 경로를 추가하거나 제거할 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if viewModel.hasTruncatedConnectionPaths {
                VStack(alignment: .leading, spacing: 8) {
                    Text("경로가 많아 상위 \(viewModel.connectionPathLimit)개만 표시합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Button("더 보기 (+\(TuistSpiderViewModel.connectionPathLimitStep))") {
                            viewModel.increaseConnectionPathLimit()
                        }
                        .buttonStyle(.bordered)

                        if viewModel.isUsingExpandedConnectionPathLimit {
                            Button("초기값") {
                                viewModel.resetConnectionPathLimit()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            } else if viewModel.isUsingExpandedConnectionPathLimit {
                Button("경로 제한 초기화") {
                    viewModel.resetConnectionPathLimit()
                }
                .buttonStyle(.bordered)
            }

            ForEach(viewModel.connectionPaths) { path in
                Button {
                    viewModel.toggleConnectionPath(
                        path.id,
                        additiveSelection: viewModel.showOnlyActivePaths && NSEvent.modifierFlags.contains(.shift)
                    )
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(GraphPathPalette.color(at: path.paletteIndex))
                            .frame(width: 10, height: 28)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("경로 \(path.paletteIndex + 1)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(path.kind.badgeText)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(GraphPathPalette.color(at: path.paletteIndex))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        GraphPathPalette.color(at: path.paletteIndex).opacity(0.14),
                                        in: Capsule()
                                    )
                                Spacer()
                                Text("\(path.edgeCount) hops")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text(path.preview(using: viewModel.graph.nodeMap))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(3)
                        }

                        Image(systemName: viewModel.isConnectionPathVisible(path.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(viewModel.isConnectionPathVisible(path.id) ? GraphPathPalette.color(at: path.paletteIndex) : .secondary)
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func relatedNodeSearchSection(focusedNode: SpiderGraphNode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("연관 노드 검색")
                    .font(.headline)
                Spacer()
                if let selectedNode = viewModel.graphSelectedNode {
                    Button("선택 해제") {
                        viewModel.clearRelatedNodeSelection()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Text(selectedNode.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Text("\(focusedNode.name) 기준으로 현재 그래프 범위 안에서 비교할 노드를 찾습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("연관 노드 검색", text: $viewModel.relatedNodeSearchText)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    viewModel.selectFirstMatchingRelatedNode()
                }

            if viewModel.relatedNodeSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("이름이나 프로젝트명으로 검색하면 현재 그래프에 보이는 노드만 후보로 나옵니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if viewModel.filteredRelatedNodes.isEmpty {
                Text("현재 필터 범위에서 일치하는 노드가 없습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    RelatedNodeSearchResults(
                        nodes: viewModel.filteredRelatedNodesPreview,
                        selectedNodeID: viewModel.visibleGraphSelectedNodeID,
                        onSelect: { nodeID in
                            viewModel.selectRelatedNode(nodeID)
                        }
                    )

                    if viewModel.filteredRelatedNodes.count > 8 {
                        Text("검색 결과 \(viewModel.filteredRelatedNodes.count)개 중 상위 8개만 표시합니다. 더 좁게 검색해보세요.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func layerEditorSection(node: SpiderGraphNode) -> some View {
        LayerEditorSection(
            node: node,
            availableLayers: viewModel.availableLayerOptions(for: node),
            onSelectLayer: { layerName in
                viewModel.applyLayerClassification(for: node.id, layerName: layerName)
            },
            onApplyCustomLayer: { layerName in
                viewModel.applyLayerClassification(for: node.id, layerName: layerName)
            },
            onResetToSuggested: {
                viewModel.resetLayerClassificationToSuggested(for: node.id)
            }
        )
        .id(node.id)
    }

    private func metadataSection(node: SpiderGraphNode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("메타데이터")
                .font(.headline)

            metadataRow(title: "Applied Layer", value: node.layerLabel)
            metadataRow(title: "Applied Source", value: node.layerSourceLabel ?? "-")
            metadataRow(title: "Suggested Layer", value: node.suggestedLayerLabel)
            metadataRow(title: "Suggested Source", value: node.suggestedLayerSourceLabel ?? "-")
            metadataRow(title: "Classification", value: node.hasSavedLayerOverride ? "Saved Override" : "Suggested Value")
            metadataRow(title: "Kind", value: node.kindLabel)
            metadataRow(title: "Project", value: node.projectLabel)
            metadataRow(title: "Bundle ID", value: node.bundleId ?? "-")
            metadataRow(title: "Sources", value: "\(node.sourceCount)")
            metadataRow(title: "Resources", value: "\(node.resourceCount)")
            metadataRow(title: "Tags (read-only)", value: node.metadataTags.isEmpty ? "-" : node.metadataTags.joined(separator: ", "))
        }
    }

    private func levelLayerSummarySection(levelGroup: SpiderGraphLevelGroup) -> some View {
        let items = Dictionary(grouping: levelGroup.nodes, by: \.layerLabel)
            .map { key, value in
                (name: key, count: value.count)
            }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

        return VStack(alignment: .leading, spacing: 10) {
            Text("레이어 구성")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                ForEach(items, id: \.name) { item in
                    HStack(spacing: 8) {
                        LayerBadge(layerName: item.name == TuistSpiderViewModel.unclassifiedLayerTitle ? nil : item.name)
                        Spacer(minLength: 0)
                        Text("\(item.count)개")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private func metadataRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func levelNodesSection(levelGroup: SpiderGraphLevelGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("계층 포함 모듈")
                .font(.headline)

            ForEach(levelGroup.nodes) { node in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(node.name)
                            .foregroundStyle(.primary)
                        HStack(spacing: 6) {
                            Text(node.projectLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            LayerBadge(layerName: node.primaryLayer, font: .caption2)
                        }
                    }
                    Spacer()
                    Text(node.kindLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func levelDescription(_ level: Int) -> String {
        switch level {
        case 0:
            return "현재 기준 모듈이 속한 계층입니다."
        case let value where value < 0:
            return "기준 모듈을 참조하는 모듈들의 \(abs(value))단계 계층입니다."
        default:
            return "기준 모듈이 의존하는 모듈들의 \(level)단계 계층입니다."
        }
    }

    private func directionColor(for relationship: SpiderGraphRelationshipDirection) -> Color {
        switch relationship {
        case .focusedDependsOnSelection:
            return .blue
        case .selectionDependsOnFocused:
            return .green
        case .bidirectional:
            return .orange
        case .mixed:
            return .purple
        }
    }
}

private struct LayerEditorSection: View {
    private static let unclassifiedToken = "__tuist_spider_unclassified__"

    let node: SpiderGraphNode
    let availableLayers: [String]
    let onSelectLayer: (String?) -> Void
    let onApplyCustomLayer: (String) -> Void
    let onResetToSuggested: () -> Void

    @State private var customLayerName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("레이어 분류")
                    .font(.headline)
                Spacer()
                if node.hasSavedLayerOverride {
                    Text("Saved Override")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.14), in: Capsule())
                }
            }

            Picker("적용 레이어", selection: appliedLayerSelection) {
                Text(TuistSpiderViewModel.unclassifiedLayerTitle).tag(Self.unclassifiedToken)
                ForEach(availableLayers, id: \.self) { layer in
                    Text(layer).tag(layer)
                }
            }
            .pickerStyle(.menu)

            HStack(spacing: 8) {
                TextField("Custom layer", text: $customLayerName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(applyCustomLayer)

                Button("적용") {
                    applyCustomLayer()
                }
                .buttonStyle(.borderedProminent)
                .disabled(normalizedCustomLayerName == nil || normalizedCustomLayerName == node.primaryLayer)
            }

            HStack(spacing: 8) {
                Button("Reset to Suggested") {
                    onResetToSuggested()
                }
                .buttonStyle(.bordered)
                .disabled(!node.hasSavedLayerOverride)

                Text("자동 제안: \(node.suggestedLayerLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var appliedLayerSelection: Binding<String> {
        Binding(
            get: { node.primaryLayer ?? Self.unclassifiedToken },
            set: { selection in
                onSelectLayer(selection == Self.unclassifiedToken ? nil : selection)
            }
        )
    }

    private var normalizedCustomLayerName: String? {
        let trimmed = customLayerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func applyCustomLayer() {
        guard let normalizedCustomLayerName else { return }
        onApplyCustomLayer(normalizedCustomLayerName)
        customLayerName = ""
    }
}

private struct RelatedNodeSearchResults: View {
    let nodes: [SpiderGraphNode]
    let selectedNodeID: String?
    let onSelect: (String) -> Void

    var body: some View {
        Group {
            if let node = node(at: 0) { relatedNodeButton(node) }
            if let node = node(at: 1) { relatedNodeButton(node) }
            if let node = node(at: 2) { relatedNodeButton(node) }
            if let node = node(at: 3) { relatedNodeButton(node) }
            if let node = node(at: 4) { relatedNodeButton(node) }
            if let node = node(at: 5) { relatedNodeButton(node) }
            if let node = node(at: 6) { relatedNodeButton(node) }
            if let node = node(at: 7) { relatedNodeButton(node) }
        }
    }

    private func node(at index: Int) -> SpiderGraphNode? {
        guard nodes.indices.contains(index) else { return nil }
        return nodes[index]
    }

    private func relatedNodeButton(_ node: SpiderGraphNode) -> some View {
        Button {
            onSelect(node.id)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(node.name)
                        .foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        Text(node.projectLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        LayerBadge(layerName: node.primaryLayer, font: .caption2)
                    }
                }
                Spacer()
                if selectedNodeID == node.id {
                    Image(systemName: "scope")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct SidebarNodeRow: View {
    let node: SpiderGraphNode

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(node.name)
                    .font(.body.weight(.semibold))
                HStack(spacing: 6) {
                    Text(node.projectLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LayerBadge(layerName: node.primaryLayer, font: .caption2)
                }
            }
            Spacer()
            Text(node.kindLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct LayerBadge: View {
    let layerName: String?
    var font: Font = .caption2.weight(.semibold)

    var body: some View {
        Text(layerName ?? TuistSpiderViewModel.unclassifiedLayerTitle)
            .font(font)
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(badgeColor.opacity(0.16), in: Capsule())
    }

    private var badgeColor: Color {
        LayerColorPalette.color(for: layerName)
    }
}
