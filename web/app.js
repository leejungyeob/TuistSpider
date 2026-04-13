const STORAGE_KEY = "tuist-spider:settings";
const BUNDLED_GRAPH_URL = "./data/current-graph.json";

const SAMPLE_GRAPH = {
  schemaVersion: 1,
  sourceFormat: "normalized-sample",
  graphName: "FixtureApp",
  rootPath: "examples/TuistFixture",
  nodes: [
    {
      id: "target::examples/TuistFixture::FixtureApp",
      name: "FixtureApp",
      displayName: "FixtureApp",
      kind: "target",
      product: "app",
      projectName: "FixtureApp",
      projectPath: "examples/TuistFixture",
      bundleId: "com.example.fixture",
      isExternal: false,
      sourceCount: 1,
      resourceCount: 0,
      metadataTags: [],
    },
    {
      id: "target::examples/TuistFixture::FeatureA",
      name: "FeatureA",
      displayName: "FeatureA",
      kind: "target",
      product: "framework",
      projectName: "FixtureApp",
      projectPath: "examples/TuistFixture",
      bundleId: "com.example.featureA",
      isExternal: false,
      sourceCount: 1,
      resourceCount: 0,
      metadataTags: ["feature"],
    },
    {
      id: "target::examples/TuistFixture::FeatureB",
      name: "FeatureB",
      displayName: "FeatureB",
      kind: "target",
      product: "framework",
      projectName: "FixtureApp",
      projectPath: "examples/TuistFixture",
      bundleId: "com.example.featureB",
      isExternal: false,
      sourceCount: 1,
      resourceCount: 0,
      metadataTags: ["feature"],
    },
    {
      id: "target::examples/TuistFixture::Core",
      name: "Core",
      displayName: "Core",
      kind: "target",
      product: "framework",
      projectName: "FixtureApp",
      projectPath: "examples/TuistFixture",
      bundleId: "com.example.core",
      isExternal: false,
      sourceCount: 1,
      resourceCount: 0,
      metadataTags: ["foundation"],
    },
    {
      id: "package::NetworkingKit",
      name: "NetworkingKit",
      displayName: "NetworkingKit",
      kind: "package",
      product: null,
      projectName: "External",
      projectPath: null,
      bundleId: null,
      isExternal: true,
      sourceCount: 0,
      resourceCount: 0,
      metadataTags: [],
    },
    {
      id: "sdk::UIKit",
      name: "UIKit",
      displayName: "UIKit",
      kind: "sdk",
      product: null,
      projectName: "External",
      projectPath: null,
      bundleId: null,
      isExternal: true,
      sourceCount: 0,
      resourceCount: 0,
      metadataTags: [],
    },
  ],
  edges: [
    {
      from: "target::examples/TuistFixture::FixtureApp",
      to: "target::examples/TuistFixture::FeatureA",
      kind: "target",
      status: "required",
    },
    {
      from: "target::examples/TuistFixture::FixtureApp",
      to: "target::examples/TuistFixture::FeatureB",
      kind: "target",
      status: "required",
    },
    {
      from: "target::examples/TuistFixture::FixtureApp",
      to: "sdk::UIKit",
      kind: "sdk",
      status: null,
    },
    {
      from: "target::examples/TuistFixture::FeatureA",
      to: "target::examples/TuistFixture::Core",
      kind: "target",
      status: "required",
    },
    {
      from: "target::examples/TuistFixture::FeatureB",
      to: "target::examples/TuistFixture::Core",
      kind: "target",
      status: "required",
    },
    {
      from: "target::examples/TuistFixture::FeatureB",
      to: "package::NetworkingKit",
      kind: "package",
      status: null,
    },
  ],
};

const state = {
  graph: null,
  selectedNodeId: null,
  direction: "both",
  depth: "all",
  includeExternal: false,
  searchTerm: "",
  graphOrigin: "sample",
  subgraph: { nodes: [], edges: [], levels: new Map() },
};

