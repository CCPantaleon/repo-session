> Design baseline from Astra. For the implemented behavior, measured validation and current deviations, see [Implementation Status](Documentation/IMPLEMENTATION_STATUS.md).

# Project Structure

The repository root is this directory. `DuplicateFinder.xcodeproj` is a real shared-scheme Xcode project; `Package.swift` builds the same sources without generating a project.

```text
DuplicateFinder/
├── DuplicateFinder.xcodeproj/
│   ├── project.pbxproj
│   └── xcshareddata/xcschemes/DuplicateFinder.xcscheme
├── Package.swift
├── Configuration/
│   ├── Base.xcconfig
│   └── DuplicateFinder.entitlements
├── Sources/
│   ├── DuplicateFinderCore/
│   │   ├── Domain/
│   │   │   ├── Files.swift
│   │   │   ├── Scan.swift
│   │   │   └── Removal.swift
│   │   ├── Services/
│   │   │   ├── Contracts.swift
│   │   │   └── UnavailableServices.swift
│   │   └── Persistence/Repositories.swift
│   └── DuplicateFinderApp/
│       ├── Application/
│       │   ├── DuplicateFinderApp.swift
│       │   └── AppModel.swift
│       └── Presentation/
│           ├── SharedViews.swift
│           ├── HomeView.swift
│           ├── ScanViews.swift
│           ├── ResultsBrowserView.swift
│           ├── PreviewInspector.swift
│           ├── ComparisonView.swift
│           ├── RemovalReviewView.swift
│           └── SettingsView.swift
├── Tests/DuplicateFinderCoreTests/
│   ├── DomainTests.swift
│   ├── BoundaryTests.swift
│   └── ImplementationScaffoldingTests.swift
├── Scripts/
│   ├── verify.sh
│   └── validate_project.py
├── Documentation/
│   ├── TEST_MATRIX.md
│   └── VALIDATION.md
├── PRODUCT_SPEC.md
├── ARCHITECTURE.md
├── UX_SPEC.md
├── PROJECT_STRUCTURE.md
├── IMPLEMENTATION_PLAN.md
├── SOL_HANDOFF.md
└── README.md
```

## Responsibilities and targets

| Layer | Responsibility | Xcode / SwiftPM target |
| --- | --- | --- |
| Application | Entry, windows, commands, Settings, composition, MainActor presentation state | DuplicateFinder / DuplicateFinderApp |
| Presentation | Structural screens and AppKit UI adapters; never filesystem algorithms | DuplicateFinder / DuplicateFinderApp |
| Domain | Sendable file/session/selection/removal values and constructor invariants | DuplicateFinderCore / DuplicateFinderCore |
| Services | Asynchronous protocol contracts and honest unavailable boundaries | DuplicateFinderCore / DuplicateFinderCore |
| Persistence | Repository, candidate index and audit contracts | DuplicateFinderCore / DuplicateFinderCore |
| Tests | Core invariant/boundary tests, explicitly disabled acceptance scaffolding | DuplicateFinderCoreTests / DuplicateFinderCoreTests |
| Configuration | macOS 14, Swift 6 strict concurrency, hardened runtime, direct distribution | Shared xcconfig + empty entitlements |

Add concrete services alongside contracts; use a few files by responsibility, not a framework per protocol. AppKit preview implementation belongs to App; Foundation/CryptoKit/SQLite disk work belongs to Core. Keep preview/demo fixtures isolated from production sources. The current test fixtures exist only in Tests. Build artifacts go under ignored `.build/` or explicit derived-data paths.
