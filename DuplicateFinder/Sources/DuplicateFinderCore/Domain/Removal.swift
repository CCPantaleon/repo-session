import Foundation

public struct SelectionState: Sendable {
    public var removalIDs: Set<UUID> = []
    public var keeperIDs: Set<UUID> = []
    public init() {}
}
public enum SelectionRule: Sendable {
    case keepNewest, keepOldest, preferredFolder(URL), selectedLocation(URL), allRedundant, clear
}

/// A reviewable intent, never proof that a file is still safe to trash.
public struct RemovalPlan: Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let groups: [DuplicateGroup]
    public let removalIDs: Set<UUID>
    public let estimatedLogicalBytes: Int64
    public var retainedFiles: [FileRecord] { groups.flatMap(\.files).filter { !removalIDs.contains($0.id) } }
    public var removalFiles: [FileRecord] { groups.flatMap(\.files).filter { removalIDs.contains($0.id) } }

    public init(groups: [DuplicateGroup], removalIDs: Set<UUID>) throws {
        let files = groups.flatMap(\.files)
        guard !removalIDs.isEmpty, Set(groups.map(\.id)).count == groups.count,
              Set(files.map(\.id)).count == files.count,
              Set(files.map { $0.snapshot.identity }).count == files.count,
              removalIDs.isSubset(of: Set(files.map(\.id))) else { throw DomainError.invalidSelection }
        for group in groups {
            guard !group.requiresRescan else { throw EngineError.changed }
            guard group.files.contains(where: { !removalIDs.contains($0.id) }) else {
                throw DomainError.noRetainedCopy
            }
        }
        var total: Int64 = 0
        for file in files where removalIDs.contains(file.id) {
            let (next, overflow) = total.addingReportingOverflow(file.snapshot.logicalBytes)
            guard !overflow else { throw DomainError.sizeOverflow }; total = next
        }
        id = UUID(); createdAt = Date(); self.groups = groups; self.removalIDs = removalIDs
        estimatedLogicalBytes = total
    }
}
public enum RemovalOutcome: String, Codable, Sendable { case trashed, failed, skipped }
public struct RemovalItemResult: Codable, Sendable {
    public let fileID: UUID
    public let originalURL: URL
    public let trashURL: URL?
    public let outcome: RemovalOutcome
    public let message: String
    public let requiresRescan: Bool?
    public init(fileID: UUID, originalURL: URL, trashURL: URL?, outcome: RemovalOutcome, message: String, requiresRescan: Bool = false) {
        self.fileID = fileID; self.originalURL = originalURL; self.trashURL = trashURL
        self.outcome = outcome; self.message = message; self.requiresRescan = requiresRescan
    }
}
public struct RemovalResult: Codable, Sendable {
    public let planID: UUID
    public let finishedAt: Date
    public let items: [RemovalItemResult]
    public init(planID: UUID, finishedAt: Date, items: [RemovalItemResult]) {
        self.planID = planID; self.finishedAt = finishedAt; self.items = items
    }
}
