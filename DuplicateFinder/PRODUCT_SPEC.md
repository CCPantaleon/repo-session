> Design baseline from Astra. For the implemented behavior, measured validation and current deviations, see [Implementation Status](Documentation/IMPLEMENTATION_STATUS.md).

# Duplicate Finder — Product Specification

Status: architecture and buildable foundation, not a working duplicate scanner. Version 1 is a local, native macOS application for exact binary duplicates. Target: macOS 14+, Swift 6, Apple frameworks only. The project is ready for Sol to implement the services; disabled controls and unavailable messages are intentional.

## Product promise

Help people identify identical file contents, compare locations and metadata, retain a trustworthy copy, and explicitly move redundant copies to Trash. Photographers with large RAW/video collections are a priority, without introducing a photography-only workflow. No advertisements, subscriptions, accounts, cloud processing, network dependency, automatic cleanup, or permanent deletion.

Success means understandable results and safe decisions before maximum throughput. Logical redundant bytes are useful estimates; actual free-space changes are never guaranteed. User trust requires that unavailable access, skipped files, interrupted scans, and unsupported Trash behavior remain visible.

## Scan entry points

| Entry | V1 meaning |
| --- | --- |
| Scan This Mac | Accessible user locations: standard personal folders in the current home, plus explicitly added locations. Never implies every file on every volume. Confirm included roots before starting. |
| Choose Folders | Native multiple-directory picker; add/remove roots, drag folders into Home or Scan Setup. Deduplicate nested roots by identity to avoid duplicate work. |
| Scan External Drives | Discover mounted non-internal storage, display name/path/read-write state, and select drives. Do not silently include network mounts; offer an explicit supported-location decision. |
| Scan Home Folder | Current home with safety exclusions. This includes files outside the standard personal-folder preset when accessible. |
| Photos / Videos Only | Set category filter and open Home Folder setup. Use UniformTypeIdentifiers and extension fallback for RAW formats. Content hashes still decide duplication. |
| All File Types | All regular local files, including unknown types as Other; “supported” does not promise preview support. |

Configuration includes category filters, optional normalized extension allow-list, minimum logical size, exclusions, saved roots, and preferred keeper folder. Category and extension filters intersect. Minimum is inclusive; default 1 byte avoids meaningless empty-file savings. Zero-byte scanning may be enabled explicitly later, with zero savings. Exclusions override inclusions and remain policy-enforced after canonicalization. No user toggle in V1 enables protected packages, symlink traversal, privileged access, or placeholder downloads.

Permissions are per-location and may change mid-scan. Distinguish granted/readable, user selection required, denied, and unavailable. Full Disk Access guidance is explanatory; do not assert its global state from a successful probe. A failed access is an issue, not “no duplicates.” Saved bookmarks are references to consent, not permanent guarantees.

## Scan lifecycle

Ready → enumerate → size grouping → optional partial fingerprints → full hashes → groups → completed. Pause is an orthogonal state and requires worker acknowledgement. Cancel stops work, drains resources, records an interrupted session, and never triggers removal. Failure carries the actionable cause. A cancelled scan may expose already verified groups as partial results, explicitly labeled; it must not appear completed.

Progress shows current root/file, discovered/analyzed/candidate counts, verified redundant logical bytes, skipped/inaccessible count, elapsed active and wall-clock time, phase and phase-local percentage only when its denominator is known. Enumeration and changing workloads are indeterminate. Avoid synthetic overall percentages. Throttle updates while preserving terminal events and all persisted issues.

## Exact duplicates and results

Only distinct physical file identities with equal size and full SHA-256 content digests qualify. Fingerprints, names, extension, dates, camera metadata, and perceptual similarity never prove duplication. RAW+JPEG and edited versions remain separate unless bytes match. Hard links represent one underlying file regardless of path count. APFS clones have distinct identities and can be exact duplicates but may share allocated blocks.

The results window uses a category sidebar, paged center browser, and optional resizable inspector. Sidebar: All Duplicates, Photos, Videos, Documents, Audio, Other Files, Largest Duplicates, Recent Scans. A group can span categories; category filtering matches members and still shows the entire group context for keeper decisions. Largest Duplicates means the All query sorted by redundant logical bytes.

