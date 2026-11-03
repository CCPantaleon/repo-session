import Foundation
import Testing
@testable import DuplicateFinderCore

struct Version050Tests {
    @Test func realScanningPropagatesVolumePolicyThroughPersistenceAndSelection() async throws {
        let root = try ScannerTests().fixture(); defer { try? FileManager.default.removeItem(at:root) }
        let media = root.appendingPathComponent("media"); try FileManager.default.createDirectory(at:media,withIntermediateDirectories:true)
        for n in 0..<2 { try Data("same actual file bytes".utf8).write(to:media.appendingPathComponent("\(n).jpg")) }
        let database = root.appendingPathComponent("scan.sqlite")
        let groups = try LocalScanCoordinator.scan(ScanConfiguration(scope:.folders([media])),databaseURL:database,
                                                   removalPolicy:{ _ in "Scan only: simulated external volume" })
        #expect(groups.count == 1)
        #expect(groups[0].files.allSatisfy { $0.removalRestriction != nil })
        let reopened = try SQLiteScanIndex(url:database).groups(checkpoint:{})
        #expect(reopened[0].files.allSatisfy { $0.removalRestriction == "Scan only: simulated external volume" })
        let selection = try await LocalSelection().suggest(.allRedundant,groups:reopened,current:SelectionState())
        #expect(selection.removalIDs.isEmpty)
        var forced = SelectionState(); forced.removalIDs = [reopened[0].files[0].id]
        await #expect(throws:(any Error).self) { try await LocalSelection().plan(groups:reopened,selection:forced) }
    }
    @Test func changedKeeperInvalidatesWholeGroupAndBlocksAnotherPlan() async throws {
        let (root,g) = try RemovalTests().setup(); defer { try? FileManager.default.removeItem(at:root) }
        try Data("changed contents".utf8).write(to:g.files[0].url)
        let remover = LocalSafeRemoval(journalURL:root.appendingPathComponent("audit"),trash:{ _ in Issue.record("Changed group reached Trash"); return nil })
        let result = try await remover.execute(RemovalPlan(groups:[g],removalIDs:[g.files[1].id]))
        #expect(result.items[0].requiresRescan == true)
        let remaining = try RemovalReconciliation.remainingGroups([g],after:result)
        #expect(remaining[0].requiresRescan); #expect(remaining[0].redundantLogicalBytes == 0)
        let selection = try await LocalSelection().suggest(.allRedundant,groups:remaining,current:SelectionState())
        #expect(selection.removalIDs.isEmpty)
        #expect(throws: (any Error).self) { try RemovalPlan(groups:remaining,removalIDs:[g.files[1].id]) }
    }
    private func records(_ count:Int, pending:Int, prefix:Int = 0) throws -> [RemovalAuditEntry] {
        let g = try ReleaseRegressionTests().group(2), date = Date()
        return (0..<count).map { n in
            RemovalAuditEntry(plan:UUID(),file:g.files[0],keepers:[g.files[1]],state:n < pending ? "intent" : "trashed",result:nil,date:date.addingTimeInterval(Double(prefix+n)))
        }
    }
    private func write(_ entries:[RemovalAuditEntry],to url:URL,append:Bool = false) throws {
        if !append { try Data().write(to:url) }
        let handle = try FileHandle(forWritingTo:url); defer { try? handle.close() }; try handle.seekToEnd()
        for entry in entries { var data = try JSONEncoder().encode(entry); data.append(10); try handle.write(contentsOf:data) }
    }
    @Test func historyPagesBoundUnresolvedAndCompletedRecords() throws {
        let root = try ScannerTests().fixture(); defer { try? FileManager.default.removeItem(at:root) }
        let journal = LocalRemovalJournal(url:root.appendingPathComponent("audit.jsonl"))
        try write(records(2500,pending:600),to:journal.url)
        let first = try journal.read(limit:100), next = try journal.read(limit:100,offset:100)
        #expect(first.totalCount == 2500); #expect(first.unresolvedCount == 600)
        #expect(first.entries.count == 100); #expect(next.entries.count == 100)
        #expect(first.entries.allSatisfy { $0.needsInspection })
        #expect(Set(first.entries.map(\.id)).isDisjoint(with:Set(next.entries.map(\.id))))
        #expect(try journal.read(limit:10000).entries.count == 500)
    }
    @Test func compactionPreservesAllUnresolvedAndDoesNotResurrectResolvedIntents() throws {
        let root = try ScannerTests().fixture(); defer { try? FileManager.default.removeItem(at:root) }
        let journal = LocalRemovalJournal(url:root.appendingPathComponent("audit.jsonl"))
        let original = try records(120,pending:2)
        try write(original,to:journal.url)
        try journal.compactIfNeeded(maximumBytes:1,completedToKeep:5,archivesToKeep:2)
        var snapshot = try journal.read()
        #expect(snapshot.totalCount == 7); #expect(snapshot.unresolvedCount == 2)
        let pending = original[0]
        try journal.append(RemovalAuditEntry(plan:pending.plan,file:pending.file,keepers:pending.keepers,state:"failed",result:nil,date:Date().addingTimeInterval(10000)))
        for n in 0..<3 {
            try write(records(60,pending:0,prefix:1000*n),to:journal.url,append:true)
            try journal.compactIfNeeded(maximumBytes:1,completedToKeep:5,archivesToKeep:2)
        }
        snapshot = try journal.read()
        #expect(snapshot.totalCount == 6); #expect(snapshot.unresolvedCount == 1)
        #expect(snapshot.entries.filter { $0.needsInspection }.map(\.id) == [original[1].id])
        let archives = try FileManager.default.contentsOfDirectory(at:journal.archiveDirectory,includingPropertiesForKeys:nil).filter { $0.pathExtension == "jsonl" }
        #expect(archives.count == 2)
    }
    @Test func unreadableRecoveryEvidencePreventsDestructiveCompaction() throws {
        let root = try ScannerTests().fixture(); defer { try? FileManager.default.removeItem(at:root) }
        let journal = LocalRemovalJournal(url:root.appendingPathComponent("audit.jsonl"))
        try write(records(30,pending:1),to:journal.url)
        let handle = try FileHandle(forWritingTo:journal.url); try handle.seekToEnd(); try handle.write(contentsOf:Data("{incomplete".utf8)); try handle.close()
        let before = try Data(contentsOf:journal.url)
        try journal.compactIfNeeded(maximumBytes:1,completedToKeep:1)
        #expect(try Data(contentsOf:journal.url) == before)
        #expect(try journal.read().unreadableLines == 1)
    }
    @Test func oversizedCorruptLineDoesNotHideFollowingValidRecord() throws {
        let root = try ScannerTests().fixture(); defer { try? FileManager.default.removeItem(at:root) }
        let journal = LocalRemovalJournal(url:root.appendingPathComponent("audit.jsonl"))
        var malformed = Data(repeating:120,count:17*1024*1024); malformed.append(10); try malformed.write(to:journal.url)
        try write(records(1,pending:1),to:journal.url,append:true)
        let snapshot = try journal.read()
        #expect(snapshot.unreadableLines == 1); #expect(snapshot.unresolvedCount == 1); #expect(snapshot.entries.count == 1)
    }
}
