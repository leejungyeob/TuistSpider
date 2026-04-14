import AppKit
import SwiftUI

enum GraphPathPalette {
    private static let colors: [Color] = [
        Color(red: 0.16, green: 0.56, blue: 0.99),
        Color(red: 0.12, green: 0.78, blue: 0.53),
        Color(red: 1.0, green: 0.67, blue: 0.16),
        Color(red: 0.92, green: 0.29, blue: 0.42),
        Color(red: 0.58, green: 0.46, blue: 0.98),
        Color(red: 0.0, green: 0.78, blue: 0.86),
        Color(red: 0.95, green: 0.44, blue: 0.2),
        Color(red: 0.73, green: 0.78, blue: 0.18)
    ]

    static func color(at index: Int) -> Color {
        colors[index % colors.count]
    }
}

struct GraphCanvasView: View {
    let subgraph: SpiderGraphSubgraph
    let presentationMode: GraphPresentationMode
    let focusedNodeID: String?
    let graphSelectedNodeID: String?
    let selectedLevel: Int
    let connectionPaths: [SpiderGraphConnectionPath]
    let hasConnectionPathContext: Bool
    let focusRequestID: Int
    @Binding var zoomScale: Double

    @GestureState private var gestureZoomScale: CGFloat = 1

    let onSelect: (String) -> Void
    let onSelectLevel: (Int) -> Void

    private var layout: SpiderGraphCanvasLayout {
        subgraph.canvasLayout
    }

    private var layerRegions: [SpiderGraphCanvasLayerRegion] {
        layout.layerRegions
    }

    private var levelGroups: [SpiderGraphLevelGroup] {
        subgraph.levelGroups
    }

    private var levelLayout: SpiderGraphLevelCanvasLayout {
        subgraph.levelCanvasLayout
    }

    private var activePathNodeIDs: Set<String> {
        Set(connectionPaths.flatMap(\.nodeIDs))
    }

    private var edgeConnectionPaths: [String: [SpiderGraphConnectionPath]] {
        Dictionary(
            grouping: connectionPaths.flatMap { path in
                path.edgeIDs.map { ($0, path) }
            },
            by: \.0
        )
        .mapValues { entries in
            entries.map(\.1)
                .sorted { lhs, rhs in lhs.paletteIndex < rhs.paletteIndex }
        }
    }

    private var effectiveZoomScale: CGFloat {
        CGFloat(clampZoomScale(zoomScale * Double(gestureZoomScale)))
    }

    private var baseCanvasSize: CGSize {
        presentationMode == .grouped ? levelLayout.canvasSize : layout.canvasSize
    }

    private var scaledCanvasSize: CGSize {
        CGSize(
            width: baseCanvasSize.width * effectiveZoomScale,
            height: baseCanvasSize.height * effectiveZoomScale
        )
    }

    private var shouldUseSelectiveRouting: Bool {
        subgraph.nodes.count > 80 || subgraph.edges.count > 140
    }

    private var expandedEdgeRenderModels: [ExpandedEdgeRenderModel] {
        var laneOccupancy = ExpandedEdgeLaneOccupancy()
        return subgraph.edges.compactMap { edge in
            guard let endpoints = subgraph.edgeEndpoints[edge.id] else { return nil }

            let matchingPaths = edgeConnectionPaths[edge.id] ?? []
            let geometry = expandedEdgeGeometry(
                for: edge,
                endpoints: endpoints,
                matchingPaths: matchingPaths,
                laneOccupancy: laneOccupancy
            )
            laneOccupancy.record(geometry)
            let baseArrowSize = baseArrowSize(for: edge)
            let baseLayer = ExpandedEdgeLayer(
                geometry: geometry,
                color: baseEdgeColor(for: edge, matchingPaths: matchingPaths),
                strokeStyle: baseEdgeStrokeStyle(for: edge),
                arrowColor: baseArrowColor(for: edge, matchingPaths: matchingPaths),
                arrowSize: baseArrowSize
            )

            let highlights = matchingPaths.enumerated().map { index, path in
                let color = GraphPathPalette.color(at: path.paletteIndex).opacity(0.98)
                let arrowSize = 11 + CGFloat(max(0, matchingPaths.count - index - 1))
                return ExpandedEdgeLayer(
                    geometry: geometry,
                    color: color,
                    strokeStyle: highlightedEdgeStrokeStyle(rank: index, total: matchingPaths.count),
                    arrowColor: color,
                    arrowSize: arrowSize
                )
            }

            return ExpandedEdgeRenderModel(id: edge.id, base: baseLayer, highlights: highlights)
        }
    }

