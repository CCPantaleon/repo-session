# Test coverage — 0.5.0

- Core/domain: identity, exact digest validation, keeper invariants, exclusions, links, changed files, large-file hashing, saved SQLite results.
- Selection: visible-vs-whole-scan scope, locked keepers, review invalidation, delayed async responses, confirmation plan IDs.
- Scale/batches: one selected file among 2,002 result members, a 2,501-member group, 1,000-file batches, 100,001 metadata records, actual 5,001-file scan.
- Outcomes: partial success, failure, skipped files, remaining duplicate copies, pending selections.
- Cancellation: cancel during an in-flight move; remaining files untouched; coordinator can immediately restart after cancellation acknowledgment.
- Storage/permissions: unreadable file, missing root/candidate, changed keeper/candidate, failed journal, durable intent/results, truncated journal line, unresolved intent visibility, owned-index cleanup and symlink safety.
- App UI: repeat the two original selection reproductions; review confirmation; generated-file native Trash; operation history; clear saved scans.
- Other machines: physical Intel, older supported macOS versions, real external disconnects and cloud-provider workflows remain manual checks.

## Added in 0.5.0

- Scanner policy propagation through real saved records and AppModel selection.
- Saved-history rescan roots after external mode; restored external-volume selections.
- Keeper unlock without automatic selection and with review invalidation.
- Changed-file group invalidation across reconciliation, suggestions, manual selection, savings, and removal planning.
- Journal paging, unresolved-intent priority, bounded memory indexing, compaction, archive limits, completed-intent non-resurrection, corrupt and oversized-line recovery.
- Generated JPEG/H.264 release benchmark: 12,200 files / 18.73 GB, exact membership and logical-byte assertions, 220 duplicate groups, 2,000 unique files.
- Packaged 0.5.0 native UI: large-media scan, pause/resume, photo/video filters, 50-copy comparison previews, Keep/Unlock without marking.

Final automated result: 57 tests passed (43 core, 14 application-state). Full results are in TEST_RESULTS.txt; benchmark details in BENCHMARK.md.
