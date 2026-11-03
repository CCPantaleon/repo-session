import Foundation

public enum FeatureUnavailable: String, Error, LocalizedError, Sendable {
    case scanning, volumes, permissions, selection, removal, persistence, previews
    public var errorDescription: String? { "\(rawValue.capitalized) is not implemented in this architecture build." }
}
public struct EnumeratedFile: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
}
public enum EnumerationEvent: Sendable { case file(EnumeratedFile), issue(ScanIssue) }
public protocol FileEnumerationService: Sendable {
    /// Producer must use bounded buffering/backpressure; never silently drop files.
    func enumerate(_ configuration: ScanConfiguration) async throws -> AsyncThrowingStream<EnumerationEvent, Error>
}
public protocol FileMetadataService: Sendable {
    func record(for url: URL) async throws -> FileRecord
    func snapshot(for url: URL) async throws -> FileSnapshot
}
public struct HashResult: Sendable {
    public let digest: ContentDigest
    public let before: FileSnapshot
    public let after: FileSnapshot
    public init(digest: ContentDigest, before: FileSnapshot, after: FileSnapshot) {
        self.digest = digest; self.before = before; self.after = after
    }
}
public protocol FileHashingService: Sendable {
    /// Bounded reads on dedicated utility workers; cancellation between chunks.
    func hash(_ file: FileRecord) async throws -> HashResult
    /// Optimization only. A match can never establish equality.
    func partialFingerprint(_ file: FileRecord) async throws -> Data
}
public protocol DuplicateDetectionService: Sendable {
    func detect(sessionID: UUID) async throws
}
public protocol ScanCoordinator: Sendable {
    func start(_ configuration: ScanConfiguration) async throws -> AsyncThrowingStream<ScanEvent, Error>
    func pause() async throws
    func resume() async throws
    func cancel() async
}
public struct StorageVolume: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let url: URL
    public let isWritable: Bool
    public init(id: String, name: String, url: URL, isWritable: Bool) {
        self.id = id; self.name = name; self.url = url; self.isWritable = isWritable
    }
}
public protocol VolumeDiscoveryService: Sendable { func externalVolumes() async throws -> [StorageVolume] }
public enum AccessStatus: Sendable { case accessible, needsUserSelection, denied, unavailable }
public struct AccessLease: Hashable, Sendable {
    public let id: UUID
    public let url: URL
    public init(url: URL) { id = UUID(); self.url = url }
}
public protocol PermissionService: Sendable {
    func status(for url: URL) async -> AccessStatus
    func bookmark(for url: URL) async throws -> Data
    func acquire(bookmark: Data) async throws -> AccessLease
    func release(_ lease: AccessLease) async
}
public struct PreviewRequest: Hashable, Sendable {
    public let url: URL
    public let maximumPixels: Int
    public init(url: URL, maximumPixels: Int) { self.url = url; self.maximumPixels = maximumPixels }
}
public protocol PreviewService: Sendable {
    /// Encoded thumbnail bytes, not a full-resolution RAW image; UI decodes on demand.
    func thumbnail(_ request: PreviewRequest) async throws -> Data
}
public protocol SelectionService: Sendable {
    func suggest(_ rule: SelectionRule, groups: [DuplicateGroup], current: SelectionState) async throws -> SelectionState
    func plan(groups: [DuplicateGroup], selection: SelectionState) async throws -> RemovalPlan
}
public protocol SafeRemovalService: Sendable {
    /// Only called by explicit confirmation. Revalidate all retained and removed files.
    /// Serial execution; journal intent before each OS Trash call; never unlink/removeItem.
    func execute(_ plan: RemovalPlan) async throws -> RemovalResult
    func execute(_ plan: RemovalPlan, progress: @escaping @Sendable (RemovalProgress) -> Void) async throws -> RemovalResult
    func cancelRemaining() async
}

/// Deliberately separate future feature: must never feed V1 removal groups.
public protocol SimilarPhotoAnalysis: Sendable {
    func similarityCandidates(for file: FileRecord) async throws -> [UUID]
}

public extension SafeRemovalService {
    func execute(_ plan: RemovalPlan, progress: @escaping @Sendable (RemovalProgress) -> Void) async throws -> RemovalResult {
        try await execute(plan)
    }
}
