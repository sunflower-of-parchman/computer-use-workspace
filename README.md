# Computer Use Workspace

Computer Use Workspace is a macOS skill that manages the space around Computer Use. It finds a safe region across active displays before an application opens, places the task window there, remembers what existed before the task, and cleans up only the resources the task created.

The first technique covers application-window placement and lifecycle cleanup. The project can hold additional workspace techniques as they become concrete.

## What It Does

- Detects active displays, visible application windows, the focused display, and the pointer display.
- Protects the display the user is actively using when another display has safe space.
- Reserves an unoccupied region before Computer Use launches an app or creates a top-level window.
- Places and verifies the new window through macOS Accessibility, with an exact Computer Use drag fallback.
- Records whether the app was already running and which windows already existed.
- Plans cleanup before applying it.
- Closes only the recorded task-owned window and quits only an app the task launched.
- Preserves edited content, modal state, sheets, active media, transfers, and ambiguous browser tabs.

## Relationship To Computer Use

This is a workflow extension around Computer Use. Computer Use continues to operate application content. Computer Use Workspace handles window placement, lifecycle ownership, restoration, and cleanup.

It is an independent project and is not an official OpenAI product or fork.

## Requirements

- macOS
- Swift toolchain
- Codex with the Computer Use skill
- Screen Recording permission for window geometry inspection
- Accessibility permission for direct window placement and cleanup

The helper inspects application identifiers, process identifiers, display bounds, and window bounds. It does not inspect window titles or screen content.

## Install For Local Development

Clone the repository, build the local helper, and link the repository into the user-level Codex skills directory:

```bash
git clone https://github.com/sunflower-of-parchman/computer-use-workspace.git \
  "$HOME/code/computer-use-workspace"
cd "$HOME/code/computer-use-workspace"
bash scripts/build.sh
mkdir -p "$HOME/.codex/skills"
ln -s "$PWD" "$HOME/.codex/skills/computer-use-workspace"
```

Then invoke `$computer-use-workspace`. Restart Codex if the skill has not appeared.

The symlink keeps the installed skill and the repository on the same source. Rebuild after changing the Swift helper.

## Lifecycle

Prepare before Computer Use can launch the target application:

```bash
WORKSPACE="$HOME/.codex/skills/computer-use-workspace/scripts/computer-use-workspace"
"$WORKSPACE" prepare --app com.apple.TextEdit
```

Retain the returned `reservationID`, launch or target the app through Computer Use, and place the new window:

```bash
"$WORKSPACE" place --reservation RESERVATION_ID
```

Plan cleanup when the task is complete:

```bash
"$WORKSPACE" finish --reservation RESERVATION_ID
```

Apply that plan after reviewing `plannedAction` and the safety state:

```bash
"$WORKSPACE" finish --reservation RESERVATION_ID --apply
```

Use `--leave-open --apply` when the user wants the result to remain visible.

See [SKILL.md](SKILL.md) for the complete workflow, cleanup policy, browser-tab boundaries, and fallback behavior.

## Verification

Run the deterministic source, shell, metadata, and planner tests:

```bash
bash tests/test.sh
```

Build the installed helper and run read-only live checks:

```bash
bash scripts/build.sh
scripts/computer-use-workspace scan
scripts/computer-use-workspace prepare --dry-run --app com.apple.TextEdit
```

A full live lifecycle test uses a disposable application and verifies placement, focus preservation, cleanup planning, exact-window closure, graceful termination, and preservation of pre-existing resources.

## Project Status

This repository is in private development. The placement and cleanup lifecycle works on the development Mac across a two-display setup. Broader macOS versions, display arrangements, permission states, browsers, and applications still need coverage before public release.

No public license has been selected. Public distribution will include an explicit license and a review of installation, permissions, privacy, compatibility, and failure behavior.
