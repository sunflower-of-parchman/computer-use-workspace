# Computer Use Workspace

![Computer Use Workspace](.github/social-preview.jpg)

Computer Use Workspace is a macOS lifecycle skill for Computer Use. It plans where task windows can safely fit across active displays before launch, places and verifies each new window, restores the user's focus, and removes only the windows and applications the task owns when the work is complete.

It extends Computer Use without replacing it: Computer Use operates the application, while Computer Use Workspace manages the surrounding desktop. The current technique covers application-window placement and ownership-based cleanup. The project can hold additional workspace techniques as they become concrete.

> **Release status:** `0.1.0` release candidate. The core single-window and multi-application workflows are working on the development Mac. Public release still requires a license decision and broader macOS compatibility testing.

## What This Skill Is

- A display-aware workspace lifecycle for Computer Use on macOS.
- A preflight planner that finds safe regions across the user's active displays before applications launch.
- A placement layer that moves each new task window into its reserved region and verifies the result.
- An ownership record that distinguishes task-created windows from everything that already existed.
- A cleanup workflow that reviews, closes, or leaves open only the resources connected to the task.
- A reusable Codex skill whose repository remains the source of truth for its installed version.

## What It Does

- Detects active displays, visible application windows, the focused display, and the pointer display.
- Prefers another active display, then uses genuinely empty space on the focused display when the other displays cannot fit the window.
- Preflights a complete application group from one exact Core Graphics display-and-window scan and reserves the layout atomically before launch.
- Supports deterministic alternate layout variants while retaining the same complete-fit and collision constraints.
- Uses bounded launch-size, minimum-size, and resizability profiles; unknown application geometry stays explicit.
- Replans the current window and every remaining application together when actual launch bounds differ from the profile, and stops before another launch when the group no longer fits.
- Places and verifies the new window through macOS Accessibility, with app-local Computer Use move or proven-safe resize-and-move drag fallbacks.
- Refuses multiple new launch windows and requires one bounded, unique Core Graphics-to-Accessibility geometry match before any Accessibility action.
- Returns a caller-held lifecycle receipt that authenticates the exact record used for later verification, restoration, proof, and cleanup.
- Returns compact batch state, remaining reservations, containment, and disjointness proof with every placement; `--verbose` exposes the complete authoritative payload.
- Restores focus and proves the complete batch automatically on the final successful placement, then finalizes every cleanup lifecycle in one helper process.
- Records whether the app was already running and which windows already existed.
- Plans cleanup before applying it.
- Closes only the recorded task-owned window and quits only an app the task launched.
- Preserves edited content, modal state, sheets, active media, transfers, and ambiguous browser tabs.

## Relationship To Computer Use

This is a workflow extension around Computer Use. Computer Use continues to operate application content. Computer Use Workspace handles window placement, lifecycle ownership, restoration, and cleanup.

It is an independent project and is not an official OpenAI product or fork.

## Safety Model

Computer Use Workspace works from an exact pre-task baseline and keeps an ownership record for every task window. Its core guarantees are:

- solve the complete requested layout before launching the first application;
- never move a pre-existing window to manufacture space;
- place only a newly created window belonging to the requested application;
- stop before launching another application when the remaining group no longer fits;
- preserve every application, window, and browser tab that predates the task;
- preserve edited, modal, active, or ambiguously owned state; and
- close or quit only resources recorded as task-owned; and
- require the caller-held lifecycle receipt before a retained record can authorize later window actions.

macOS can briefly display a newly launched application at its own initial position before its window becomes available for placement. The helper minimizes that interval by placing the window immediately after it appears.

## Requirements

- macOS
- Swift toolchain
- Codex with the Computer Use skill
- Screen Recording permission for window geometry inspection
- Accessibility permission for direct window placement and cleanup

The helper inspects application identifiers, process identifiers, display bounds, and window bounds. It does not inspect window titles or screen content.

## Install

Clone the skill into the user-level Codex skills directory and build its local Swift helper:

```bash
mkdir -p "$HOME/.codex/skills"
git clone https://github.com/sunflower-of-parchman/computer-use-workspace.git \
  "$HOME/.codex/skills/computer-use-workspace"
bash "$HOME/.codex/skills/computer-use-workspace/scripts/build.sh" --release --verify
```

Restart Codex if the skill does not appear immediately, then invoke `$computer-use-workspace`.

### Local development checkout

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

## Enable It For Computer Use

To make the lifecycle automatic, add this instruction to your global or project `AGENTS.md`:

> Before Computer Use first targets a macOS application that is not already running or opens a new top-level application window in the session, use `$computer-use-workspace` to reserve a safe display region. Place and verify the new window immediately after launch, retain its lifecycle record while working, and at completion clean up only task-owned apps, windows, and tabs while preserving pre-existing, edited, ambiguous, or user-requested-visible state.

## Lifecycle

