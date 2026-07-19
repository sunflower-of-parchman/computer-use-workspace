# AGENTS.md

## Project

- This repository contains a macOS workspace-lifecycle extension for Computer Use.
- Keep placement display-aware, cleanup ownership-based, and ambiguous user state preserved.
- Treat macOS Accessibility behavior, window-server behavior, and app window metadata as version-dependent.

## Working agreements

- Read `SKILL.md`, the Swift helper, the wrapper, and the tests before changing behavior.
- Preserve every app, window, and browser tab that predates the task.
- Keep direct cleanup limited to the exact task-owned window recorded by the lifecycle state.
- Keep compiled binaries and local state out of Git.
- Keep `README.md`, `SKILL.md`, agent metadata, helper output, and tests consistent when behavior changes.
- Do not publish releases, change repository visibility, or select a public license without Michael's explicit approval.

## Verification

- Run `bash tests/test.sh` after source, shell, metadata, or instruction changes.
- Run `bash scripts/build.sh` before live testing the installed skill.
- Use `scan` and `prepare --dry-run` for read-only desktop verification.
- Use a disposable application for live lifecycle verification and confirm focus preservation, exact-window cleanup, and preservation of pre-existing resources.
- Report changed files, verification results, and remaining macOS permission or compatibility uncertainty clearly.
