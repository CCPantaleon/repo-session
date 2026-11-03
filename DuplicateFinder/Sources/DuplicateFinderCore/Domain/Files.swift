import Foundation

public enum FileCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case photos, videos, documents, audio, other
    public var id: Self { self }
    public var title: String { rawValue.capitalized }
}

/// Stable only within a mounted volume; never use a pathname as file identity.
public struct FileIdentity: Hashable, Codable, Sendable {
    public let volumeID: String
    public let resourceID: String
    public init(volumeID: String, resourceID: String) {
        self.volumeID = volumeID; self.resourceID = resourceID
    }
}

public struct FileSnapshot: Equatable, Codable, Sendable {
    public let identity: FileIdentity
    public let logicalBytes: Int64
    public let allocatedBytes: Int64?
    public let linkCount: UInt64
    public let modifiedAt: Date
    public let metadataChangedAt: Date
    public init(identity: FileIdentity, logicalBytes: Int64, allocatedBytes: Int64? = nil, linkCount: UInt64 = 1,
                modifiedAt: Date, metadataChangedAt: Date) {
        self.identity = identity; self.logicalBytes = logicalBytes
        self.allocatedBytes = allocatedBytes; self.linkCount = linkCount; self.modifiedAt = modifiedAt
        self.metadataChangedAt = metadataChangedAt
    }
}

public struct MediaMetadata: Codable, Sendable {
    public let width: Int?
    public let height: Int?
    public let camera: String?
    public let lens: String?
    public init(width: Int? = nil, height: Int? = nil, camera: String? = nil, lens: String? = nil) {
        self.width = width; self.height = height; self.camera = camera; self.lens = lens
    }
}

public struct ContentDigest: Hashable, Codable, Sendable {
    public let sha256: String
    public init(sha256: String) throws {
        guard sha256.count == 64, sha256.allSatisfy({ "0123456789abcdef".contains($0) }) else {
            throw DomainError.invalidDigest
        }
        self.sha256 = sha256
    }
    private enum CodingKeys: String, CodingKey { case sha256 }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(sha256: container.decode(String.self, forKey: .sha256))
    }
}

public enum VerificationStatus: Codable, Sendable, Equatable {
    case unverified
    case exact(ContentDigest, verifiedAt: Date)
    case changed
}

public struct FileRecord: Identifiable, Codable, Sendable {
    public let id: UUID
    public let url: URL
    public let snapshot: FileSnapshot
    public let createdAt: Date?
    public let category: FileCategory
    public let media: MediaMetadata?
    public let verification: VerificationStatus
    /// Nil means eligible at scan time; execution always checks the volume again.
    public let removalRestriction: String?
    public init(id: UUID = UUID(), url: URL, snapshot: FileSnapshot, createdAt: Date? = nil,
                category: FileCategory, media: MediaMetadata? = nil,
                verification: VerificationStatus = .unverified, removalRestriction: String? = nil) {
        self.id = id; self.url = url; self.snapshot = snapshot; self.createdAt = createdAt
        self.category = category; self.media = media; self.verification = verification; self.removalRestriction = removalRestriction
    }
}

public enum DomainError: Error, Equatable {
    case invalidDigest, invalidGroup, invalidSelection, noRetainedCopy, sizeOverflow
}

/// Construct only after full hashing; distinct hard links cannot enter one group.
/// Deliberately not Decodable: persisted results must be reconstructed and validated.
public struct DuplicateGroup: Identifiable, Sendable {
    public let id: UUID
    public let files: [FileRecord]
    public let digest: ContentDigest
    public let redundantLogicalBytes: Int64
    /// The original scan's membership is retained for inspection, not removal authorization.
    public let requiresRescan: Bool
    public init(id: UUID = UUID(), files: [FileRecord], digest: ContentDigest, requiresRescan: Bool = false) throws {
        guard files.count >= 2,
              Set(files.map(\.id)).count == files.count,
              Set(files.map { $0.snapshot.identity }).count == files.count,
              let size = files.first?.snapshot.logicalBytes, size >= 0,
              files.allSatisfy({ file in
                  guard file.snapshot.logicalBytes == size,
                        case .exact(let value, _) = file.verification else { return false }
                  return value == digest
              }) else { throw DomainError.invalidGroup }
        let (bytes, overflow) = size.multipliedReportingOverflow(by: Int64(files.count - 1))
        guard !overflow else { throw DomainError.sizeOverflow }
        self.id = id; self.files = files; self.digest = digest; self.requiresRescan = requiresRescan; redundantLogicalBytes = requiresRescan ? 0 : bytes
    }
}

/// Lightweight result rows. Never materialize an entire million-member group for a list row.
public struct DuplicateGroupSummary: Identifiable, Sendable {
    public let id: UUID
    public let representative: FileRecord
    public let copyCount: Int64
    public let redundantLogicalBytes: Int64
    public init(id: UUID, representative: FileRecord, copyCount: Int64, redundantLogicalBytes: Int64) {
        self.id = id; self.representative = representative; self.copyCount = copyCount
        self.redundantLogicalBytes = redundantLogicalBytes
    }
}
public struct FilePage: Sendable {
    public let files: [FileRecord]
    public let nextCursor: String?
    public init(files: [FileRecord], nextCursor: String?) { self.files = files; self.nextCursor = nextCursor }
}
