import CoreGraphics
import Foundation

enum SpiderGraphLayerSource: String, Hashable, Sendable {
    case metadataTag = "metadata-tag"
    case projectSnapshot = "project-snapshot"
    case inferredPath = "inferred-path"
    case inferredName = "inferred-name"
    case inferredProduct = "inferred-product"
    case normalizedNode = "normalized-node"

    var label: String {
        switch self {
        case .metadataTag:
            return "metadata.tags"
        case .projectSnapshot:
            return "project snapshot"
        case .inferredPath:
            return "inferred from path"
        case .inferredName:
            return "inferred from name"
        case .inferredProduct:
            return "inferred from product"
        case .normalizedNode:
            return "normalized node"
        }
    }
}

enum SpiderGraphLayerFilter: Hashable, Identifiable, Sendable {
    case all
    case newModules
    case unclassified
    case layer(String)

    init?(persistedValue: String) {
        switch persistedValue {
        case "all":
            self = .all
        case "new-modules":
            self = .newModules
        case "unclassified":
            self = .unclassified
        default:
            let prefix = "layer:"
            guard persistedValue.hasPrefix(prefix) else { return nil }
            let value = String(persistedValue.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            self = .layer(value)
        }
    }

    var id: String { persistedValue }

    var persistedValue: String {
        switch self {
        case .all:
            return "all"
        case .newModules:
            return "new-modules"
        case .unclassified:
            return "unclassified"
        case let .layer(name):
            return "layer:\(name)"
        }
    }

    var title: String {
        switch self {
        case .all:
            return "전체"
        case .newModules:
            return SpiderGraphNode.newModulesLayerTitle
        case .unclassified:
            return "Unclassified"
        case let .layer(name):
            return name
        }
    }

    func matches(_ node: SpiderGraphNode) -> Bool {
        switch self {
        case .all:
            return true
        case .newModules:
            return !node.isExternal && node.isNewlyDiscovered
        case .unclassified:
            return !node.isExternal && !node.isNewlyDiscovered && node.primaryLayer == nil
        case let .layer(name):
            return !node.isExternal && node.primaryLayer?.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
    }
}

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
    let primaryLayer: String?
    let layerSource: SpiderGraphLayerSource?
    let metadataTags: [String]
    let suggestedLayer: String?
    let suggestedLayerSource: SpiderGraphLayerSource?
    let hasPersistedClassification: Bool
    let isNewlyDiscovered: Bool

    static let newModulesLayerTitle = "New Modules"

    init(
        id: String,
        name: String,
        displayName: String,
        kind: String,
        product: String?,
        bundleId: String?,
        projectName: String?,
        projectPath: String?,
        isExternal: Bool,
        sourceCount: Int,
        resourceCount: Int,
        primaryLayer: String?,
        layerSource: SpiderGraphLayerSource?,
        metadataTags: [String],
        suggestedLayer: String? = nil,
        suggestedLayerSource: SpiderGraphLayerSource? = nil,
        hasPersistedClassification: Bool = false,
        isNewlyDiscovered: Bool = false
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.kind = kind
        self.product = product
        self.bundleId = bundleId
        self.projectName = projectName
        self.projectPath = projectPath
        self.isExternal = isExternal
        self.sourceCount = sourceCount
        self.resourceCount = resourceCount
        self.primaryLayer = primaryLayer
        self.layerSource = layerSource
        self.metadataTags = metadataTags
        self.suggestedLayer = suggestedLayer
        self.suggestedLayerSource = suggestedLayerSource
        self.hasPersistedClassification = hasPersistedClassification
        self.isNewlyDiscovered = isNewlyDiscovered
    }

    var kindLabel: String {
        if kind == "target" {
            return product ?? "target"
        }
        return kind
    }

    var projectLabel: String {
        projectName ?? "External"
    }

    var layerLabel: String {
        if isNewlyDiscovered {
            return Self.newModulesLayerTitle
        }
        return primaryLayer ?? "Unclassified"
    }

    var layerColorKey: String? {
        if isNewlyDiscovered {
            return Self.newModulesLayerTitle
        }
        return primaryLayer
    }

    var layerSourceLabel: String? {
        layerSource?.label
    }

    var suggestedLayerLabel: String {
        suggestedLayer ?? "Unclassified"
    }

    var suggestedLayerSourceLabel: String? {
        suggestedLayerSource?.label
    }

    var isInternalTarget: Bool {
        !isExternal && kind == "target"
    }

    var hasSavedLayerOverride: Bool {
        guard !isNewlyDiscovered else { return false }
        return primaryLayer != suggestedLayer
    }

    var classificationLabel: String {
        if isNewlyDiscovered {
            return "Pending Review"
        }
        return hasSavedLayerOverride ? "Saved Override" : "Suggested Value"
    }

    func updatingClassification(
        primaryLayer: String?,
        layerSource: SpiderGraphLayerSource?,
        hasPersistedClassification: Bool,
        isNewlyDiscovered: Bool = false
    ) -> SpiderGraphNode {
        SpiderGraphNode(
            id: id,
            name: name,
            displayName: displayName,
            kind: kind,
            product: product,
            bundleId: bundleId,
            projectName: projectName,
            projectPath: projectPath,
            isExternal: isExternal,
            sourceCount: sourceCount,
            resourceCount: resourceCount,
            primaryLayer: primaryLayer,
            layerSource: layerSource,
            metadataTags: metadataTags,
            suggestedLayer: suggestedLayer,
            suggestedLayerSource: suggestedLayerSource,
            hasPersistedClassification: hasPersistedClassification,
            isNewlyDiscovered: isNewlyDiscovered
        )
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
            return "내가 의존하는 쪽"
        case .dependents:
            return "나에게 의존하는 쪽"
        }
    }
}

struct GraphDepth: Hashable, Identifiable, Sendable {
    let maxDepth: Int?

    init(maxDepth: Int?) {
        if let maxDepth {
            self.maxDepth = max(1, maxDepth)
        } else {
            self.maxDepth = nil
        }
    }

    init?(rawValue: String) {
        if rawValue == "all" {
            self.init(maxDepth: nil)
            return
        }

        guard let value = Int(rawValue), value > 0 else { return nil }
        self.init(maxDepth: value)
    }

    static let all = GraphDepth(maxDepth: nil)

    var rawValue: String {
        maxDepth.map(String.init) ?? "all"
    }

    var id: String { rawValue }

