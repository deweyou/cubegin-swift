# Provenance and dependencies

The repository remains GPL-3.0-only. Rebuilding or translating legacy behavior does
not erase source provenance. Preserve LICENSE and NOTICE in distributed artifacts.

- Legacy implementation: `79a1e4c4c5239fbcda8cccf313a81b8d7d430a97`. State fixtures
  were extracted before deletion. Prior sources included TNoodle-lib v0.19.2 (GPL-3.0)
  and cstimer. Historical attribution is retained; no AGPL TNoodle app code is copied.
- Maintained backend: `crates/tnoodle`, based on `tnoodle-rs 0.1.1`, upstream
  commit `373e868f802e0f095bea9353282d9fdca5d1883d` in enekocm7/cube-tui.
  GPL-3.0-or-later, GPLv3 selected for combined distribution. The package archive
  omitted LICENSE; the upstream repository GPLv3 text was retrieved at that commit.
  Source headers and UPSTREAM.md retain original solver attribution. Local changes:
  project crate identity, serial default, WASM-safe time, state construction/access,
  extended Clock rotations and cube permutation accessors. No upstream fixture
  test results are claimed: those fixtures were excluded from the archive.
- Player static geometry and move mappings: legacy `packages/player` at `79a1e4c`.
  Pyraminx/Skewb/Megaminx reference cubing.js (MPL-2.0 OR GPL-3.0-or-later), GPL
  option selected. No cubing.js/Three.js runtime dependency is shipped.
- Training cases, auxiliary coordinate/pruning tables and subgroup rules are
  declarative data ported from the legacy GPL implementation. See crate data READMEs.
- The separate min2phase 0.2.4 dependency was replaced; historical MIT notice remains.
- UniFFI 0.32.2: MPL-2.0. Runtime is bundled into native artifacts; preserve its
  notices and source availability requirements in a public release.
- JNA 5.17.0: LGPL-2.1-or-later OR Apache-2.0. Select Apache-2.0 for Android distribution.
- wasm-bindgen: MIT OR Apache-2.0; rand and rand_chacha: MIT OR Apache-2.0;
  serde/serde_json: MIT OR Apache-2.0; thiserror: MIT OR Apache-2.0.
- Gradle wrapper 8.11.1: Apache-2.0; fetched from Gradle's official tagged source.
- Vite: MIT; TypeScript and Playwright: Apache-2.0; development tools only.

Cargo.lock and pnpm-lock.yaml pin resolved dependencies. Before public release,
produce a full transitive dependency/license inventory for each shipped artifact,
include required license texts, and review source availability and mobile distribution.
Initial scaffold NOTICE is not a completed transitive license audit.
