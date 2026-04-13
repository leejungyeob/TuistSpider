import CoreGraphics
import Foundation

struct SpiderGraphNode: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let displayName: String
    let kind: String
    let product: String?
    let bundleId: String?
    let projectName: String?
    let projectPath: String?
    let isExternal: Bool
    let sourceCount: Int
    let resourceCount: Int
    let metadataTags: [String]

    var kindLabel: String {
        if kind == "target" {
            return product ?? "target"
        }
        return kind
    }

    var projectLabel: String {
        projectName ?? "External"
    }
}

struct SpiderGraphEdge: Hashable, Identifiable, Sendable {
    let from: String
    let to: String
    let kind: String
    let status: String?

    var id: String {
        "\(from)->\(to)::\(kind)::\(status ?? "none")"
    }
}

enum GraphDirection: String, CaseIterable, Identifiable, Sendable {
    case both
    case dependencies
    case dependents

    var id: String { rawValue }

    var title: String {
        switch self {
        case .both:
            return "양방향"
        case .dependencies:
            return "의존하는 쪽"
        case .dependents:
            return "의존받는 쪽"
        }
    }
}

enum GraphDepth: String, CaseIterable, Identifiable, Sendable {
    case one = "1"
    case two = "2"
    case three = "3"
    case all = "all"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .one:
            return "1 단계"
        case .two:
            return "2 단계"
        case .three:
            return "3 단계"
        case .all:
            return "전체"
        }
    }

    var maxDepth: Int? {
        switch self {
        case .one:
            return 1
        case .two:
            return 2
        case .three:
            return 3
        case .all:
            return nil
        }
    }
}

enum GraphPresentationMode: String, CaseIterable, Identifiable, Sendable {
    case expanded
    case grouped

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expanded:
            return "펼쳐서 보기"
        case .grouped:
            return "계층 묶음"
        }
    }

    var shortTitle: String {
        switch self {
        case .expanded:
            return "펼침"
        case .grouped:
            return "계층"
        }
    }
}

struct SpiderGraphSubgraph: Sendable {
    let nodes: [SpiderGraphNode]
    let edges: [SpiderGraphEdge]
    let levels: [String: Int]

    var levelGroups: [SpiderGraphLevelGroup] {
        var groupedNodes: [Int: [SpiderGraphNode]] = [:]
        for node in nodes {
            groupedNodes[levels[node.id] ?? 0, default: []].append(node)
        }

        return groupedNodes.keys.sorted().map { level in
            let levelNodes = (groupedNodes[level] ?? []).sorted(by: SpiderGraph.nodeSort)
            let internalEdgeCount = edges.reduce(into: 0) { count, edge in
                guard levels[edge.from] == level, levels[edge.to] == level else { return }
                count += 1
            }

            return SpiderGraphLevelGroup(
                level: level,
                nodes: levelNodes,
                internalEdgeCount: internalEdgeCount
            )
        }
    }

    var levelEdges: [SpiderGraphLevelEdge] {
        var counts: [SpiderGraphLevelPair: Int] = [:]

        for edge in edges {
            let fromLevel = levels[edge.from] ?? 0
            let toLevel = levels[edge.to] ?? 0
            guard fromLevel != toLevel else { continue }
            counts[SpiderGraphLevelPair(fromLevel: fromLevel, toLevel: toLevel), default: 0] += 1
        }

        return counts.map { pair, count in
            SpiderGraphLevelEdge(
                fromLevel: pair.fromLevel,
                toLevel: pair.toLevel,
                edgeCount: count
            )
        }
        .sorted { lhs, rhs in
            if lhs.fromLevel != rhs.fromLevel { return lhs.fromLevel < rhs.fromLevel }
            return lhs.toLevel < rhs.toLevel
        }
    }
}

struct SpiderGraphLevelGroup: Identifiable, Hashable, Sendable {
    let level: Int
    let nodes: [SpiderGraphNode]
    let internalEdgeCount: Int

    var id: Int { level }

    var title: String {
        switch level {
        case 0:
            return "기준 계층"
        case let value where value < 0:
            return "역의존 \(abs(value)) 단계"
        default:
            return "의존 \(level) 단계"
        }
    }

    var badge: String {
        switch level {
        case 0:
            return "L0"
        case let value where value < 0:
            return "L\(value)"
        default:
            return "L+\(level)"
        }
    }
}

