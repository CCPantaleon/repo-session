import AppKit
import SwiftUI
import DuplicateFinderCore

enum Screen: String, CaseIterable, Identifiable {
    case home = "Home", configuration = "Scan Setup", progress = "Scan Progress"
    case results = "Results", comparison = "Compare", review = "Removal Review", history = "Recent Scans", operations = "Operation History"
    var id: Self { self }
}
enum ResultSection: String, CaseIterable, Identifiable {
    case all = "All Duplicates", photos = "Photos", videos = "Videos", documents = "Documents"
    case audio = "Audio", other = "Other Files", largest = "Largest Duplicates", recent = "Recent Scans"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .all: "square.on.square"; case .photos: "photo"; case .videos: "film"
        case .documents: "doc"; case .audio: "music.note"; case .other: "folder"
        case .largest: "externaldrive"; case .recent: "clock"
        }
    }
}

struct AppDependencies {
    let scanner: any ScanCoordinator
    let volumes: any VolumeDiscoveryService
    let selection: any SelectionService
    let removal: any SafeRemovalService
    static func live(scanDirectory: URL, journalURL: URL) -> Self {
        Self(scanner: LocalScanCoordinator(storageDirectory: scanDirectory), volumes: LocalVolumes(),
             selection: LocalSelection(), removal: LocalSafeRemoval(journalURL: journalURL))
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var screen: Screen = .home
    @Published var configuration = ScanConfiguration()
    @Published var folders: [URL] = []
    @Published var externalVolumes: [StorageVolume] = []
    var volumeIDs: Set<String> {
        get { if case .externalVolumes(let urls) = configuration.scope { return Set(urls.map(\.path)) }; return [] }
        set { configuration.scope = .externalVolumes(externalVolumes.filter { newValue.contains($0.id) }.map(\.url)) }
    }
    @Published var volumeMessage: String?
    var isExternalScope: Bool { if case .externalVolumes = configuration.scope { return true }; return false }
    @Published var progress = ScanProgress(phase: .ready)
    @Published var scanActive = false
    @Published var isPaused = false
    @Published var message: String?
    @Published var scanMessage: String?
    @Published var section: ResultSection = .all
    @Published var groups: [DuplicateGroup] = []
    @Published var issues: [ScanIssue] = []
    @Published var removalBusy = false
    @Published var history: [SavedScan] = []
    @Published var savedPaths: [String] = []
    @Published var showingSavedResults = false
    @Published var preferredFolder: URL?
    struct SavedScan: Codable, Identifiable { var id: UUID; var date: Date; var roots: [URL]; var groupCount: Int; var databaseURL: URL? = nil }
    @Published var selectedGroupIDs: Set<UUID> = []
    @Published var selectedFileID: UUID?
    @Published private(set) var selection = SelectionState()
    @Published var removalPlan: RemovalPlan?
    @Published var removalResult: RemovalResult?
    @Published var showInspector = false
    @Published var useGrid = false
    @Published var query = ResultQuery()
    private let dependencies: AppDependencies
    @Published var removalProgress: RemovalProgress?
    @Published var cancellationRequested = false
    @Published var maintenanceBusy = false
    @Published var historyLoading = false
    @Published var auditLoading = false
    @Published var auditEntries: [RemovalAuditEntry] = []
    @Published var auditWarning: String?
    @Published private(set) var auditOffset = 0
    @Published private(set) var auditTotalCount = 0
    @Published private(set) var auditUnresolvedCount = 0
    private var selectionRevision = UUID()
    private var reviewRevision: UUID?
    private var dataRevision = UUID()
    private var currentRemovalID: UUID?
    private let defaults: UserDefaults
    let scanDirectory: URL
    let journalURL: URL
    private var scanTask: Task<Void, Never>?
    init(dependencies: AppDependencies? = nil, defaults: UserDefaults = .standard,
         scanDirectory: URL = ScanArchiveStore.defaultDirectory, journalURL: URL = LocalRemovalJournal.defaultURL,
         performMaintenance: Bool = true) {
        self.defaults = defaults; self.scanDirectory = scanDirectory; self.journalURL = journalURL
        self.dependencies = dependencies ?? .live(scanDirectory: scanDirectory, journalURL: journalURL)
        if let data = defaults.data(forKey:"scanConfiguration"), let config = try? JSONDecoder().decode(ScanConfiguration.self,from:data) { configuration = config; if case .folders(let urls) = config.scope { folders = urls } }
        showInspector = defaults.object(forKey:"inspector") as? Bool ?? false
        useGrid = defaults.bool(forKey:"grid")
        savedPaths = defaults.stringArray(forKey:"locations") ?? []
        if let data = defaults.data(forKey:"history") { history = (try? JSONDecoder().decode([SavedScan].self,from:data)) ?? [] }
        if let value = defaults.string(forKey:"preferredFolder") { preferredFolder = URL(fileURLWithPath:value) }
        if performMaintenance { pruneScanHistory(); refreshAudit() }
    }
    var visibleGroups: [DuplicateGroup] {
        let category: FileCategory? = [.photos:FileCategory.photos,.videos:.videos,.documents:.documents,.audio:.audio,.other:.other][section]
        let matches = groups.filter { group in
            (category == nil || group.files.contains { $0.category == category }) &&
            (query.search.isEmpty || group.files.contains { $0.url.path.localizedCaseInsensitiveContains(query.search) })
        }
        return matches.sorted { a,b in
            let x = a.files[0], y = b.files[0]
            if section == .largest { return a.redundantLogicalBytes > b.redundantLogicalBytes }
            switch query.sort {
            case .wastedSpace: return a.redundantLogicalBytes > b.redundantLogicalBytes
            case .fileSize: return x.snapshot.logicalBytes > y.snapshot.logicalBytes
            case .copies: return a.files.count > b.files.count
            case .created: return (x.createdAt ?? .distantPast) > (y.createdAt ?? .distantPast)
            case .modified: return x.snapshot.modifiedAt > y.snapshot.modifiedAt
            case .type: return x.url.pathExtension < y.url.pathExtension
            case .location: return x.url.path < y.url.path
            case .name: return x.url.lastPathComponent.localizedStandardCompare(y.url.lastPathComponent) == .orderedAscending
            }
        }
    }
    func compare(_ group: DuplicateGroup) { selectedGroupIDs = [group.id]; selectedFileID = group.files.first?.id; screen = .comparison }
    var workActive: Bool { scanActive || removalBusy || maintenanceBusy || historyLoading }
    var hiddenSelectionCount: Int {
        let visible = Set(visibleGroups.flatMap(\.files).map(\.id))
        return selection.removalIDs.subtracting(visible).count
    }
    var canConfirmRemoval: Bool {
        guard let plan = removalPlan else { return false }
        return !workActive && reviewRevision == selectionRevision && plan.removalIDs.isSubset(of: selection.removalIDs)
    }
    var unresolvedOperationCount: Int { auditUnresolvedCount }
    private func invalidateReview() {
        selectionRevision = UUID(); reviewRevision = nil; removalPlan = nil
    }
    func clearSelection() {
        guard !removalBusy else { return }
        invalidateReview(); selection.removalIDs.removeAll()
    }
    func mark(_ file: FileRecord, removal: Bool) {
        guard !workActive, !showingSavedResults else { message = "Wait for active work or rescan saved results before marking copies."; return }
        guard let group = groups.first(where: { $0.files.contains { $0.id == file.id } }) else { return }
        if removal {
            guard !group.requiresRescan else { message = "This group changed or became unavailable. Rescan before selecting copies."; return }
            if let restriction = file.removalRestriction { message = restriction; return }
            guard file.snapshot.linkCount == 1, !selection.keeperIDs.contains(file.id), group.files.contains(where:{ $0.id != file.id && !selection.removalIDs.contains($0.id) }) else {
                message = "Keep at least one copy. Hard-linked files and locked keepers cannot be marked."; return
            }
        }
        invalidateReview()
        if removal { selection.removalIDs.insert(file.id) } else { selection.removalIDs.remove(file.id) }
    }
    func keep(_ file: FileRecord) {
        guard !workActive, !showingSavedResults else { return }
        invalidateReview(); selection.removalIDs.remove(file.id); selection.keeperIDs.insert(file.id)
    }
    func unlockKeeper(_ file: FileRecord) {
        guard !workActive, !showingSavedResults else { return }
        invalidateReview(); selection.keeperIDs.remove(file.id)
    }
    func needsRescan(_ file: FileRecord) -> Bool {
        groups.contains { $0.requiresRescan && $0.files.contains { $0.id == file.id } }
    }
    var hasStaleResults: Bool { groups.contains { $0.requiresRescan } }
    func choosePreferredFolder() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        if panel.runModal() == .OK { preferredFolder = panel.url; defaults.set(panel.url?.path,forKey:"preferredFolder") }
    }
    func confirmRemoval(expectedPlanID: UUID? = nil) {
        guard canConfirmRemoval, let plan = removalPlan, expectedPlanID == nil || expectedPlanID == plan.id else { return }
        removalBusy = true; cancellationRequested = false; currentRemovalID = plan.id
        removalProgress = RemovalProgress(completed: 0, total: plan.removalFiles.count, currentURL: nil, phase: "Preparing")
        Task { [self] in
            defer {
                currentRemovalID = nil; removalBusy = false; cancellationRequested = false
                invalidateReview(); refreshAudit()
            }
            do {
                let result = try await dependencies.removal.execute(plan, progress: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self, self.currentRemovalID == plan.id else { return }
                        self.removalProgress = progress
                    }
                })
                removalResult = result
                groups = try RemovalReconciliation.remainingGroups(groups, after: result)
                let remainingIDs = Set(groups.filter { !$0.requiresRescan }.flatMap(\.files).map(\.id))
                selection.removalIDs.formIntersection(remainingIDs)
                selection.keeperIDs.formIntersection(remainingIDs)
                selectedGroupIDs.formIntersection(Set(groups.map(\.id)))
                dataRevision = UUID()
            } catch { message = error.localizedDescription }
        }
    }
    func saveLocations() { savedPaths = folders.map(\.path); defaults.set(savedPaths,forKey:"locations") }
    func restoreLocation(_ path: String) { addFolders([URL(fileURLWithPath:path)]); configure(.folders(folders)) }
    func openHistory(_ scan: SavedScan) {
        guard !workActive else { return }
        guard let url = scan.databaseURL else { rescan(scan); return }
        historyLoading = true
        let revision = dataRevision
        Task {
            defer { historyLoading = false }
            do {
                let cached = try await SavedScanReader.read(url, directory: scanDirectory)
                guard revision == dataRevision else { return }
                groups = cached; folders = scan.roots; configuration.scope = .folders(scan.roots)
                selection = SelectionState(); invalidateReview(); removalResult = nil
                showingSavedResults = true; screen = .results
            } catch { message = error.localizedDescription }
        }
    }
    func cancelRemoval() {
        guard removalBusy else { return }
        cancellationRequested = true
        Task { await dependencies.removal.cancelRemaining() }
    }
    func rescan(_ scan: SavedScan) { guard !workActive else { return }; folders = scan.roots; configure(.folders(folders)) }

    var selectedFile: FileRecord? { groups.flatMap(\.files).first { $0.id == selectedFileID } }
    var selectedGroups: [DuplicateGroup] { groups.filter { selectedGroupIDs.contains($0.id) } }

    func configure(_ scope: ScanScope) {
        guard !workActive else { return }
        configuration.scope = scope
        screen = .configuration
    }
    func chooseFolders(excluded: Bool = false) {
        guard !workActive else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = excluded ? "Exclude Folders" : "Add Folders"
        guard panel.runModal() == .OK else { return }
        if excluded { configuration.excludedFolders += panel.urls }
        else { addFolders(panel.urls); configure(.folders(folders)) }
    }
    func addFolders(_ urls: [URL]) {
        guard !workActive else { return }
        for url in urls where url.isFileURL {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            if !folders.contains(url.standardizedFileURL) { folders.append(url.standardizedFileURL) }
        }
        configuration.scope = .folders(folders)
    }
    func removeFolder(_ url: URL) {
        guard !workActive else { return }
        folders.removeAll { $0 == url }; configuration.scope = .folders(folders)
    }
    func chooseExternalVolumes() {
        guard !workActive else { return }
        configuration.scope = .externalVolumes([]); screen = .configuration
        refreshExternalVolumes()
    }
    func refreshExternalVolumes() {
        Task {
            do { externalVolumes = try await dependencies.volumes.externalVolumes(); volumeMessage = nil }
            catch { volumeMessage = error.localizedDescription }
        }
    }
    func startScan() {
        guard !workActive else { return }
        dataRevision = UUID(); invalidateReview()
        showingSavedResults = false; groups = []; selection = SelectionState(); removalPlan = nil; removalResult = nil; issues = []; progress = ScanProgress(phase:.ready); scanMessage = nil; screen = .progress; scanActive = true; isPaused = false
        let config = configuration
        defaults.set(try? JSONEncoder().encode(config),forKey:"scanConfiguration")
        scanTask = Task {
            defer { scanActive = false; pruneScanHistory() }
            do {
                let events = try await dependencies.scanner.start(config)
                for try await event in events {
                    try Task.checkCancellation()
                    switch event {
                    case .progress(let value): progress = value
                    case .issue(let issue): if issues.count < 1000 { issues.append(issue) }; scanMessage = issue.message
                    case .resultsChanged:
                        if let scanner = dependencies.scanner as? LocalScanCoordinator { groups = await scanner.groups() }
                        let roots: [URL]
                        switch config.scope {
                        case .folders(let urls), .externalVolumes(let urls): roots = urls
                        case .homeFolder: roots = [FileManager.default.homeDirectoryForCurrentUser]
                        case .accessibleUserLocations: roots = ["Desktop","Documents","Downloads","Pictures","Movies","Music"].map { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent($0) }
                        }
                        let db = await (dependencies.scanner as? LocalScanCoordinator)?.persistedDatabase()
                        let record = SavedScan(id:UUID(),date:Date(),roots:roots,groupCount:groups.count,databaseURL:db)
                        history.insert(record,at:0); history = Array(history.prefix(50))
                        defaults.set(try? JSONEncoder().encode(history),forKey:"history")
                        screen = .results
                    case .finished(let session): progress = ScanProgress(phase: session.phase)
                    }
                }
            } catch is CancellationError { progress = ScanProgress(phase: .cancelled) }
              catch { scanMessage = error.localizedDescription; progress = ScanProgress(phase: .failed) }
        }
    }
    func togglePause() {
        Task {
            do {
                if isPaused { try await dependencies.scanner.resume() }
                else { try await dependencies.scanner.pause() }
                isPaused.toggle()
            } catch { message = error.localizedDescription }
        }
    }
    func cancelScan() {
        // Keep consuming until the worker acknowledges cancellation; quitting must wait for it.
        guard scanActive else { return }
        Task { await dependencies.scanner.cancel() }
    }
    func apply(_ rule: SelectionRule, allResults: Bool = false) {
        guard !showingSavedResults else { message = "Rescan saved results before selecting copies."; return }
        guard !workActive else { return }
        invalidateReview()
        let revision = selectionRevision, snapshot = selection
        let scope = allResults ? groups : visibleGroups
        Task {
            do {
                let proposed = try await dependencies.selection.suggest(rule, groups: scope, current: snapshot)
                guard revision == selectionRevision, !workActive else { return }
                selection = proposed
            } catch { if revision == selectionRevision { message = error.localizedDescription } }
        }
    }
    func reviewSelection() {
        guard !workActive, !showingSavedResults else { return }
        screen = .review; invalidateReview(); removalResult = nil
        guard !selection.removalIDs.isEmpty else { return }
        let revision = selectionRevision, snapshot = selection, currentGroups = groups
        Task {
            do {
                let plan = try await dependencies.selection.plan(groups: currentGroups, selection: snapshot)
                guard revision == selectionRevision, !workActive else { return }
                removalPlan = plan; reviewRevision = revision
            } catch { if revision == selectionRevision { message = error.localizedDescription } }
        }
    }
    func clearScanHistory() {
        guard !workActive else { return }
        maintenanceBusy = true
        let store = ScanArchiveStore(directory: scanDirectory)
        Task {
            defer { maintenanceBusy = false }
            do {
                try await Task.detached(priority: .utility) { try store.retainOnly([]) }.value
                history = []; defaults.removeObject(forKey: "history")
                if showingSavedResults { groups = []; selection = SelectionState(); invalidateReview(); showingSavedResults = false }
            } catch { message = "Could not clear all saved scans: " + error.localizedDescription }
        }
    }
    private func pruneScanHistory() {
        guard !workActive else { return }
        maintenanceBusy = true
        let retained = Array(history.filter { $0.date > Date().addingTimeInterval(-30 * 24 * 60 * 60) }.prefix(50))
        let urls = Set(retained.compactMap(\.databaseURL)), store = ScanArchiveStore(directory: scanDirectory)
        Task {
            defer { maintenanceBusy = false }
            do {
                try await Task.detached(priority: .utility) { try store.retainOnly(urls) }.value
                history = retained; defaults.set(try? JSONEncoder().encode(history), forKey: "history")
            } catch { message = "Saved-scan cleanup needs attention: " + error.localizedDescription }
        }
    }
    func nextAuditPage() {
        guard !auditLoading, auditOffset + auditEntries.count < auditTotalCount else { return }
        auditOffset += 200; refreshAudit(resetPage: false)
    }
    func previousAuditPage() {
        guard !auditLoading, auditOffset > 0 else { return }
        auditOffset = max(0, auditOffset - 200); refreshAudit(resetPage: false)
    }
    func refreshAudit(resetPage: Bool = true) {
        guard !auditLoading else { return }
        auditLoading = true
        if resetPage { auditOffset = 0 }
        let offset = auditOffset
        let journal = LocalRemovalJournal(url: journalURL)
        Task {
            defer { auditLoading = false }
            do {
                let snapshot = try await Task.detached(priority: .utility) {
                    try journal.compactIfNeeded()
                    return try journal.read(offset: offset)
                }.value
                auditEntries = snapshot.entries; auditTotalCount = snapshot.totalCount; auditUnresolvedCount = snapshot.unresolvedCount
                auditWarning = snapshot.unreadableLines == 0 ? nil : "Some operation-log records are incomplete or unreadable. Check the log before retrying an interrupted removal."
            } catch { auditWarning = "Operation history could not be read: " + error.localizedDescription }
        }
    }
    func openSelectedFile() { if let file = selectedFile { NSWorkspace.shared.open(file.url) } }
    func revealSelectedFile() { if let file = selectedFile { NSWorkspace.shared.activateFileViewerSelecting([file.url]) } }
}