const elements = {
  pageShell: document.querySelector(".page-shell"),
  graphFileInput: document.querySelector("#graphFileInput"),
  loadBundledButton: document.querySelector("#loadBundledButton"),
  loadSampleButton: document.querySelector("#loadSampleButton"),
  resetViewButton: document.querySelector("#resetViewButton"),
  statusMessage: document.querySelector("#statusMessage"),
  moduleSearchInput: document.querySelector("#moduleSearchInput"),
  directionSelect: document.querySelector("#directionSelect"),
  depthSelect: document.querySelector("#depthSelect"),
  includeExternalCheckbox: document.querySelector("#includeExternalCheckbox"),
  totalNodeCount: document.querySelector("#totalNodeCount"),
  visibleNodeCount: document.querySelector("#visibleNodeCount"),
  totalEdgeCount: document.querySelector("#totalEdgeCount"),
  visibleEdgeCount: document.querySelector("#visibleEdgeCount"),
  filteredCountBadge: document.querySelector("#filteredCountBadge"),
  moduleList: document.querySelector("#moduleList"),
  graphSourceLabel: document.querySelector("#graphSourceLabel"),
  graphTitle: document.querySelector("#graphTitle"),
  graphSummary: document.querySelector("#graphSummary"),
  graphRootPath: document.querySelector("#graphRootPath"),
  graphSvg: document.querySelector("#graphSvg"),
  graphEmptyState: document.querySelector("#graphEmptyState"),
  detailEmptyState: document.querySelector("#detailEmptyState"),
  detailPanel: document.querySelector("#detailPanel"),
  selectedKindLabel: document.querySelector("#selectedKindLabel"),
  selectedName: document.querySelector("#selectedName"),
  selectedMeta: document.querySelector("#selectedMeta"),
  dependencyCount: document.querySelector("#dependencyCount"),
  dependentCount: document.querySelector("#dependentCount"),
  dependencyList: document.querySelector("#dependencyList"),
  dependentList: document.querySelector("#dependentList"),
  metadataList: document.querySelector("#metadataList"),
};

void bootstrap();

async function bootstrap() {
  restoreSettings();
  syncControls();
  bindEvents();
  await loadInitialGraph();
}

function bindEvents() {
  elements.loadBundledButton.addEventListener("click", async () => {
    await loadBundledGraph(true);
  });

  elements.loadSampleButton.addEventListener("click", () =>
    applyGraph(SAMPLE_GRAPH, {
      origin: "sample",
      statusMessage: "샘플 그래프를 불러왔습니다.",
    }),
  );
  elements.resetViewButton.addEventListener("click", resetView);

  elements.graphFileInput.addEventListener("change", async (event) => {
    const [file] = event.target.files || [];
    if (!file) return;

    await loadGraphFile(file);
  });

  elements.moduleSearchInput.addEventListener("input", (event) => {
    state.searchTerm = event.target.value.trim().toLowerCase();
    renderModuleList();
    persistSettings();
  });

  elements.directionSelect.addEventListener("change", (event) => {
    state.direction = event.target.value;
    persistSettings();
    render();
  });

  elements.depthSelect.addEventListener("change", (event) => {
    state.depth = event.target.value;
    persistSettings();
    render();
  });

  elements.includeExternalCheckbox.addEventListener("change", (event) => {
    state.includeExternal = event.target.checked;
    persistSettings();
    render();
  });

  window.addEventListener("dragenter", handleDragEvent);
  window.addEventListener("dragover", handleDragEvent);
  window.addEventListener("dragleave", handleDragLeave);
  window.addEventListener("drop", handleDrop);
}

async function loadInitialGraph() {
  const loaded = await loadBundledGraph(false);
  if (!loaded) {
    applyGraph(SAMPLE_GRAPH, {
      origin: "sample",
      statusMessage: "샘플 그래프를 불러왔습니다.",
    });
  }
}

async function loadBundledGraph(forceMessage) {
  try {
    const response = await fetch(BUNDLED_GRAPH_URL, { cache: "no-store" });
    if (!response.ok) {
      if (forceMessage) {
        setStatus("현재 그래프 파일이 아직 없습니다. 먼저 run 스크립트로 export 하세요.");
      }
      return false;
    }

    const rawJson = await response.json();
    applyGraph(rawJson, {
      origin: "bundled",
      statusMessage: forceMessage ? "현재 그래프를 다시 불러왔습니다." : "번들 그래프를 자동으로 불러왔습니다.",
    });
    return true;
  } catch (error) {
    if (forceMessage) {
      setStatus("현재 그래프를 읽지 못했습니다. JSON 파일을 직접 올릴 수도 있습니다.");
    }
    return false;
  }
}

