import Foundation

public struct RemovalProgress: Sendable {
    public let completed: Int
    public let total: Int
    public let currentURL: URL?
    public let phase: String
    public init(completed: Int, total: Int, currentURL: URL?, phase: String) {
        self.completed = completed; self.total = total; self.currentURL = currentURL; self.phase = phase
    }
}

public enum RemovalReconciliation {
    /// A failed/skipped item remains visible. Never infer success from a missing result.
    public static func remainingGroups(_ groups: [DuplicateGroup], after result: RemovalResult) throws -> [DuplicateGroup] {
        let moved = Set(result.items.filter { $0.outcome == .trashed }.map(\.fileID))
        let stale = Set(result.items.filter { $0.requiresRescan == true }.map(\.fileID))
        return try groups.compactMap { group in
            let remaining = group.files.filter { !moved.contains($0.id) }
            guard remaining.count >= 2 else { return nil }
            return try DuplicateGroup(id: group.id, files: remaining, digest: group.digest, requiresRescan: group.requiresRescan || group.files.contains { stale.contains($0.id) })
        }
    }
}
