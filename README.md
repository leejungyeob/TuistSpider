# TuistSpider

![TuistSpider banner](./assets/branding/hero-banner-readme.png)

Inspect only the part of a Tuist dependency graph you actually care about.

`TuistSpider` is a native macOS app for exploring large Tuist module graphs without drowning in the full image export. Pick one module, narrow by direction and depth, group by level when needed, and inspect only the connected paths you want to see.

## Why

Tuist's generated graph is useful, but once a project grows to dozens or hundreds of modules, the full graph image becomes hard to read.

Most of the time, the real questions are simpler:

- What does this module depend on?
- Who depends on this module?
- Which path connects module A to module B?
- Which of those paths do I want to inspect right now?

`TuistSpider` is built for that workflow.

## Highlights

- Open a Tuist project directly and run `tuist graph --format json` from the app
- Load exported graph JSON files
- Filter around one focused module by direction and depth
- Toggle third-party dependencies on or off
- Switch between:
  - `Expanded`: every module as its own card
  - `Grouped`: same-level modules folded into one layer card
- Click a graph node without changing the left-side focus
- Show multiple connection paths from the focused module to the clicked node
- Toggle individual paths on and off, each with its own color
- Zoom and pan with native macOS interactions

## Download

If you only want to use the app, download the release build instead of cloning the repo.

Repository:

- [github.com/leejungyeob/TuistSpider](https://github.com/leejungyeob/TuistSpider)

Releases:

- [github.com/leejungyeob/TuistSpider/releases](https://github.com/leejungyeob/TuistSpider/releases)

### How To Download The Released App

1. Open the [Releases page](https://github.com/leejungyeob/TuistSpider/releases)
2. Open the latest release
3. Under `Assets`, download `TuistSpider.dmg`
4. Open the DMG
5. Drag `TuistSpider.app` into `Applications`
6. Launch the app from `Applications`

If macOS blocks the app because it is unsigned:

1. Right-click `TuistSpider.app`
2. Choose `Open`
3. Click `Open` again in the warning dialog

If you prefer Terminal, you can also remove quarantine manually:

```bash
xattr -dr com.apple.quarantine /Applications/TuistSpider.app
```

macOS apps normally do not auto-copy themselves into `Applications`.
The standard distribution flow is a DMG that shows the app next to the `Applications` shortcut.

## App-Only Distribution

Yes. Users do not need to clone the repo or build from source.

The recommended flow is:

1. Build a release DMG
2. Upload that DMG to GitHub Releases
3. Share the Releases link

Release build command:

```bash
./scripts/mac/build-release-dmg.sh
```

This creates:

```text
dist/TuistSpider.dmg
```

That DMG file is the recommended download for end users.

### How To Publish A Release Asset

If you are uploading the app yourself:

1. Run:

```bash
./scripts/mac/build-release-dmg.sh
```

2. Open [GitHub Releases](https://github.com/leejungyeob/TuistSpider/releases)
3. Click `Draft a new release`
4. Create a tag such as `v0.1.0`
5. Set a release title such as `TuistSpider v0.1.0`
6. Upload `dist/TuistSpider.dmg` to `Assets`
7. Publish the release

After that, users only need the Releases link.

## Quick Start

Run the app locally:

```bash
./scripts/run_mac_app.sh
```

Open the Xcode project instead:

```bash
./scripts/open_mac_app.sh
```

Build a distributable DMG:

```bash
./scripts/mac/build-release-dmg.sh
```

## Screenshots

### Focused graph exploration

![TuistSpider overview](./assets/screenshots/overview-readme.png)

### Multi-path connection tracing

![TuistSpider multi-paths](./assets/screenshots/multi-paths-readme.png)

## Usage

### 1. Open a Tuist project

- Click `프로젝트 열기`
- Select a Tuist project root
- The app runs `tuist graph --format json` internally and loads the graph

### 2. Or open JSON directly

- Click `JSON 열기`
- Load an exported graph JSON file

### 3. Narrow the graph

- Select the focus module from the left sidebar
- Choose `양방향`, `의존하는 쪽`, or `의존받는 쪽`
- Limit depth if needed
- Toggle external dependencies

### 4. Change presentation

- `펼침`
  - Shows every module as its own card
- `계층`
  - Groups same-level modules into one card
  - Click a level card to inspect the modules inside it

### 5. Inspect connection paths

- In expanded mode, click any node in the graph
- The left-side focus stays fixed
- TuistSpider finds multiple visible paths between:
  - the focused module
  - the clicked module
- Each path gets its own color
- Use the right inspector to:
  - show all paths
  - hide all paths
  - toggle specific paths only

## Controls

- Zoom panel in the top-right corner
- Trackpad pinch to zoom
- `space + drag` to pan
- `control + wheel` to zoom

## External Dependency Detection

The `외부 의존성 포함` toggle treats a node as external when:

- the dependency kind is `package`, `packageProduct`, `external`, `sdk`, `framework`, `xcframework`, `library`, or similar
- the path is outside the project root
- the path contains markers like `checkouts`, `SourcePackages`, `.build`, `.cache`, `CocoaPods`, `Carthage`

This means third-party modules still get classified correctly even when Tuist resolves them as `project/target`.

## Requirements

- macOS
- Xcode
- Tuist CLI installed

Example:

```bash
brew install tuist
```

If the app cannot find `tuist` from the GUI environment:

```bash
TUIST_EXECUTABLE=/opt/homebrew/bin/tuist ./scripts/run_mac_app.sh
```

## License

This project is licensed under the MIT License. See [LICENSE](./LICENSE).

## Repository Layout

- `App/`
  - SwiftUI macOS app
- `Project.swift`
  - Tuist manifest for the app itself
- `scripts/run_mac_app.sh`
  - generate + build + launch
- `scripts/open_mac_app.sh`
  - generate + open Xcode project
- `scripts/mac/build-release-zip.sh`
  - build a Release `.app` and package it as a plain zip
- `scripts/mac/build-release-dmg.sh`
  - build a Release `.app` and package it as a drag-to-Applications DMG
- `examples/TuistFixture`
  - local sample Tuist project

## Release Workflow

1. Push `main`
2. Run:

```bash
./scripts/mac/build-release-dmg.sh
```

3. Open GitHub `Releases`
4. Create a new release
5. Upload `dist/TuistSpider.dmg`
6. Share the release URL

If you want, the next step can be automating this with GitHub Actions so every tag builds and uploads the DMG automatically.