async function loadGraphFile(file) {
  try {
    const rawText = await file.text();
    const rawJson = JSON.parse(rawText);
    applyGraph(rawJson, {
      origin: "uploaded",
      statusMessage: `${file.name} 파일을 불러왔습니다.`,
    });
  } catch (error) {
    setStatus("JSON 파일을 읽지 못했습니다. 형식을 다시 확인해 주세요.");
  } finally {
    elements.graphFileInput.value = "";
  }
}

function applyGraph(input, options = {}) {
  const graph = buildIndex(normalizeGraphInput(input));
  state.graph = graph;
  state.graphOrigin = options.origin ?? "uploaded";
  state.selectedNodeId = graph.nodeMap.has(state.selectedNodeId)
    ? state.selectedNodeId
    : pickInitialNode(graph);
  if (!graph.nodeMap.has(state.selectedNodeId)) {
    state.selectedNodeId = pickInitialNode(graph);
  }
  setStatus(options.statusMessage ?? "그래프를 불러왔습니다.");
  persistSettings();
  render();
}

function resetView() {
  state.direction = "both";
  state.depth = "all";
  state.includeExternal = false;
  state.searchTerm = "";
  state.selectedNodeId = pickInitialNode(state.graph);
  syncControls();
  persistSettings();
  render();
  setStatus("뷰를 초기화했습니다.");
}

function pickInitialNode(graph) {
  const preferred = graph.nodes.find((node) => !node.isExternal);
  return preferred ? preferred.id : graph.nodes[0]?.id ?? null;
}

function normalizeGraphInput(raw) {
  if (Array.isArray(raw?.nodes) && Array.isArray(raw?.edges)) {
    return {
      schemaVersion: raw.schemaVersion ?? 1,
      sourceFormat: raw.sourceFormat ?? "normalized",
      graphName: raw.graphName ?? "Normalized graph",
      rootPath: raw.rootPath ?? null,
      nodes: raw.nodes,
      edges: raw.edges,
    };
  }

  if (!raw?.projects) {
    throw new Error("지원하지 않는 JSON 형식입니다.");
  }

  const projectEntries = Array.isArray(raw.projects)
    ? pairTuistEntries(raw.projects)
    : Object.entries(raw.projects);

  const nodesById = new Map();
  const edges = [];

  for (const [projectPath, project] of projectEntries) {
    const projectName = project.name ?? basename(projectPath);
    for (const target of extractTargets(project)) {
      if (!target?.name) continue;
      const nodeId = targetId(projectPath, target.name);
      nodesById.set(nodeId, {
        id: nodeId,
        name: target.name,
        displayName: target.name,
        kind: "target",
        product: target.product ?? null,
        projectName,
        projectPath,
        bundleId: target.bundleId ?? null,
        isExternal: false,
        sourceCount: Array.isArray(target.sources) ? target.sources.length : 0,
        resourceCount: Array.isArray(target.resources) ? target.resources.length : 0,
        metadataTags: target.metadata?.tags ?? [],
      });
    }
  }

  for (const [projectPath, project] of projectEntries) {
    for (const target of extractTargets(project)) {
      if (!target?.name) continue;
      const sourceId = targetId(projectPath, target.name);

      for (const dependency of target.dependencies ?? []) {
        const descriptor = parseDependency(dependency, projectPath);
        if (!descriptor) continue;

        if (!nodesById.has(descriptor.id)) {
          nodesById.set(descriptor.id, {
            id: descriptor.id,
            name: descriptor.name,
            displayName: descriptor.displayName,
            kind: descriptor.kind,
            product: null,
            projectName: descriptor.isExternal ? "External" : null,
            projectPath: descriptor.projectPath ?? null,
            bundleId: null,
            isExternal: descriptor.isExternal,
            sourceCount: 0,
            resourceCount: 0,
            metadataTags: [],
          });
        }

        edges.push({
          from: sourceId,
          to: descriptor.id,
          kind: descriptor.kind,
          status: descriptor.status ?? null,
        });
      }
    }
  }

  return {
    schemaVersion: 1,
    sourceFormat: Array.isArray(raw.projects) ? "tuist-json" : "tuist-legacy-json",
    graphName: raw.name ?? "Tuist graph",
    rootPath: raw.path ?? null,
    nodes: Array.from(nodesById.values()).sort(sortNodes),
    edges,
  };
}

function pairTuistEntries(projects) {
  const entries = [];
  for (let index = 0; index < projects.length; index += 2) {
    entries.push([projects[index], projects[index + 1]]);
  }
  return entries;
}

