import Foundation
import Darwin
import Testing
@testable import DuplicateFinderCore

private final class MoveGate: @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0)
    let resume = DispatchSemaphore(value: 0)
    func waitForEntry() -> Bool { entered.wait(timeout: .now() + 10) == .success }
}
struct InterruptionTests {
    @Test func cancellingDuringMoveFinishesThatMoveAndSkipsRemainingFiles() async throws {
        let root = try ScannerTests().fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var files: [FileRecord] = []
        for n in 0..<4 {
            let url = root.appendingPathComponent("copy-\(n).txt")
            try Data("duplicate content".utf8).write(to: url)
            let record = FileRecord(url: url, snapshot: try LocalFiles.snapshot(url), category: .documents)
            let hash = try LocalFiles.hash(record)
            files.append(FileRecord(id: record.id, url: url, snapshot: record.snapshot, category: .documents, verification: .exact(hash.digest, verifiedAt: Date())))
        }
        guard case .exact(let digest, _) = files[0].verification else { throw DomainError.invalidGroup }
        let group = try DuplicateGroup(files: files, digest: digest)
        let plan = try RemovalPlan(groups: [group], removalIDs: Set(files.dropFirst().map(\.id)))
        let gate = MoveGate()
        let service = LocalSafeRemoval(journalURL: root.appendingPathComponent("audit"), trash: { url in
            gate.entered.signal()
            guard gate.resume.wait(timeout: .now() + 10) == .success else { throw EngineError.invalid("Test gate timed out") }
            let destination = root.appendingPathComponent("moved-" + url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        })
        let work = Task { try await service.execute(plan) }
        let entered = await Task.detached { gate.waitForEntry() }.value
        #expect(entered)
        await service.cancelRemaining(); gate.resume.signal()
        let result = try await work.value
        #expect(result.items.map(\.outcome) == [.trashed, .skipped, .skipped])
        #expect(FileManager.default.fileExists(atPath: files[0].url.path))
        #expect(FileManager.default.fileExists(atPath: files[2].url.path))
        let history = try LocalRemovalJournal(url: root.appendingPathComponent("audit")).read()
        #expect(history.entries.count == 3); #expect(!history.entries.contains { $0.needsInspection })
    }
    @Test func realPermissionDeniedFileIsLeftInPlace() async throws {
        let (root,g) = try RemovalTests().setup(); defer { try? FileManager.default.removeItem(at: root) }
        let file = g.files[1]
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.url.path) }
        #expect(access(file.url.path, R_OK) != 0)
        let service = LocalSafeRemoval(journalURL: root.appendingPathComponent("audit"), trash: { _ in Issue.record("Denied file reached Trash"); return nil })
        let result = try await service.execute(RemovalPlan(groups: [g], removalIDs: [file.id]))
        #expect(result.items[0].outcome == .failed)
        #expect(FileManager.default.fileExists(atPath: file.url.path))
    }
    @Test func unavailableRootProducesIssueAndNoFalseResults() throws {
        let root = try ScannerTests().fixture()
        let missing = root.appendingPathComponent("disconnected")
        defer { try? FileManager.default.removeItem(at: root) }
        var issues: [ScanIssue] = []
        let groups = try LocalScanCoordinator.scan(ScanConfiguration(scope: .folders([missing])), emit: {
            if case .issue(let issue) = $0 { issues.append(issue) }
        })
        #expect(groups.isEmpty); #expect(!issues.isEmpty)
    }
}
