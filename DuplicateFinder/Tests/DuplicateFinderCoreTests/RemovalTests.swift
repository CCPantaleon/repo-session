import Foundation
import Testing
@testable import DuplicateFinderCore
struct RemovalTests {
    func setup() throws -> (URL,DuplicateGroup) {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        var files:[FileRecord] = []
        for name in ["keep","remove"] {
            let url = root.appendingPathComponent(name); try Data("duplicate fixture".utf8).write(to:url)
            let f = FileRecord(url:url,snapshot:try LocalFiles.snapshot(url),category:.documents)
            let h = try LocalFiles.hash(f)
            files.append(FileRecord(id:f.id,url:url,snapshot:f.snapshot,category:.documents,verification:.exact(h.digest,verifiedAt:Date())))
        }
        guard case .exact(let hash,_) = files[0].verification else { fatalError() }
        return (root,try DuplicateGroup(files:files,digest:hash))
    }
    @Test func smartSelectionRetainsLockedKeeper() async throws {
        let (root,g) = try setup(); defer { try? FileManager.default.removeItem(at:root) }
        var s = SelectionState(); s.keeperIDs = [g.files[0].id]
        s = try await LocalSelection().suggest(.allRedundant,groups:[g],current:s)
        #expect(s.removalIDs == [g.files[1].id])
        #expect(try await LocalSelection().plan(groups:[g],selection:s).retainedFiles.count == 1)
    }
    @Test func changedKeeperPreventsAnyMove() async throws {
        let (root,g) = try setup(); defer { try? FileManager.default.removeItem(at:root) }
        let plan = try RemovalPlan(groups:[g],removalIDs:[g.files[1].id])
        try Data("changed".utf8).write(to:g.files[0].url)
        let service = LocalSafeRemoval(journalURL:root.appendingPathComponent("audit"),trash:{ _ in Issue.record("Trash must not be invoked"); return nil })
        let result = try await service.execute(plan)
        #expect(result.items[0].outcome == .failed)
        #expect(FileManager.default.fileExists(atPath:g.files[1].url.path))
    }
    @Test func reviewedMoveUsesAdapterAndDurableAudit() async throws {
        let (root,g) = try setup(); defer { try? FileManager.default.removeItem(at:root) }
        let target = root.appendingPathComponent("test-trash")
        let service = LocalSafeRemoval(journalURL:root.appendingPathComponent("audit"),trash:{ url in
            try FileManager.default.moveItem(at:url,to:target); return target
        })
        let plan = try RemovalPlan(groups:[g],removalIDs:[g.files[1].id])
        let result = try await service.execute(plan)
        #expect(result.items[0].outcome == .trashed)
        #expect(FileManager.default.fileExists(atPath:g.files[0].url.path))
        let audit = try String(contentsOf:root.appendingPathComponent("audit"),encoding:.utf8)
        #expect(audit.contains("intent")); #expect(audit.contains("trashed"))
        await #expect(throws:(any Error).self) { try await service.execute(plan) }
    }
    @Test func failedJournalCannotMoveAnything() async throws {
        let (root,g) = try setup(); defer { try? FileManager.default.removeItem(at:root) }
        let journal = g.files[0].url.appendingPathComponent("impossible")
        let service = LocalSafeRemoval(journalURL:journal,trash:{ _ in Issue.record("Trash called without durable intent"); return nil })
        let result = try await service.execute(RemovalPlan(groups:[g],removalIDs:[g.files[1].id]))
        #expect(result.items[0].outcome == .failed)
        #expect(FileManager.default.fileExists(atPath:g.files[1].url.path))
    }
}