function extractTargets(project) {
  if (Array.isArray(project?.targets)) return project.targets;
  if (project?.targets && typeof project.targets === "object") {
    return Object.values(project.targets);
  }
  return [];
}

function targetId(projectPath, name) {
  return `target::${projectPath}::${name}`;
}

function basename(value) {
  return String(value).split("/").filter(Boolean).pop() ?? value;
}

function normalizePath(basePath, maybePath) {
  if (!maybePath) return basePath;
  if (maybePath.startsWith("/")) return maybePath;
  return `${basePath}/${maybePath}`.replace(/\/+/g, "/");
}

function dependencyName(payload) {
  if (typeof payload === "string") return payload;
  if (!payload || typeof payload !== "object") return null;
  return payload.name ?? payload.product ?? payload.target ?? (payload.path ? basename(payload.path) : null);
}

function parseDependency(dependency, currentProjectPath) {
  if (!dependency || typeof dependency !== "object") return null;

  if (dependency.target) {
    const payload = dependency.target;
    const projectPath = normalizePath(currentProjectPath, payload.path);
    return {
      id: targetId(projectPath, payload.name),
      kind: "target",
      name: payload.name,
      displayName: payload.name,
      projectPath,
      isExternal: false,
      status: payload.status ?? null,
    };
  }

  if (dependency.project) {
    const payload = dependency.project;
    const targetName = payload.target ?? payload.name;
    const projectPath = normalizePath(currentProjectPath, payload.path);
    return {
      id: targetId(projectPath, targetName),
      kind: "target",
      name: targetName,
      displayName: targetName,
      projectPath,
      isExternal: false,
      status: payload.status ?? null,
    };
  }

  for (const kind of [
    "package",
    "packageProduct",
    "external",
    "sdk",
    "framework",
    "xcframework",
    "library",
    "xctest",
    "macro",
    "plugin",
  ]) {
    if (!dependency[kind]) continue;
    const name = dependencyName(dependency[kind]);
    if (!name) return null;
    return {
      id: `${kind}::${name}`,
      kind,
      name,
      displayName: name,
      projectPath: null,
      isExternal: true,
      status: null,
    };
  }

  return null;
}

function sortNodes(left, right) {
  return (
    Number(left.isExternal) - Number(right.isExternal) ||
    String(left.projectName ?? "").localeCompare(String(right.projectName ?? "")) ||
    left.name.localeCompare(right.name)
  );
}

function buildIndex(graph) {
  const nodeMap = new Map(graph.nodes.map((node) => [node.id, node]));
  const outgoing = new Map(graph.nodes.map((node) => [node.id, []]));
  const incoming = new Map(graph.nodes.map((node) => [node.id, []]));

  for (const edge of graph.edges) {
    if (!nodeMap.has(edge.from) || !nodeMap.has(edge.to)) continue;
    outgoing.get(edge.from).push(edge.to);
    incoming.get(edge.to).push(edge.from);
  }

  return { ...graph, nodeMap, outgoing, incoming };
}

function render() {
  if (!state.graph) return;
  state.subgraph = buildSubgraph();

  elements.totalNodeCount.textContent = String(state.graph.nodes.length);
  elements.totalEdgeCount.textContent = String(state.graph.edges.length);
  elements.visibleNodeCount.textContent = String(state.subgraph.nodes.length);
  elements.visibleEdgeCount.textContent = String(state.subgraph.edges.length);
  elements.graphSourceLabel.textContent = buildOriginLabel();
  elements.graphTitle.textContent = state.graph.graphName;
  elements.graphSummary.textContent = buildSummaryText();
  elements.graphRootPath.textContent = state.graph.rootPath ? `root: ${state.graph.rootPath}` : "root path 없음";
  syncControls();

  renderModuleList();
  renderGraph();
  renderDetailPanel();
}

function buildOriginLabel() {
  const originLabel =
    state.graphOrigin === "bundled"
      ? "Bundled graph"
      : state.graphOrigin === "uploaded"
        ? "Uploaded graph"
        : "Sample graph";
  return `${originLabel} / ${state.graph.sourceFormat}`;
}

