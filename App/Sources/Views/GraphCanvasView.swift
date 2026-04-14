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
    @Binding var zoomScale: Double

    @GestureState private var gestureZoomScale: CGFloat = 1

    let onSelect: (String) -> Void
    let onSelectLevel: (Int) -> Void

    private var layout: SpiderGraphCanvasLayout {
        SpiderGraphCanvasLayout.make(for: subgraph.nodes, levels: subgraph.levels)
    }

    private var levelGroups: [SpiderGraphLevelGroup] {
        subgraph.levelGroups
    }

    private var levelLayout: SpiderGraphLevelCanvasLayout {
        SpiderGraphLevelCanvasLayout.make(for: levelGroups)
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
            ForEach(subgraph.edges) { edge in
                if let from = layout.nodeFrames[edge.from], let to = layout.nodeFrames[edge.to] {
                    expandedEdgeView(edge: edge, from: from, to: to)
                }
            }

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
            ForEach(subgraph.levelEdges) { edge in
                if let from = levelLayout.groupFrames[edge.fromLevel], let to = levelLayout.groupFrames[edge.toLevel] {
                    LevelEdgeView(
                        edge: edge,
                        from: from,
                        to: to,
                        isSelected: edge.fromLevel == selectedLevel || edge.toLevel == selectedLevel
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

    @ViewBuilder
    private func expandedEdgeView(edge: SpiderGraphEdge, from: CGRect, to: CGRect) -> some View {
        let matchingPaths = edgeConnectionPaths[edge.id] ?? []

        ZStack {
            EdgeShape(from: from, to: to)
                .stroke(baseEdgeColor(for: edge, matchingPaths: matchingPaths), style: baseEdgeStrokeStyle(for: edge))

            ForEach(Array(matchingPaths.enumerated()), id: \.element.id) { index, path in
                EdgeShape(from: from, to: to)
                    .stroke(
                        GraphPathPalette.color(at: path.paletteIndex).opacity(0.98),
                        style: highlightedEdgeStrokeStyle(rank: index, total: matchingPaths.count)
                    )
            }
        }
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

private struct EdgeShape: Shape {
    let from: CGRect
    let to: CGRect

    func path(in _: CGRect) -> Path {
        let start = CGPoint(x: from.maxX, y: from.midY)
        let end = CGPoint(x: to.minX, y: to.midY)
        let deltaX = max((end.x - start.x) * 0.45, 36)

        var path = Path()
        path.move(to: start)
        path.addCurve(
            to: end,
            control1: CGPoint(x: start.x + deltaX, y: start.y),
            control2: CGPoint(x: end.x - deltaX, y: end.y)
        )
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

private struct LevelEdgeView: View {
    let edge: SpiderGraphLevelEdge
    let from: CGRect
    let to: CGRect
    let isSelected: Bool

    var body: some View {
        ZStack {
            EdgeShape(from: from, to: to)
                .stroke(
                    isSelected ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.22),
                    style: StrokeStyle(lineWidth: isSelected ? 3 : 2, lineCap: .round)
                )

            Text("\(edge.edgeCount)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: Capsule())
                .position(edgeLabelPosition)
        }
    }

    private var edgeLabelPosition: CGPoint {
        CGPoint(
            x: (from.maxX + to.minX) / 2,
            y: (from.midY + to.midY) / 2 - 16
        )
    }
}

private struct InteractiveCanvasScrollView<Content: View>: NSViewRepresentable {
    @Binding var zoomScale: Double
    let contentSize: CGSize
    let content: Content

    init(
        zoomScale: Binding<Double>,
        contentSize: CGSize,
        @ViewBuilder content: () -> Content
    ) {
        _zoomScale = zoomScale
        self.contentSize = contentSize
        self.content = content()
    }

    func makeNSView(context _: Context) -> CanvasInteractionScrollView {
        let scrollView = CanvasInteractionScrollView()
        scrollView.install(content: AnyView(content), contentSize: contentSize)
        return scrollView
    }

    func updateNSView(_ nsView: CanvasInteractionScrollView, context _: Context) {
        nsView.zoomScale = zoomScale
        nsView.onZoomScaleChange = { newScale in
            self.zoomScale = newScale
        }
        nsView.update(content: AnyView(content), contentSize: contentSize)
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
    }

    override func reflectScrolledClipView(_ cView: NSClipView) {
        super.reflectScrolledClipView(cView)
        updateDocumentLayout()
    }

    func install(content: AnyView, contentSize: CGSize) {
        hostingView.rootView = content
        currentContentSize = contentSize
        updateDocumentLayout()
    }

    func update(content: AnyView, contentSize: CGSize) {
        hostingView.rootView = content
        currentContentSize = contentSize
        updateDocumentLayout()
        hostingView.layoutSubtreeIfNeeded()
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
