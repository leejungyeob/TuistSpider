# TuistSpider

![TuistSpider banner](./assets/branding/hero-banner-readme.png)

Native macOS graph explorer for large [Tuist](https://github.com/tuist/tuist) module graphs.

Tuist's full graph export is useful, but once the module count grows, the image becomes hard to read. `TuistSpider` focuses on the workflow people actually need: choose one module, narrow by direction and depth, inspect real connection paths, and hide the rest.

## Why

Most questions about a large dependency graph are not "show me everything."

- What does this module depend on?
- Who depends on this module?
- How does module A connect to module B?
- Which specific path do I care about right now?

`TuistSpider` is built for those questions.

## Highlights

- Open a Tuist project directly from the app and run `tuist graph --format json`
- Load exported graph JSON files
- Focus one module and filter by direction and depth
- Auto-classify project layers from `metadata.tags`, project path, target name, and product hints
- Persist per-project layer decisions in `.tuist-spider/layers.json`
- Edit the applied layer for internal targets from the inspector without touching Tuist manifests
- See read-only `metadata.tags`, applied layer, suggested layer, and classification source together
- Toggle third-party dependencies on or off
- Switch between:
  - `Expanded`: one card per module
  - `Grouped`: one card per level
- Show clear layer bands in `Expanded` mode so modules stay grouped by project layer
- Click a node in the graph without changing the left-side focus
- Discover multiple visible connection paths between the focused node and the clicked node
- Toggle paths individually and color them separately
- Turn on `선택 경로만 보기` to hide everything except the currently active paths
- Route edges around obstacles and reduce overlapping trunks when multiple paths pass through nearby lanes
- See dependency direction directly on the graph
- Zoom and pan with native macOS controls

## Screenshots

### Focused graph exploration

![TuistSpider overview](./assets/screenshots/overview-readme.png)

### Multi-path connection tracing

![TuistSpider multi-paths](./assets/screenshots/multi-paths-readme.png)

## Download

Repository:

- [github.com/leejungyeob/TuistSpider](https://github.com/leejungyeob/TuistSpider)

Latest release:

- [github.com/leejungyeob/TuistSpider/releases/latest](https://github.com/leejungyeob/TuistSpider/releases/latest)

Recommended download:

- `TuistSpider.dmg`

### Install From Release

1. Open the [latest release](https://github.com/leejungyeob/TuistSpider/releases/latest)
2. Download `TuistSpider.dmg`
3. Open the DMG
4. Drag `TuistSpider.app` into `Applications`
5. Launch the app from `Applications`

If macOS blocks the app because it is unsigned:

1. Right-click `TuistSpider.app`
2. Choose `Open`
3. Click `Open` again in the warning dialog

Or remove quarantine manually:

```bash
xattr -dr com.apple.quarantine /Applications/TuistSpider.app
```

## Quick Start

Run the app locally:

```bash
./scripts/run_mac_app.sh
```

Open the generated Xcode project:

```bash
./scripts/open_mac_app.sh
```

Build a release DMG:

```bash
./scripts/mac/build-release-dmg.sh
```

Build a release ZIP:

```bash
./scripts/mac/build-release-zip.sh
```

## How It Works

### 1. Load a graph

- Click `프로젝트 열기` to open a Tuist project root
- Or click `JSON 열기` to load a graph JSON file directly
- The app keeps the focused module fixed while you inspect the graph around it

### 2. Narrow the graph

- Pick a focus module in the left sidebar
- Choose `양방향`, `의존하는 쪽`, or `의존받는 쪽`
- Limit depth if needed
- Toggle `외부 의존성 포함` when you want third-party modules visible

### 3. Change the presentation

- `펼침`
  - shows every module as its own node
  - keeps modules inside visible layer bands
- `계층`
  - groups same-level modules into one card
  - click a level card to inspect the modules inside it

### 4. Review and adjust project layers

- TuistSpider first tries `metadata.tags` values like `layer:feature`
- If no explicit layer tag exists, it falls back to project path, target name, and product inference
- In `Expanded` mode, the canvas draws separate layer regions so modules from the same layer stay aligned
- Select an internal target to see:
  - `Applied Layer`
  - `Suggested Layer`
  - `Applied Source`
  - `Suggested Source`
  - read-only `metadata.tags`
- Change the applied layer from the inspector
- Add a custom layer name when the inferred or tagged result is not what you want
- Use `Reset to Suggested` to go back to the current automatic classification

### 5. Persist layer decisions

- TuistSpider stores project-specific layer classifications in:

```text
<project-root>/.tuist-spider/layers.json
```

- The saved value is applied first when you reload the same project or graph
- New targets are auto-classified and synced into the snapshot file
- Deleted targets are pruned from the snapshot automatically
- External dependencies are not persisted in the snapshot

### 6. Trace paths between two modules

- Keep the left-side focus as your source node
- Click another node in the graph
- TuistSpider finds multiple visible paths between those two nodes
- Each path gets its own color
- Use the inspector to:
  - show all paths
  - hide all paths
  - toggle specific paths
  - enable `선택 경로만 보기` to keep only the active paths on screen
  - use `shift + click` on path rows to add or remove paths while path-only mode is on
  - load more paths step-by-step with `더 보기` when the current result is truncated

## Controls

- Zoom controls in the top-right corner
- Trackpad pinch to zoom
- `space + drag` to pan
- `control + wheel` to zoom
- `shift + click` on a path row to add or remove it from the current path-only selection

## Layer Classification Rules

TuistSpider uses this priority order when deciding a module's layer:

1. Saved project snapshot in `.tuist-spider/layers.json`
2. `metadata.tags` entries using `layer:<name>`
3. Project path inference
4. Target name inference
5. Product or test-target inference
6. `Unclassified`

Notes:

- `layer:<name>` is the only metadata tag syntax treated as a layer source
- Other metadata tags stay visible as read-only tags in the inspector
- If multiple `layer:` tags exist, the first one is used and a warning is shown

## External Dependency Detection

The `외부 의존성 포함` toggle treats a dependency as external when any of these match:

- the dependency kind is `package`, `packageProduct`, `external`, `sdk`, `framework`, `xcframework`, `library`, or similar
- the resolved path is outside the project root
- the path contains markers such as `checkouts`, `SourcePackages`, `.build`, `.cache`, `CocoaPods`, or `Carthage`

This keeps third-party dependencies classified correctly even when Tuist resolves them through `project/target`.

## Requirements

- macOS
- Xcode
- Tuist CLI installed

Install Tuist:

```bash
brew install tuist
```

If the app cannot find `tuist` from a GUI-launched environment:

```bash
TUIST_EXECUTABLE=/opt/homebrew/bin/tuist ./scripts/run_mac_app.sh
```

## Release Workflow

The recommended end-user artifact is the DMG.

1. Run:

```bash
./scripts/mac/build-release-dmg.sh
```

2. Upload `dist/TuistSpider.dmg` to [GitHub Releases](https://github.com/leejungyeob/TuistSpider/releases)
3. Share the release URL

Use the ZIP build only when you need a plain `.app.zip` artifact for testing or internal distribution.

## Repository Layout

- `App/`
  - SwiftUI macOS app
- `Project.swift`
  - Tuist manifest for TuistSpider itself
- `scripts/run_mac_app.sh`
  - generate, build, and launch the app
- `scripts/open_mac_app.sh`
  - generate and open the Xcode project
- `scripts/mac/build-release-dmg.sh`
  - build a release app and package it as a drag-to-Applications DMG
- `scripts/mac/build-release-zip.sh`
  - build a release app and package it as a plain zip
- `examples/TuistFixture`
  - sample Tuist project for local testing

## License

MIT. See [LICENSE](./LICENSE).
