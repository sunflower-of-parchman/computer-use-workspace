# Changelog

## 0.1.0 - 2026-07-20

- Established the `computer-use-workspace` project and skill identity.
- Added display-aware placement reservations for Computer Use application windows.
- Added lifecycle ownership, restoration, cleanup planning, exact-window closure, and graceful app termination.
- Added deterministic planner tests and source-first local builds.
- Allowed safe focused-display gaps when other displays cannot fit a task window.
- Added post-launch replanning from actual window bounds and ordered Computer Use resize-and-move fallbacks.
- Added atomic multi-application preflight with bounded geometry profiles and an explicit refusal for unknown or impossible layouts.
- Added remaining-application replanning after launch-size drift, including a stop-before-next-launch failure contract.
- Changed Computer Use drag fallbacks to app-local coordinates and limited resize fallbacks to profiled resizable windows above their minimum size.
- Added deterministic coverage for batch fit and no-fit, remaining-space preservation, coordinate conversion, and unresizable minimum-size behavior.
- Added baseline capture to preflight and embedded authoritative proof to every placement result.
- Added `prove --restore-focus` for complete batch geometry and focus verification.
- Added `finish-batch` for one-process cleanup planning and lifecycle finalization.
- Reused the fingerprinted built binary for tests so build and verification compile only once.
- Added a fast development build and a combined `build.sh --verify` gate; retained `--release` for optimized builds.
- Made routine state reads non-mutating and replaced full-desktop settle polling with exact-window queries.
- Added compact placement proof summaries with `--verbose` full payloads.
- Made the final successful placement restore focus and prove the complete batch automatically.
- Consolidated single-window cleanup through the same cleanup implementation used by batch finalization.
- Moved recovery and compatibility instructions into progressive-disclosure reference guidance.
- Added deterministic `--layout-variant` selection for alternate safe arrangements, including preservation through post-launch replanning.
- Added the approved repository social preview and release-facing skill language.
- Documented installation, automatic Computer Use invocation, privacy boundaries, and private security reporting.
- Added caller-held lifecycle receipts so mutable local state cannot independently authorize verification, restoration, proof, or cleanup.
- Replaced largest-window launch selection and nearest-window Accessibility matching with fail-closed unique binding.
- Enforced owner-only lifecycle-state permissions and rejected non-finite numeric arguments.