function buildSummaryText() {
  const selected = state.graph.nodeMap.get(state.selectedNodeId);
  if (!selected) return "왼쪽에서 모듈을 선택하세요.";
  const directionLabel =
    state.direction === "dependencies"
      ? "의존하는 쪽"
      : state.direction === "dependents"
        ? "의존받는 쪽"
        : "양방향";
  const depthLabel = state.depth === "all" ? "전체 depth" : `${state.depth} 단계`;
  return `${selected.name} 기준, ${directionLabel}, ${depthLabel}`;
}

function buildSubgraph() {
  const selected = state.graph.nodeMap.get(state.selectedNodeId);
  if (!selected) return { nodes: [], edges: [], levels: new Map() };

  const allowNode = (nodeId) => {
    const node = state.graph.nodeMap.get(nodeId);
    if (!node) return false;
    return state.includeExternal || !node.isExternal;
  };

  const levels = new Map([[selected.id, 0]]);
  if (state.direction !== "dependencies") {
    for (const [nodeId, distance] of bfs(selected.id, state.graph.incoming, allowNode)) {
      levels.set(nodeId, -distance);
    }
  }

  if (state.direction !== "dependents") {
    for (const [nodeId, distance] of bfs(selected.id, state.graph.outgoing, allowNode)) {
      const current = levels.get(nodeId);
      if (current === undefined || Math.abs(distance) < Math.abs(current)) {
        levels.set(nodeId, distance);
      }
    }
  }

  const nodeIds = new Set([...levels.keys()].filter(allowNode));
  nodeIds.add(selected.id);

  const nodes = [...nodeIds]
    .map((nodeId) => state.graph.nodeMap.get(nodeId))
    .filter(Boolean)
    .sort(sortNodes);

  const edges = state.graph.edges.filter(
    (edge) => nodeIds.has(edge.from) && nodeIds.has(edge.to),
  );

  return { nodes, edges, levels };
}

function bfs(startId, adjacency, allowNode) {
  const maxDepth = state.depth === "all" ? Number.POSITIVE_INFINITY : Number(state.depth);
  const seen = new Map();
  const queue = [{ nodeId: startId, distance: 0 }];

  while (queue.length > 0) {
    const { nodeId, distance } = queue.shift();
    if (distance >= maxDepth) continue;

    for (const nextId of adjacency.get(nodeId) ?? []) {
      if (!allowNode(nextId) || seen.has(nextId)) continue;
      const nextDistance = distance + 1;
      seen.set(nextId, nextDistance);
      queue.push({ nodeId: nextId, distance: nextDistance });
    }
  }

  return seen;
}

function renderModuleList() {
  const query = state.searchTerm;
  const nodes = state.graph.nodes.filter((node) => {
    if (!state.includeExternal && node.isExternal) return false;
    if (!query) return true;
    return `${node.name} ${node.projectName ?? ""}`.toLowerCase().includes(query);
  });

  elements.filteredCountBadge.textContent = String(nodes.length);
  elements.moduleList.replaceChildren();

  for (const node of nodes) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "module-button";
    if (node.id === state.selectedNodeId) {
      button.classList.add("is-active");
    }
    button.addEventListener("click", () => {
      state.selectedNodeId = node.id;
      persistSettings();
      render();
    });

    const main = document.createElement("span");
    main.className = "module-button-main";
    main.innerHTML = `
      <span class="module-name">${escapeHtml(node.name)}</span>
      <span class="module-meta">${escapeHtml(node.projectName ?? "External")}</span>
    `;

    const kind = document.createElement("span");
    kind.className = "module-kind";
    kind.textContent = node.kind === "target" ? node.product ?? "target" : node.kind;

    button.append(main, kind);
    elements.moduleList.append(button);
  }
}

