# cubegin

Native SwiftUI speedcubing timer for iPhone and iPad. Requires Xcode 26+ and iOS/iPadOS 26+. Uses Apple's Liquid Glass with system light/dark appearance.

## Run

The app uses the installed **Cubegin SDK 0.1.0** in `Vendor/CubeginSDK`.
Open `Cubegin.xcodeproj`, select **CubeginApp** and an iPhone/iPad simulator.
For a physical device, select a development team in Signing & Capabilities.
Building the app requires Xcode only; no core checkout, Rust or Node is needed.

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
hashes. This installation is a local dirty candidate, not a published release.
SDK versions come from core's Cargo workspace version and are independent of the
app version. Current SDK: 0.1.0. Do not mix bindings and binaries between builds.

Without the SDK, open `CubeginPreview.xcodeproj` to inspect the interface. It shows an explicit integration error; generation, timing and assistance require the real SDK. No mock cube algorithms are used.

## Ownership and behavior

`Engine.swift` is a thin background adapter for `generateEvent`, `evaluateEvent` (SVG net) and `solveAssist` (Cross JSON). Cube semantics stay in Rust. Swift owns timing, gestures, local JSON persistence, native layout and SVG display in a JavaScript-disabled WKWebView. Assistance currently displays the SDK JSON response.

Tap to start/stop. Time uses ContinuousClock; interruption cancels an active attempt without saving. Results retain date, event and scramble in Documents/solves.json. Statistics are per-event lifetime count/best/mean. This scaffold does not yet implement inspection, hold-to-ready, penalties, sessions, rolling averages, editing, sync or competition workflows. iPad layout supports resizable windows through a centered adaptive width.

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