List and grid rows show representative thumbnail, name, size, copy count, redundant bytes, locations, and per-file keep/remove state. Sort by wasted space, file size, filename, creation date, modification date, type, location, or copies; stable identity breaks ties. Missing dates sort last. Search matches name/path; location filters use path components, not substring prefixes. History is an untrusted snapshot until freshly verified.

Inspector: large bounded preview, filename/extension, logical size, full selectable path, creation/modification dates, image dimensions, EXIF camera/lens when available, full digest/status, Open, Reveal in Finder, Keep, Mark for Removal. Missing metadata says Unavailable. Opening files launches their associated native application; it does not change scan verification.

Comparison shows two selected group members side by side with independent/linked zoom, fit/actual size, fullscreen, Quick Look, and metadata differences. Other files use native thumbnails/icons and properties. Full-resolution decoding is on-demand and memory-bounded; Quick Look and RAW preview behavior must be tested on real assets.

## Selection and removal

Each checkbox explicitly marks removal. No suggestion executes deletion. Commands: Keep Newest, Keep Oldest, Keep Preferred Folder, Keep Selected Location, Select All Redundant Copies, Clear, Review. “Newest” uses modification date, not creation date. Stable ties use normalized full path then identity. Preferred-folder rules use descendant boundaries and prioritize user selection; if no candidate matches, retain a deterministic copy and disclose the fallback. A manually locked keeper stays protected until the user changes it. Reversing an unavailable keeper is not automatic: require review.

At least one verified independent copy must remain per group. Marking the last retained copy is rejected with an inline explanation. Cross-group or stale selections are invalid. Changed or inaccessible files cannot remain trusted keepers. Selections are bound to session and verification revision, not reused on a new scan.

Review shows selected file count, affected groups, estimated logical bytes, all retained and removal paths, warnings, access status, and Trash eligibility. Large selections use paged rows and bounded execution batches, with each batch explicitly reviewed. The only destructive command is **Move to Trash** after explicit confirmation. Disable it until preparation has succeeded. Require fresh review whenever source state changes.

Every operation is journaled. Completion distinguishes moved, failed, skipped, and cancelled remainder, with per-path explanations. Show resulting Trash location only if the OS supplies it. Do not advertise undo/restore support in V1. Unsupported volumes fail or skip; never emulate Trash by permanent deletion or a private arbitrary folder. Recovery is not guaranteed, especially on external/network volumes. Retry always creates a new validated plan.

## Safety exclusions

Exclude /System, /bin, /sbin, /usr, /private, /dev, /Library, /Applications, hidden metadata/service directories, current user's Library, .Trash/.Trashes, and app-owned support/cache/journal directories by default. Resolve physical identities and volume-relative equivalents; path prefixes alone are insufficient. Treat application bundles and packages as protected units and skip their contents. Detect Photos libraries, Lightroom catalogs and their companion data, backup bundles, and managed repositories even when package flags are missing. No managed-library safe mode ships in V1.

Do not follow directory or file symlinks, Finder aliases, mount boundaries not selected explicitly, sockets, devices, FIFOs, or special files. Do not trigger iCloud/File Provider hydration merely to hash. Report skipped placeholders and unavailable providers. Enumerating content is read-only; scanner never writes xattrs or changes originals.

## Performance and quality gates

Use streaming hashes, bounded worker pools, disk-backed indexes, summary pages and virtualized rows. Initial goals to measure on documented hardware: UI input p95 under 100 ms during a scan; cancellation acknowledgement under 1 second between bounded reads (blocked OS I/O may delay it); RSS target under 300 MB for a one-million-file metadata fixture excluding preview spikes. These are engineering targets, not benchmark claims. Limit previews by decoded pixel cost. Explain low disk space for index storage before a scan; stop cleanly on database errors.

No launch until service acceptance tests, accessibility, privacy boundaries, disconnect behavior, crash recovery, and representative RAW/video libraries pass. Similar Photos is a future isolated analysis type; it must not generate V1 exact groups or removal eligibility.