Preflight a multi-application task before Computer Use launches any application:

```bash
WORKSPACE="$HOME/.codex/skills/computer-use-workspace/scripts/computer-use-workspace"
"$WORKSPACE" preflight --request '[
  {"app":"com.apple.Chess","width":620,"height":560},
  {"app":"com.apple.SystemProfiler","width":720,"height":520},
  {"app":"com.apple.FontBook","width":680,"height":520}
]'
```

Add `--layout-variant N` when a different safe arrangement is desired; the selected variant also governs any post-launch group replan.

Launch in the returned `launchOrder`. After each app appears, run `place` with that item's `reservationID` before launching the next app. Retain each returned `lifecycleReceipt`; this caller-held value is required for later lifecycle commands. Pass the accumulated receipt map to each later placement or verification so the final embedded proof authenticates every lifecycle. A launch-size mismatch causes a group replan that preserves space for every remaining app. Routine output contains compact batch and proof results; add `--verbose` for the complete scan, batch, and proof payload.

Create one JSON receipt map keyed by reservation ID:

```bash
RECEIPTS='{"RESERVATION_ID":"LIFECYCLE_RECEIPT"}'
"$WORKSPACE" place --reservation NEXT_RESERVATION_ID --receipts "$RECEIPTS"
```

The final successful placement proves the complete batch, restores the original frontmost application, and returns `placed_and_proved`. Rerun proof only for recovery:

```bash
"$WORKSPACE" prove --batch BATCH_ID --receipts "$RECEIPTS" --restore-focus
```

Finalize cleanup in one process:

```bash
"$WORKSPACE" finish-batch --batch BATCH_ID --receipts "$RECEIPTS" --apply
```

Use `--leave-open` to preserve every proof window while finalizing its lifecycle record.

For one application, prepare before Computer Use can launch it:

```bash
WORKSPACE="$HOME/.codex/skills/computer-use-workspace/scripts/computer-use-workspace"
"$WORKSPACE" prepare --app com.apple.TextEdit
```

Retain the returned `reservationID`, launch or target the app through Computer Use, and place the new window:

```bash
"$WORKSPACE" place --reservation RESERVATION_ID
```

Retain the returned `lifecycleReceipt` with the reservation ID.

When `place` returns `computerUseDrag` or `computerUseDrags`, pass the app-local points directly to Computer Use, execute ordered drags in array order, and run `verify`. Resize fallbacks are emitted only for a profiled resizable app above its proven minimum.

Plan cleanup when the task is complete:

```bash
"$WORKSPACE" finish --reservation RESERVATION_ID --receipt LIFECYCLE_RECEIPT
```

Apply that plan after reviewing `plannedAction` and the safety state:

```bash
"$WORKSPACE" finish --reservation RESERVATION_ID --receipt LIFECYCLE_RECEIPT --apply
```

Use `--leave-open --apply` when the user wants the result to remain visible.

See [SKILL.md](SKILL.md) for the complete workflow, cleanup policy, browser-tab boundaries, and fallback behavior.

## Verification

Compile once and run the deterministic shell, metadata, planner, and proof tests against that exact binary:

```bash
bash scripts/build.sh --verify
```

The default development build uses the faster `-Onone` compilation path. Use `--release` for an optimized release binary.

Run read-only live checks:

```bash
scripts/computer-use-workspace scan
scripts/computer-use-workspace prepare --dry-run --app com.apple.TextEdit
scripts/computer-use-workspace preflight --dry-run --request '[{"app":"com.apple.Chess","width":620,"height":560}]'
```

A full live batch test uses distinct disposable applications only after complete preflight succeeds. It verifies final non-overlap, focus restoration, remaining-app space preservation, ownership-based cleanup or explicit leave-open handling, and preservation of every pre-existing resource. macOS can briefly show an application at its own initial position before its new window exists and can be moved.

## Privacy

The helper reads local macOS display geometry, application bundle identifiers, process identifiers, window identifiers, and window bounds through Core Graphics and Accessibility APIs. It does not read window titles, screen pixels, application content, keystrokes, credentials, or network traffic.

Lifecycle state is stored locally in `/private/tmp` for the current macOS user with owner-only permissions and bounded expiration and retention rules. Cleanup-relevant records require a caller-held receipt that is never written into lifecycle state. The helper makes no network requests. Installing or updating the repository through Git remains a separate user action.

## Security

See [SECURITY.md](SECURITY.md) for private vulnerability reporting. The release candidate is also reviewed with Codex Security before publication.

## Project Status

The single-window and batch placement lifecycle works on the development Mac across a two-display setup. The helper supports compact embedded placement proof, automatic final batch proof with focus restoration, and batch cleanup finalization. Broader macOS versions, display arrangements, permission states, browsers, and applications still need coverage before a stable public release.

No public license has been selected. Until a license is added, the repository is source-available for review but is not ready for public reuse or distribution.