struct SpiderGraphLevelEdge: Identifiable, Hashable, Sendable {
    let fromLevel: Int
    let toLevel: Int
    let edgeCount: Int

    var id: String { "\(fromLevel)->\(toLevel)" }
}

private struct SpiderGraphLevelPair: Hashable, Sendable {
    let fromLevel: Int
    let toLevel: Int
}

struct SpiderGraphCanvasLayout: Sendable {
    let nodeFrames: [String: CGRect]
    let canvasSize: CGSize

    static func make(for nodes: [SpiderGraphNode], levels: [String: Int]) -> SpiderGraphCanvasLayout {
        let nodeWidth: CGFloat = 220
        let nodeHeight: CGFloat = 72
        let columnGap: CGFloat = 280
        let rowGap: CGFloat = 110
        let paddingX: CGFloat = 120
        let paddingY: CGFloat = 100

        var groups: [Int: [SpiderGraphNode]] = [:]
        for node in nodes {
            let level = levels[node.id] ?? 0
            groups[level, default: []].append(node)
        }

        let orderedLevels = groups.keys.sorted()
        for level in orderedLevels {
            groups[level]?.sort(by: SpiderGraph.nodeSort)
        }

        let maxColumnSize = max(orderedLevels.compactMap { groups[$0]?.count }.max() ?? 0, 1)
        let width = paddingX * 2 + CGFloat(max(orderedLevels.count - 1, 1)) * columnGap + nodeWidth
        let height = paddingY * 2 + CGFloat(max(maxColumnSize - 1, 1)) * rowGap + nodeHeight
        let centerY = height / 2

        var nodeFrames: [String: CGRect] = [:]
        for (columnIndex, level) in orderedLevels.enumerated() {
            let columnNodes = groups[level] ?? []
            let columnHeight = CGFloat(max(columnNodes.count - 1, 0)) * rowGap
            let startY = centerY - columnHeight / 2
            for (rowIndex, node) in columnNodes.enumerated() {
                let origin = CGPoint(
                    x: paddingX + CGFloat(columnIndex) * columnGap,
                    y: startY + CGFloat(rowIndex) * rowGap
                )
                nodeFrames[node.id] = CGRect(origin: origin, size: CGSize(width: nodeWidth, height: nodeHeight))
            }
        }

        return SpiderGraphCanvasLayout(nodeFrames: nodeFrames, canvasSize: CGSize(width: width, height: height))
    }
}

struct SpiderGraphLevelCanvasLayout: Sendable {
    let groupFrames: [Int: CGRect]
    let canvasSize: CGSize

    static func make(for groups: [SpiderGraphLevelGroup]) -> SpiderGraphLevelCanvasLayout {
        let cardWidth: CGFloat = 240
        let cardHeight: CGFloat = 116
        let columnGap: CGFloat = 300
        let paddingX: CGFloat = 140
        let paddingY: CGFloat = 140

        let orderedGroups = groups.sorted { $0.level < $1.level }
        let width = paddingX * 2 + CGFloat(max(orderedGroups.count - 1, 1)) * columnGap + cardWidth
        let height = paddingY * 2 + cardHeight
        let originY = (height - cardHeight) / 2

        var groupFrames: [Int: CGRect] = [:]
        for (index, group) in orderedGroups.enumerated() {
            let origin = CGPoint(
                x: paddingX + CGFloat(index) * columnGap,
                y: originY
            )
            groupFrames[group.level] = CGRect(origin: origin, size: CGSize(width: cardWidth, height: cardHeight))
        }

        return SpiderGraphLevelCanvasLayout(groupFrames: groupFrames, canvasSize: CGSize(width: width, height: height))
    }
}

struct SpiderGraph: Hashable, Sendable {
    let graphName: String
    let sourceFormat: String
    let rootPath: String?
    let generatedAt: String?
    let nodes: [SpiderGraphNode]
    let edges: [SpiderGraphEdge]
    let nodeMap: [String: SpiderGraphNode]
    let outgoing: [String: [String]]
    let incoming: [String: [String]]

