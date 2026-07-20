# Recovery and compatibility

Use these paths when the compact batch workflow cannot complete normally.

## Read-only inspection

```bash
"$COMPUTER_USE_WORKSPACE" scan
"$COMPUTER_USE_WORKSPACE" preflight --dry-run --request JSON
"$COMPUTER_USE_WORKSPACE" prepare --dry-run --app BUNDLE_ID
```

Core Graphics display and window bounds are the geometry authority. The helper collects bundle identifiers, process identifiers, window identifiers, and geometry. It does not collect window titles or screen content.

## Standalone compatibility lifecycle

Reserve one application without batch proof:

```bash
"$COMPUTER_USE_WORKSPACE" prepare --app BUNDLE_ID --width 900 --height 700
"$COMPUTER_USE_WORKSPACE" place --reservation RESERVATION_ID
```

Retain the `lifecycleReceipt` from `place`. Lifecycle commands fail closed when the receipt is missing, incorrect, or no longer matches the stored record.

Treat `reserved_uncertain` as explicit launch-geometry uncertainty. When the app already had windows, placement requires a newly created window and never repurposes existing state.

Release a reservation that was never used:

```bash
"$COMPUTER_USE_WORKSPACE" release --reservation RESERVATION_ID
```

Restore a moved task window to its recorded original bounds:

```bash
"$COMPUTER_USE_WORKSPACE" restore --reservation RESERVATION_ID --receipt LIFECYCLE_RECEIPT
```

## Manual proof recovery

Inspect retained batch state or rerun the complete proof:

```bash
"$COMPUTER_USE_WORKSPACE" batch-status --batch BATCH_ID
"$COMPUTER_USE_WORKSPACE" prove --batch BATCH_ID --receipts '{"RESERVATION_ID":"LIFECYCLE_RECEIPT"}' --restore-focus
```

Add `--verbose` to placement or verification for the authoritative snapshot, complete batch, baseline comparison, proof-window results, and remaining reservations.

## Single-window cleanup

Preview and apply cleanup:

```bash
"$COMPUTER_USE_WORKSPACE" finish --reservation RESERVATION_ID --receipt LIFECYCLE_RECEIPT
"$COMPUTER_USE_WORKSPACE" finish --reservation RESERVATION_ID --receipt LIFECYCLE_RECEIPT --apply
```

Leave a user-requested result open while finalizing lifecycle ownership:

```bash
"$COMPUTER_USE_WORKSPACE" finish --reservation RESERVATION_ID --receipt LIFECYCLE_RECEIPT --leave-open --apply
```

If direct cleanup is unavailable, close the exact recorded window with Computer Use and verify closure:

```bash
"$COMPUTER_USE_WORKSPACE" finish --reservation RESERVATION_ID --receipt LIFECYCLE_RECEIPT --confirm-closed
```

Preserve the window when identity, edits, modal state, transfers, playback, recording, or ownership is ambiguous.

## Browser tabs

Retain exact task-owned page or tab identifiers from the Browser or Chrome tool that created them. Close only those identifiers. Preserve pinned tabs, pre-existing tabs, downloads, uploads, media, forms with entered data, and tabs left for review. Preserve ambiguous tabs when stable identity is unavailable; title and tab count do not establish ownership.
