import Foundation
import Darwin

public struct LocalSelection: SelectionService {
    public init() {}
    public func suggest(_ rule: SelectionRule, groups: [DuplicateGroup], current: SelectionState) async throws -> SelectionState {
        var result = current
        if case .clear = rule { result.removalIDs = []; return result }
        for group in groups {
            if group.requiresRescan { result.removalIDs.subtract(group.files.map(\.id)); continue }
            let sorted = group.files.sorted { a,b in
                switch rule {
                case .keepNewest where a.snapshot.modifiedAt != b.snapshot.modifiedAt: return a.snapshot.modifiedAt > b.snapshot.modifiedAt
                case .keepOldest where a.snapshot.modifiedAt != b.snapshot.modifiedAt: return a.snapshot.modifiedAt < b.snapshot.modifiedAt
                case .preferredFolder(let folder), .selectedLocation(let folder):
                    let prefix = folder.standardizedFileURL.path + "/"
                    let x = a.url.path.hasPrefix(prefix), y = b.url.path.hasPrefix(prefix)
                    if x != y { return x }
                default: break
                }
                return a.url.path < b.url.path
            }
            let keepers = Set(group.files.filter { current.keeperIDs.contains($0.id) }.map(\.id))
            let keep = keepers.isEmpty ? Set([sorted[0].id]) : keepers
            for file in group.files {
                if keep.contains(file.id) || file.snapshot.linkCount > 1 || file.removalRestriction != nil { result.removalIDs.remove(file.id) }
                else { result.removalIDs.insert(file.id) }
            }
        }
        return result
    }
    public func plan(groups: [DuplicateGroup], selection: SelectionState) async throws -> RemovalPlan {
        guard selection.removalIDs.isDisjoint(with: selection.keeperIDs) else { throw DomainError.invalidSelection }
        let affected = groups.filter { $0.files.contains { selection.removalIDs.contains($0.id) } }
        // Validate the complete intent before splitting it, so a later batch always has a keeper.
        _ = try RemovalPlan(groups: affected, removalIDs: selection.removalIDs)
        let candidates = affected.flatMap(\.files).filter { selection.removalIDs.contains($0.id) }
        guard candidates.allSatisfy({ $0.removalRestriction == nil && $0.snapshot.linkCount == 1 }) else {
            throw EngineError.invalid("Scan-only and hard-linked files cannot be selected for removal.")
        }
        let batchIDs = Set(candidates.sorted { $0.url.path < $1.url.path }.prefix(1000).map(\.id))
        return try RemovalPlan(groups: affected.filter { $0.files.contains { batchIDs.contains($0.id) } }, removalIDs: batchIDs)
    }
}

public actor LocalSafeRemoval: SafeRemovalService {
    public typealias Trash = @Sendable (URL) throws -> URL?
    private let journalURL: URL
    private let trash: Trash
    private var active = false
    private var consumed = Set<UUID>()
    private var control = ScanControl()
    public init(journalURL: URL, trash: @escaping Trash = { url in
        if let restriction = LocalRemovalPolicy.restriction(for: url) { throw EngineError.invalid(restriction) }
        var destination: NSURL?
        try FileManager.default.trashItem(at:url,resultingItemURL:&destination)
        return destination as URL?
    }) { self.journalURL = journalURL; self.trash = trash }
    public func cancelRemaining() { control.cancel() }
    public func execute(_ plan: RemovalPlan) async throws -> RemovalResult {
        try await execute(plan, progress: { _ in })
    }
    public func execute(_ plan: RemovalPlan, progress: @escaping @Sendable (RemovalProgress) -> Void) async throws -> RemovalResult {
        guard !active, !consumed.contains(plan.id) else { throw EngineError.busy }
        guard plan.removalFiles.count <= 1000 else { throw EngineError.invalid("Review at most 1,000 files at a time") }
        active = true; consumed.insert(plan.id); control = ScanControl()
        defer { active = false }
        let control = control, journalURL = journalURL, trash = trash
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos:.utility).async {
                var items: [RemovalItemResult] = []
                var stopped = false
                let journal = LocalRemovalJournal(url: journalURL)
                let total = plan.removalFiles.count
                for group in plan.groups {
                    let retained = group.files.filter { !plan.removalIDs.contains($0.id) }
                    for file in group.files where plan.removalIDs.contains(file.id) {
                        func log(_ state: String, result: RemovalItemResult? = nil) throws {
                            // Only this group's keeper is needed to explain an operation.
                            try journal.append(RemovalAuditEntry(plan: plan.id, file: file, keepers: Array(retained.prefix(1)), state: state, result: result, date: Date()))
                        }
                        progress(RemovalProgress(completed: items.count, total: total, currentURL: file.url, phase: stopped ? "Cancelling" : "Verifying"))
                        var requiresRescan = false
                        var verifying = true
                        var outcome = RemovalOutcome.skipped; var text = "Cancelled or stopped after an audit failure"; var destination: URL?
                        if !stopped {
                            do {
                                try control.check()
                                guard file.removalRestriction == nil, file.snapshot.linkCount == 1, let keeper = retained.first else { throw DomainError.noRetainedCopy }
                                for item in [keeper,file] {
                                    guard try LocalFiles.hash(item,checkpoint:control.check).digest == group.digest else { throw EngineError.changed }
                                }
                                try control.check()
                                guard keeper.url.resolvingSymlinksInPath().path == keeper.url.standardizedFileURL.path, file.url.resolvingSymlinksInPath().path == file.url.standardizedFileURL.path, try LocalFiles.snapshot(keeper.url) == keeper.snapshot, try LocalFiles.snapshot(file.url) == file.snapshot else { throw EngineError.changed }
                                verifying = false
                                try log("intent")
                                verifying = true
                                // Last path/keeper checks after durable intent, immediately before OS mutation.
                                guard keeper.url.resolvingSymlinksInPath().path == keeper.url.standardizedFileURL.path, file.url.resolvingSymlinksInPath().path == file.url.standardizedFileURL.path, try LocalFiles.snapshot(keeper.url) == keeper.snapshot, try LocalFiles.snapshot(file.url) == file.snapshot else { throw EngineError.changed }
                                // Cancellation after durable intent must also prevent the next move.
                                try control.check()
                                progress(RemovalProgress(completed: items.count, total: total, currentURL: file.url, phase: "Moving to Trash"))
                                verifying = false
                                destination = try trash(file.url); outcome = .trashed; text = "Moved to Trash"
                            } catch { requiresRescan = verifying && !(error is CancellationError); outcome = .failed; text = error.localizedDescription; if error is CancellationError { stopped = true; outcome = .skipped } }
                        }
                        let result = RemovalItemResult(fileID:file.id,originalURL:file.url,trashURL:destination,outcome:outcome,message:text,requiresRescan:requiresRescan)
                        items.append(result)
                        do { try log(outcome.rawValue,result:result) }
                        catch { stopped = true; items[items.count-1] = RemovalItemResult(fileID:file.id,originalURL:file.url,trashURL:destination,outcome:outcome,message:text+". Audit failure: stop and inspect the operation log before retrying.",requiresRescan:requiresRescan) }
                    }
                }
                progress(RemovalProgress(completed: items.count, total: total, currentURL: nil, phase: "Finished"))
                continuation.resume(returning:RemovalResult(planID:plan.id,finishedAt:Date(),items:items))
            }
        }
    }
}
