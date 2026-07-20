---
name: computer-use-workspace
description: "Preflight and manage macOS application windows around Computer Use: solve safe multi-app layouts across active displays before launch, place and prove each task-owned window, restore focus, and perform ownership-based cleanup. Use whenever Computer Use will launch a Mac app, create a top-level window, arrange one to four apps, or clean up windows, apps, or tabs created during the task."
---

# Computer Use Workspace

Use this skill as the display-aware workspace lifecycle around Computer Use. Computer Use operates app content; this helper plans window geometry, records ownership, proves placement, and performs bounded cleanup.

Set the helper path once:

```bash
COMPUTER_USE_WORKSPACE="$HOME/.codex/skills/computer-use-workspace/scripts/computer-use-workspace"
```

## Fast batch workflow

Before launching one to four applications, preflight the complete group in one call:

```bash
"$COMPUTER_USE_WORKSPACE" preflight --request '[
  {"app":"com.apple.Dictionary","width":690,"height":624},
  {"app":"com.apple.DigitalColorMeter","width":500,"height":500,"launchWidth":500,"launchHeight":500,"minimumWidth":300,"minimumHeight":250,"resizable":true},
  {"app":"com.apple.calculator","width":230,"height":408}
]'
```

Continue only after `batch_planned`. Retain `batchID`, `launchOrder`, and every `reservationID`. Launch one app at a time in the returned order. Immediately after its first Computer Use `get_app_state`, place it before launching the next app:

```bash
"$COMPUTER_USE_WORKSPACE" place --reservation RESERVATION_ID
```

Retain the `lifecycleReceipt` returned for every placed window. It is caller-held proof that binds later verification, restoration, proof, and cleanup to the exact lifecycle record. Build one JSON object keyed by reservation ID, and pass the accumulated map to each later `place` or `verify` so the final embedded proof can authenticate the entire batch:

```bash
RECEIPTS='{"RESERVATION_ID":"LIFECYCLE_RECEIPT"}'
"$COMPUTER_USE_WORKSPACE" place --reservation NEXT_RESERVATION_ID --receipts "$RECEIPTS"
```

When the user explicitly asks for a different valid arrangement, add `--layout-variant N` to preflight with a non-negative integer. The variant changes candidate order while retaining the same complete-fit, collision, display, reservation, and proof requirements. It is stored with the batch so launch-size replanning preserves the chosen variant.

Routine `place` output is compact. It includes batch status, remaining reservations, and a proof summary. The final successful `place` restores the baseline frontmost app and returns `placed_and_proved` only when complete batch proof passes. This replaces routine `scan`, `batch-status`, and `prove` calls.

If `place` returns `computerUseDrag` or `computerUseDrags`, pass each app-local `from` and `to` directly to Computer Use in array order, then run:

```bash
"$COMPUTER_USE_WORKSPACE" verify --reservation RESERVATION_ID --receipt LIFECYCLE_RECEIPT --receipts "$RECEIPTS"
```

Run `prove --batch BATCH_ID --receipts "$RECEIPTS" --restore-focus` only to repeat or recover final proof. Add `--verbose` to `preflight`, `place`, or `verify` when the complete snapshot, batch, and proof payload is needed.

At completion, preview ownership-based cleanup when any app state is ambiguous:

```bash
"$COMPUTER_USE_WORKSPACE" finish-batch --batch BATCH_ID --receipts "$RECEIPTS"
```

Apply the reviewed batch in one process:

```bash
"$COMPUTER_USE_WORKSPACE" finish-batch --batch BATCH_ID --receipts "$RECEIPTS" --apply
```

Add `--leave-open` only when the user wants the proof windows left visible.

## Required behavior

1. Preflight the complete requested app set before the first launch. The preflight baseline is authoritative; screenshots are optional visual context.
2. Stop on `unknown_geometry`, `preexisting_apps`, or `batch_no_safe_layout`. Use an explicitly bounded geometry profile for an unknown app only when its constraints are known.
3. Follow `launchOrder`. Launch and place one app before launching the next.
4. Stop before another launch on `ambiguous_new_windows`, `ambiguous_ax_window`, `batch_replan_failed`, `unresizable_target`, or any placement or verification failure.
5. Accept `placed_and_proved` on the final app only when containment, display bounds, pairwise disjointness, exact baseline-window equality, and restored focus are all true.
6. Finish the batch once. Preserve all pre-existing, edited, modal, active, ambiguous, or user-requested-visible state.

macOS may show a new app at its own initial position briefly before its window exists for placement. Keep that interval short by placing immediately after the first app-state call.

## Cleanup boundaries

- Close only the exact task-owned window recorded by the lifecycle state.
- Require the caller-held receipt before trusting a retained lifecycle record.
- Quit an app only when the task launched it and no other visible window remains.
- Preserve every app, window, and browser tab that predates the task.
- Preserve edited content, modal surfaces, sheets, transfers, playback, recording, and ambiguous ownership.
- Never force quit for routine cleanup.
- Track task-owned browser tabs through the same browser tool that created them; preserve tabs without stable identity.

## Recovery and compatibility

Read [references/recovery.md](references/recovery.md) only for standalone reservations, manual proof recovery, restore, exact-window Computer Use cleanup, or browser-tab ambiguity.

## Verification

After helper, wrapper, metadata, or instruction changes, compile once and reuse that binary for all deterministic checks:

```bash
bash "$HOME/.codex/skills/computer-use-workspace/scripts/build.sh" --verify
```

Use `--release` only for a release-performance build. Before live testing, use `scan` or `preflight --dry-run` for read-only desktop verification. A live test must use disposable apps, begin after complete preflight succeeds, preserve baseline windows, prove the final layout and focus, and clean up only task-owned resources.