    var title: String {
        if let maxDepth {
            return "\(maxDepth) 단계"
        }
        return "전체"
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

enum SpiderGraphRelationshipDirection: Sendable {
    case focusedDependsOnSelection
    case selectionDependsOnFocused
    case bidirectional
    case mixed

    var badgeText: String {
        switch self {
        case .focusedDependsOnSelection:
            return "기준이 선택에 의존"
        case .selectionDependsOnFocused:
            return "선택이 기준에 의존"
        case .bidirectional:
            return "서로 의존"
        case .mixed:
            return "공통 의존 경로"
        }
    }

    func description(focusedName: String, selectedName: String) -> String {
        switch self {
        case .focusedDependsOnSelection:
            return "\(focusedName)이(가) \(selectedName)에 의존합니다."
        case .selectionDependsOnFocused:
            return "\(selectedName)이(가) \(focusedName)에 의존합니다."
        case .bidirectional:
            return "\(focusedName)과 \(selectedName) 사이에 순환 의존이 있습니다."
        case .mixed:
            return "한쪽이 다른 한쪽에 바로 이어지는 형태가 아니라 공통 의존 관계를 경유한 연결입니다."
        }
    }
}

struct SpiderGraphSubgraph: Sendable {
    let nodes: [SpiderGraphNode]
    let edges: [SpiderGraphEdge]
    let levels: [String: Int]
    let nodeIDs: Set<String>
    let levelGroups: [SpiderGraphLevelGroup]
    let levelEdges: [SpiderGraphLevelEdge]
    let canvasLayout: SpiderGraphCanvasLayout
    let levelCanvasLayout: SpiderGraphLevelCanvasLayout
    let edgeEndpoints: [String: SpiderGraphEdgeEndpoints]
    let renderSignature: Int

    init(nodes: [SpiderGraphNode], edges: [SpiderGraphEdge], levels: [String: Int]) {
        self.nodes = nodes
        self.edges = edges
        self.levels = levels
        self.nodeIDs = Set(nodes.map(\.id))
        self.levelGroups = Self.makeLevelGroups(nodes: nodes, edges: edges, levels: levels)
        self.levelEdges = Self.makeLevelEdges(edges: edges, levels: levels)
        self.canvasLayout = SpiderGraphCanvasLayout.make(for: nodes, levels: levels)
        self.levelCanvasLayout = SpiderGraphLevelCanvasLayout.make(for: self.levelGroups)
        self.edgeEndpoints = Self.makeEdgeEndpoints(edges: edges, layout: canvasLayout)
        self.renderSignature = Self.makeRenderSignature(
            nodes: nodes,
            edges: edges,
            levels: levels,
            canvasLayout: canvasLayout,
            levelLayout: levelCanvasLayout
        )
    }

    static let empty = SpiderGraphSubgraph(nodes: [], edges: [], levels: [:])

    func filtered(
        toNodeIDs includedNodeIDs: Set<String>,
        edgeIDs includedEdgeIDs: Set<String>
    ) -> SpiderGraphSubgraph {
        guard !includedNodeIDs.isEmpty else { return .empty }

        let filteredNodes = nodes.filter { includedNodeIDs.contains($0.id) }
        let filteredEdges = edges.filter { edge in
            includedEdgeIDs.contains(edge.id)
                && includedNodeIDs.contains(edge.from)
                && includedNodeIDs.contains(edge.to)
        }
        let filteredLevels = levels.filter { includedNodeIDs.contains($0.key) }
        return SpiderGraphSubgraph(nodes: filteredNodes, edges: filteredEdges, levels: filteredLevels)
    }

    private static func makeRenderSignature(
        nodes: [SpiderGraphNode],
        edges: [SpiderGraphEdge],
        levels: [String: Int],
        canvasLayout: SpiderGraphCanvasLayout,
        levelLayout: SpiderGraphLevelCanvasLayout
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(nodes.count)
        hasher.combine(edges.count)
        hasher.combine(canvasLayout.canvasSize)

        for node in nodes {
            hasher.combine(node.id)
            hasher.combine(levels[node.id] ?? 0)
            if let frame = canvasLayout.nodeFrames[node.id] {
                hasher.combine(frame)
            }
        }

        for edge in edges {
            hasher.combine(edge.id)
            hasher.combine(edge.from)
            hasher.combine(edge.to)
        }

        for level in levelLayout.groupFrames.keys.sorted() {
            hasher.combine(level)
            if let frame = levelLayout.groupFrames[level] {
                hasher.combine(frame)
            }
        }

        return hasher.finalize()
    }

    func connectionPaths(
        from startID: String,
        to endID: String,
        maxPaths: Int = 12,
        maxExtraHops: Int = 3
    ) -> SpiderGraphConnectionPathResult? {
        guard startID != endID else {
            return SpiderGraphConnectionPathResult(
                paths: [
                    SpiderGraphConnectionPath(
                        primaryNodeIDs: [startID],
                        secondaryNodeIDs: nil,
                        edgeIDs: [],
                        paletteIndex: 0,
                        kind: .directedForward
                    )
                ],
                isTruncated: false
            )
        }

        let availableNodeIDs = Set(nodes.map(\.id))
        guard availableNodeIDs.contains(startID), availableNodeIDs.contains(endID) else { return nil }

        let nodeMap = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var outgoingAdjacency: [String: [(nodeID: String, edgeID: String)]] = [:]
        var incomingAdjacency: [String: [(nodeID: String, edgeID: String)]] = [:]

        for edge in edges {
            guard availableNodeIDs.contains(edge.from), availableNodeIDs.contains(edge.to) else { continue }
            outgoingAdjacency[edge.from, default: []].append((edge.to, edge.id))
            incomingAdjacency[edge.to, default: []].append((edge.from, edge.id))
        }

        for key in Set(outgoingAdjacency.keys).union(incomingAdjacency.keys) {
            outgoingAdjacency[key]?.sort { lhs, rhs in
                let lhsName = nodeMap[lhs.nodeID]?.name ?? lhs.nodeID
                let rhsName = nodeMap[rhs.nodeID]?.name ?? rhs.nodeID
                if lhsName != rhsName { return lhsName < rhsName }
                return lhs.edgeID < rhs.edgeID
            }
            incomingAdjacency[key]?.sort { lhs, rhs in
                let lhsName = nodeMap[lhs.nodeID]?.name ?? lhs.nodeID
                let rhsName = nodeMap[rhs.nodeID]?.name ?? rhs.nodeID
                if lhsName != rhsName { return lhsName < rhsName }
                return lhs.edgeID < rhs.edgeID
            }
        }

        let candidateLimit = min(max(maxPaths * 5, 24), 72)
        var candidates = enumerateDirectedPathCandidates(
            from: startID,
            to: endID,
            kind: .directedForward,
            adjacency: outgoingAdjacency,
            reverseAdjacency: incomingAdjacency,
            nodeMap: nodeMap,
            maxCandidates: candidateLimit,
            maxExtraHops: maxExtraHops
        )

        candidates.append(
            contentsOf: enumerateDirectedPathCandidates(
                from: endID,
                to: startID,
                kind: .directedReverse,
                adjacency: outgoingAdjacency,
                reverseAdjacency: incomingAdjacency,
                nodeMap: nodeMap,
                maxCandidates: candidateLimit,
                maxExtraHops: maxExtraHops
            )
        )

        if candidates.isEmpty {
            candidates = bridgePathCandidates(
                from: startID,
                to: endID,
                outgoingAdjacency: outgoingAdjacency,
                incomingAdjacency: incomingAdjacency,
                maxCandidates: candidateLimit
            )
        }

        guard !candidates.isEmpty else { return nil }

        var uniqueCandidates: [String: ConnectionPathCandidate] = [:]
        for candidate in candidates {
            if let existing = uniqueCandidates[candidate.id] {
                if candidate.score < existing.score {
                    uniqueCandidates[candidate.id] = candidate
                }
            } else {
                uniqueCandidates[candidate.id] = candidate
            }
        }

        let orderedCandidates = uniqueCandidates.values
            .sorted(by: ConnectionPathCandidate.sort)
        let isTruncated = orderedCandidates.count > maxPaths
        let visibleCandidates = Array(orderedCandidates.prefix(maxPaths))

        let visiblePaths = visibleCandidates.enumerated().map { index, candidate in
            SpiderGraphConnectionPath(
                primaryNodeIDs: candidate.primaryNodeIDs,
                secondaryNodeIDs: candidate.secondaryNodeIDs,
                edgeIDs: candidate.edgeIDs,
                paletteIndex: index,
                kind: candidate.kind
            )
        }

        return SpiderGraphConnectionPathResult(paths: visiblePaths, isTruncated: isTruncated)
    }

    private func shortestDistances(
        from startID: String,
        adjacency: [String: [(nodeID: String, edgeID: String)]]
    ) -> [String: Int] {
        var queue = [startID]
        var distances: [String: Int] = [startID: 0]
        var index = 0

        while index < queue.count {
            let current = queue[index]
            index += 1

            for next in adjacency[current] ?? [] where distances[next.nodeID] == nil {
                distances[next.nodeID] = (distances[current] ?? 0) + 1
                queue.append(next.nodeID)
            }
        }

        return distances
    }

    private func shortestPathTree(
        from startID: String,
        adjacency: [String: [(nodeID: String, edgeID: String)]]
    ) -> (distances: [String: Int], parents: [String: (nodeID: String, edgeID: String)]) {
        var queue = [startID]
        var distances: [String: Int] = [startID: 0]
        var parents: [String: (nodeID: String, edgeID: String)] = [:]
        var index = 0

        while index < queue.count {
            let current = queue[index]
            index += 1

            for next in adjacency[current] ?? [] where distances[next.nodeID] == nil {
                distances[next.nodeID] = (distances[current] ?? 0) + 1
                parents[next.nodeID] = (current, next.edgeID)
                queue.append(next.nodeID)
            }
        }

        return (distances, parents)
    }

    private func enumerateDirectedPathCandidates(
        from startID: String,
        to endID: String,
        kind: SpiderGraphConnectionPathKind,
        adjacency: [String: [(nodeID: String, edgeID: String)]],
        reverseAdjacency: [String: [(nodeID: String, edgeID: String)]],
        nodeMap: [String: SpiderGraphNode],
        maxCandidates: Int,
        maxExtraHops: Int
    ) -> [ConnectionPathCandidate] {
        let distancesToEnd = shortestDistances(from: endID, adjacency: reverseAdjacency)
        guard let shortestDistance = distancesToEnd[startID] else { return [] }

        let maxEdgeCount = shortestDistance + maxExtraHops
        var pathNodeIDs = [startID]
        var pathEdgeIDs: [String] = []
        var visited = Set([startID])
        var discoveredPaths: [ConnectionPathCandidate] = []

        func walk(from currentID: String, accumulatedScore: Int) {
            guard discoveredPaths.count < maxCandidates else { return }

            if currentID == endID {
                let detourPenalty = max(0, pathEdgeIDs.count - shortestDistance) * 40
                discoveredPaths.append(
                    ConnectionPathCandidate(
                        primaryNodeIDs: pathNodeIDs,
                        secondaryNodeIDs: nil,
                        edgeIDs: pathEdgeIDs,
                        kind: kind,
                        score: accumulatedScore + detourPenalty
                    )
                )
                return
            }

            let sortedNeighbors = (adjacency[currentID] ?? []).sorted { lhs, rhs in
                let lhsDistance = distancesToEnd[lhs.nodeID] ?? .max
                let rhsDistance = distancesToEnd[rhs.nodeID] ?? .max
                if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
                let lhsPenalty = traversalPenalty(
                    from: currentID,
                    to: lhs.nodeID,
                    targetID: endID,
                    adjacency: adjacency,
                    reverseAdjacency: reverseAdjacency
                )
                let rhsPenalty = traversalPenalty(
                    from: currentID,
                    to: rhs.nodeID,
                    targetID: endID,
                    adjacency: adjacency,
                    reverseAdjacency: reverseAdjacency
                )
                if lhsPenalty != rhsPenalty { return lhsPenalty < rhsPenalty }
                let lhsName = nodeMap[lhs.nodeID]?.name ?? lhs.nodeID
                let rhsName = nodeMap[rhs.nodeID]?.name ?? rhs.nodeID
                if lhsName != rhsName { return lhsName < rhsName }
                return lhs.edgeID < rhs.edgeID
            }

            for next in sortedNeighbors {
                guard !visited.contains(next.nodeID) else { continue }
                guard let remainingDistance = distancesToEnd[next.nodeID] else { continue }

                let projectedEdgeCount = pathEdgeIDs.count + 1 + remainingDistance
                guard projectedEdgeCount <= maxEdgeCount else { continue }

                let stepPenalty = traversalPenalty(
                    from: currentID,
                    to: next.nodeID,
                    targetID: endID,
                    adjacency: adjacency,
                    reverseAdjacency: reverseAdjacency
                )

                visited.insert(next.nodeID)
                pathNodeIDs.append(next.nodeID)
                pathEdgeIDs.append(next.edgeID)
                walk(from: next.nodeID, accumulatedScore: accumulatedScore + stepPenalty)
                pathEdgeIDs.removeLast()
                pathNodeIDs.removeLast()
                visited.remove(next.nodeID)

                if discoveredPaths.count >= maxCandidates {
                    return
                }
            }
        }

        walk(from: startID, accumulatedScore: 0)
        return discoveredPaths
    }

    private func bridgePathCandidates(
        from startID: String,
        to endID: String,
        outgoingAdjacency: [String: [(nodeID: String, edgeID: String)]],
        incomingAdjacency: [String: [(nodeID: String, edgeID: String)]],
        maxCandidates: Int
    ) -> [ConnectionPathCandidate] {
        let dependencyCandidates = commonDependencyBridgeCandidates(
            from: startID,
            to: endID,
            outgoingAdjacency: outgoingAdjacency,
            maxCandidates: maxCandidates
        )
        let dependentCandidates = commonDependentBridgeCandidates(
            from: startID,
            to: endID,
            incomingAdjacency: incomingAdjacency,
            maxCandidates: maxCandidates
        )
        return (dependencyCandidates + dependentCandidates)
            .sorted(by: ConnectionPathCandidate.sort)
    }

    private func commonDependencyBridgeCandidates(
        from startID: String,
        to endID: String,
        outgoingAdjacency: [String: [(nodeID: String, edgeID: String)]],
        maxCandidates: Int
    ) -> [ConnectionPathCandidate] {
        let startTree = shortestPathTree(from: startID, adjacency: outgoingAdjacency)
        let endTree = shortestPathTree(from: endID, adjacency: outgoingAdjacency)
        let commonNodeIDs = Set(startTree.distances.keys)
            .intersection(endTree.distances.keys)
            .subtracting([startID, endID])

        let pivotNodeIDs = commonNodeIDs
            .sorted { lhs, rhs in
                bridgeCandidateScore(nodeID: lhs, distancesA: startTree.distances, distancesB: endTree.distances)
                    < bridgeCandidateScore(nodeID: rhs, distancesA: startTree.distances, distancesB: endTree.distances)
            }
            .prefix(maxCandidates)

        return pivotNodeIDs.compactMap { pivotID in
            guard
                let primary = reconstructPath(from: startID, to: pivotID, parents: startTree.parents),
                let secondary = reconstructPath(from: endID, to: pivotID, parents: endTree.parents)
            else {
                return nil
            }

            return ConnectionPathCandidate(
                primaryNodeIDs: primary.nodeIDs,
                secondaryNodeIDs: secondary.nodeIDs,
                edgeIDs: orderedUnique(primary.edgeIDs + secondary.edgeIDs),
                kind: .commonDependency,
                score: bridgeCandidateScore(
                    nodeID: pivotID,
                    distancesA: startTree.distances,
                    distancesB: endTree.distances
                ) + 120
            )
        }
    }

    private func commonDependentBridgeCandidates(
        from startID: String,
        to endID: String,
        incomingAdjacency: [String: [(nodeID: String, edgeID: String)]],
        maxCandidates: Int
    ) -> [ConnectionPathCandidate] {
        let startTree = shortestPathTree(from: startID, adjacency: incomingAdjacency)
        let endTree = shortestPathTree(from: endID, adjacency: incomingAdjacency)
        let commonNodeIDs = Set(startTree.distances.keys)
            .intersection(endTree.distances.keys)
            .subtracting([startID, endID])

        let pivotNodeIDs = commonNodeIDs
            .sorted { lhs, rhs in
                bridgeCandidateScore(nodeID: lhs, distancesA: startTree.distances, distancesB: endTree.distances)
                    < bridgeCandidateScore(nodeID: rhs, distancesA: startTree.distances, distancesB: endTree.distances)
            }
            .prefix(maxCandidates)

        return pivotNodeIDs.compactMap { pivotID in
            guard
                let primary = reconstructReverseTreePath(rootID: startID, targetID: pivotID, parents: startTree.parents),
                let secondary = reconstructReverseTreePath(rootID: endID, targetID: pivotID, parents: endTree.parents)
            else {
                return nil
            }

            return ConnectionPathCandidate(
                primaryNodeIDs: primary.nodeIDs,
                secondaryNodeIDs: secondary.nodeIDs,
                edgeIDs: orderedUnique(primary.edgeIDs + secondary.edgeIDs),
                kind: .commonDependent,
                score: bridgeCandidateScore(
                    nodeID: pivotID,
                    distancesA: startTree.distances,
                    distancesB: endTree.distances
                ) + 180
            )
        }
    }

    private func bridgeCandidateScore(
        nodeID: String,
        distancesA: [String: Int],
        distancesB: [String: Int]
    ) -> Int {
        let totalDistance = (distancesA[nodeID] ?? 0) + (distancesB[nodeID] ?? 0)
        let nodeLevel = abs(levels[nodeID] ?? 0)
        let degree = edges.reduce(into: 0) { count, edge in
            guard edge.from == nodeID || edge.to == nodeID else { return }
            count += 1
        }
        return totalDistance * 30 + nodeLevel * 8 + max(0, degree - 4) * 5
    }

    private func reconstructPath(
        from startID: String,
        to endID: String,
        parents: [String: (nodeID: String, edgeID: String)]
    ) -> (nodeIDs: [String], edgeIDs: [String])? {
        guard startID == endID || parents[endID] != nil else { return nil }
        var nodeIDs = [endID]
        var edgeIDs: [String] = []
        var cursor = endID

        while cursor != startID {
            guard let parent = parents[cursor] else { return nil }
            edgeIDs.append(parent.edgeID)
            nodeIDs.append(parent.nodeID)
            cursor = parent.nodeID
        }

        return (nodeIDs.reversed(), edgeIDs.reversed())
    }

    private func reconstructReverseTreePath(
        rootID: String,
        targetID: String,
        parents: [String: (nodeID: String, edgeID: String)]
    ) -> (nodeIDs: [String], edgeIDs: [String])? {
        guard let reversePath = reconstructPath(from: rootID, to: targetID, parents: parents) else {
            return nil
        }
        return (
            nodeIDs: reversePath.nodeIDs.reversed(),
            edgeIDs: reversePath.edgeIDs.reversed()
        )
    }

    private func traversalPenalty(
        from fromID: String,
        to toID: String,
        targetID: String,
        adjacency: [String: [(nodeID: String, edgeID: String)]],
        reverseAdjacency: [String: [(nodeID: String, edgeID: String)]]
    ) -> Int {
        let fromLevel = levels[fromID] ?? 0
        let toLevel = levels[toID] ?? 0
        let targetLevel = levels[targetID] ?? 0
        let currentGap = abs(targetLevel - fromLevel)
        let nextGap = abs(targetLevel - toLevel)

        var penalty = 0
        if nextGap > currentGap { penalty += 18 }
        if nextGap == currentGap && toLevel == fromLevel { penalty += 6 }

        let desiredStep = stepDirection(from: fromLevel, to: targetLevel)
        let actualStep = stepDirection(from: fromLevel, to: toLevel)
        if desiredStep != 0, actualStep != 0, desiredStep != actualStep {
            penalty += 12
        }

        let degree = (adjacency[toID]?.count ?? 0) + (reverseAdjacency[toID]?.count ?? 0)
        if toID != targetID {
            penalty += max(0, degree - 4) * 2
        }

        return penalty
    }

    private func stepDirection(from startLevel: Int, to endLevel: Int) -> Int {
        if endLevel > startLevel { return 1 }
        if endLevel < startLevel { return -1 }
        return 0
    }

    private func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private struct ConnectionPathCandidate {
        let primaryNodeIDs: [String]
        let secondaryNodeIDs: [String]?
        let edgeIDs: [String]
        let kind: SpiderGraphConnectionPathKind
        let score: Int

        var id: String {
            "\(kind.rawValue)::\(edgeIDs.sorted().joined(separator: "|"))"
        }

        static func sort(_ lhs: ConnectionPathCandidate, _ rhs: ConnectionPathCandidate) -> Bool {
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            if lhs.edgeIDs.count != rhs.edgeIDs.count { return lhs.edgeIDs.count < rhs.edgeIDs.count }
            if lhs.kind.rawValue != rhs.kind.rawValue { return lhs.kind.rawValue < rhs.kind.rawValue }
            return lhs.id < rhs.id
        }
    }

    private static func makeLevelGroups(
        nodes: [SpiderGraphNode],
        edges: [SpiderGraphEdge],
        levels: [String: Int]
    ) -> [SpiderGraphLevelGroup] {
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

    private static func makeLevelEdges(
        edges: [SpiderGraphEdge],
        levels: [String: Int]
    ) -> [SpiderGraphLevelEdge] {
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

    private static func makeEdgeEndpoints(
        edges: [SpiderGraphEdge],
        layout: SpiderGraphCanvasLayout
    ) -> [String: SpiderGraphEdgeEndpoints] {
        let inputs: [EdgeLayoutInput] = edges.compactMap { edge in
            guard
                let fromFrame = layout.nodeFrames[edge.from],
                let toFrame = layout.nodeFrames[edge.to]
            else {
                return nil
            }

            let sourceSide: SpiderGraphAnchorSide
            let targetSide: SpiderGraphAnchorSide
            if shouldUseVerticalAnchors(from: fromFrame, to: toFrame) {
                sourceSide = fromFrame.midY <= toFrame.midY ? .bottom : .top
                targetSide = sourceSide == .bottom ? .top : .bottom
            } else {
                sourceSide = fromFrame.midX <= toFrame.midX ? .right : .left
                targetSide = sourceSide == .right ? .left : .right
            }
            return EdgeLayoutInput(
                edge: edge,
                fromFrame: fromFrame,
                toFrame: toFrame,
                sourceSide: sourceSide,
                targetSide: targetSide
            )
        }

        var sourceOffsets: [String: CGFloat] = [:]
        var targetOffsets: [String: CGFloat] = [:]
        let mixedFlowPortKeys = makeMixedFlowPortKeys(inputs: inputs)

        let sourceGroups = Dictionary(grouping: inputs) { input in
            SpiderGraphEdgePortKey(nodeID: input.edge.from, side: input.sourceSide)
        }
        let targetGroups = Dictionary(grouping: inputs) { input in
            SpiderGraphEdgePortKey(nodeID: input.edge.to, side: input.targetSide)
        }

        for group in sourceGroups.values {
            let sorted = group.sorted { lhs, rhs in
                edgeSortTuple(
                    counterpartFrame: lhs.toFrame,
                    counterpartNodeID: lhs.edge.to,
                    edgeID: lhs.edge.id
                ) < edgeSortTuple(
                    counterpartFrame: rhs.toFrame,
                    counterpartNodeID: rhs.edge.to,
                    edgeID: rhs.edge.id
                )
            }

            for (index, input) in sorted.enumerated() {
                sourceOffsets[input.edge.id] = portOffset(
                    index: index,
                    count: sorted.count,
                    frame: input.fromFrame,
                    side: input.sourceSide,
                    role: .outgoing,
                    separateFlows: mixedFlowPortKeys.contains(
                        SpiderGraphEdgePortKey(nodeID: input.edge.from, side: input.sourceSide)
                    )
                )
            }
        }

        for group in targetGroups.values {
            let sorted = group.sorted { lhs, rhs in
                edgeSortTuple(
                    counterpartFrame: lhs.fromFrame,
                    counterpartNodeID: lhs.edge.from,
                    edgeID: lhs.edge.id
                ) < edgeSortTuple(
                    counterpartFrame: rhs.fromFrame,
                    counterpartNodeID: rhs.edge.from,
                    edgeID: rhs.edge.id
                )
            }

            for (index, input) in sorted.enumerated() {
                targetOffsets[input.edge.id] = portOffset(
                    index: index,
                    count: sorted.count,
                    frame: input.toFrame,
                    side: input.targetSide,
                    role: .incoming,
                    separateFlows: mixedFlowPortKeys.contains(
                        SpiderGraphEdgePortKey(nodeID: input.edge.to, side: input.targetSide)
                    )
                )
            }
        }

        return inputs.reduce(into: [:]) { endpoints, input in
            let start = input.sourceSide.anchorPoint(
                in: input.fromFrame,
                yOffset: sourceOffsets[input.edge.id] ?? 0
            )
            let end = input.targetSide.anchorPoint(
                in: input.toFrame,
                yOffset: targetOffsets[input.edge.id] ?? 0
            )
            endpoints[input.edge.id] = SpiderGraphEdgeEndpoints(
                start: start,
                end: end,
                sourceSide: input.sourceSide,
                targetSide: input.targetSide
            )
        }
    }

    private static func edgeSortTuple(
        counterpartFrame: CGRect,
        counterpartNodeID: String,
        edgeID: String
    ) -> (CGFloat, CGFloat, String, String) {
        (counterpartFrame.midY, counterpartFrame.midX, counterpartNodeID, edgeID)
    }

    private static func shouldUseVerticalAnchors(from fromFrame: CGRect, to toFrame: CGRect) -> Bool {
        let horizontalOverlap = min(fromFrame.maxX, toFrame.maxX) - max(fromFrame.minX, toFrame.minX)
        let minimumRequiredOverlap = min(fromFrame.width, toFrame.width) * 0.28
        let centerDeltaX = abs(fromFrame.midX - toFrame.midX)
        let centerDeltaY = abs(fromFrame.midY - toFrame.midY)
        let sameColumnThreshold = min(fromFrame.width, toFrame.width) * 0.32
        let stackedDistance = max(min(fromFrame.height, toFrame.height) * 0.45, 28)
        let isSameColumn = centerDeltaX <= sameColumnThreshold
        let hasMeaningfulOverlap = horizontalOverlap >= minimumRequiredOverlap
        let isStacked = centerDeltaY >= stackedDistance
        return (isSameColumn || hasMeaningfulOverlap) && isStacked
    }

    private static func makeMixedFlowPortKeys(inputs: [EdgeLayoutInput]) -> Set<SpiderGraphEdgePortKey> {
        var rolesByPortKey: [SpiderGraphEdgePortKey: Set<SpiderGraphEdgePortRole>] = [:]
        for input in inputs {
            rolesByPortKey[
                SpiderGraphEdgePortKey(nodeID: input.edge.from, side: input.sourceSide),
                default: []
            ].insert(.outgoing)
            rolesByPortKey[
                SpiderGraphEdgePortKey(nodeID: input.edge.to, side: input.targetSide),
                default: []
            ].insert(.incoming)
        }

        return Set(
            rolesByPortKey.compactMap { portKey, roles in
                roles.count > 1 ? portKey : nil
            }
        )
    }

    private static func portOffset(
        index: Int,
        count: Int,
        frame: CGRect,
        side: SpiderGraphAnchorSide,
        role: SpiderGraphEdgePortRole,
        separateFlows: Bool
    ) -> CGFloat {
        if separateFlows {
            return separatedPortOffset(index: index, count: count, frame: frame, side: side, role: role)
        }

        guard count > 1 else { return 0 }
        let halfSpan = CGFloat(count - 1) / 2
        let axisLength = side.isHorizontal ? frame.height : frame.width
        let maxSpread = min(axisLength * 0.32, 26)
        let step = min(12, maxSpread / max(halfSpan, 1))
        return (CGFloat(index) - halfSpan) * step
    }

    private static func separatedPortOffset(
        index: Int,
        count: Int,
        frame: CGRect,
        side: SpiderGraphAnchorSide,
        role: SpiderGraphEdgePortRole
    ) -> CGFloat {
        let crossAxisLength = side.isHorizontal ? frame.height : frame.width
        let halfCrossAxis = crossAxisLength / 2
        let edgeInset = min(crossAxisLength * 0.12, 8)
        let laneGap = min(crossAxisLength * 0.12, 8)
        let usableStart = -(halfCrossAxis - edgeInset)
        let usableEnd = halfCrossAxis - edgeInset

        let range: ClosedRange<CGFloat> = switch role {
        case .outgoing:
            usableStart...(min(-laneGap, usableEnd))
        case .incoming:
            max(laneGap, usableStart)...usableEnd
        }

        let clampedLower = min(range.lowerBound, range.upperBound)
        let clampedUpper = max(range.lowerBound, range.upperBound)
        if count <= 1 {
            return (clampedLower + clampedUpper) / 2
        }

        let step = (clampedUpper - clampedLower) / CGFloat(max(count - 1, 1))
        return clampedLower + CGFloat(index) * step
    }
}

struct SpiderGraphConnectionPathResult: Sendable {
    let paths: [SpiderGraphConnectionPath]
    let isTruncated: Bool
}

enum SpiderGraphConnectionPathKind: String, Hashable, Sendable {
    case directedForward
    case directedReverse
    case commonDependency
    case commonDependent

    var badgeText: String {
        switch self {
        case .directedForward:
            return "기준 -> 선택"
        case .directedReverse:
            return "선택 -> 기준"
        case .commonDependency:
            return "같이 의존"
        case .commonDependent:
            return "둘 다에 의존"
        }
    }
}

struct SpiderGraphConnectionPath: Identifiable, Hashable, Sendable {
    let primaryNodeIDs: [String]
    let secondaryNodeIDs: [String]?
    let edgeIDs: [String]
    let paletteIndex: Int
    let kind: SpiderGraphConnectionPathKind

    var id: String {
        "\(kind.rawValue)::\(edgeIDs.sorted().joined(separator: "|"))"
    }

    var edgeCount: Int {
        edgeIDs.count
    }

    var dependencyScopeLabel: String {
        switch kind {
        case .directedForward:
            return edgeCount == 1 ? "직접 의존" : "간접 의존"
        case .directedReverse:
            return edgeCount == 1 ? "나에게 직접 의존" : "나에게 간접 의존"
        case .commonDependency:
            return "같이 의존하는 모듈 경유"
        case .commonDependent:
            return "둘 다에 의존하는 모듈 경유"
        }
    }

    var isDirectConnection: Bool {
        switch kind {
        case .directedForward, .directedReverse:
            return edgeCount == 1
        case .commonDependency, .commonDependent:
            return false
        }
    }

    var nodeIDs: [String] {
        let combined = primaryNodeIDs + (secondaryNodeIDs ?? [])
        var seen = Set<String>()
        return combined.filter { seen.insert($0).inserted }
    }

    func preview(using nodeMap: [String: SpiderGraphNode], visibleNameCount: Int = 5) -> String {
        switch kind {
        case .directedForward, .directedReverse:
            return previewSequence(
                primaryNodeIDs.map { nodeMap[$0]?.name ?? $0 },
                connector: " -> ",
                visibleNameCount: visibleNameCount
            )
        case .commonDependency:
            let leading = primaryNodeIDs.map { nodeMap[$0]?.name ?? $0 }
            let trailing = Array((secondaryNodeIDs ?? []).dropLast().reversed()).map { nodeMap[$0]?.name ?? $0 }
            return previewBridge(
                leading: leading,
                trailing: trailing,
                leadingConnector: " -> ",
                bridgeConnector: " <- ",
                trailingConnector: " <- ",
                visibleNameCount: visibleNameCount
            )
        case .commonDependent:
            let leading = Array(primaryNodeIDs.reversed()).map { nodeMap[$0]?.name ?? $0 }
            let trailing = Array((secondaryNodeIDs ?? []).dropFirst()).map { nodeMap[$0]?.name ?? $0 }
            return previewBridge(
                leading: leading,
                trailing: trailing,
                leadingConnector: " <- ",
                bridgeConnector: " -> ",
                trailingConnector: " -> ",
                visibleNameCount: visibleNameCount
            )
        }
    }

    private func previewSequence(
        _ names: [String],
        connector: String,
        visibleNameCount: Int
    ) -> String {
        guard names.count > visibleNameCount else {
            return names.joined(separator: connector)
        }

        let prefix = names.prefix(2)
        let suffix = names.suffix(2)
        return Array(prefix + ["..."] + suffix).joined(separator: connector)
    }

    private func previewBridge(
        leading: [String],
        trailing: [String],
        leadingConnector: String,
        bridgeConnector: String,
        trailingConnector: String,
        visibleNameCount: Int
    ) -> String {
        if leading.count + trailing.count <= visibleNameCount {
            let left = leading.joined(separator: leadingConnector)
            let right = trailing.joined(separator: trailingConnector)
            if left.isEmpty { return right }
            if right.isEmpty { return left }
            return left + bridgeConnector + right
        }

        let left = Array(leading.prefix(2)).joined(separator: leadingConnector)
        let right = Array(trailing.suffix(2)).joined(separator: trailingConnector)
        if right.isEmpty {
            return left + leadingConnector + "..."
        }
        return left + leadingConnector + "..." + bridgeConnector + "..." + trailingConnector + right
    }
}

enum SpiderGraphConnectionPathFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case directOnly
    case indirectOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "전체"
        case .directOnly:
            return "직접만"
        case .indirectOnly:
            return "간접만"
        }
    }

    func includes(_ path: SpiderGraphConnectionPath) -> Bool {
        switch self {
        case .all:
            return true
        case .directOnly:
            return path.isDirectConnection
        case .indirectOnly:
            return !path.isDirectConnection
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

struct SpiderGraphEdgeEndpoints: Hashable, Sendable {
    let start: CGPoint
    let end: CGPoint
    let sourceSide: SpiderGraphAnchorSide
    let targetSide: SpiderGraphAnchorSide
}

private struct SpiderGraphLevelPair: Hashable, Sendable {
    let fromLevel: Int
    let toLevel: Int
}

private struct SpiderGraphEdgePortKey: Hashable, Sendable {
    let nodeID: String
    let side: SpiderGraphAnchorSide
}

private struct EdgeLayoutInput: Sendable {
    let edge: SpiderGraphEdge
    let fromFrame: CGRect
    let toFrame: CGRect
    let sourceSide: SpiderGraphAnchorSide
    let targetSide: SpiderGraphAnchorSide
}

private enum SpiderGraphEdgePortRole: Sendable {
    case outgoing
    case incoming
}

enum SpiderGraphAnchorSide: Hashable, Sendable {
    case left
    case right
    case top
    case bottom

    var isHorizontal: Bool {
        switch self {
        case .left, .right:
            return true
        case .top, .bottom:
            return false
        }
    }

    var outwardUnitVector: CGPoint {
        switch self {
        case .left:
            return CGPoint(x: -1, y: 0)
        case .right:
            return CGPoint(x: 1, y: 0)
        case .top:
            return CGPoint(x: 0, y: -1)
        case .bottom:
            return CGPoint(x: 0, y: 1)
        }
    }

    func anchorPoint(in frame: CGRect, yOffset: CGFloat) -> CGPoint {
        switch self {
        case .left:
            return CGPoint(x: frame.minX, y: frame.midY + yOffset)
        case .right:
            return CGPoint(x: frame.maxX, y: frame.midY + yOffset)
        case .top:
            return CGPoint(x: frame.midX + yOffset, y: frame.minY)
        case .bottom:
            return CGPoint(x: frame.midX + yOffset, y: frame.maxY)
        }
    }
}

struct SpiderGraphCanvasLayout: Sendable {
    let layerRegions: [SpiderGraphCanvasLayerRegion]
    let nodeFrames: [String: CGRect]
    let canvasSize: CGSize

    static func make(for nodes: [SpiderGraphNode], levels: [String: Int]) -> SpiderGraphCanvasLayout {
        guard !nodes.isEmpty else {
            return SpiderGraphCanvasLayout(layerRegions: [], nodeFrames: [:], canvasSize: .zero)
        }

        let nodeWidth: CGFloat = 220
        let nodeHeight: CGFloat = 72
        let columnGap: CGFloat = 280
        let rowGap: CGFloat = 96
        let layerGap: CGFloat = 40
        let layerHeaderHeight: CGFloat = 38
        let layerPaddingY: CGFloat = 18
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

        let width = paddingX * 2 + CGFloat(max(orderedLevels.count - 1, 1)) * columnGap + nodeWidth
        let layerKinds = canvasLayerKinds(for: nodes)
        let nodesByLevelAndLayer = Dictionary(
            uniqueKeysWithValues: orderedLevels.map { level in
                let groupedNodes = Dictionary(grouping: groups[level] ?? [], by: canvasLayerKind(for:))
                return (level, groupedNodes)
            }
        )
        let layerSlotCounts = Dictionary(
            uniqueKeysWithValues: layerKinds.map { layerKind in
                let maxCount = orderedLevels.map { level in
                    nodesByLevelAndLayer[level]?[layerKind]?.count ?? 0
                }.max() ?? 0
                return (layerKind, max(maxCount, 1))
            }
        )

        let regionX = max(32, paddingX - 36)
        let regionWidth = max(nodeWidth, width - regionX - 44)
        var layerFrames: [SpiderGraphCanvasLayerKind: CGRect] = [:]
        var currentY = paddingY

        for layerKind in layerKinds {
            let slotCount = layerSlotCounts[layerKind] ?? 1
            let contentHeight = nodeHeight + CGFloat(max(slotCount - 1, 0)) * rowGap
            let layerHeight = contentHeight + layerHeaderHeight + layerPaddingY * 2
            layerFrames[layerKind] = CGRect(
                x: regionX,
                y: currentY,
                width: regionWidth,
                height: layerHeight
            )
            currentY += layerHeight + layerGap
        }

        let height = max(currentY - layerGap + paddingY, paddingY * 2 + nodeHeight)

        var nodeFrames: [String: CGRect] = [:]
        for (columnIndex, level) in orderedLevels.enumerated() {
            let originX = paddingX + CGFloat(columnIndex) * columnGap

            for layerKind in layerKinds {
                guard
                    let layerFrame = layerFrames[layerKind],
                    let layerNodes = nodesByLevelAndLayer[level]?[layerKind]?.sorted(by: SpiderGraph.nodeSort),
                    !layerNodes.isEmpty
                else {
                    continue
                }

                let contentHeight = nodeHeight + CGFloat(max(layerNodes.count - 1, 0)) * rowGap
                let contentOriginY = layerFrame.minY + layerHeaderHeight + layerPaddingY
                let contentRegionHeight = layerFrame.height - layerHeaderHeight - layerPaddingY * 2
                var currentNodeY = contentOriginY + (contentRegionHeight - contentHeight) / 2

                for node in layerNodes {
                    let origin = CGPoint(x: originX, y: currentNodeY)
                    nodeFrames[node.id] = CGRect(origin: origin, size: CGSize(width: nodeWidth, height: nodeHeight))
                    currentNodeY += rowGap
                }
            }
        }

        let layerRegions = layerKinds.compactMap { layerKind -> SpiderGraphCanvasLayerRegion? in
            guard let frame = layerFrames[layerKind] else { return nil }
            let nodeIDs = nodes
                .filter { canvasLayerKind(for: $0) == layerKind }
                .map(\.id)
            return SpiderGraphCanvasLayerRegion(kind: layerKind, frame: frame, nodeIDs: nodeIDs)
        }

        return SpiderGraphCanvasLayout(
            layerRegions: layerRegions,
            nodeFrames: nodeFrames,
            canvasSize: CGSize(width: width, height: height)
        )
    }

    private static func canvasLayerKinds(for nodes: [SpiderGraphNode]) -> [SpiderGraphCanvasLayerKind] {
        let internalLayerNames = Set<String>(
            nodes.compactMap { node in
                guard !node.isExternal, !node.isNewlyDiscovered else { return nil }
                return node.primaryLayer
            }
        )
        let orderedInternalLayerNames = internalLayerNames.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }

        var kinds: [SpiderGraphCanvasLayerKind] = orderedInternalLayerNames.map(SpiderGraphCanvasLayerKind.layer)
        if nodes.contains(where: { !$0.isExternal && $0.isNewlyDiscovered }) {
            kinds.append(.newModules)
        }
        if nodes.contains(where: { !$0.isExternal && !$0.isNewlyDiscovered && $0.primaryLayer == nil }) {
            kinds.append(SpiderGraphCanvasLayerKind.unclassified)
        }
        if nodes.contains(where: \.isExternal) {
            kinds.append(SpiderGraphCanvasLayerKind.external)
        }

        return kinds.isEmpty ? [SpiderGraphCanvasLayerKind.unclassified] : kinds
    }

    private static func canvasLayerKind(for node: SpiderGraphNode) -> SpiderGraphCanvasLayerKind {
        if node.isExternal {
            return .external
        }
        if node.isNewlyDiscovered {
            return .newModules
        }
        if let primaryLayer = node.primaryLayer {
            return .layer(primaryLayer)
        }
        return .unclassified
    }
}

enum SpiderGraphCanvasLayerKind: Hashable, Sendable {
    case layer(String)
    case newModules
    case unclassified
    case external

    var id: String {
        switch self {
        case let .layer(name):
            return "layer:\(name)"
        case .newModules:
            return "new-modules"
        case .unclassified:
            return "unclassified"
        case .external:
            return "external"
        }
    }

    var title: String {
        switch self {
        case let .layer(name):
            return name
        case .newModules:
            return SpiderGraphNode.newModulesLayerTitle
        case .unclassified:
            return "Unclassified"
        case .external:
            return "External"
        }
    }

    var layerName: String? {
        switch self {
        case let .layer(name):
            return name
        case .newModules:
            return SpiderGraphNode.newModulesLayerTitle
        case .unclassified, .external:
            return nil
        }
    }
}

struct SpiderGraphCanvasLayerRegion: Identifiable, Hashable, Sendable {
    let kind: SpiderGraphCanvasLayerKind
    let frame: CGRect
    let nodeIDs: [String]

    var id: String { kind.id }
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
    let warnings: [String]
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
        warnings: [String] = [],
        nodes: [SpiderGraphNode],
        edges: [SpiderGraphEdge]
    ) {
        self.graphName = graphName
        self.sourceFormat = sourceFormat
        self.rootPath = rootPath
        self.generatedAt = generatedAt
        self.warnings = warnings
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

    func replacingNodes(_ nodes: [SpiderGraphNode], warnings: [String]? = nil) -> SpiderGraph {
        SpiderGraph(
            graphName: graphName,
            sourceFormat: sourceFormat,
            rootPath: rootPath,
            generatedAt: generatedAt,
            warnings: warnings ?? self.warnings,
            nodes: nodes,
            edges: edges
        )
    }

    func appendingWarnings(_ additionalWarnings: [String]) -> SpiderGraph {
        guard !additionalWarnings.isEmpty else { return self }
        return replacingNodes(nodes, warnings: warnings + additionalWarnings)
    }

    var preferredRootID: String? {
        let internalNodes = nodes.filter { !$0.isExternal }
        guard !internalNodes.isEmpty else { return nodes.first?.id }

        return internalNodes
            .sorted { lhs, rhs in
                let lhsIncomingCount = incoming[lhs.id]?.count ?? 0
                let rhsIncomingCount = incoming[rhs.id]?.count ?? 0
                if lhsIncomingCount != rhsIncomingCount {
                    return lhsIncomingCount < rhsIncomingCount
                }

                let lhsProductRank = productRank(for: lhs)
                let rhsProductRank = productRank(for: rhs)
                if lhsProductRank != rhsProductRank {
                    return lhsProductRank < rhsProductRank
                }

                let lhsOutgoingCount = outgoing[lhs.id]?.count ?? 0
                let rhsOutgoingCount = outgoing[rhs.id]?.count ?? 0
                if lhsOutgoingCount != rhsOutgoingCount {
                    return lhsOutgoingCount > rhsOutgoingCount
                }

                return SpiderGraph.nodeSort(lhs, rhs)
            }
            .first?
            .id
    }

    func directDependencies(
        of nodeID: String,
        includeExternal: Bool,
        layerFilter: SpiderGraphLayerFilter = .all
    ) -> [SpiderGraphNode] {
        let ids = outgoing[nodeID] ?? []
        return ids.compactMap { nodeMap[$0] }
            .filter { matchesFilters(for: $0, includeExternal: includeExternal, layerFilter: layerFilter) }
            .sorted(by: SpiderGraph.nodeSort)
    }

    func directDependents(
        of nodeID: String,
        includeExternal: Bool,
        layerFilter: SpiderGraphLayerFilter = .all
    ) -> [SpiderGraphNode] {
        let ids = incoming[nodeID] ?? []
        return ids.compactMap { nodeMap[$0] }
            .filter { matchesFilters(for: $0, includeExternal: includeExternal, layerFilter: layerFilter) }
            .sorted(by: SpiderGraph.nodeSort)
    }

    func maxReachableDepth(
        centeredOn rootID: String,
        direction: GraphDirection,
        includeExternal: Bool,
        layerFilter: SpiderGraphLayerFilter = .all
    ) -> Int {
        guard nodeMap[rootID] != nil else { return 0 }

        func allows(_ nodeID: String) -> Bool {
            guard let node = nodeMap[nodeID] else { return false }
            return matchesFilters(for: node, includeExternal: includeExternal, layerFilter: layerFilter) || nodeID == rootID
        }

        var maxDistance = 0
        if direction != .dependencies {
            maxDistance = max(maxDistance, bfs(from: rootID, adjacency: incoming, maxDepth: nil, allows: allows).values.max() ?? 0)
        }
        if direction != .dependents {
            maxDistance = max(maxDistance, bfs(from: rootID, adjacency: outgoing, maxDepth: nil, allows: allows).values.max() ?? 0)
        }
        return maxDistance
    }

    func subgraph(
        centeredOn rootID: String,
        direction: GraphDirection,
        depth: GraphDepth,
        includeExternal: Bool,
        layerFilter: SpiderGraphLayerFilter = .all
    ) -> SpiderGraphSubgraph {
        guard nodeMap[rootID] != nil else {
            return SpiderGraphSubgraph(nodes: [], edges: [], levels: [:])
        }

        func allows(_ nodeID: String) -> Bool {
            guard let node = nodeMap[nodeID] else { return false }
            return matchesFilters(for: node, includeExternal: includeExternal, layerFilter: layerFilter) || nodeID == rootID
        }

        var levels: [String: Int] = [rootID: 0]
        if direction != .dependencies {
            for (nodeID, distance) in bfs(from: rootID, adjacency: incoming, maxDepth: depth.maxDepth, allows: allows) {
                levels[nodeID] = -distance
            }
        }
        if direction != .dependents {
            for (nodeID, distance) in bfs(from: rootID, adjacency: outgoing, maxDepth: depth.maxDepth, allows: allows) {
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

    func relationshipDirection(
        from focusedNodeID: String,
        to selectedNodeID: String,
        restrictedTo allowedNodeIDs: Set<String>? = nil
    ) -> SpiderGraphRelationshipDirection? {
        let allowedNodeIDs = allowedNodeIDs ?? Set(nodeMap.keys)
        guard allowedNodeIDs.contains(focusedNodeID), allowedNodeIDs.contains(selectedNodeID) else {
            return nil
        }

        let focusedDependsOnSelection = hasDirectedPath(
            from: focusedNodeID,
            to: selectedNodeID,
            allowedNodeIDs: allowedNodeIDs
        )
        let selectionDependsOnFocused = hasDirectedPath(
            from: selectedNodeID,
            to: focusedNodeID,
            allowedNodeIDs: allowedNodeIDs
        )

        switch (focusedDependsOnSelection, selectionDependsOnFocused) {
        case (true, true):
            return .bidirectional
        case (true, false):
            return .focusedDependsOnSelection
        case (false, true):
            return .selectionDependsOnFocused
        case (false, false):
            return .mixed
        }
    }

    private func bfs(
        from startID: String,
        adjacency: [String: [String]],
        maxDepth: Int?,
        allows: (String) -> Bool
    ) -> [String: Int] {
        let maxDepth = maxDepth ?? Int.max
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

    private func hasDirectedPath(
        from startID: String,
        to endID: String,
        allowedNodeIDs: Set<String>
    ) -> Bool {
        guard startID != endID else { return true }

        var queue = [startID]
        var seen = Set([startID])
        var index = 0

        while index < queue.count {
            let nodeID = queue[index]
            index += 1

            for nextID in outgoing[nodeID] ?? [] {
                guard allowedNodeIDs.contains(nextID), seen.insert(nextID).inserted else { continue }
                if nextID == endID {
                    return true
                }
                queue.append(nextID)
            }
        }

        return false
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
        if lhs.layerLabel != rhs.layerLabel {
            return lhs.layerLabel.localizedCaseInsensitiveCompare(rhs.layerLabel) == .orderedAscending
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private func matchesFilters(
        for node: SpiderGraphNode,
        includeExternal: Bool,
        layerFilter: SpiderGraphLayerFilter
    ) -> Bool {
        guard includeExternal || !node.isExternal else { return false }
        return layerFilter.matches(node)
    }

    private func productRank(for node: SpiderGraphNode) -> Int {
        switch node.product?.lowercased() {
        case "app":
            return 0
        case "framework", "staticframework", "dynamicframework":
            return 1
        default:
            return 2
        }
    }
}
