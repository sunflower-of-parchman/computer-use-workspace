---
name: computer-use-workspace
description: "Manage the lifecycle of macOS application windows used by Computer Use: reserve safe display space, place and verify new windows, restore layouts, and clean up only task-owned apps, windows, and browser tabs. Use before Computer Use first targets an app that is not already running or creates a new top-level window, and again when Computer Use finishes with resources it created."
---

# Computer Use Workspace

Treat this skill as a workspace-lifecycle extension to the Computer Use skill. Keep Computer Use and purpose-built browser tools as the interfaces for operating app content.

## Commands

Set the helper path once:

```bash
COMPUTER_USE_WORKSPACE="$HOME/.codex/skills/computer-use-workspace/scripts/computer-use-workspace"
```

Inspect the desktop without moving anything:

```bash
"$COMPUTER_USE_WORKSPACE" scan
```

Reserve a placement before the first Computer Use call that can launch the app:

```bash
"$COMPUTER_USE_WORKSPACE" prepare --app com.apple.TextEdit
```

Retain the returned `reservationID`. Then initialize or target the app through Computer Use. Immediately place the new window:

```bash
"$COMPUTER_USE_WORKSPACE" place --reservation RESERVATION_ID
```

If `place` returns `computerUseDrag`, execute that exact drag with Computer Use and verify it:

```bash
"$COMPUTER_USE_WORKSPACE" verify --reservation RESERVATION_ID
```

Restore a moved window when placement disrupts the user's layout:

```bash
"$COMPUTER_USE_WORKSPACE" restore --reservation RESERVATION_ID
```

Release an unused reservation:

```bash
"$COMPUTER_USE_WORKSPACE" release --reservation RESERVATION_ID
```

Plan cleanup without closing anything:

```bash
"$COMPUTER_USE_WORKSPACE" finish --reservation RESERVATION_ID
```

Review `plannedAction`, ownership, and safety state. Apply the plan only when it matches the completed task:

```bash
"$COMPUTER_USE_WORKSPACE" finish --reservation RESERVATION_ID --apply
```

When the user asked to keep the result visible, finalize ownership while leaving it open:

```bash
"$COMPUTER_USE_WORKSPACE" finish --reservation RESERVATION_ID --leave-open --apply
```

If direct cleanup is unavailable, close the exact task-owned window through Computer Use and verify it:

```bash
"$COMPUTER_USE_WORKSPACE" finish --reservation RESERVATION_ID --confirm-closed
```

## Required workflow

1. Run `prepare` before Computer Use can launch the target app.
2. Preserve the focused display. Prefer an empty region on another active display.
3. Stop placement when `prepare` returns `no_safe_placement`. Continue only with the user's awareness that macOS may place the app in their active workspace.
4. Use Computer Use normally to launch or activate the app.
5. Run `place` immediately after the first `get_app_state` call.
6. Use the returned Computer Use drag only when direct Accessibility placement is unavailable.
7. Run `verify` after a drag fallback.
8. Keep the reservation ID available for `restore` and `finish` throughout the task.
9. At task completion, run `finish` without `--apply` and review the cleanup plan.
10. Leave the result visible when the user asked to open, show, compare, review, or continue using it.
11. Otherwise run `finish --apply` to close only the task-owned window and quit only an app the agent launched.
12. Run `release` if the target app never opens.

## Cleanup policy

- Preserve every app, window, and browser tab that existed before the task.
- Close the exact window created for the task when it is no longer useful.
- Quit the app only when it was not running before `prepare` and no other visible window remains.
- Preserve edited windows, modal surfaces, sheets, active transfers, playback, recording, or any ambiguous state.
- Treat `leave_open`, `preserve_edited`, and `preserve_modal` as successful safe outcomes and report what remains.
- Use `finish --confirm-closed` only after Computer Use closes the exact window named by the lifecycle record.

## Browser tabs

Track browser tabs through the same Browser or Chrome tool that creates them. Retain exact task-owned page or tab identifiers in the working context and close only those identifiers at task completion.

- Preserve pinned tabs, pre-existing tabs, downloads, uploads, media, forms with entered data, and tabs left for user review.
- Close a dedicated browser window only when the task created that window and all of its task-owned tabs are finished.
- When Computer Use does not expose stable tab identity, preserve ambiguous tabs and report them. Do not infer ownership from tab count or title alone.

## Safety boundaries

- Treat `scan` and `prepare` as read-only desktop inspection. They collect bundle identifiers, process identifiers, display bounds, and window bounds. They do not collect titles or screen content.
- Move only a window belonging to the requested bundle identifier.
- When the target app already had windows before `prepare`, require a newly created window. Do not repurpose an existing window automatically.
- Never move another app's windows to manufacture empty space.
- Never place over a live reservation held by another agent.
- Keep the focused display protected whenever another display has safe space.
- Preserve the original bounds before every move.
- Preserve the recorded pre-launch process and window baseline through cleanup.
- Never use force quit for routine cleanup.
- Report `no_safe_placement`, `no_new_window`, permission failures, and verification failures directly.

## Verification

Run the project verification after editing the helper:

```bash
bash "$HOME/.codex/skills/computer-use-workspace/tests/test.sh"
```

Use `scan` and `prepare --dry-run --app BUNDLE_ID` for live read-only verification. A live lifecycle test must use a disposable application window and prove placement, focus preservation, cleanup planning, exact-window closure, graceful app termination, and preservation of pre-existing resources.
