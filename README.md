# cubegin

Native SwiftUI speedcubing timer for iPhone and iPad. Requires Xcode 26+ and iOS/iPadOS 26+. Uses Apple's Liquid Glass with system light/dark appearance.

## Run

The app uses the installed **Cubegin SDK 0.1.0** in `Vendor/CubeginSDK`.
Open `Cubegin.xcodeproj`, select **CubeginApp** and an iPhone/iPad simulator.
For a physical device, select a development team in Signing & Capabilities.
Building the app requires Xcode only; no core checkout, Rust or Node is needed.

## Tests and CI

Run the **CubeginApp** scheme’s Test action on an iOS simulator to execute
the App’s unit and XCUITest suites. [App checks](.github/workflows/check.yml) builds the Release
app for iOS, runs both suites in an iOS simulator, and runs the bundled SDK’s
SwiftPM consumer tests. See [testing](docs/testing.md) for commands and test coverage.

## Upgrade the installed SDK

In a core checkout run `cargo xtask build-sdk ios`. Verify the checksum of
`dist/CubeginSDK-<version>.zip`, extract it, then run in this app repository:

```sh
python3 scripts/install-sdk.py /path/to/CubeginSDK-0.1.0
```

The installer verifies every file against `SDK.json` before replacing
`Vendor/CubeginSDK`. Keep that entire directory with the app repository, including
binaries, generated bindings, manifest and notices. Treat it as an installed
artifact; make engine changes in core and reinstall a newly built package.
`SDK.json` records version, packaging-time source commit/dirty status and file
hashes. This installation is a locally built candidate.
SDK versions come from core's Cargo workspace version and are independent of the
app version. Current SDK: 0.1.0. Do not mix bindings and binaries between builds.

Without the SDK, open `CubeginPreview.xcodeproj` to inspect the interface. It shows an explicit integration error; generation and timing require the real SDK. No mock cube algorithms are used.

## Ownership and behavior

`Engine.swift` is a thin background adapter for `generateEvent` and `evaluateEvent` (SVG net). Cube semantics stay in Rust. Swift owns timing, gestures, local JSON persistence, native layout and SVG display in a JavaScript-disabled WKWebView.

Select an event from the compact native menu; the dumbbell icon on the right toggles Training. A new app process starts in Standard. Standard includes 16 events (FMC and multi-blind excluded); Training includes 94 types grouped in two menu levels. Each mode remembers its last event selection across launches. Training uses the installed SDK's generateTraining API with default options; case filtering is not yet exposed.

Hold the screen or spacebar until the timer turns green, then release to start. Press again to stop. The start delay defaults to 0.2 seconds and can be adjusted in Settings. Time uses ContinuousClock; interruption cancels an active attempt without saving. Results retain date, event, group and scramble in Documents/solves.json, including the complete training type ID. Each event has a default group; Results supports creating, reordering and editing groups in a sheet. Editing includes the name and default setting. Deleting a non-default group also permanently deletes its results after confirmation. The event and Training controls are shared with Home. The group and view pickers share one row, with Results, Averages, Overview and Charts views. Charts uses icons to switch between solve trends and a time histogram for the current group. The trend shows single solves and all available rolling averages by default. The color legend identifies each series, and the Averages menu toggles individual lines. After stopping, use +2 to add two seconds, DNF to mark the result invalid, or the trash button to open a deletion confirmation. Tap an active penalty again to clear it. The original time is retained for penalized solves. The solve details screen supports changing or clearing +2/DNF, deleting a solve, moving it to another group in the same event, and viewing its scramble diagram. Inspection, sync and competition workflows are not yet implemented. iPad layout supports resizable windows through a centered adaptive width.

The timer footer shows the current group’s valid and total attempts, overall mean, best single, and current mo3, ao5 and ao12 next to the scramble diagram.

The Averages view shows rolling mo3, ao5, ao12, ao50, ao100, ao500, ao1000 and ao10000 once the selected group has enough attempts. Tap an average to see its standard deviation (σ), fastest and worst singles, and open any solve in the window. Settings can exclude DNF from the worst-result highlight.

Overview shows the selected group’s valid and total attempts, mean and single extremes, current and best rolling averages, and attempt counts for the latest eight active days.

GPL-3.0-only; see LICENSE and NOTICE. Core provenance and bundled dependency notices must accompany distribution. Device rendering acceptance and distribution/signing remain separate verification steps.

## Verified locally (2026-11-03)

Rust 1.96.0, Node 24.21.0, pnpm 10.33.0 and Xcode 27.2. `cargo xtask build-sdk ios` completed, including host SwiftPM tests and an isolated consumer extracted from the SDK ZIP (2 tests passed). The CubeginApp scheme built and launched on iPhone 18 Pro / iOS 27.2 Simulator; real Rust-generated 3×3 scramble and SVG net appeared. Physical-device acceptance and distribution are not verified.

Use **CubeginApp**, rather than the Swift package's auto-generated **Cubegin** scheme, when running the app. The SDK is installed in Vendor/CubeginSDK; the app has no sibling core dependency.

The installed SDK package passed its SwiftPM consumer tests, and the app was rebuilt with a fresh DerivedData directory using only Vendor/CubeginSDK.

## 知识库

- [代理与协作规则](AGENTS.md)
- [架构与产品边界](docs/architecture.md)
- [SDK 安装、版本和调用](docs/sdk.md)
- [构建与验证](docs/testing.md)
- [当前状态与待办](docs/status.md)
- [打乱项目中英文名称对照](docs/scramble-names.md)
