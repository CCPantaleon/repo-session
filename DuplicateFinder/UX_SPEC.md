> Design baseline from Astra. For the implemented behavior, measured validation and current deviations, see [Implementation Status](Documentation/IMPLEMENTATION_STATUS.md).

# Native macOS UX Specification

## Window and visual language

One primary window, default 1250×800, minimum 980×640 in the skeleton. macOS Settings scene is separate. Results sidebar: 170–280 pt (ideal 200); inspector: 240–500 pt (ideal 320); center expands. Use system typography, semantic primary/secondary colors, native materials, standard 8/12/16/24 pt spacing, separators and restrained SF Symbols. No branded gradient background, giant dashboard counters or custom title-bar imitation. Respect system light/dark and accent color automatically.

Architecture-build notice remains visible in this foundation. Remove only when real services are wired and release gates pass. Empty results must never suggest a successful scan occurred. Disabled unfinished controls explain their unavailability with adjacent copy or help. No demo results enter AppDependencies.architectureBuild(). Any future previews belong to a separate DEBUG-only fixtures folder, with a visible preview banner.

## Screens and transitions

| Screen | Content and actions | Empty/error behavior |
| --- | --- | --- |
| Home | Three equal entry cards: This Mac, Choose Folders, External Drives. Home/Photos/Videos/All presets, saved locations, permission explanation. Drop folders to setup. | Missing saved locations shows helpful text. Folder-picker cancel preserves existing state. |
| Scan Setup | Selected scope/roots with remove buttons, add/exclude folder pickers, categories, extensions, minimum bytes, permission statuses. | Reject negative sizes, empty category/extension intersection and no roots. External unavailable differs from zero connected drives. |
| Scan Progress | Phase, location, counters, logical byte estimate, elapsed time, issues link, Pause/Resume/Cancel. | Unavailable scanner shows explicit failure message. Paused waits for acknowledgement; cancelled/failed remain separate. |
| Results | Category sidebar; central toolbar with sort/view/search; paged list/grid; optional inspector; bottom selection/review controls. | Not scanned, successful zero duplicates, filtered zero matches, partial results, stale history, and unavailable are distinct states. |
| Comparison | Two members, large previews, path/metadata, fit/actual zoom and Quick Look. | Missing preview falls back to native icon; decoding failure cannot invalidate exact content verification. |
| Removal Review | Retained vs removal paths, counts, estimate, warnings and single confirm button. | No selection, invalid keeper, changed file, unsupported volume, denied permission block confirmation and identify paths. |
| Completion | Moved/failed/skipped counts with row outcomes and resulting Trash locations when supplied. | Partial success is never “all done.” Retry starts a fresh review. |
| History | Session time, roots, filters, completion/partial status, cached metrics. | All historical data is marked stale pending verification. Never restore old removal selection. |
| Settings | Scan defaults, exclusions, preferred folder, viewing preferences, local data retention, privacy guidance. | Persistence not yet implemented is visible in skeleton. |

Home → Setup → Progress → Results → optional Comparison → Results → Review → Completion → Results. New Scan returns Home without discarding an active scan silently. Navigating away from Progress does not cancel. One scan/removal operation at a time; active state remains accessible from toolbar/menus. Closing the window while busy requires a native cancel-and-close decision in the real implementation. Current skeleton Navigate menu exposes every structural screen for review.

## Results details

Use native List/Table selection for keyboard and command/shift range selection. Distinguish row focus, selected file for inspector, and removal checkbox; selection highlighting alone never means removal. List rows group members without loading all members for all groups. Grid uses LazyVGrid and bounded thumbnails, with native-equivalent range and command selection implemented at M5. File name and folder path remain visible; abbreviate middle of long paths while inspector exposes full selectable text. Native context menus: Open, Reveal, Quick Look, Keep, Mark/Unmark.

Keep/remove state must be textual and accessible, not only green/red. A retained copy is labeled “Keep.” Marking its final available copy is prevented with an inline explanation. Smart commands show resulting selections and preserved copies immediately, with reversible selection changes and a brief “N copies marked” announcement. Never invoke Review automatically after every checkbox.

All sorts are stable and persisted. Search is debounced and runs in the store, with category and folder filters applied consistently across pages. Largest Duplicates sets redundant-byte descending order. Result counts reflect the total matching query, not merely the loaded page. Paginate within large duplicate groups; a group summary alone does not authorize removal.

## Preview and comparison

Inspector thumbnail target uses physical pixel dimensions based on backing scale, capped by cache policy. QLThumbnailGenerator supplies previews; NSWorkspace supplies native icon fallback. AVFoundation metadata is asynchronous. ImageIO extracts dimensions and EXIF without full RAW decode. Quick Look panel integration uses a retained AppKit data-source/coordinator with correct responder ownership. Space toggles Quick Look only when file rows are focused; text fields keep typing behavior. Fullscreen uses native presentation, Escape closes. Zoom preserves relative focus and never feeds detection.

## Keyboard and accessibility

| Interaction | Binding / behavior |
| --- | --- |
| New scan | Command-N |
| Add folders | Command-O |
| Preferences | Standard Command-, via Settings scene |
| Review selection | Command-Shift-R |
| Toggle inspector | Command-Option-I |
| Multiselect | Command-click / Shift-click and standard keyboard extension |
| Quick Look | Space with file-list focus (pending) |
| Open selected file | Return with file-row focus (pending) |
| Move between groups | Arrow keys; disclosure preserves focus (pending integration) |
| Cancel preview | Escape |

Provide labels for every icon/checkbox, meaningful group headings, full filenames/paths as accessibility values, and state announcements for progress phase/selection changes without announcing every hash chunk. Retain standard tab order and visible focus. Screen reader must distinguish current row, marked-for-removal status and keeper status. Dynamic system font sizing, larger accessibility text, high contrast, reduced motion, light/dark and keyboard-only use are QA gates. Do not use custom animation where native transitions suffice.

## Implemented versus specified

Working skeleton interactions: primary navigation, Settings scene, native multi-folder picker, add/remove folders, drop URLs to Home/Setup, category/extension/size configuration, sort/view state, inspector toggle, empty/error layouts, command menu shortcuts. Start Scan intentionally reports scanner unavailable.

Structurally present but pending: real counts/results/filter queries, volume discovery, saved locations/history, group member multiselection, checkbox selection, Quick Look/Return handling, previews/zoom/fullscreen, keeper rules, review preparation, Trash confirmation/execution, completion population, issue browser, persistent preferences, lifecycle prompts. A list selection binding is present; populated-data keyboard/range behavior has not been verified. Never describe these as shipped behavior merely because the controls exist.