function renderGraph() {
  const { nodes, edges, levels } = state.subgraph;
  const svg = elements.graphSvg;
  svg.replaceChildren();

  if (nodes.length === 0) {
    elements.graphEmptyState.hidden = false;
    return;
  }

  elements.graphEmptyState.hidden = true;

  const layout = layoutNodes(nodes, levels);
  const defs = document.createElementNS("http://www.w3.org/2000/svg", "defs");
  defs.innerHTML = `
    <marker id="arrowhead" markerWidth="8" markerHeight="8" refX="6" refY="4" orient="auto">
      <path d="M0,0 L8,4 L0,8 Z" fill="rgba(31, 39, 48, 0.26)"></path>
    </marker>
  `;
  svg.append(defs);

  for (const edge of edges) {
    const from = layout.positions.get(edge.from);
    const to = layout.positions.get(edge.to);
    if (!from || !to) continue;

    const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
    path.setAttribute("class", edgeTouchesSelection(edge) ? "graph-edge is-active" : "graph-edge");
    path.setAttribute("marker-end", "url(#arrowhead)");
    path.setAttribute("d", edgePath(from, to));
    svg.append(path);
  }

  for (const node of nodes) {
    const position = layout.positions.get(node.id);
    if (!position) continue;

    const group = document.createElementNS("http://www.w3.org/2000/svg", "g");
    const classes = ["graph-node"];
    if (node.id === state.selectedNodeId) classes.push("is-selected");
    if (node.isExternal) classes.push("is-external");
    group.setAttribute("class", classes.join(" "));
    group.setAttribute("transform", `translate(${position.x}, ${position.y})`);
    group.addEventListener("click", () => {
      state.selectedNodeId = node.id;
      persistSettings();
      render();
    });

    const rect = document.createElementNS("http://www.w3.org/2000/svg", "rect");
    rect.setAttribute("rx", "20");
    rect.setAttribute("width", String(layout.nodeWidth));
    rect.setAttribute("height", String(layout.nodeHeight));

    const title = document.createElementNS("http://www.w3.org/2000/svg", "text");
    title.setAttribute("class", "node-name");
    title.setAttribute("x", "18");
    title.setAttribute("y", "28");
    title.textContent = truncate(node.name, 22);

    const subtitle = document.createElementNS("http://www.w3.org/2000/svg", "text");
    subtitle.setAttribute("class", "node-meta");
    subtitle.setAttribute("x", "18");
    subtitle.setAttribute("y", "48");
    subtitle.textContent = truncate(node.kind === "target" ? `${node.projectName} / ${node.product ?? "target"}` : `${node.kind} / external`, 30);

    group.append(rect, title, subtitle);
    svg.append(group);
  }

  svg.setAttribute("viewBox", `0 0 ${layout.width} ${layout.height}`);
}

function layoutNodes(nodes, levels) {
  const groups = new Map();
  for (const node of nodes) {
    const level = levels.get(node.id) ?? 0;
    if (!groups.has(level)) groups.set(level, []);
    groups.get(level).push(node);
  }

  const orderedLevels = [...groups.keys()].sort((left, right) => left - right);
  for (const level of orderedLevels) {
    groups.get(level).sort(sortNodes);
  }

  const nodeWidth = 200;
  const nodeHeight = 68;
  const columnGap = 250;
  const rowGap = 106;
  const paddingX = 120;
  const paddingY = 90;
  const maxColumnSize = Math.max(...orderedLevels.map((level) => groups.get(level).length), 1);
  const width = paddingX * 2 + columnGap * Math.max(orderedLevels.length - 1, 1) + nodeWidth;
  const height = paddingY * 2 + rowGap * Math.max(maxColumnSize - 1, 1) + nodeHeight;
  const centerY = height / 2;
  const positions = new Map();

  orderedLevels.forEach((level, columnIndex) => {
    const column = groups.get(level);
    const columnHeight = rowGap * Math.max(column.length - 1, 0);
    const startY = centerY - columnHeight / 2;

    column.forEach((node, rowIndex) => {
      positions.set(node.id, {
        x: paddingX + columnGap * columnIndex,
        y: startY + rowGap * rowIndex,
      });
    });
  });

  return { nodeWidth, nodeHeight, positions, width, height };
}

function edgePath(from, to) {
  const startX = from.x + 200;
  const startY = from.y + 34;
  const endX = to.x;
  const endY = to.y + 34;
  const deltaX = Math.max((endX - startX) * 0.45, 32);
  return `M ${startX} ${startY} C ${startX + deltaX} ${startY}, ${endX - deltaX} ${endY}, ${endX} ${endY}`;
}

function edgeTouchesSelection(edge) {
  return edge.from === state.selectedNodeId || edge.to === state.selectedNodeId;
}

