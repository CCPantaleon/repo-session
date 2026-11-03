> Design baseline from Astra. For the implemented behavior, measured validation and current deviations, see [Implementation Status](Documentation/IMPLEMENTATION_STATUS.md).

# Implementation Plan for Sol

Every milestone ends with a build, focused tests, and an update to the capability/limitation matrix. Never enable a destructive control early to demonstrate progress. Existing skipped tests are acceptance placeholders, not coverage.

## M0 — Verify foundation

Open the shared Xcode scheme, build app/core/tests and run tests under Xcode 16+. Set a developer-owned bundle ID/team only if signing is needed. Run the app and inspect every Navigate destination, folder picker cancel/add/remove, drop, Settings, resizing, light/dark, and unavailable-scan behavior. Confirm no fake production results. Review Documentation/VALIDATION.md for what this environment did and did not verify.

Acceptance: Xcode build/test pass; unchanged safety tests pass; no compiler/concurrency warnings; UI smoke checklist recorded. Depends on full Xcode for scheme validation.

## M1 — Storage, access and lifecycle

Implement SQLite store actor for ScanRepository, CandidateIndex, RemovalJournal with versioned schema, migrations, stable pagination, indexed size/hash joins, batched writes and interrupted-session reconciliation. Add preferences/bookmark storage. Implement PermissionService leases and VolumeDiscoveryService with mount/unmount updates. Define typed runtime errors for denied/missing/changed/disconnected/invalid config/busy/cancelled/store failure. Add lifecycle cancellation and enforce one active operation. Validate configuration in Core independently of UI. Add session/revision keys to the UI’s selection context before results become usable.

Acceptance: fresh/migrated DB tests; pagination has no duplicated/missing rows across stable queries; crash-intent reconciliation never retries mutation; stale bookmark rejection; balanced lease counts even on throw/cancel; disconnected volume reports an issue. No scanner yet. Dependencies: M0.

## M2 — Read-only enumeration and metadata

Implement FileEnumerationService and FileMetadataService on bounded utility workers. Apply exclusion policies before descent; collect lstat/resource identities, high-resolution snapshots, logical/allocated bytes and link counts. Normalize overlapping roots, never follow symlinks/aliases, ignore special files, packages/catalogs, system/service folders and cloud placeholders. Preserve alias information without counting hard links as separate copies. Type classification uses UTType and documented fallback for RAW; avoid reading media bytes for filter classification. Persist issues.

Acceptance: temporary-directory suite with nested exclusions, symlink loop, two hard links, renamed file, same name in separate directories, unreadable entry (skip where test privileges defeat permissions), package without extension, managed catalog, empty file, Unicode names, overlapping roots, placeholder adapter and unmount adapter. Assert original bytes/metadata unchanged. Consume a million synthetic metadata entries with bounded memory and backpressure. Dependencies: M1.

## M3 — Hashing and exact grouping

Implement streaming CryptoKit SHA256; optional fingerprint stage behind internal policy. Open with no-follow semantics, compare descriptor snapshots before/after and against enumeration, and reject changes. Bound workers, file handles and buffers. Query size candidates from SQLite, store full verified hashes, form digest+size groups using distinct identities. Keep SimilarPhotoAnalysis unimplemented and disconnected.

Acceptance: SHA-256 golden vectors (empty, short, multi-chunk), very large sparse fixture without huge allocation, cancellation between chunks, same names/different bytes, different names/equal bytes, RAW/JPEG mismatch, cloned-file fixture where supported, mutation during read, reopen identity replacement, errors/disconnects. Partial fingerprint collision must still require full hashes. RSS does not scale with file size or total candidate count. Dependencies: M2.

## M4 — Coordinator, progress and results integration

Implement ScanCoordinator actor state machine, pause gates, resume, cooperative cancel, task/resource cleanup, throttled counters, durable issues and result invalidations. Connect AppModel to session IDs, summary queries, member pages and terminal states. Replace unbounded `groups` presentation storage with a bounded page of summaries plus selected member pages; existing DuplicateGroup is a validated review/detail transport, not the global database. Add issue browser and safe partial-result states. Restore view/filter preferences.

Acceptance: phase-by-phase cancellation/error tests; pause acknowledgement; progress counts consistent and no dropped records; stale event from previous session ignored; no fake success on empty/disconnected inputs; selected roots/filters restored. UI stays interactive on synthetic million-file fixture. Dependencies: M3.

## M5 — Comparison, previews and selection

Implement bounded PreviewService cache with cancellation, ImageIO/QL thumbnails, AVFoundation properties, icons and Quick Look bridge. Wire Return/Space with responder focus rules. Add file-row native multiselection, grid equivalent and accessible keep/remove controls. SelectionService resolves newest/oldest/preferred/selected-location/all-redundant with deterministic ties, manual keeper locks, cross-page selection and at least one retained copy. Preferred folders must be configured by user; no-match fallback is visible. Build immutable bounded RemovalPlan only for reviewed IDs, excluding protected/changed/multiple-hard-link cases.

Acceptance: tests for every rule, ties, preferred `/Photos` versus `/Photos-old`, all-copy rejection, stale IDs/session, inaccessible keeper, cross-page selection; RAW/video preview cache stress and decode failures. Verify VoiceOver, keyboard-only, dark/light, large text. Selection alone performs no file operations. Dependencies: M4.

## M6 — Safe Trash, durable audit and review

Introduce a narrow injectable filesystem/Trash adapter and actual SafeRemovalService actor. Review preparation and execution both check fresh access; execution rehashes retained and removal files and checks path identity immediately before each Trash call. Persist intent before OS mutation and result after. Surface unsupported/unknown Trash eligibility honestly. Serial execution, cancel remaining, partial failures and uncertain journal outcomes. Never use permanent deletion or arbitrary user-data moves as a fallback. Enable Move to Trash only after explicit review/confirmation wiring and tests are complete.

Acceptance: fake adapter proves no Trash call on keeper/source modification, path replacement, no surviving copy, hard-link ambiguity, denied access, protected path, invalid/stale plan, journal-write failure, unmount or cancellation. Tests cover success then failure, post-move journal failure, crash reconciliation and duplicate confirmation. Real Trash integration is opt-in and uses only generated temporary copies on a verified local volume, with explicit recovery/cleanup instructions; never real user libraries. Tests cannot prove absence of external-process races: document URL-based Trash limitation. Dependencies: M1 and M5.

## M7 — Release hardening

Measure performance on internal SSD and representative removable media, large RAW/video assets, sparse/compressed/clone data and many small files. Tune pool sizes and paging with Instruments. Implement storage-budget warnings, history cleanup, accessibility/localization and polished native empty states. Audit every unfinished marker and disabled acceptance test. Review permissions copy and protected exclusions with real macOS access behavior. Run signed app with least necessary access, hardened runtime, notarization/stapling and clean-machine Gatekeeper verification.

Acceptance: all required tests enabled/pass; supported macOS versions validated; Xcode archive and signed clean install work; no dependency or telemetry surprise; no unconditional permanent deletion in production sources; known limitations documented. Final UI polish cannot weaken keeper/Trash invariants. Dependencies: M6.

## Definition of done for each service

Protocol-backed implementation injected once at composition root; no globals or UI filesystem loops. Tests cover its failure/cancellation behavior, not only happy path. Every change documents whether it changes access, storage or deletion semantics. Run focused tests, then full suite once at integration. Tests in temporary sample directories must clean only their own generated artifacts.