    private var groupedEdgeRenderModels: [GroupedEdgeRenderModel] {
        subgraph.levelEdges.compactMap { edge in
            guard
                let from = levelLayout.groupFrames[edge.fromLevel],
                let to = levelLayout.groupFrames[edge.toLevel]
            else {
                return nil
            }

            let geometry = EdgePathGeometry.curve(EdgeCurveGeometry(from: from, to: to))
            return GroupedEdgeRenderModel(
                id: edge.id,
                geometry: geometry,
                strokeColor: edge.fromLevel == selectedLevel || edge.toLevel == selectedLevel ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.22),
                arrowColor: edge.fromLevel == selectedLevel || edge.toLevel == selectedLevel ? Color.accentColor.opacity(0.82) : Color.secondary.opacity(0.4),
                lineWidth: edge.fromLevel == selectedLevel || edge.toLevel == selectedLevel ? 3 : 2,
                arrowSize: edge.fromLevel == selectedLevel || edge.toLevel == selectedLevel ? 10 : 8
            )
        }
    }

    private var contentFocusRect: CGRect? {
        switch presentationMode {
        case .expanded:
            let targetNodeID = focusedNodeID ?? subgraph.nodes.first?.id
            guard let targetNodeID, let frame = layout.nodeFrames[targetNodeID] else { return nil }
            return scaledContentRect(for: frame)
        case .grouped:
            let targetLevel: Int? = {
                if levelLayout.groupFrames[selectedLevel] != nil { return selectedLevel }
                if let focusedNodeID, let level = subgraph.levels[focusedNodeID], levelLayout.groupFrames[level] != nil {
                    return level
                }
                if levelLayout.groupFrames[0] != nil { return 0 }
                return levelGroups.first?.level
            }()

            guard let targetLevel, let frame = levelLayout.groupFrames[targetLevel] else { return nil }
            return scaledContentRect(for: frame)
        }
    }

    var body: some View {
        if subgraph.nodes.isEmpty {
            ContentUnavailableView(
                "표시할 그래프가 없습니다",
                systemImage: "point.3.filled.connected.trianglepath.dotted",
                description: Text("왼쪽 목록에서 모듈을 선택하거나 외부 의존성 표시 옵션을 바꿔보세요.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ZStack(alignment: .topTrailing) {
                InteractiveCanvasScrollView(
                    zoomScale: $zoomScale,
                    focusRect: contentFocusRect,
                    focusRequestID: focusRequestID,
                    contentSize: CGSize(
                        width: scaledCanvasSize.width + 48,
                        height: scaledCanvasSize.height + 48
                    )
                ) {
                    canvasContent
                    .scaleEffect(effectiveZoomScale, anchor: .topLeading)
                    .frame(width: scaledCanvasSize.width, height: scaledCanvasSize.height, alignment: .topLeading)
                    .padding(24)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .simultaneousGesture(magnificationGesture)

                zoomControls
                    .padding(16)
            }
        }
    }

    @ViewBuilder
    private var canvasContent: some View {
        if presentationMode == .grouped {
            groupedCanvasContent
        } else {
            expandedCanvasContent
        }
    }

    private var expandedCanvasContent: some View {
        ZStack(alignment: .topLeading) {
            ForEach(layerRegions) { region in
                LayerRegionBackground(region: region)
                    .frame(width: region.frame.width, height: region.frame.height)
                    .position(x: region.frame.midX, y: region.frame.midY)
            }

            Canvas(rendersAsynchronously: true) { context, _ in
                drawExpandedEdges(in: context)
            }
            .allowsHitTesting(false)
            .frame(width: layout.canvasSize.width, height: layout.canvasSize.height)

            ForEach(subgraph.nodes) { node in
                if let frame = layout.nodeFrames[node.id] {
                    GraphNodeCard(
                        node: node,
                        isFocused: node.id == focusedNodeID,
                        isGraphSelected: node.id == graphSelectedNodeID,
                        isPathNode: activePathNodeIDs.contains(node.id),
                        action: { onSelect(node.id) }
                    )
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .frame(width: layout.canvasSize.width, height: layout.canvasSize.height, alignment: .topLeading)
    }

    private var groupedCanvasContent: some View {
        ZStack(alignment: .topLeading) {
            Canvas(rendersAsynchronously: true) { context, _ in
                drawGroupedEdges(in: context)
            }
            .allowsHitTesting(false)
            .frame(width: levelLayout.canvasSize.width, height: levelLayout.canvasSize.height)

            ForEach(subgraph.levelEdges) { edge in
                if let from = levelLayout.groupFrames[edge.fromLevel], let to = levelLayout.groupFrames[edge.toLevel] {
                    Text("\(edge.edgeCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(edge.fromLevel == selectedLevel || edge.toLevel == selectedLevel ? Color.accentColor : Color.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: Capsule())
                        .position(
                            x: (from.maxX + to.minX) / 2,
                            y: (from.midY + to.midY) / 2 - 16
                        )
                }
            }

            ForEach(levelGroups) { group in
                if let frame = levelLayout.groupFrames[group.level] {
                    LevelGroupCard(
                        group: group,
                        isSelected: group.level == selectedLevel,
                        action: { onSelectLevel(group.level) }
                    )
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .frame(width: levelLayout.canvasSize.width, height: levelLayout.canvasSize.height, alignment: .topLeading)
    }

    private var zoomControls: some View {
        VStack(alignment: .trailing, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    setZoomScale(zoomScale - TuistSpiderViewModel.zoomStep)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .disabled(zoomScale <= TuistSpiderViewModel.zoomScaleRange.lowerBound)

                Text("\(Int((effectiveZoomScale * 100).rounded()))%")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .frame(minWidth: 48)

                Button {
                    setZoomScale(zoomScale + TuistSpiderViewModel.zoomStep)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .disabled(zoomScale >= TuistSpiderViewModel.zoomScaleRange.upperBound)
            }

            Slider(
                value: Binding(
                    get: { zoomScale },
                    set: { setZoomScale($0) }
                ),
                in: TuistSpiderViewModel.zoomScaleRange
            )
            .frame(width: 140)

            Button("100%") {
                setZoomScale(TuistSpiderViewModel.defaultZoomScale)
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .updating($gestureZoomScale) { value, state, _ in
                state = value
            }
            .onEnded { value in
                setZoomScale(zoomScale * Double(value))
            }
    }

    private func setZoomScale(_ value: Double) {
        zoomScale = clampZoomScale(value)
    }

    private func clampZoomScale(_ value: Double) -> Double {
        min(max(value, TuistSpiderViewModel.zoomScaleRange.lowerBound), TuistSpiderViewModel.zoomScaleRange.upperBound)
    }

    private func scaledContentRect(for frame: CGRect) -> CGRect {
        CGRect(
            x: 24 + frame.origin.x * effectiveZoomScale,
            y: 24 + frame.origin.y * effectiveZoomScale,
            width: frame.width * effectiveZoomScale,
            height: frame.height * effectiveZoomScale
        )
    }

    private func baseEdgeColor(for edge: SpiderGraphEdge, matchingPaths: [SpiderGraphConnectionPath]) -> Color {
        let isFocusedEdge = edge.from == focusedNodeID || edge.to == focusedNodeID
        let isGraphSelectedEdge = edge.from == graphSelectedNodeID || edge.to == graphSelectedNodeID
        let isOnVisiblePath = !matchingPaths.isEmpty

        if hasConnectionPathContext {
            if isOnVisiblePath {
                return Color.white.opacity(0.14)
            }
            if isFocusedEdge || isGraphSelectedEdge {
                return Color.secondary.opacity(0.14)
            }
            return Color.secondary.opacity(0.05)
        }

        if isFocusedEdge {
            return Color.accentColor.opacity(0.45)
        }
        return Color.secondary.opacity(0.22)
    }

    private func baseEdgeStrokeStyle(for edge: SpiderGraphEdge) -> StrokeStyle {
        let lineWidth: CGFloat
        if hasConnectionPathContext {
            lineWidth = edge.from == focusedNodeID || edge.to == focusedNodeID || edge.from == graphSelectedNodeID || edge.to == graphSelectedNodeID ? 2.5 : 1.5
        } else if edge.from == focusedNodeID || edge.to == focusedNodeID {
            lineWidth = 3
        } else {
            lineWidth = 2
        }

        return StrokeStyle(lineWidth: lineWidth, lineCap: .round)
    }

    private func highlightedEdgeStrokeStyle(rank: Int, total: Int) -> StrokeStyle {
        let outerWidth: CGFloat = total == 1 ? 4.5 : 4.5 + CGFloat(total - 1) * 2.25
        let width = max(2.4, outerWidth - CGFloat(rank) * 2.25)
        return StrokeStyle(lineWidth: width, lineCap: .round)
    }

    private func baseArrowColor(for edge: SpiderGraphEdge, matchingPaths: [SpiderGraphConnectionPath]) -> Color {
        if let primaryPath = matchingPaths.first {
            return GraphPathPalette.color(at: primaryPath.paletteIndex).opacity(0.94)
        }
        return baseEdgeColor(for: edge, matchingPaths: matchingPaths).opacity(0.9)
    }

    private func baseArrowSize(for edge: SpiderGraphEdge) -> CGFloat {
        if hasConnectionPathContext, edge.from != focusedNodeID, edge.to != focusedNodeID {
            return 8
        }
        return 10
    }

    private func arrowLineInset(for arrowSize: CGFloat) -> CGFloat {
        max(7, arrowSize + 1.5)
    }

    private func expandedEdgeGeometry(
        for edge: SpiderGraphEdge,
        endpoints: SpiderGraphEdgeEndpoints,
        matchingPaths: [SpiderGraphConnectionPath],
        laneOccupancy: ExpandedEdgeLaneOccupancy
    ) -> EdgePathGeometry {
        let directGeometry = preferredExpandedDirectGeometry(
            for: endpoints,
            laneOccupancy: laneOccupancy
        )
        guard shouldRouteAroundObstacles(for: edge, matchingPaths: matchingPaths) else {
            return directGeometry
        }
        let obstacles = expandedObstacleFrames(for: edge, endpoints: endpoints)
        let directIntersections = intersectingObstacles(for: directGeometry, obstacles: obstacles)
        let directOverlapPenalty = laneOccupancy.overlapPenalty(for: directGeometry)
        guard !directIntersections.isEmpty || directOverlapPenalty > 0 else {
            return directGeometry
        }

        let startX = min(endpoints.start.x, endpoints.end.x)
        let startY = min(endpoints.start.y, endpoints.end.y)
        let routeBounds = directIntersections.isEmpty
            ? CGRect(
                x: startX,
                y: startY,
                width: max(abs(endpoints.end.x - endpoints.start.x), 1),
                height: max(abs(endpoints.end.y - endpoints.start.y), 1)
            )
            : directIntersections.reduce(into: directIntersections[0]) { partialResult, frame in
                partialResult = partialResult.union(frame)
            }
        var bestCandidate = (
            geometry: directGeometry,
            collisionCount: directIntersections.count,
            overlapPenalty: directOverlapPenalty,
            distanceCost: CGFloat(0)
        )

        if endpoints.sourceSide.isHorizontal && endpoints.targetSide.isHorizontal {
            let horizontalDistance = abs(endpoints.end.x - endpoints.start.x)
            let baseHorizontalInset = min(max(horizontalDistance * 0.2, 28), 56)
            let insetCandidates = [
                baseHorizontalInset,
                min(baseHorizontalInset + 24, max(72, horizontalDistance * 0.4)),
                min(baseHorizontalInset + 52, max(96, horizontalDistance * 0.55))
            ]

            let minStartEndY = min(endpoints.start.y, endpoints.end.y)
            let maxStartEndY = max(endpoints.start.y, endpoints.end.y)
            let nearLaneMargin: CGFloat = 22
            let farLaneMargin: CGFloat = 36
            let obstacleLanes = directIntersections.flatMap { frame in
                [
                    max(18, frame.minY - nearLaneMargin),
                    min(layout.canvasSize.height - 18, frame.maxY + nearLaneMargin)
                ]
            }
            let topLane = max(18, routeBounds.minY - farLaneMargin)
            let bottomLane = min(layout.canvasSize.height - 18, routeBounds.maxY + farLaneMargin)
            let farTopLane = max(18, min(topLane - 28, minStartEndY - 24))
            let farBottomLane = min(layout.canvasSize.height - 18, max(bottomLane + 28, maxStartEndY + 24))
            let laneCandidates = uniqueLaneValues(obstacleLanes + [topLane, bottomLane, farTopLane, farBottomLane])
                .sorted {
                    laneDistanceCost(for: endpoints, laneY: $0) < laneDistanceCost(for: endpoints, laneY: $1)
                }

            for laneY in laneCandidates {
                for horizontalInset in insetCandidates {
                    let startLead = offsetPoint(endpoints.start, toward: endpoints.sourceSide, distance: horizontalInset)
                    let endLead = offsetPoint(endpoints.end, toward: endpoints.targetSide, distance: horizontalInset)
                    let rawPoints: [CGPoint] = [
                        endpoints.start,
                        startLead,
                        CGPoint(x: startLead.x, y: laneY),
                        CGPoint(x: endLead.x, y: laneY),
                        endLead,
                        endpoints.end
                    ]
                    let points = deduplicatedRoutePoints(rawPoints)
                    guard points.count >= 2 else { continue }

                    let geometry = EdgePathGeometry.routed(EdgeRoutedGeometry(points: points))
                    let collisions = intersectingObstacles(for: geometry, obstacles: obstacles)
                    let overlapPenalty = laneOccupancy.overlapPenalty(for: geometry)
                    if collisions.isEmpty, overlapPenalty <= 0.5 {
                        return geometry
                    }

                    let candidate = (
                        geometry: geometry,
                        collisionCount: collisions.count,
                        overlapPenalty: overlapPenalty,
                        distanceCost: laneDistanceCost(for: endpoints, laneY: laneY) + centerBias(for: endpoints, laneY: laneY) * 0.45 + horizontalInset * 0.12
                    )

                    if candidate.collisionCount < bestCandidate.collisionCount ||
                        (candidate.collisionCount == bestCandidate.collisionCount && candidate.overlapPenalty < bestCandidate.overlapPenalty) ||
                        (candidate.collisionCount == bestCandidate.collisionCount &&
                            abs(candidate.overlapPenalty - bestCandidate.overlapPenalty) < 0.5 &&
                            candidate.distanceCost < bestCandidate.distanceCost) {
                        bestCandidate = candidate
                    }
                }
            }
        } else {
            let verticalDistance = abs(endpoints.end.y - endpoints.start.y)
            let baseVerticalInset = min(max(verticalDistance * 0.2, 26), 54)
            let insetCandidates = [
                baseVerticalInset,
                min(baseVerticalInset + 20, max(68, verticalDistance * 0.38)),
                min(baseVerticalInset + 44, max(92, verticalDistance * 0.52))
            ]

            let minStartEndX = min(endpoints.start.x, endpoints.end.x)
            let maxStartEndX = max(endpoints.start.x, endpoints.end.x)
            let nearLaneMargin: CGFloat = 22
            let farLaneMargin: CGFloat = 36
            let obstacleLanes = directIntersections.flatMap { frame in
                [
                    max(18, frame.minX - nearLaneMargin),
                    min(layout.canvasSize.width - 18, frame.maxX + nearLaneMargin)
                ]
            }
            let leftLane = max(18, routeBounds.minX - farLaneMargin)
            let rightLane = min(layout.canvasSize.width - 18, routeBounds.maxX + farLaneMargin)
            let farLeftLane = max(18, min(leftLane - 28, minStartEndX - 24))
            let farRightLane = min(layout.canvasSize.width - 18, max(rightLane + 28, maxStartEndX + 24))
            let laneCandidates = uniqueLaneValues(obstacleLanes + [leftLane, rightLane, farLeftLane, farRightLane])
                .sorted {
                    laneDistanceCost(for: endpoints, laneX: $0) < laneDistanceCost(for: endpoints, laneX: $1)
                }

            for laneX in laneCandidates {
                for verticalInset in insetCandidates {
                    let startLead = offsetPoint(endpoints.start, toward: endpoints.sourceSide, distance: verticalInset)
                    let endLead = offsetPoint(endpoints.end, toward: endpoints.targetSide, distance: verticalInset)
                    let rawPoints: [CGPoint] = [
                        endpoints.start,
                        startLead,
                        CGPoint(x: laneX, y: startLead.y),
                        CGPoint(x: laneX, y: endLead.y),
                        endLead,
                        endpoints.end
                    ]
                    let points = deduplicatedRoutePoints(rawPoints)
                    guard points.count >= 2 else { continue }

                    let geometry = EdgePathGeometry.routed(EdgeRoutedGeometry(points: points))
                    let collisions = intersectingObstacles(for: geometry, obstacles: obstacles)
                    let overlapPenalty = laneOccupancy.overlapPenalty(for: geometry)
                    if collisions.isEmpty, overlapPenalty <= 0.5 {
                        return geometry
                    }

                    let candidate = (
                        geometry: geometry,
                        collisionCount: collisions.count,
                        overlapPenalty: overlapPenalty,
                        distanceCost: laneDistanceCost(for: endpoints, laneX: laneX) + centerBias(for: endpoints, laneX: laneX) * 0.45 + verticalInset * 0.12
                    )

                    if candidate.collisionCount < bestCandidate.collisionCount ||
                        (candidate.collisionCount == bestCandidate.collisionCount && candidate.overlapPenalty < bestCandidate.overlapPenalty) ||
                        (candidate.collisionCount == bestCandidate.collisionCount &&
                            abs(candidate.overlapPenalty - bestCandidate.overlapPenalty) < 0.5 &&
                            candidate.distanceCost < bestCandidate.distanceCost) {
                        bestCandidate = candidate
                    }
                }
            }
        }

        return bestCandidate.geometry
    }

    private func preferredExpandedDirectGeometry(
        for endpoints: SpiderGraphEdgeEndpoints,
        laneOccupancy: ExpandedEdgeLaneOccupancy
    ) -> EdgePathGeometry {
        let directGeometry = baseExpandedDirectGeometry(for: endpoints)
        let candidates = [directGeometry] + directDetourGeometries(for: endpoints)

        return candidates.min { lhs, rhs in
            let lhsPenalty = laneOccupancy.overlapPenalty(for: lhs)
            let rhsPenalty = laneOccupancy.overlapPenalty(for: rhs)
            if abs(lhsPenalty - rhsPenalty) >= 0.5 {
                return lhsPenalty < rhsPenalty
            }
            return geometryDistanceCost(lhs) < geometryDistanceCost(rhs)
        } ?? directGeometry
    }

    private func baseExpandedDirectGeometry(for endpoints: SpiderGraphEdgeEndpoints) -> EdgePathGeometry {
        if shouldUseStraightExpandedGeometry(for: endpoints) {
            return .routed(EdgeRoutedGeometry(points: [endpoints.start, endpoints.end]))
        }

        if endpoints.sourceSide.isHorizontal && endpoints.targetSide.isHorizontal {
            let leadDistance: CGFloat = max(min(abs(endpoints.end.x - endpoints.start.x) * 0.18, 34), 18)
            let startLead = offsetPoint(endpoints.start, toward: endpoints.sourceSide, distance: leadDistance)
            let endLead = offsetPoint(endpoints.end, toward: endpoints.targetSide, distance: leadDistance)
            guard abs(startLead.y - endLead.y) > 6 else {
                return .routed(EdgeRoutedGeometry(points: deduplicatedRoutePoints([endpoints.start, startLead, endLead, endpoints.end])))
            }

            let midpointX = startLead.x + (endLead.x - startLead.x) / 2
            let points = deduplicatedRoutePoints([
                endpoints.start,
                startLead,
                CGPoint(x: midpointX, y: startLead.y),
                CGPoint(x: midpointX, y: endLead.y),
                endLead,
                endpoints.end
            ])
            return .routed(EdgeRoutedGeometry(points: points))
        }

        let leadDistance: CGFloat = max(min(abs(endpoints.end.y - endpoints.start.y) * 0.22, 42), 24)
        let startLead = offsetPoint(endpoints.start, toward: endpoints.sourceSide, distance: leadDistance)
        let endLead = offsetPoint(endpoints.end, toward: endpoints.targetSide, distance: leadDistance)
        let midpointY = startLead.y + (endLead.y - startLead.y) / 2
        let rawPoints = [
            endpoints.start,
            startLead,
            CGPoint(x: startLead.x, y: midpointY),
            CGPoint(x: endLead.x, y: midpointY),
            endLead,
            endpoints.end
        ]
        let points = deduplicatedRoutePoints(rawPoints)

        guard points.count >= 2 else {
            return .curve(EdgeCurveGeometry(start: endpoints.start, end: endpoints.end))
        }

        return .routed(EdgeRoutedGeometry(points: points))
    }

    private func directDetourGeometries(for endpoints: SpiderGraphEdgeEndpoints) -> [EdgePathGeometry] {
        if endpoints.sourceSide.isHorizontal && endpoints.targetSide.isHorizontal {
            let leadDistance: CGFloat = max(min(abs(endpoints.end.x - endpoints.start.x) * 0.18, 34), 18)
            let startLead = offsetPoint(endpoints.start, toward: endpoints.sourceSide, distance: leadDistance)
            let endLead = offsetPoint(endpoints.end, toward: endpoints.targetSide, distance: leadDistance)
            let centerY = (startLead.y + endLead.y) / 2
            let baseOffset = max(18, min(abs(endpoints.end.y - endpoints.start.y) * 0.24 + 14, 36))
            let laneYs = uniqueLaneValues([
                centerY - baseOffset,
                centerY + baseOffset,
                centerY - baseOffset * 1.75,
                centerY + baseOffset * 1.75
            ].map { min(max($0, 18), layout.canvasSize.height - 18) })

            return laneYs.compactMap { laneY in
                let points = deduplicatedRoutePoints([
                    endpoints.start,
                    startLead,
                    CGPoint(x: startLead.x, y: laneY),
                    CGPoint(x: endLead.x, y: laneY),
                    endLead,
                    endpoints.end
                ])
                guard points.count >= 2 else { return nil }
                return .routed(EdgeRoutedGeometry(points: points))
            }
        }

        let leadDistance: CGFloat = max(min(abs(endpoints.end.y - endpoints.start.y) * 0.22, 42), 24)
        let startLead = offsetPoint(endpoints.start, toward: endpoints.sourceSide, distance: leadDistance)
        let endLead = offsetPoint(endpoints.end, toward: endpoints.targetSide, distance: leadDistance)
        let centerX = (startLead.x + endLead.x) / 2
        let baseOffset = max(18, min(abs(endpoints.end.x - endpoints.start.x) * 0.24 + 14, 36))
        let laneXs = uniqueLaneValues([
            centerX - baseOffset,
            centerX + baseOffset,
            centerX - baseOffset * 1.75,
            centerX + baseOffset * 1.75
        ].map { min(max($0, 18), layout.canvasSize.width - 18) })

        return laneXs.compactMap { laneX in
            let points = deduplicatedRoutePoints([
                endpoints.start,
                startLead,
                CGPoint(x: laneX, y: startLead.y),
                CGPoint(x: laneX, y: endLead.y),
                endLead,
                endpoints.end
            ])
            guard points.count >= 2 else { return nil }
            return .routed(EdgeRoutedGeometry(points: points))
        }
    }

    private func geometryDistanceCost(_ geometry: EdgePathGeometry) -> CGFloat {
        geometry.sampledPoints().adjacentPairs().reduce(into: 0) { partialResult, pair in
            partialResult += hypot(pair.1.x - pair.0.x, pair.1.y - pair.0.y)
        }
    }

    private func shouldUseStraightExpandedGeometry(for endpoints: SpiderGraphEdgeEndpoints) -> Bool {
        guard endpoints.sourceSide.isHorizontal == endpoints.targetSide.isHorizontal else {
            return false
        }
        guard areOpposingSides(endpoints.sourceSide, endpoints.targetSide) else {
            return false
        }

        let deltaX = abs(endpoints.end.x - endpoints.start.x)
        let deltaY = abs(endpoints.end.y - endpoints.start.y)

        if endpoints.sourceSide.isHorizontal {
            return deltaX >= 56 && deltaY <= 18
        }

        return deltaY >= 56 && deltaX <= 18
    }

    private func areOpposingSides(_ lhs: SpiderGraphAnchorSide, _ rhs: SpiderGraphAnchorSide) -> Bool {
        switch (lhs, rhs) {
        case (.left, .right), (.right, .left), (.top, .bottom), (.bottom, .top):
            return true
        default:
            return false
        }
    }

    private func expandedObstacleFrames(
        for edge: SpiderGraphEdge,
        endpoints: SpiderGraphEdgeEndpoints
    ) -> [CGRect] {
        let usesHorizontalAnchors = endpoints.sourceSide.isHorizontal && endpoints.targetSide.isHorizontal
        let horizontalPadding = usesHorizontalAnchors ? CGSize(width: 10, height: 14) : CGSize(width: 16, height: 8)
        return layout.nodeFrames.compactMap { nodeID, frame in
            guard nodeID != edge.from, nodeID != edge.to else { return nil }
            return frame.insetBy(dx: -horizontalPadding.width, dy: -horizontalPadding.height)
        }
    }

    private func intersectingObstacles(
        for geometry: EdgePathGeometry,
        obstacles: [CGRect]
    ) -> [CGRect] {
        obstacles.filter { geometry.intersects($0) }
    }

    private func laneDistanceCost(
        for endpoints: SpiderGraphEdgeEndpoints,
        laneY: CGFloat
    ) -> CGFloat {
        abs(endpoints.start.y - laneY) + abs(endpoints.end.y - laneY)
    }

    private func laneDistanceCost(
        for endpoints: SpiderGraphEdgeEndpoints,
        laneX: CGFloat
    ) -> CGFloat {
        abs(endpoints.start.x - laneX) + abs(endpoints.end.x - laneX)
    }

    private func centerBias(
        for endpoints: SpiderGraphEdgeEndpoints,
        laneY: CGFloat
    ) -> CGFloat {
        abs(((endpoints.start.y + endpoints.end.y) / 2) - laneY)
    }

    private func centerBias(
        for endpoints: SpiderGraphEdgeEndpoints,
        laneX: CGFloat
    ) -> CGFloat {
        abs(((endpoints.start.x + endpoints.end.x) / 2) - laneX)
    }

    private func uniqueLaneValues(_ values: [CGFloat]) -> [CGFloat] {
        values.reduce(into: [CGFloat]()) { lanes, value in
            guard !lanes.contains(where: { abs($0 - value) < 1 }) else { return }
            lanes.append(value)
        }
    }

    private func deduplicatedRoutePoints(_ points: [CGPoint]) -> [CGPoint] {
        points.reduce(into: [CGPoint]()) { partialResult, point in
            guard partialResult.last != point else { return }
            partialResult.append(point)
        }
    }

    private func offsetPoint(_ point: CGPoint, toward side: SpiderGraphAnchorSide, distance: CGFloat) -> CGPoint {
        let vector = side.outwardUnitVector
        return CGPoint(
            x: point.x + vector.x * distance,
            y: point.y + vector.y * distance
        )
    }

    private func shouldRouteAroundObstacles(
        for edge: SpiderGraphEdge,
        matchingPaths: [SpiderGraphConnectionPath]
    ) -> Bool {
        if !shouldUseSelectiveRouting {
            return true
        }

        if !matchingPaths.isEmpty {
            return true
        }

        let isFocusedEdge = edge.from == focusedNodeID || edge.to == focusedNodeID
        let isGraphSelectedEdge = edge.from == graphSelectedNodeID || edge.to == graphSelectedNodeID
        return isFocusedEdge || isGraphSelectedEdge
    }

    private func drawExpandedEdges(in context: GraphicsContext) {
        for model in expandedEdgeRenderModels {
            var layerContext = context
            drawEdgeLayer(model.base, in: &layerContext)
            for highlight in model.highlights {
                drawEdgeLayer(highlight, in: &layerContext)
            }
        }
    }

    private func drawGroupedEdges(in context: GraphicsContext) {
        let context = context
        for model in groupedEdgeRenderModels {
            let linePath = model.geometry.trimmedEnd(by: arrowLineInset(for: model.arrowSize)).path()
            context.stroke(
                linePath,
                with: .color(model.strokeColor),
                style: StrokeStyle(lineWidth: model.lineWidth, lineCap: .round)
            )

            let arrowPath = ArrowHeadShape(
                tip: model.geometry.arrowTip(),
                angle: model.geometry.arrowAngle,
                size: model.arrowSize
            ).path(in: .zero)
            context.fill(arrowPath, with: .color(model.arrowColor))
        }
    }

    private func drawEdgeLayer(_ layer: ExpandedEdgeLayer, in context: inout GraphicsContext) {
        let linePath = layer.geometry.trimmedEnd(by: arrowLineInset(for: layer.arrowSize)).path()
        context.stroke(linePath, with: .color(layer.color), style: layer.strokeStyle)

        let arrowPath = ArrowHeadShape(
            tip: layer.geometry.arrowTip(),
            angle: layer.geometry.arrowAngle,
            size: layer.arrowSize
        ).path(in: .zero)
        context.fill(arrowPath, with: .color(layer.arrowColor))
    }
}

private struct GraphNodeCard: View {
    let node: SpiderGraphNode
    let isFocused: Bool
    let isGraphSelected: Bool
    let isPathNode: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(node.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(node.projectLabel) / \(node.kindLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return shape
            .fill(baseBackgroundColor)
            .overlay {
                shape.fill(highlightOverlayColor)
            }
    }

    private var baseBackgroundColor: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    private var highlightOverlayColor: Color {
        if isGraphSelected {
            return Color.accentColor.opacity(0.22)
        }
        if isFocused {
            return Color.accentColor.opacity(0.16)
        }
        if isPathNode {
            return Color.accentColor.opacity(0.08)
        }
        if node.isExternal {
            return Color.orange.opacity(0.12)
        }
        return .clear
    }

    private var borderColor: Color {
        if isGraphSelected { return .accentColor.opacity(0.95) }
        if isFocused { return .accentColor.opacity(0.6) }
        if isPathNode { return .accentColor.opacity(0.28) }
        if node.isExternal { return .orange.opacity(0.35) }
        return .secondary.opacity(0.15)
    }

    private var borderWidth: CGFloat {
        if isGraphSelected { return 2.5 }
        if isFocused { return 2 }
        if isPathNode { return 1.5 }
        return 1
    }
}

private struct LayerRegionBackground: View {
    let region: SpiderGraphCanvasLayerRegion

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(regionColor.opacity(region.kind == .external ? 0.08 : 0.11))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(
                            boundaryColor,
                            lineWidth: 1.6
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .inset(by: 3)
                        .strokeBorder(
                            regionColor.opacity(region.kind == .external ? 0.24 : 0.34),
                            style: StrokeStyle(lineWidth: 1.1, dash: [10, 8])
                        )
                )
                .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 10)

            VStack(spacing: 0) {
                regionDivider
                Spacer()
                regionDivider
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(regionColor)
                    .frame(width: 6, height: 22)

                Text(region.kind.title)
                    .font(.caption.weight(.bold))
                Text("\(region.nodeIDs.count)개")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(headerBackground, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(regionColor.opacity(0.55), lineWidth: 1)
            )
            .shadow(color: regionColor.opacity(0.18), radius: 6, x: 0, y: 3)
            .padding(14)
        }
        .allowsHitTesting(false)
    }

    private var regionColor: Color {
        LayerColorPalette.color(
            for: region.kind.layerName,
            isExternal: region.kind == .external
        )
    }

    private var boundaryColor: Color {
        Color.primary.opacity(0.18)
    }

    private var headerBackground: Color {
        Color(nsColor: .windowBackgroundColor).opacity(0.92)
    }

    private var regionDivider: some View {
        Rectangle()
            .fill(boundaryColor)
            .frame(height: 1.5)
            .overlay(
                Rectangle()
                    .fill(regionColor.opacity(0.25))
                    .frame(height: 0.5)
                    .offset(y: 0.5)
            )
    }
}

private struct ExpandedEdgeRenderModel: Identifiable {
    let id: String
    let base: ExpandedEdgeLayer
    let highlights: [ExpandedEdgeLayer]
}

private struct ExpandedEdgeLayer {
    let geometry: EdgePathGeometry
    let color: Color
    let strokeStyle: StrokeStyle
    let arrowColor: Color
    let arrowSize: CGFloat
}

private struct GroupedEdgeRenderModel: Identifiable {
    let id: String
    let geometry: EdgePathGeometry
    let strokeColor: Color
    let arrowColor: Color
    let lineWidth: CGFloat
    let arrowSize: CGFloat
}

private struct EdgeShape: Shape {
    let geometry: EdgePathGeometry

    init(from: CGRect, to: CGRect) {
        geometry = .curve(EdgeCurveGeometry(from: from, to: to))
    }

    init(geometry: EdgePathGeometry) {
        self.geometry = geometry
    }

    func path(in _: CGRect) -> Path {
        geometry.path()
    }
}

private enum EdgePathGeometry {
    case curve(EdgeCurveGeometry)
    case routed(EdgeRoutedGeometry)

    var arrowAngle: CGFloat {
        switch self {
        case let .curve(geometry):
            geometry.arrowAngle
        case let .routed(geometry):
            geometry.arrowAngle
        }
    }

    func trimmedEnd(by distance: CGFloat) -> EdgePathGeometry {
        switch self {
        case let .curve(geometry):
            .curve(geometry.trimmedEnd(by: distance))
        case let .routed(geometry):
            .routed(geometry.trimmedEnd(by: distance))
        }
    }

    func arrowTip(inset: CGFloat = 4) -> CGPoint {
        switch self {
        case let .curve(geometry):
            geometry.arrowTip(inset: inset)
        case let .routed(geometry):
            geometry.arrowTip(inset: inset)
        }
    }

    func path() -> Path {
        switch self {
        case let .curve(geometry):
            var path = Path()
            path.move(to: geometry.start)
            path.addCurve(
                to: geometry.end,
                control1: geometry.control1,
                control2: geometry.control2
            )
            return path
        case let .routed(geometry):
            return geometry.path()
        }
    }

    func intersects(_ rect: CGRect) -> Bool {
        sampledPoints().adjacentPairs().contains { start, end in
            segmentIntersectsRect(start: start, end: end, rect: rect)
        }
    }

    func sampledPoints() -> [CGPoint] {
        switch self {
        case let .curve(geometry):
            geometry.sampledPoints(steps: 24)
        case let .routed(geometry):
            geometry.sampledPoints()
        }
    }

    var axisAlignedSegments: [ExpandedEdgeLaneOccupancy.Segment] {
        sampledPoints().adjacentPairs().compactMap { start, end in
            ExpandedEdgeLaneOccupancy.Segment(start: start, end: end)
        }
    }
}

private struct EdgeCurveGeometry {
    let start: CGPoint
    let end: CGPoint
    let control1: CGPoint
    let control2: CGPoint

    init(from: CGRect, to: CGRect) {
        let isForward = from.midX <= to.midX
        let start = CGPoint(x: isForward ? from.maxX : from.minX, y: from.midY)
        let end = CGPoint(x: isForward ? to.minX : to.maxX, y: to.midY)
        self.init(start: start, end: end)
    }

    init(start: CGPoint, end: CGPoint, control1: CGPoint, control2: CGPoint) {
        self.start = start
        self.end = end
        self.control1 = control1
        self.control2 = control2
    }

    init(start: CGPoint, end: CGPoint) {
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y

        if abs(deltaX) < abs(deltaY) * 0.7 {
            let direction: CGFloat = deltaY >= 0 ? 1 : -1
            let verticalDelta = max(abs(deltaY) * 0.4, 30)
            self.init(
                start: start,
                end: end,
                control1: CGPoint(x: start.x, y: start.y + direction * verticalDelta),
                control2: CGPoint(x: end.x, y: end.y - direction * verticalDelta)
            )
        } else {
            let direction: CGFloat = deltaX >= 0 ? 1 : -1
            let horizontalDelta = max(abs(deltaX) * 0.45, 36)
            self.init(
                start: start,
                end: end,
                control1: CGPoint(x: start.x + direction * horizontalDelta, y: start.y),
                control2: CGPoint(x: end.x - direction * horizontalDelta, y: end.y)
            )
        }
    }

    var arrowAngle: CGFloat {
        atan2(end.y - control2.y, end.x - control2.x)
    }

    func trimmedEnd(by distance: CGFloat) -> EdgeCurveGeometry {
        let clampedDistance = max(0, distance)
        let end = pointByMovingBack(from: end, distance: clampedDistance)
        let control2 = pointByMovingBack(from: control2, distance: clampedDistance * 0.88)
        return EdgeCurveGeometry(start: start, end: end, control1: control1, control2: control2)
    }

    func arrowTip(inset: CGFloat = 4) -> CGPoint {
        pointByMovingBack(from: end, distance: inset)
    }

    private func pointByMovingBack(from point: CGPoint, distance: CGFloat) -> CGPoint {
        CGPoint(
            x: point.x - cos(arrowAngle) * distance,
            y: point.y - sin(arrowAngle) * distance
        )
    }

    func sampledPoints(steps: Int) -> [CGPoint] {
        guard steps > 1 else { return [start, end] }
        return (0...steps).map { step in
            let t = CGFloat(step) / CGFloat(steps)
            let oneMinusT = 1 - t
            let x =
                oneMinusT * oneMinusT * oneMinusT * start.x +
                3 * oneMinusT * oneMinusT * t * control1.x +
                3 * oneMinusT * t * t * control2.x +
                t * t * t * end.x
            let y =
                oneMinusT * oneMinusT * oneMinusT * start.y +
                3 * oneMinusT * oneMinusT * t * control1.y +
                3 * oneMinusT * t * t * control2.y +
                t * t * t * end.y
            return CGPoint(x: x, y: y)
        }
    }
}

private struct EdgeRoutedGeometry {
    let points: [CGPoint]

    var arrowAngle: CGFloat {
        guard points.count >= 2 else { return 0 }
        let from = points[points.count - 2]
        let to = points[points.count - 1]
        return atan2(to.y - from.y, to.x - from.x)
    }

    func trimmedEnd(by distance: CGFloat) -> EdgeRoutedGeometry {
        guard points.count >= 2 else { return self }
        var adjustedPoints = points
        let lastIndex = adjustedPoints.count - 1
        let previous = adjustedPoints[lastIndex - 1]
        let end = adjustedPoints[lastIndex]
        let segmentLength = hypot(end.x - previous.x, end.y - previous.y)
        guard segmentLength > .ulpOfOne else { return self }

        let clampedDistance = min(max(0, distance), max(0, segmentLength - 1))
        let ratio = (segmentLength - clampedDistance) / segmentLength
        adjustedPoints[lastIndex] = CGPoint(
            x: previous.x + (end.x - previous.x) * ratio,
            y: previous.y + (end.y - previous.y) * ratio
        )
        return EdgeRoutedGeometry(points: adjustedPoints)
    }

    func arrowTip(inset: CGFloat = 4) -> CGPoint {
        guard points.count >= 2 else { return points.last ?? .zero }
        let previous = points[points.count - 2]
        let end = points[points.count - 1]
        let segmentLength = hypot(end.x - previous.x, end.y - previous.y)
        guard segmentLength > .ulpOfOne else { return end }

        let clampedInset = min(max(0, inset), max(0, segmentLength - 1))
        let ratio = (segmentLength - clampedInset) / segmentLength
        return CGPoint(
            x: previous.x + (end.x - previous.x) * ratio,
            y: previous.y + (end.y - previous.y) * ratio
        )
    }

    func path() -> Path {
        guard let first = points.first else { return Path() }
        guard points.count >= 2 else {
            var path = Path()
            path.move(to: first)
            return path
        }

        var path = Path()
        path.move(to: first)

        if points.count == 2 {
            path.addLine(to: points[1])
            return path
        }

        let cornerRadius: CGFloat = 16
        var currentPoint = first

        for index in 1..<(points.count - 1) {
            let previous = points[index - 1]
            let current = points[index]
            let next = points[index + 1]

            let incomingLength = hypot(current.x - previous.x, current.y - previous.y)
            let outgoingLength = hypot(next.x - current.x, next.y - current.y)
            guard incomingLength > .ulpOfOne, outgoingLength > .ulpOfOne else { continue }

            let radius = min(cornerRadius, incomingLength / 2, outgoingLength / 2)
            let incomingDirection = CGPoint(
                x: (current.x - previous.x) / incomingLength,
                y: (current.y - previous.y) / incomingLength
            )
            let outgoingDirection = CGPoint(
                x: (next.x - current.x) / outgoingLength,
                y: (next.y - current.y) / outgoingLength
            )

            let cornerStart = CGPoint(
                x: current.x - incomingDirection.x * radius,
                y: current.y - incomingDirection.y * radius
            )
            let cornerEnd = CGPoint(
                x: current.x + outgoingDirection.x * radius,
                y: current.y + outgoingDirection.y * radius
            )

            if currentPoint != cornerStart {
                path.addLine(to: cornerStart)
            }
            path.addQuadCurve(to: cornerEnd, control: current)
            currentPoint = cornerEnd
        }

        if let last = points.last, currentPoint != last {
            path.addLine(to: last)
        }

        return path
    }

    func sampledPoints() -> [CGPoint] {
        points
    }
}

struct ExpandedEdgeLaneOccupancy {
    struct Segment: Hashable {
        enum Orientation: Hashable {
            case horizontal
            case vertical
        }

        let orientation: Orientation
        let laneValue: CGFloat
        let lowerBound: CGFloat
        let upperBound: CGFloat

        init?(start: CGPoint, end: CGPoint) {
            let deltaX = end.x - start.x
            let deltaY = end.y - start.y
            let axisTolerance: CGFloat = 1

            if abs(deltaX) <= axisTolerance, abs(deltaY) > axisTolerance {
                orientation = .vertical
                laneValue = start.x
                lowerBound = min(start.y, end.y)
                upperBound = max(start.y, end.y)
            } else if abs(deltaY) <= axisTolerance, abs(deltaX) > axisTolerance {
                orientation = .horizontal
                laneValue = start.y
                lowerBound = min(start.x, end.x)
                upperBound = max(start.x, end.x)
            } else {
                return nil
            }
        }

        var length: CGFloat {
            upperBound - lowerBound
        }

        func overlapPenalty(with other: Segment) -> CGFloat {
            guard orientation == other.orientation else { return 0 }

            let laneDistance = abs(laneValue - other.laneValue)
            let laneThreshold: CGFloat = 12
            guard laneDistance < laneThreshold else { return 0 }

            let overlapLength = min(upperBound, other.upperBound) - max(lowerBound, other.lowerBound)
            guard overlapLength > 8 else { return 0 }

            let proximityWeight = 1 + (laneThreshold - laneDistance) / 4
            return overlapLength * proximityWeight + 28
        }
    }

    private var segments: [Segment] = []

    fileprivate mutating func record(_ geometry: EdgePathGeometry) {
        segments.append(contentsOf: geometry.axisAlignedSegments)
    }

    mutating func record(points: [CGPoint]) {
        segments.append(contentsOf: points.adjacentPairs().compactMap { Segment(start: $0.0, end: $0.1) })
    }

    fileprivate func overlapPenalty(for geometry: EdgePathGeometry) -> CGFloat {
        overlapPenalty(for: geometry.axisAlignedSegments)
    }

    func overlapPenalty(for points: [CGPoint]) -> CGFloat {
        overlapPenalty(for: points.adjacentPairs().compactMap { Segment(start: $0.0, end: $0.1) })
    }

    private func overlapPenalty(for candidateSegments: [Segment]) -> CGFloat {
        candidateSegments.reduce(into: 0) { partialResult, candidate in
            partialResult += segments.reduce(into: 0) { innerResult, occupied in
                innerResult += candidate.overlapPenalty(with: occupied)
            }
        }
    }
}

private func segmentIntersectsRect(start: CGPoint, end: CGPoint, rect: CGRect) -> Bool {
    if rect.contains(start) || rect.contains(end) {
        return true
    }

    let corners = [
        CGPoint(x: rect.minX, y: rect.minY),
        CGPoint(x: rect.maxX, y: rect.minY),
        CGPoint(x: rect.maxX, y: rect.maxY),
        CGPoint(x: rect.minX, y: rect.maxY)
    ]

    for (edgeStart, edgeEnd) in corners.adjacentPairs(closingLoop: true) {
        if segmentsIntersect(start, end, edgeStart, edgeEnd) {
            return true
        }
    }

    return false
}

private func segmentsIntersect(_ p1: CGPoint, _ p2: CGPoint, _ q1: CGPoint, _ q2: CGPoint) -> Bool {
    let o1 = orientation(p1, p2, q1)
    let o2 = orientation(p1, p2, q2)
    let o3 = orientation(q1, q2, p1)
    let o4 = orientation(q1, q2, p2)

    if o1 != o2 && o3 != o4 {
        return true
    }

    if o1 == 0 && onSegment(p1, q1, p2) { return true }
    if o2 == 0 && onSegment(p1, q2, p2) { return true }
    if o3 == 0 && onSegment(q1, p1, q2) { return true }
    if o4 == 0 && onSegment(q1, p2, q2) { return true }
    return false
}

private func orientation(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Int {
    let value = (b.y - a.y) * (c.x - b.x) - (b.x - a.x) * (c.y - b.y)
    if abs(value) < 0.0001 { return 0 }
    return value > 0 ? 1 : 2
}

private func onSegment(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Bool {
    b.x <= max(a.x, c.x) + 0.0001 &&
    b.x >= min(a.x, c.x) - 0.0001 &&
    b.y <= max(a.y, c.y) + 0.0001 &&
    b.y >= min(a.y, c.y) - 0.0001
}

private extension Array where Element == CGPoint {
    func adjacentPairs(closingLoop: Bool = false) -> [(CGPoint, CGPoint)] {
        guard count >= 2 else { return [] }
        var pairs: [(CGPoint, CGPoint)] = zip(self, dropFirst()).map { ($0, $1) }
        if closingLoop, let first, let last {
            pairs.append((last, first))
        }
        return pairs
    }
}

private struct ArrowHeadShape: Shape {
    let tip: CGPoint
    let angle: CGFloat
    let size: CGFloat

    func path(in _: CGRect) -> Path {
        let length = size
        let width = size * 0.88
        let tailDepth = size * 0.22
        let directionX = cos(angle)
        let directionY = sin(angle)
        let normalX = cos(angle + (.pi / 2))
        let normalY = sin(angle + (.pi / 2))
        let baseCenter = CGPoint(
            x: tip.x - directionX * length,
            y: tip.y - directionY * length
        )
        let tailCenter = CGPoint(
            x: baseCenter.x - directionX * tailDepth,
            y: baseCenter.y - directionY * tailDepth
        )
        let left = CGPoint(
            x: baseCenter.x + normalX * (width / 2),
            y: baseCenter.y + normalY * (width / 2)
        )
        let right = CGPoint(
            x: baseCenter.x - normalX * (width / 2),
            y: baseCenter.y - normalY * (width / 2)
        )
        let tail = CGPoint(
            x: tailCenter.x,
            y: tailCenter.y
        )
        var path = Path()
        path.move(to: left)
        path.addLine(to: tip)
        path.addLine(to: right)
        path.addQuadCurve(to: tail, control: CGPoint(x: baseCenter.x, y: baseCenter.y))
        path.closeSubpath()
        return path
    }
}

private struct LevelGroupCard: View {
    let group: SpiderGraphLevelGroup
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(group.badge)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    Spacer()
                    Text("\(group.nodes.count)개")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(group.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(group.nodes.map(\.name).prefix(3).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if group.internalEdgeCount > 0 {
                    Text("내부 연결 \(group.internalEdgeCount)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(14)
            .background(cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isSelected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return shape
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay {
                shape.fill(isSelected ? Color.accentColor.opacity(0.16) : .clear)
            }
    }

    private var borderColor: Color {
        isSelected ? .accentColor.opacity(0.6) : .secondary.opacity(0.15)
    }
}

private struct InteractiveCanvasScrollView<Content: View>: NSViewRepresentable {
    @Binding var zoomScale: Double
    let focusRect: CGRect?
    let focusRequestID: Int
    let contentSize: CGSize
    let content: Content

    init(
        zoomScale: Binding<Double>,
        focusRect: CGRect?,
        focusRequestID: Int,
        contentSize: CGSize,
        @ViewBuilder content: () -> Content
    ) {
        _zoomScale = zoomScale
        self.focusRect = focusRect
        self.focusRequestID = focusRequestID
        self.contentSize = contentSize
        self.content = content()
    }

    func makeNSView(context _: Context) -> CanvasInteractionScrollView {
        let scrollView = CanvasInteractionScrollView()
        scrollView.install(
            content: AnyView(content),
            contentSize: contentSize,
            focusRect: focusRect,
            focusRequestID: focusRequestID
        )
        return scrollView
    }

    func updateNSView(_ nsView: CanvasInteractionScrollView, context _: Context) {
        nsView.zoomScale = zoomScale
        nsView.onZoomScaleChange = { newScale in
            self.zoomScale = newScale
        }
        nsView.update(
            content: AnyView(content),
            contentSize: contentSize,
            focusRect: focusRect,
            focusRequestID: focusRequestID
        )
    }
}

private final class CanvasInteractionScrollView: NSScrollView {
    var zoomScale = TuistSpiderViewModel.defaultZoomScale
    var onZoomScaleChange: ((Double) -> Void)?

    private var eventMonitors: [Any] = []
    private var isSpacePressed = false
    private var isPanning = false
    private var lastPanLocation: NSPoint?
    private var isCursorPushed = false
    private let documentContainerView = CenteringDocumentView(frame: .zero)
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private var currentContentSize: CGSize = .zero
    private var pendingFocusRect: CGRect?
    private var pendingFocusRequestID = 0
    private var appliedFocusRequestID = -1

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    deinit {
        removeEventMonitors()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            removeEventMonitors()
        } else {
            installEventMonitorsIfNeeded()
        }
    }

    private func configure() {
        drawsBackground = false
        hasHorizontalScroller = true
        hasVerticalScroller = true
        autohidesScrollers = true
        borderType = .noBorder
        scrollerStyle = .overlay

        documentContainerView.wantsLayer = true
        documentContainerView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        documentContainerView.addSubview(hostingView)
        documentView = documentContainerView
    }

    override func layout() {
        super.layout()
        updateDocumentLayout()
        applyPendingViewportFocusIfNeeded()
    }

    override func reflectScrolledClipView(_ cView: NSClipView) {
        super.reflectScrolledClipView(cView)
        updateDocumentLayout()
    }

    func install(content: AnyView, contentSize: CGSize, focusRect: CGRect?, focusRequestID: Int) {
        hostingView.rootView = content
        currentContentSize = contentSize
        pendingFocusRect = focusRect
        pendingFocusRequestID = focusRequestID
        updateDocumentLayout()
        applyPendingViewportFocusIfNeeded()
    }

    func update(content: AnyView, contentSize: CGSize, focusRect: CGRect?, focusRequestID: Int) {
        hostingView.rootView = content
        currentContentSize = contentSize
        pendingFocusRect = focusRect
        pendingFocusRequestID = focusRequestID
        updateDocumentLayout()
        hostingView.layoutSubtreeIfNeeded()
        applyPendingViewportFocusIfNeeded()
    }

    private func updateDocumentLayout() {
        let visibleSize = contentView.bounds.size
        let containerWidth = max(currentContentSize.width, visibleSize.width)
        let containerHeight = max(currentContentSize.height, visibleSize.height)

        documentContainerView.frame = CGRect(
            origin: .zero,
            size: CGSize(width: containerWidth, height: containerHeight)
        )

        let originX = max((containerWidth - currentContentSize.width) * 0.5, 0)
        let originY = max((containerHeight - currentContentSize.height) * 0.5, 0)
        hostingView.frame = CGRect(
            origin: CGPoint(x: originX, y: originY),
            size: currentContentSize
        )
    }

    private func applyPendingViewportFocusIfNeeded() {
        guard pendingFocusRequestID != appliedFocusRequestID else { return }
        guard contentView.bounds.width > 0, contentView.bounds.height > 0 else { return }

        appliedFocusRequestID = pendingFocusRequestID

        guard let pendingFocusRect else { return }

        let documentFocusRect = pendingFocusRect.offsetBy(
            dx: hostingView.frame.minX,
            dy: hostingView.frame.minY
        )
        let targetOrigin = CGPoint(
            x: documentFocusRect.midX - contentView.bounds.width * 0.5,
            y: documentFocusRect.midY - contentView.bounds.height * 0.5
        )
        let constrainedBounds = contentView.constrainBoundsRect(
            CGRect(origin: targetOrigin, size: contentView.bounds.size)
        )

        contentView.scroll(to: constrainedBounds.origin)
        super.reflectScrolledClipView(contentView)
    }

    private func installEventMonitorsIfNeeded() {
        guard eventMonitors.isEmpty else { return }

        let mask: NSEvent.EventTypeMask = [
            .keyDown,
            .keyUp,
            .leftMouseDown,
            .leftMouseDragged,
            .leftMouseUp,
            .scrollWheel,
        ]

        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handleEvent(event)
        }) {
            eventMonitors.append(monitor)
        }
    }

    private func removeEventMonitors() {
        for monitor in eventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        eventMonitors.removeAll()
        finishPanning()
    }

    private func handleEvent(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .keyDown where event.keyCode == 49:
            guard shouldCaptureSpaceKey else { return event }
            isSpacePressed = true
            window?.makeFirstResponder(self)
            return nil

        case .keyUp where event.keyCode == 49:
            guard isSpacePressed else { return event }
            isSpacePressed = false
            finishPanning()
            return nil

        case .leftMouseDown:
            guard isSpacePressed, containsWindowPoint(event.locationInWindow) else {
                return event
            }
            beginPanning(at: event.locationInWindow)
            return nil

        case .leftMouseDragged:
            guard isPanning else { return event }
            updatePanning(to: event.locationInWindow)
            return nil

        case .leftMouseUp:
            guard isPanning else { return event }
            updatePanning(to: event.locationInWindow)
            finishPanning()
            return nil

        case .scrollWheel:
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard modifiers.contains(.control), containsWindowPoint(event.locationInWindow) else {
                return event
            }
            applyZoom(for: event)
            return nil

        default:
            return event
        }
    }

    private func beginPanning(at point: NSPoint) {
        guard documentView != nil else { return }
        isPanning = true
        lastPanLocation = point

        if !isCursorPushed {
            NSCursor.closedHand.push()
            isCursorPushed = true
        }
    }

    private func updatePanning(to point: NSPoint) {
        guard let lastPanLocation else {
            self.lastPanLocation = point
            return
        }

        var nextOrigin = contentView.bounds.origin
        nextOrigin.x -= point.x - lastPanLocation.x
        nextOrigin.y += point.y - lastPanLocation.y

        let constrainedBounds = contentView.constrainBoundsRect(
            CGRect(origin: nextOrigin, size: contentView.bounds.size)
        )

        contentView.scroll(to: constrainedBounds.origin)
        reflectScrolledClipView(contentView)
        self.lastPanLocation = point
    }

    private func finishPanning() {
        isPanning = false
        lastPanLocation = nil

        if isCursorPushed {
            NSCursor.pop()
            isCursorPushed = false
        }
    }

    private func applyZoom(for event: NSEvent) {
        let delta = normalizedZoomDelta(for: event)
        guard abs(delta) > .ulpOfOne else { return }

        let zoomFactor = exp(delta * 0.01)
        let nextScale = clampZoomScale(zoomScale * zoomFactor)
        guard abs(nextScale - zoomScale) > .ulpOfOne else { return }

        zoomScale = nextScale
        onZoomScaleChange?(nextScale)
    }

    private func normalizedZoomDelta(for event: NSEvent) -> Double {
        let rawDelta = event.scrollingDeltaY
        if event.hasPreciseScrollingDeltas {
            return Double(rawDelta)
        }
        return Double(rawDelta) * 12
    }

    private func clampZoomScale(_ value: Double) -> Double {
        min(max(value, TuistSpiderViewModel.zoomScaleRange.lowerBound), TuistSpiderViewModel.zoomScaleRange.upperBound)
    }

    private var shouldCaptureSpaceKey: Bool {
        guard let window else { return false }
        let mouseLocation = window.mouseLocationOutsideOfEventStream
        return isPanning || containsWindowPoint(mouseLocation)
    }

    private func containsWindowPoint(_ point: NSPoint) -> Bool {
        guard window != nil else { return false }
        let localPoint = convert(point, from: nil)
        return bounds.contains(localPoint)
    }
}

private final class CenteringDocumentView: NSView {
    override var isFlipped: Bool { true }
}
