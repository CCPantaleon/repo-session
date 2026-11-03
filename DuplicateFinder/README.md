# Duplicate Finder 0.5.0

A native exact-duplicate finder for macOS 14 or later. The release package includes both Apple Silicon and Intel code. Processing stays on the Mac; no accounts, telemetry, or network service.

## Use

Open **Duplicate Finder.app**, choose folders, and scan. Select a group to compare copies. Mark unwanted copies, review the exact paths, and confirm Move to Trash. At least one copy must remain in every group.

- Selection commands in Results apply to the visible category and search results. A separately labelled command selects across the entire scan. Existing selections outside the filter are counted explicitly.
- Keep locks a copy; Unlock releases that lock without automatically selecting it. Clearing selection or changing a keeper cancels the old review. The final confirmation is tied to the specific reviewed plan.
- Reviews contain up to 1,000 removal files per batch. Larger selections remain available for subsequent reviews. The old 2,000-result-member restriction is removed.
- Failed, skipped, and unselected duplicate copies remain visible. Groups rejected during verification are labelled Rescan required, excluded from savings and suggestions, and cannot be marked until a fresh scan.
- External, network, and read-only volumes are **scan-only**. Copies on those volumes cannot be marked. Internal-drive eligibility is checked again immediately before a native Trash call.
- Removal shows file progress and a Cancel Remaining Files button. A move already underway may finish; subsequent moves stop. Quit waits for active work to stop.
- Navigate → Operation History shows bounded pages, with unresolved intents first and their total count. Logs over 8 MiB are compacted when at least 25% can be reclaimed: every unresolved intent and the latest 1,000 completed outcomes stay in the active log; the latest three full archives are retained. Unreadable evidence prevents compaction. Interrupted operations are never retried automatically. Check Finder's Trash and the original folder, then rescan.
- Recent Scans retains up to 50 scans for 30 days. Settings → Clear Saved Scans and Their Databases removes the saved indexes, including their paths/hashes, without touching originals. The removal audit is retained separately for recovery.

Moving a file to Trash does not free its disk space until Trash is emptied. The app never empties Trash or falls back to permanent deletion. Restore through Finder's Trash.

## Build and verify

Xcode must have its license accepted and first-launch setup complete.

```sh
zsh Scripts/verify.sh
zsh Scripts/build_app.sh
```

The first command validates the project and runs the core and application-state tests. The second runs those checks, builds an optimized universal Release app, verifies both architectures and its local ad-hoc signature, and creates `../Release-0.5.0/DuplicateFinder-0.5.0.zip`. `--skip-tests` is available for packaging after a separately completed verification run.

The bundle identifier is preserved from the supplied development app so existing preferences/history continue to work. The generated Xcode project includes core and application-state test targets. Run `python3 Scripts/generate_project.py` after adding Swift files.

## Boundaries

- Exact data-content matching only; similar-photo detection is not included.
- Packages, managed libraries, hidden/system locations, symbolic links, hard-link aliases, and cloud placeholders are excluded or protected. Files can be identical and still be needed by different projects; review their locations.
- Results still materialize duplicate-group membership in memory. No million-file performance claim is made.
- Native URL-based Trash cannot eliminate every race with another process modifying files. Use stable folders, and avoid working inside active managed libraries.
- The release is locally ad-hoc signed. Developer identity signing/notarization are outside this update.
- A universal build is not a substitute for physical Intel testing or testing every supported macOS version. See Documentation/VALIDATION.md for what was actually run and what remains to check.

Original product/architecture documents are historical design references. Documentation/IMPLEMENTATION_STATUS.md describes this release.
