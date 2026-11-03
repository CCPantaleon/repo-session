> Design baseline from Astra. For the implemented behavior, measured validation and current deviations, see [Implementation Status](Documentation/IMPLEMENTATION_STATUS.md).

# Sol Handoff

## Start here

Read README, PRODUCT_SPEC, ARCHITECTURE, UX_SPEC, IMPLEMENTATION_PLAN and Documentation/VALIDATION. Open DuplicateFinder.xcodeproj and use the shared DuplicateFinder scheme. Start at M0/M1; do not redesign the app into a web wrapper or add a dependency framework. This handoff does not authorize automatic cleanup of the user's files.

## What exists

- Real native Xcode app, Core framework and Swift Testing unit-test target, shared scheme and build configuration.
- Equivalent dependency-free Swift package for compiling the same Core and SwiftUI app with command-line tools.
- Swift 6 Sendable domain models, immutable validated duplicate groups/removal plans and service/persistence contracts.
- MainActor AppModel with dependency injection, navigation, native multiple-folder selection, drops, configuration state, app commands and Settings scene.
- Home, Setup, Progress, three-part Results, group rows, Inspector, Comparison, Review/Completion, History and Settings structural views.
- Explicitly unavailable scanner, selection, volumes and safe-removal services. No real scanning, hashes, Trash operation or generated production results.
- Meaningful structural safety/boundary tests plus named disabled acceptance scaffolding. The test runner's total includes skips: inspect the validation report.

## Implementation map

| Area | Files / contract | Next action |
| --- | --- | --- |
| Composition | Application/AppModel.swift, AppDependencies | Add real factory only as services become tested; keep unavailable seams for unfinished areas. |
| Domain | Core/Domain | Preserve constructor validation; add session/revision scoping before state integration. Decode persisted groups through validated construction, not synthesized Decodable. |
| Access / roots | PermissionService, VolumeDiscoveryService | Implement leases, bookmark persistence and external mount events. No inference of global FDA. |
| Enumeration | FileEnumerationService / FileMetadataService | Bounded pull stream; policy exclusions; physical identity; no hydration/symlinks. |
| Hash / grouping | FileHashingService, DuplicateDetectionService, CandidateIndex | Stream full SHA-256; indexed size/hash stages; before/after snapshots. |
| Scan lifecycle | ScanCoordinator | Actor state machine, pause/cancel/backpressure; wire resultsChanged TODO in AppModel. |
| Persistence | Repositories.swift | SQLite store and journal; small versioned prefs/bookmarks; no hidden in-memory success fallback. |
| Result UI | ResultsBrowserView, DuplicateGroupDetail | Wire summary/member paging, section/query semantics, native file selection and persistent view state. |
| Preview | PreviewService, PreviewInspector, ComparisonView | Bounded native thumbnails, metadata, Quick Look, zoom, fullscreen, Return/Space. |
| Selection | SelectionService | Suggestions, manual keeper state, deterministic tie rules, cross-page IDs, validated review plans. |
| Removal | SafeRemovalService / RemovalJournal / RemovalReviewView | Prepare review, explicit confirmation, fresh full verification of keeper AND candidates, serial OS Trash calls, durable outcomes. |
| History/settings | RootView history placeholder / SettingsView | Real history list/details and preferences binding. |

## Unfinished-function registry

Every unimplemented public operation either exists only as a protocol, throws FeatureUnavailable, or is a disabled UI control. Unavailable cancellation methods have no task to cancel and are deliberately harmless. No placeholder returns synthetic success.

Protocol-only: enumeration, metadata, hashing, detection, permissions, previews, scan/prefs repositories, journal, candidate index, and future SimilarPhotoAnalysis. Placeholder implementations: all operations in UnavailableServices.swift. AppModel's resultsChanged branch is a marked M4 TODO. All empty button closures in UI are disabled: preferred/selected-location selection, Quick Look, Keep/Mark, fullscreen, Move to Trash. Zoom is disabled. No action may be enabled until a real handler exists.

State-only controls: search/sort/category sidebar/grid toggle currently have no live data source; external volume selection has no discovery; filters have no scanner; folders are session-only without saved bookmarks. Comparison and completion layouts accept eventual state but do not produce it. Root navigation/Settings work. Tests in ImplementationScaffoldingTests are intentionally disabled and must gain assertions before enabling.

## Non-negotiable constraints

1. Never treat a fingerprint, filename or photo similarity as exact verification.
2. Never count hard-link aliases as independent storage copies; do not promise exclusive bytes for APFS clones.
3. No scanner writes originals or downloads cloud placeholders.
4. No package/catalog traversal, symlink following, root elevation or access bypass.
5. No removal without explicit review; preserve a freshly verified accessible independent keeper in every group.
6. Revalidate immediately; reject changed identities/content. Cached hashes alone are insufficient.
7. Only FileManager Trash. No production removeItem/unlink/rm or fallback permanent deletion. Test-only cleanup may remove generated fixtures.
8. Journal before mutation; fail closed if intent cannot be persisted. Uncertain outcomes require reconciliation, never blind retry.
9. URL-based Trash cannot eliminate all races with external processes. Do not overstate safety or recovery.
10. Keep unfinished services visibly unavailable. Production contains no fake results.

## First concrete implementation session

Validate the Xcode project/scheme, then implement SQLite schema/migration and permission lease fixtures. Add configuration validation and session-scoped selection revision. Build a temporary-directory fixture helper reusable by M2–M6. Implement enumeration only after that boundary is tested. Keep a per-milestone capability table in README. Do not enable Move to Trash until M6 acceptance passes.

## Known architectural extension points

The skeletal AppModel uses arrays only because no results are loaded yet. Replace its visible page with DuplicateGroupSummary and paged FilePage before integrating real scans. CandidateIndex groups in SQL; individual groups can be huge. Review should materialize at most 1,000 selected files plus keepers and require explicit subsequent batches. Add a bounded group-review loader without replacing Core contracts. A manually locked keeper and selection revision belong in persisted session selection state at M5; current SelectionState is only a minimal set of removal IDs.

Service implementation errors need richer typed cases than FeatureUnavailable. Add them next to contracts; FeatureUnavailable remains only for missing capabilities. Add metadata precision and filesystem adapter details as implementation types without exposing raw descriptors to the UI. Do not move blocking disk I/O onto MainActor or spawn a task per file.
