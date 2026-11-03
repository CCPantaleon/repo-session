import Foundation
import Testing
import DuplicateFinderCore
@testable import DuplicateFinderApp

private actor RecordingRemoval: SafeRemovalService {
    private(set) var calls = 0
    let outcomes: [RemovalOutcome]
    let requiresRescan: Bool
    init(outcomes: [RemovalOutcome] = [], requiresRescan: Bool = false) { self.outcomes = outcomes; self.requiresRescan = requiresRescan }
    func execute(_ plan: RemovalPlan) async throws -> RemovalResult {
        calls += 1
        return RemovalResult(planID: plan.id, finishedAt: Date(), items: plan.removalFiles.enumerated().map { index, file in
            RemovalItemResult(fileID: file.id, originalURL: file.url, trashURL: nil,
                              outcome: index < outcomes.count ? outcomes[index] : .failed, message: "test result", requiresRescan: requiresRescan)
        })
    }
    func cancelRemaining() {}
}
private actor DelayedSelection: SelectionService {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var waiting = false
    func suggest(_ rule: SelectionRule, groups: [DuplicateGroup], current: SelectionState) async throws -> SelectionState {
        waiting = true
        await withCheckedContinuation { continuation = $0 }
        return try await LocalSelection().suggest(rule, groups: groups, current: current)
    }
    func release() { continuation?.resume(); continuation = nil }
    func plan(groups: [DuplicateGroup], selection: SelectionState) async throws -> RemovalPlan {
        try await LocalSelection().plan(groups: groups, selection: selection)
    }
}

private actor CapturingScanner: ScanCoordinator {
    private(set) var roots: [URL]?
    func start(_ configuration: ScanConfiguration) async throws -> AsyncThrowingStream<ScanEvent, Error> {
        switch configuration.scope { case .folders(let urls), .externalVolumes(let urls): roots = urls; default: roots = [] }
        return AsyncThrowingStream { $0.finish() }
    }
    func pause() {}
    func resume() {}
    func cancel() {}
}

