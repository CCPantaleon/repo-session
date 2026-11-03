import Foundation
import Testing
@testable import DuplicateFinderCore

struct ReleaseRegressionTests {
    func group(_ count: Int, name: String = "g", restricted: Bool = false) throws -> DuplicateGroup {
        let digest = try ContentDigest(sha256: String(repeating: "a", count: 64))
        let date = Date()
        let files = (0..<count).map { n in
            FileRecord(url: URL(fileURLWithPath: "/fixtures/\(name)/\(n)"),
                       snapshot: FileSnapshot(identity: FileIdentity(volumeID: "fixture", resourceID: "\(name)-\(n)"), logicalBytes: 8, modifiedAt: date, metadataChangedAt: date),
                       category: .documents, verification: .exact(digest, verifiedAt: date), removalRestriction: restricted ? "Scan only" : nil)
        }
        return try DuplicateGroup(files: files, digest: digest)
    }
    @Test func singleSelectionWorksBeyondTwoThousandResultMembers() async throws {
        let groups = try (0..<1001).map { try group(2, name: "\($0)") }
        var selection = SelectionState(); selection.removalIDs = [groups[0].files[1].id]
        let plan = try await LocalSelection().plan(groups: groups, selection: selection)
        #expect(plan.removalFiles.count == 1)
        #expect(plan.groups.count == 1)
    }
    @Test func hugeGroupAndSelectionCanBeReviewedInSafeBatches() async throws {
        let g = try group(2501)
        var selection = SelectionState(); selection.removalIDs = Set(g.files.dropFirst().map(\.id))
        let plan = try await LocalSelection().plan(groups: [g], selection: selection)
        #expect(plan.removalFiles.count == 1000)
        #expect(plan.retainedFiles.contains { $0.id == g.files[0].id })
        let result = RemovalResult(planID: plan.id, finishedAt: Date(), items: plan.removalFiles.map {
            RemovalItemResult(fileID: $0.id, originalURL: $0.url, trashURL: nil, outcome: .trashed, message: "fixture")
        })
        let remaining = try RemovalReconciliation.remainingGroups([g], after: result)
        selection.removalIDs.subtract(plan.removalIDs)
        let next = try await LocalSelection().plan(groups: remaining, selection: selection)
        #expect(next.removalFiles.count == 1000)
        #expect(next.retainedFiles.contains { $0.id == g.files[0].id })
    }
    @Test func batchesNeverAllowSelectingEveryCopy() async throws {
        let g = try group(1500)
        var selection = SelectionState(); selection.removalIDs = Set(g.files.map(\.id))
        await #expect(throws: DomainError.noRetainedCopy) { try await LocalSelection().plan(groups: [g], selection: selection) }
    }
    @Test func resultsKeepFailuresSkippedAndUnselectedCopies() throws {
        let g = try group(5)
        let outcomes: [RemovalOutcome] = [.trashed, .failed, .skipped]
        let result = RemovalResult(planID: UUID(), finishedAt: Date(), items: zip(g.files, outcomes).map { file, outcome in
            RemovalItemResult(fileID: file.id, originalURL: file.url, trashURL: nil, outcome: outcome, message: "fixture")
        })
        let remaining = try RemovalReconciliation.remainingGroups([g], after: result)
        #expect(remaining[0].files.count == 4)
        #expect(remaining[0].id == g.id)
        #expect(!remaining[0].files.contains { $0.id == g.files[0].id })
        #expect(remaining[0].files.contains { $0.id == g.files[1].id })
    }
    @Test func scanOnlyCopiesCannotEnterPlans() async throws {
        let g = try group(2, restricted: true)
        let selected = try await LocalSelection().suggest(.allRedundant, groups: [g], current: SelectionState())
        #expect(selected.removalIDs.isEmpty)
        var manual = SelectionState(); manual.removalIDs = [g.files[1].id]
        await #expect(throws: (any Error).self) { try await LocalSelection().plan(groups: [g], selection: manual) }
        #expect(LocalRemovalPolicy.restriction(isLocal: true, isInternal: false, isReadOnly: false) != nil)
        #expect(LocalRemovalPolicy.restriction(isLocal: false, isInternal: false, isReadOnly: false) != nil)
        #expect(LocalRemovalPolicy.restriction(isLocal: true, isInternal: true, isReadOnly: true) != nil)
        #expect(LocalRemovalPolicy.restriction(isLocal: true, isInternal: true, isReadOnly: false) == nil)
    }
    @Test func operationHistoryPreservesUncertainIntentsAndSurvivesTruncatedRecord() throws {
        let root = try ScannerTests().fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let journal = LocalRemovalJournal(url: root.appendingPathComponent("audit.jsonl")), g = try group(3), id = UUID()
        try journal.append(RemovalAuditEntry(plan: id, file: g.files[0], keepers: [g.files[2]], state: "intent", result: nil, date: Date()))
        try journal.append(RemovalAuditEntry(plan: id, file: g.files[1], keepers: [g.files[2]], state: "intent", result: nil, date: Date()))
        let handle = try FileHandle(forWritingTo: journal.url); try handle.seekToEnd(); try handle.write(contentsOf: Data("{broken".utf8)); try handle.close()
        let result = RemovalItemResult(fileID: g.files[1].id, originalURL: g.files[1].url, trashURL: nil, outcome: .failed, message: "left in place")
        try journal.append(RemovalAuditEntry(plan: id, file: g.files[1], keepers: [g.files[2]], state: "failed", result: result, date: Date()))
        let loaded = try journal.read()
        #expect(loaded.entries.count == 2)
        #expect(loaded.unreadableLines == 1)
        #expect(loaded.entries.filter(\.needsInspection).map(\.file.id) == [g.files[0].id])
        #expect(try journal.read(limit: 0).entries.isEmpty)
        #expect(try journal.read(limit: 0).unresolvedCount == 1)
    }
    @Test func scanCleanupDeletesOnlyOwnedUnretainedIndexes() throws {
        let root = try ScannerTests().fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent(UUID().uuidString + ".sqlite"), b = root.appendingPathComponent(UUID().uuidString + ".sqlite")
        let sidecar = URL(fileURLWithPath: b.path + "-journal"), other = root.appendingPathComponent("personal.sqlite")
        for url in [a,b,sidecar,other] { try Data("fixture".utf8).write(to: url) }
        let link = root.appendingPathComponent(UUID().uuidString + ".sqlite")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: other)
        try ScanArchiveStore(directory: root).retainOnly([a])
        #expect(FileManager.default.fileExists(atPath: a.path))
        #expect(!FileManager.default.fileExists(atPath: b.path))
        #expect(!FileManager.default.fileExists(atPath: sidecar.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
        #expect(FileManager.default.fileExists(atPath: link.path))
        try ScanArchiveStore(directory: root).retainOnly([])
        #expect(!FileManager.default.fileExists(atPath: a.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
    }
    @Test func changedOrMissingCandidatesNeverReachTrash() async throws {
        for missing in [false, true] {
            let (root,g) = try RemovalTests().setup(); defer { try? FileManager.default.removeItem(at: root) }
            if missing { try FileManager.default.removeItem(at: g.files[1].url) }
            else { try Data("modified contents".utf8).write(to: g.files[1].url) }
            let remover = LocalSafeRemoval(journalURL: root.appendingPathComponent("audit"), trash: { _ in Issue.record("Unsafe move"); return nil })
            let result = try await remover.execute(RemovalPlan(groups: [g], removalIDs: [g.files[1].id]))
            #expect(result.items[0].outcome == .failed)
            #expect(FileManager.default.fileExists(atPath: g.files[0].url.path))
        }
    }
    @Test func cancelledCoordinatorCanImmediatelyStartAgain() async throws {
        let root = try ScannerTests().fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let scanner = LocalScanCoordinator(storageDirectory: root.appendingPathComponent("indexes"))
        let stream = try await scanner.start(ScanConfiguration(scope: .folders([root])))
        await scanner.pause(); await scanner.cancel()
        do { for try await _ in stream {} } catch is CancellationError {} catch { throw error }
        let second = try await scanner.start(ScanConfiguration(scope: .folders([root])))
        await scanner.cancel()
        do { for try await _ in second {} } catch is CancellationError {} catch { throw error }
    }
}
