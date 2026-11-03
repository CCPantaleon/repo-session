import Foundation

public struct SavedLocation: Identifiable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var bookmark: Data
    public init(name: String, bookmark: Data) { id = UUID(); self.name = name; self.bookmark = bookmark }
}
public struct UserPreferences: Codable, Sendable {
    public var schemaVersion = 1
    public var minimumBytes: Int64 = 1
    public var extensions: Set<String> = []
    public var categories: Set<FileCategory> = Set(FileCategory.allCases)
    public var excludedBookmarks: [Data] = []
    public var preferredFolderBookmark: Data?
    public var showInspector = true
    public var useGrid = false
    public init() {}
}
public protocol ScanRepository: Sendable {
    func save(_ session: ScanSession) async throws
    func history() async throws -> [ScanSession]
    func ingest(_ files: [FileRecord], sessionID: UUID) async throws
    func saveGroups(_ groups: [DuplicateGroup], sessionID: UUID) async throws
    /// For bounded review/detail batches only; primary list uses summaries and member paging.
    func groups(sessionID: UUID, query: ResultQuery) async throws -> [DuplicateGroup]
    func groupSummaries(sessionID: UUID, query: ResultQuery) async throws -> [DuplicateGroupSummary]
    func members(groupID: UUID, cursor: String?, limit: Int) async throws -> FilePage
    func issues(sessionID: UUID, offset: Int, limit: Int) async throws -> [ScanIssue]
}
public protocol PreferencesRepository: Sendable {
    func load() async throws -> UserPreferences
    func save(_ preferences: UserPreferences) async throws
    func savedLocations() async throws -> [SavedLocation]
    func saveLocations(_ locations: [SavedLocation]) async throws
}
public enum JournalState: String, Codable, Sendable { case intent, completed, failed, skipped, needsReview }
public struct RemovalJournalEntry: Codable, Sendable {
    public let operationID: UUID
    public let planID: UUID
    public let fileID: UUID
    public let timestamp: Date
    public let state: JournalState
    public let result: RemovalItemResult?
    public init(operationID: UUID, planID: UUID, fileID: UUID, timestamp: Date,
                state: JournalState, result: RemovalItemResult? = nil) {
        self.operationID = operationID; self.planID = planID; self.fileID = fileID
        self.timestamp = timestamp; self.state = state; self.result = result
    }
}
public protocol RemovalJournal: Sendable {
    func appendDurably(_ entry: RemovalJournalEntry) async throws
    func unresolvedIntents() async throws -> [RemovalJournalEntry]
}

/// SQL-backed staging index shared by enumeration and detection; no in-memory global buckets.
public protocol CandidateIndex: Sendable {
    /// Cursor is an opaque stable row key. Only size buckets with distinct identities > 1 qualify.
    func sizeCandidates(sessionID: UUID, cursor: String?, limit: Int) async throws -> FilePage
    func storeFingerprint(fileID: UUID, sessionID: UUID, fingerprint: Data) async throws
    func storeVerifiedHash(fileID: UUID, sessionID: UUID, result: HashResult) async throws
    /// Build group/member rows using indexed full-digest + size + distinct identity queries.
    func finalizeExactGroups(sessionID: UUID) async throws
}