function renderDetailPanel() {
  const node = state.graph.nodeMap.get(state.selectedNodeId);
  if (!node) {
    elements.detailEmptyState.hidden = false;
    elements.detailPanel.hidden = true;
    return;
  }

  const outgoingIds = state.graph.outgoing.get(node.id) ?? [];
  const incomingIds = state.graph.incoming.get(node.id) ?? [];
  const directDependencies = outgoingIds
    .map((nodeId) => state.graph.nodeMap.get(nodeId))
    .filter(Boolean)
    .filter((entry) => state.includeExternal || !entry.isExternal)
    .sort(sortNodes);
  const directDependents = incomingIds
    .map((nodeId) => state.graph.nodeMap.get(nodeId))
    .filter(Boolean)
    .filter((entry) => state.includeExternal || !entry.isExternal)
    .sort(sortNodes);

  elements.detailEmptyState.hidden = true;
  elements.detailPanel.hidden = false;
  elements.selectedKindLabel.textContent = node.kind === "target" ? node.product ?? "target" : node.kind;
  elements.selectedName.textContent = node.name;
  elements.selectedMeta.textContent = node.projectPath ?? "External dependency";
  elements.dependencyCount.textContent = String(directDependencies.length);
  elements.dependentCount.textContent = String(directDependents.length);

  renderLinkList(elements.dependencyList, directDependencies);
  renderLinkList(elements.dependentList, directDependents);
  renderMetadata(node);
}

function renderLinkList(container, nodes) {
  container.replaceChildren();
  if (nodes.length === 0) {
    const empty = document.createElement("div");
    empty.className = "link-chip-empty";
    empty.textContent = "없음";
    container.append(empty);
    return;
  }

  for (const node of nodes) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "link-chip";
    button.innerHTML = `
      <span class="module-button-main">
        <span class="module-name">${escapeHtml(node.name)}</span>
        <span class="module-meta">${escapeHtml(node.projectName ?? "External")}</span>
      </span>
      <span class="module-kind">${escapeHtml(node.kind === "target" ? node.product ?? "target" : node.kind)}</span>
    `;
    button.addEventListener("click", () => {
      state.selectedNodeId = node.id;
      persistSettings();
      render();
    });
    container.append(button);
  }
}

function renderMetadata(node) {
  const rows = [
    ["Kind", node.kind === "target" ? node.product ?? "target" : node.kind],
    ["Project", node.projectName ?? "External"],
    ["Path", node.projectPath ?? "-"],
    ["Bundle ID", node.bundleId ?? "-"],
    ["Sources", String(node.sourceCount ?? 0)],
    ["Resources", String(node.resourceCount ?? 0)],
    ["Tags", Array.isArray(node.metadataTags) && node.metadataTags.length > 0 ? node.metadataTags.join(", ") : "-"],
  ];

  elements.metadataList.replaceChildren();
  for (const [label, value] of rows) {
    const wrapper = document.createElement("div");
    wrapper.className = "metadata-row";

    const title = document.createElement("dt");
    title.textContent = label;

    const description = document.createElement("dd");
    description.textContent = value;

    wrapper.append(title, description);
    elements.metadataList.append(wrapper);
  }
}

function truncate(value, limit) {
  if (value.length <= limit) return value;
  return `${value.slice(0, limit - 1)}…`;
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function syncControls() {
  elements.moduleSearchInput.value = state.searchTerm;
  elements.directionSelect.value = state.direction;
  elements.depthSelect.value = state.depth;
  elements.includeExternalCheckbox.checked = state.includeExternal;
}

function restoreSettings() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return;
    const parsed = JSON.parse(raw);
    state.direction = parsed.direction ?? state.direction;
    state.depth = parsed.depth ?? state.depth;
    state.includeExternal = Boolean(parsed.includeExternal);
    state.searchTerm = parsed.searchTerm ?? "";
    state.selectedNodeId = parsed.selectedNodeId ?? null;
  } catch (error) {
    localStorage.removeItem(STORAGE_KEY);
  }
}

function persistSettings() {
  const payload = {
    direction: state.direction,
    depth: state.depth,
    includeExternal: state.includeExternal,
    searchTerm: state.searchTerm,
    selectedNodeId: state.selectedNodeId,
  };
  localStorage.setItem(STORAGE_KEY, JSON.stringify(payload));
}

function setStatus(message) {
  elements.statusMessage.textContent = message;
}

function handleDragEvent(event) {
  event.preventDefault();
  elements.pageShell.classList.add("is-dragging");
}

function handleDragLeave(event) {
  if (event.relatedTarget) return;
  elements.pageShell.classList.remove("is-dragging");
}

async function handleDrop(event) {
  event.preventDefault();
  elements.pageShell.classList.remove("is-dragging");
  const [file] = [...(event.dataTransfer?.files ?? [])];
  if (!file) return;
  await loadGraphFile(file);
}
