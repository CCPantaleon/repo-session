# Reliability update — 0.5.0

This release addresses the five follow-up findings from 0.4.0. Earlier source and release ZIPs remain available separately.

1. **Scan-only status reaches the UI.** The scanner now calls the volume policy while constructing each file record. Restrictions survive hashing, SQLite persistence/reopening, smart selection, and app-level selection. New tests use actual filesystem scans with an injected external-volume policy, covering the connection missed in 0.4.0. Native volume checks remain in the Trash adapter.
2. **Saved scans keep their intended roots.** External mode and selected volume IDs are derived from the scan configuration. Opening history switches configuration to the saved roots; startScan no longer overrides it using a stale mode flag. Restored external selections remain visible and selectable.
3. **Keep is reversible.** Comparison and inspector views offer Keep/Unlock. Unlock invalidates any old review and releases the lock without automatically marking the file for removal. Clear Selection continues to clear removal marks; keeper locks are explicit and independently reversible.
4. **Changed groups require rescanning.** Verification failures carry a structured rescan flag. Result reconciliation retains the affected group for inspection but marks it stale, excludes its savings, removes its removal marks, and blocks suggestions, manual marking, and plan construction. Comparison and inspector labels explain the state. Successful/failed/skipped outcomes remain visible as before.
5. **Operation history has bounded reads and retention.** A temporary SQLite index replaces the in-memory dictionary of every historical operation. The UI shows 200-record pages, unresolved first, with accurate total/unresolved counts. Lines over 16 MiB are treated as unreadable evidence without unbounded buffering. Active logs above 8 MiB are compacted when at least 25% can be reclaimed. The atomic replacement preserves every unresolved intent plus the latest 1,000 completed outcomes; three historical full archives are retained. Unreadable records prevent compaction. A stable cross-process file lock serializes appends, reads, and compaction. Archives are never replayed, avoiding resurrection of old intents whose later outcomes are already known.

The earlier 0.4.0 safeguards remain: reviewed plan IDs, filtered selection, safe batches, actual-outcome result reconciliation, progress/cancellation, worker-aware quitting, saved-scan cleanup, and universal optimized packaging with bundled-framework validation.

## Validation and scope

57 automated tests pass, including actual scanner-to-app restriction flow, history mode switching, keeper unlock, changed-keeper rejection, history paging, archive rotation, unresolved-intent preservation, and corrupted-log handling. See TEST_RESULTS.txt and VALIDATION.md.

The read-only generated-media benchmark covers 12,200 valid JPEG/MOV files totaling 18.73 GB. All 220 groups match the full ground-truth membership manifest; no issues were reported. Details and limits: BENCHMARK.md.

External/network/read-only removal remains deliberately unavailable. User files may be identical yet required by different projects. Large result membership still materializes in memory; million-file performance is not claimed. Physical Intel, earlier macOS, real removable-drive disconnection, cloud-provider integration, full accessibility, and localization testing remain outside the completed checks. The operation log supports inspection, not automatic undo. Developer identity signing/notarization are separate.