@MainActor
struct AppModelTests {
    private func model(removal: RecordingRemoval = RecordingRemoval(), selection: any SelectionService = LocalSelection()) -> AppModel {
        AppModel(dependencies: AppDependencies(scanner: UnavailableScanCoordinator(), volumes: UnavailableVolumeDiscovery(), selection: selection, removal: removal),
                 defaults: UserDefaults(suiteName: "DuplicateFinderTests." + UUID().uuidString)!,
                 journalURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), performMaintenance: false)
    }
    private func group(_ name: String, count: Int = 3, restriction: String? = nil) throws -> DuplicateGroup {
        let digest = try ContentDigest(sha256: String(repeating: "b", count: 64)), date = Date()
        return try DuplicateGroup(files: (0..<count).map { n in
            FileRecord(url: URL(fileURLWithPath: "/fixtures/\(name)/\(n).txt"), snapshot: FileSnapshot(identity: FileIdentity(volumeID: "v", resourceID: "\(name)-\(n)"), logicalBytes: 10, modifiedAt: date, metadataChangedAt: date), category: .documents, verification: .exact(digest, verifiedAt: date), removalRestriction: restriction)
        }, digest: digest)
    }
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw EngineError.invalid("Timed out waiting for app state")
    }
    @Test func clearingSelectionInvalidatesReviewAndCannotExecuteOldPlan() async throws {
        let remover = RecordingRemoval(), model = model(removal: remover), g = try group("clear")
        model.groups = [g]; model.mark(g.files[1], removal: true); model.reviewSelection()
        try await waitUntil { model.canConfirmRemoval }
        model.clearSelection()
        #expect(model.removalPlan == nil); #expect(!model.canConfirmRemoval)
        model.confirmRemoval()
        #expect(await remover.calls == 0)
    }
    @Test func clearWhileReviewIsPendingCannotRestoreOldPlan() async throws {
        let model = model(), g = try group("pending")
        model.groups = [g]; model.mark(g.files[1], removal: true); model.reviewSelection(); model.clearSelection()
        try await Task.sleep(for: .milliseconds(30))
        #expect(model.removalPlan == nil); #expect(model.selection.removalIDs.isEmpty)
    }
    @Test func oldConfirmationCannotExecuteReplacementPlan() async throws {
        let remover = RecordingRemoval(), model = model(removal: remover), g = try group("confirmation")
        model.groups = [g]; model.mark(g.files[1], removal: true); model.reviewSelection()
        try await waitUntil { model.canConfirmRemoval }
        let oldID = try #require(model.removalPlan?.id)
        model.mark(g.files[2], removal: true); model.reviewSelection()
        try await waitUntil { model.canConfirmRemoval }
        model.confirmRemoval(expectedPlanID: oldID)
        #expect(await remover.calls == 0); #expect(!model.removalBusy)
    }
    @Test func defaultSelectionRespectsSearchAndWholeScanIsExplicit() async throws {
        let model = model(), visible = try group("visible"), hidden = try group("hidden")
        model.groups = [visible, hidden]; model.query.search = "visible"
        model.apply(.allRedundant)
        try await waitUntil { model.selection.removalIDs.count == 2 }
        #expect(model.selection.removalIDs.isDisjoint(with: Set(hidden.files.map(\.id))))
        model.apply(.allRedundant, allResults: true)
        try await waitUntil { model.selection.removalIDs.count == 4 }
        #expect(model.hiddenSelectionCount == 2)
    }
    @Test func changingKeeperInvalidatesReview() async throws {
        let model = model(), g = try group("keep")
        model.groups = [g]; model.mark(g.files[1], removal: true); model.reviewSelection()
        try await waitUntil { model.canConfirmRemoval }
        model.keep(g.files[1])
        #expect(model.removalPlan == nil); #expect(model.selection.removalIDs.isEmpty)
    }
    @Test func failedRemovalAndRemainingDuplicatesStayVisible() async throws {
        let model = model(removal: RecordingRemoval(outcomes: [.trashed, .failed])), g = try group("partial", count: 4)
        model.groups = [g]; model.mark(g.files[1], removal: true); model.mark(g.files[2], removal: true)
        model.reviewSelection(); try await waitUntil { model.canConfirmRemoval }
        model.confirmRemoval(); try await waitUntil { model.removalResult != nil && !model.removalBusy }
        #expect(model.groups.count == 1); #expect(model.groups[0].files.count == 3)
        #expect(model.selection.removalIDs == [g.files[2].id])
    }
    @Test func scanOnlyFileCannotBeMarked() throws {
        let model = model(), g = try group("external", restriction: "Scan only")
        model.groups = [g]; model.mark(g.files[1], removal: true)
        #expect(model.selection.removalIDs.isEmpty); #expect(model.message == "Scan only")
    }
    @Test func lateSuggestionCannotUndoClearSelection() async throws {
        let delayed = DelayedSelection(), model = model(selection: delayed), g = try group("delayed")
        model.groups = [g]; model.apply(.allRedundant)
        for _ in 0..<100 {
            if await delayed.waiting { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await delayed.waiting)
        model.clearSelection(); await delayed.release()
        try await Task.sleep(for: .milliseconds(30))
        #expect(model.selection.removalIDs.isEmpty)
    }
    @Test func clearingHistoryRemovesDatabaseButKeepsOriginals() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = root.appendingPathComponent(UUID().uuidString + ".sqlite"), original = root.appendingPathComponent("original.txt")
        try Data("fixture".utf8).write(to: db); try Data("keep me".utf8).write(to: original)
        let model = AppModel(dependencies: AppDependencies(scanner: UnavailableScanCoordinator(), volumes: UnavailableVolumeDiscovery(), selection: LocalSelection(), removal: RecordingRemoval()),
                             defaults: UserDefaults(suiteName: "DuplicateFinderTests." + UUID().uuidString)!, scanDirectory: root, performMaintenance: false)
        model.history = [AppModel.SavedScan(id: UUID(), date: Date(), roots: [], groupCount: 1, databaseURL: db)]
        model.clearScanHistory(); try await waitUntil { !model.maintenanceBusy }
        #expect(model.history.isEmpty); #expect(!FileManager.default.fileExists(atPath: db.path))
        #expect(try String(contentsOf: original, encoding: .utf8) == "keep me")
    }
    @Test func keeperCanBeUnlockedWithoutAutomaticallySelectingIt() async throws {
        let model = model(), g = try group("unlock")
        model.groups = [g]; model.keep(g.files[1]); model.mark(g.files[1],removal:true)
        #expect(model.selection.removalIDs.isEmpty)
        model.unlockKeeper(g.files[1])
        #expect(!model.selection.keeperIDs.contains(g.files[1].id)); #expect(model.selection.removalIDs.isEmpty)
        model.mark(g.files[1],removal:true); model.reviewSelection()
        try await waitUntil { model.canConfirmRemoval }
        model.keep(g.files[0]); model.reviewSelection()
        try await waitUntil { model.canConfirmRemoval }
        model.unlockKeeper(g.files[0]); #expect(model.removalPlan == nil)
    }
    @Test func changedResultsCannotBeSuggestedOrManuallyMarkedAgain() async throws {
        let model = model(removal:RecordingRemoval(outcomes:[.failed],requiresRescan:true)), g = try group("stale")
        model.groups = [g]; model.mark(g.files[1],removal:true); model.reviewSelection()
        try await waitUntil { model.canConfirmRemoval }
        model.confirmRemoval(); try await waitUntil { model.removalResult != nil && !model.removalBusy }
        #expect(model.hasStaleResults); #expect(model.needsRescan(g.files[0])); #expect(model.selection.removalIDs.isEmpty)
        model.mark(g.files[2],removal:true); #expect(model.selection.removalIDs.isEmpty)
        model.apply(.allRedundant); try await Task.sleep(for:.milliseconds(30))
        #expect(model.selection.removalIDs.isEmpty)
    }
    @Test func reopeningHistoryAfterExternalModeRescansSavedFolders() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        let media = root.appendingPathComponent("media"), store = root.appendingPathComponent("indexes")
        try FileManager.default.createDirectory(at:media,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        for n in 0..<2 { try Data("same file".utf8).write(to:media.appendingPathComponent("\(n).txt")) }
        let db = store.appendingPathComponent(UUID().uuidString+".sqlite")
        _ = try LocalScanCoordinator.scan(ScanConfiguration(scope:.folders([media])),databaseURL:db)
        let scanner = CapturingScanner()
        let model = AppModel(dependencies:AppDependencies(scanner:scanner,volumes:UnavailableVolumeDiscovery(),selection:LocalSelection(),removal:RecordingRemoval()),
                             defaults:UserDefaults(suiteName:"DuplicateFinderTests."+UUID().uuidString)!,scanDirectory:store,performMaintenance:false)
        let saved = AppModel.SavedScan(id:UUID(),date:Date(),roots:[media],groupCount:1,databaseURL:db)
        model.history = [saved]; model.configuration.scope = .externalVolumes([URL(fileURLWithPath:"/Volumes/PreviousDrive")])
        #expect(model.isExternalScope)
        model.openHistory(saved); try await waitUntil { model.showingSavedResults && !model.historyLoading }
        #expect(!model.isExternalScope); #expect(model.volumeIDs.isEmpty)
        model.startScan(); try await waitUntil { !model.scanActive && !model.maintenanceBusy }
        #expect(await scanner.roots == [media])
    }
    @Test func restoredExternalConfigurationKeepsItsSelection() throws {
        let defaults = UserDefaults(suiteName:"DuplicateFinderTests."+UUID().uuidString)!
        let url = URL(fileURLWithPath:"/Volumes/SavedDrive")
        defaults.set(try JSONEncoder().encode(ScanConfiguration(scope:.externalVolumes([url]))),forKey:"scanConfiguration")
        let model = AppModel(defaults:defaults,performMaintenance:false)
        #expect(model.isExternalScope); #expect(model.volumeIDs == [url.path])
    }
    @Test func scannerToAppFlowPreventsSelectingExternalCopies() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        let media = root.appendingPathComponent("media"), store = root.appendingPathComponent("indexes")
        try FileManager.default.createDirectory(at:media,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        for n in 0..<2 { try Data("same image contents".utf8).write(to:media.appendingPathComponent("\(n).jpg")) }
        let scanner = LocalScanCoordinator(storageDirectory:store,removalPolicy:{ _ in "Scan only: external volume" })
        let model = AppModel(dependencies:AppDependencies(scanner:scanner,volumes:UnavailableVolumeDiscovery(),selection:LocalSelection(),removal:RecordingRemoval()),
                             defaults:UserDefaults(suiteName:"DuplicateFinderTests."+UUID().uuidString)!,scanDirectory:store,performMaintenance:false)
        model.configuration.scope = .folders([media]); model.startScan()
        try await waitUntil { !model.scanActive && !model.maintenanceBusy }
        #expect(model.groups.count == 1)
        let file = try #require(model.groups.first?.files.first)
        #expect(file.removalRestriction == "Scan only: external volume")
        model.mark(file,removal:true); #expect(model.selection.removalIDs.isEmpty)
        model.apply(.allRedundant); try await Task.sleep(for:.milliseconds(30)); #expect(model.selection.removalIDs.isEmpty)
    }

}
