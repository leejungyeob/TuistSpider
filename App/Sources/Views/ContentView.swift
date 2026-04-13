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
                        ForEach(GraphDepth.allCases) { depth in
                            Text(depth.title).tag(depth)
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
                subgraph: viewModel.visibleSubgraph,
                presentationMode: viewModel.presentationMode,
                selectedNodeID: viewModel.selectedNodeID,
                selectedLevel: viewModel.selectedLevel,
                zoomScale: $viewModel.zoomScale,
                onSelect: { nodeID in
                    viewModel.selectNode(nodeID)
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
                } else if let node = viewModel.selectedNode {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(node.name)
                            .font(.title3.weight(.bold))
                        Text(node.kindLabel.uppercased())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(node.projectPath ?? "External dependency")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    HStack(spacing: 10) {
                        statCard(title: "직접 의존", value: "\(viewModel.directDependencies.count)")
                        statCard(title: "직접 역의존", value: "\(viewModel.directDependents.count)")
                    }

                    dependencySection(title: "직접 의존성", nodes: viewModel.directDependencies)
                    dependencySection(title: "직접 역의존성", nodes: viewModel.directDependents)
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
                                Text(node.projectLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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

    private func metadataSection(node: SpiderGraphNode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("메타데이터")
                .font(.headline)

            metadataRow(title: "Kind", value: node.kindLabel)
            metadataRow(title: "Project", value: node.projectLabel)
            metadataRow(title: "Bundle ID", value: node.bundleId ?? "-")
            metadataRow(title: "Sources", value: "\(node.sourceCount)")
            metadataRow(title: "Resources", value: "\(node.resourceCount)")
            metadataRow(title: "Tags", value: node.metadataTags.isEmpty ? "-" : node.metadataTags.joined(separator: ", "))
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
                        Text(node.projectLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
}

private struct SidebarNodeRow: View {
    let node: SpiderGraphNode

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(node.name)
                    .font(.body.weight(.semibold))
                Text(node.projectLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(node.kindLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