    init(
        graphName: String,
        sourceFormat: String,
        rootPath: String?,
        generatedAt: String?,
        nodes: [SpiderGraphNode],
        edges: [SpiderGraphEdge]
    ) {
        self.graphName = graphName
        self.sourceFormat = sourceFormat
        self.rootPath = rootPath
        self.generatedAt = generatedAt
        self.nodes = nodes.sorted(by: SpiderGraph.nodeSort)
        self.edges = edges.sorted { lhs, rhs in
            if lhs.from != rhs.from { return lhs.from < rhs.from }
            if lhs.to != rhs.to { return lhs.to < rhs.to }
            return lhs.kind < rhs.kind
        }

        var nodeMap: [String: SpiderGraphNode] = [:]
        for node in self.nodes {
            nodeMap[node.id] = node
        }
        self.nodeMap = nodeMap

        var outgoing: [String: [String]] = [:]
        var incoming: [String: [String]] = [:]
        for node in self.nodes {
            outgoing[node.id] = []
            incoming[node.id] = []
        }
        for edge in self.edges where nodeMap[edge.from] != nil && nodeMap[edge.to] != nil {
            outgoing[edge.from, default: []].append(edge.to)
            incoming[edge.to, default: []].append(edge.from)
        }
        self.outgoing = outgoing
        self.incoming = incoming
    }

    var preferredRootID: String? {
        nodes.first(where: { !$0.isExternal })?.id ?? nodes.first?.id
    }

    func directDependencies(of nodeID: String, includeExternal: Bool) -> [SpiderGraphNode] {
        let ids = outgoing[nodeID] ?? []
        return ids.compactMap { nodeMap[$0] }
            .filter { includeExternal || !$0.isExternal }
            .sorted(by: SpiderGraph.nodeSort)
    }

    func directDependents(of nodeID: String, includeExternal: Bool) -> [SpiderGraphNode] {
        let ids = incoming[nodeID] ?? []
        return ids.compactMap { nodeMap[$0] }
            .filter { includeExternal || !$0.isExternal }
            .sorted(by: SpiderGraph.nodeSort)
    }

    func subgraph(
        centeredOn rootID: String,
        direction: GraphDirection,
        depth: GraphDepth,
        includeExternal: Bool
    ) -> SpiderGraphSubgraph {
        guard nodeMap[rootID] != nil else {
            return SpiderGraphSubgraph(nodes: [], edges: [], levels: [:])
        }

        func allows(_ nodeID: String) -> Bool {
            guard let node = nodeMap[nodeID] else { return false }
            return includeExternal || !node.isExternal || nodeID == rootID
        }

        var levels: [String: Int] = [rootID: 0]
        if direction != .dependencies {
            for (nodeID, distance) in bfs(from: rootID, adjacency: incoming, depth: depth, allows: allows) {
                levels[nodeID] = -distance
            }
        }
        if direction != .dependents {
            for (nodeID, distance) in bfs(from: rootID, adjacency: outgoing, depth: depth, allows: allows) {
                let current = levels[nodeID]
                if current == nil || abs(distance) < abs(current ?? distance) {
                    levels[nodeID] = distance
                }
            }
        }

        var nodeIDs = Set(levels.keys.filter(allows))
        nodeIDs.insert(rootID)

        let nodes = nodeIDs.compactMap { nodeMap[$0] }.sorted(by: SpiderGraph.nodeSort)
        let edges = edges.filter { nodeIDs.contains($0.from) && nodeIDs.contains($0.to) }
        return SpiderGraphSubgraph(nodes: nodes, edges: edges, levels: levels)
    }

    private func bfs(
        from startID: String,
        adjacency: [String: [String]],
        depth: GraphDepth,
        allows: (String) -> Bool
    ) -> [String: Int] {
        let maxDepth = depth.maxDepth ?? Int.max
        var seen: [String: Int] = [:]
        var queue: [(nodeID: String, distance: Int)] = [(startID, 0)]
        var index = 0

        while index < queue.count {
            let entry = queue[index]
            index += 1
            if entry.distance >= maxDepth { continue }

            for nextID in adjacency[entry.nodeID] ?? [] {
                guard allows(nextID), seen[nextID] == nil else { continue }
                let nextDistance = entry.distance + 1
                seen[nextID] = nextDistance
                queue.append((nextID, nextDistance))
            }
        }

        return seen
    }

    static func nodeSort(_ lhs: SpiderGraphNode, _ rhs: SpiderGraphNode) -> Bool {
        if lhs.isExternal != rhs.isExternal {
            return !lhs.isExternal && rhs.isExternal
        }
        let leftProject = lhs.projectName ?? ""
        let rightProject = rhs.projectName ?? ""
        if leftProject != rightProject {
            return leftProject.localizedCaseInsensitiveCompare(rightProject) == .orderedAscending
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}
