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

    private var expandedEdgeRenderModels: [ExpandedEdgeRenderModel] {
        subgraph.edges.compactMap { edge in
            guard let endpoints = subgraph.edgeEndpoints[edge.id] else { return nil }

            let matchingPaths = edgeConnectionPaths[edge.id] ?? []
            let geometry = EdgeCurveGeometry(start: endpoints.start, end: endpoints.end)
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

            let geometry = EdgeCurveGeometry(from: from, to: to)
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
            let linePath = EdgeShape(geometry: model.geometry.trimmedEnd(by: arrowLineInset(for: model.arrowSize))).path(in: .zero)
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
        let linePath = EdgeShape(geometry: layer.geometry.trimmedEnd(by: arrowLineInset(for: layer.arrowSize))).path(in: .zero)
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
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var background: some ShapeStyle {
        if isGraphSelected {
            return AnyShapeStyle(Color.accentColor.opacity(0.22))
        }
        if isFocused {
            return AnyShapeStyle(Color.accentColor.opacity(0.16))
        }
        if isPathNode {
            return AnyShapeStyle(Color.accentColor.opacity(0.08))
        }
        if node.isExternal {
            return AnyShapeStyle(Color.orange.opacity(0.12))
        }
        return AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
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

private struct ExpandedEdgeRenderModel: Identifiable {
    let id: String
    let base: ExpandedEdgeLayer
    let highlights: [ExpandedEdgeLayer]
}

private struct ExpandedEdgeLayer {
    let geometry: EdgeCurveGeometry
    let color: Color
    let strokeStyle: StrokeStyle
    let arrowColor: Color
    let arrowSize: CGFloat
}

private struct GroupedEdgeRenderModel: Identifiable {
    let id: String
    let geometry: EdgeCurveGeometry
    let strokeColor: Color
    let arrowColor: Color
    let lineWidth: CGFloat
    let arrowSize: CGFloat
}

private struct EdgeShape: Shape {
    let geometry: EdgeCurveGeometry

    init(from: CGRect, to: CGRect) {
        geometry = EdgeCurveGeometry(from: from, to: to)
    }

    init(geometry: EdgeCurveGeometry) {
        self.geometry = geometry
    }

    func path(in _: CGRect) -> Path {
        var path = Path()
        path.move(to: geometry.start)
        path.addCurve(
            to: geometry.end,
            control1: geometry.control1,
            control2: geometry.control2
        )
        return path
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
        let direction: CGFloat = end.x >= start.x ? 1 : -1
        let deltaX = max(abs(end.x - start.x) * 0.45, 36)
        self.init(
            start: start,
            end: end,
            control1: CGPoint(x: start.x + direction * deltaX, y: start.y),
            control2: CGPoint(x: end.x - direction * deltaX, y: end.y)
        )
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
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isSelected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var background: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(Color.accentColor.opacity(0.16))
        }
        return AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
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
