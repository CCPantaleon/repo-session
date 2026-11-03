# Validation — Duplicate Finder 0.5.0

Completed 31 October 2026 (Asia/Dubai). Host: Apple Silicon, macOS 27.2 (26B123), Xcode 27.2 / Swift 6.4.2.

## Automated checks

- **57 tests passed:** 43 core tests across 10 suites, plus 14 application-state tests. No failures, disabled tests, or compiler warnings in the final verification run. Full output: TEST_RESULTS.txt.
- Actual 5,001-file debug scan: **13.47 seconds**. Test-process peak RSS: **249,626,624 bytes** (~238 MiB). Other tests run concurrently; this is not isolated release-app memory or a million-file benchmark.
- 100,001 metadata records indexed in SQLite.
- One-file selection with 2,002 duplicate result members; safe repeated 1,000-file batches within a 2,501-member group.
- Cancellation while a fixture move is in flight completes that move and skips all remaining files. Cancelled scanning can immediately start again after worker acknowledgment.
- A genuinely unreadable fixture file, changed/missing files, and a missing scan root are safely rejected/reported. Missing-root coverage does not substitute for physically unplugging a drive.
- Truncated audit records remain detectable, later records remain readable, and unresolved intents are retained even when completed-history display is limited.
- Clearing saved scans deletes owned indexes and sidecars while leaving unrelated files/symlinks/originals intact.
- Project references validate: 37 Swift files, 4 targets, shared scheme.

## Release package

- Xcode Release build succeeds for **arm64 and x86_64**, with optimization enabled.
- Both architectures verified in the executable and embedded framework.
- Framework load path verified as bundled `@rpath`, avoiding dependence on a framework installed on the developer's Mac. This check was added after a launch test exposed the original project's absolute install path.
- Local ad-hoc signature verified with strict/deep checking.
- Bundle version 0.5.0 (6); minimum macOS 14; identifier preserved from the supplied app.
- The only remaining Xcode build warning concerns skipped App Intents metadata extraction because this app has no App Intents integration.

## Native app checks

Prior 0.4.0 release checks, retained as historical evidence (not repeated removal checks for 0.5.0):

1. Launched the final release app and retained the previous build's saved scan configuration.
2. Scanned five sample files; found two exact groups with three and two copies.
3. Filtered to one three-copy group and used visible-results selection; exactly two files were marked, with no selection from the hidden group.
4. Prepared a review, used the app menu's Clear Selection command, and verified the review disappeared and Move to Trash became disabled.
5. Selected only generated `b.txt`, reviewed the two retained paths, and confirmed a native Trash operation. Result: **1 moved, 0 failed, 0 skipped**.
6. Returned to Results and verified the two unselected duplicate copies remained visible, with no marked files.
7. Quit/relaunched the final app and opened Operation History. The completed operation remained visible with original folder and Show in Trash actions.

No personal files were scanned or removed during these checks. The single generated fixture remains recoverable through Finder's Trash. Native settings-based history clearing was not applied to the user's existing history; it is covered by automated app/core tests.

## Additional 0.5.0 checks

- Actual scanner-to-saved-record-to-selection and scanner-to-AppModel paths carry removal restrictions; external-policy copies cannot be marked.
- Reopening a saved scan after external-drive mode uses that saved scan's roots. Restored external configuration preserves its selected paths.
- Keep locks can be unlocked; unlocking does not mark a file and invalidates an existing removal review.
- Changed keeper/candidate results mark the entire affected group as requiring a rescan, remove its savings, and reject manual selection, suggestions, and new removal plans.
- Journal tests cover 2,500 operations, 600 unresolved operations, bounded pages, compaction, archive retention, no resurrection of completed intents, malformed lines, and recovery after a 17 MiB oversized line.
- Launched the packaged 0.5.0 app and scanned the generated media folder. Paused and resumed hashing successfully. Completed results showed 220 groups, 10,200 copies, and 15.56 GB potential logical savings.
- Photos filtering showed 200 groups / 10,000 copies; Videos showed 20 groups / 200 copies. Opened a 50-copy photo comparison with decoded previews, clicked Keep then Unlock, and confirmed the file remained unmarked. No files in the benchmark dataset were moved or deleted.
- Separate optimized scanner benchmark matched every expected group member and byte total: 12,200 valid media files, 18,731,789,642 logical bytes, 53.12 seconds, 239,206,400 bytes peak process RSS (228.13 MiB), zero issues. This memory measurement is for the benchmark process, not the GUI app. See BENCHMARK.md and BENCHMARK_RESULTS.json for reproducible details and cache/APFS limitations.

## Not claimed

Physical Intel runtime validation, earlier macOS runtime validation, real external-drive disconnect testing, live cloud-provider integration, a full VoiceOver audit, localization, million-file scale, and a sustained real photo/video-library benchmark were not performed. External/network/read-only removal is deliberately unavailable and is labelled scan-only. Developer identity signing and notarization remain outside scope.

## Icon packaging update — build 6

Added the generated blue/indigo file-card and magnifier artwork as a bundled ICNS icon, with standard and Retina representations from 16 through 1024 pixels. Visually inspected the artwork at reduced size. Rebuilt both architectures, verified the local signature and ZIP contents, and launched the packaged app. The native About window displayed the custom icon and Version 0.5.0 (6). No scanning/removal logic changed; the previous 57-test and benchmark results remain the behavioral validation, and were not rerun for this icon-only update.
