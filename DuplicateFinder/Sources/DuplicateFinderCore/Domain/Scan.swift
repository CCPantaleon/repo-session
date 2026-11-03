import Foundation

public enum ScanScope: Codable, Sendable {
    case accessibleUserLocations
    case homeFolder
    case folders([URL])
    case externalVolumes([URL])
}

public struct ScanConfiguration: Codable, Sendable {
    public var scope: ScanScope
    public var categories: Set<FileCategory> = Set(FileCategory.allCases)
    public var extensions: Set<String> = []
    public var minimumBytes: Int64 = 1
    public var excludedFolders: [URL] = []
    // V1 safety policy is not a user-toggle: no symlinks, packages or downloads of placeholders.
    public init(scope: ScanScope = .folders([])) { self.scope = scope }
}

public enum ScanPhase: String, Codable, Sendable {
    case ready, enumerating, sizing, fingerprinting, hashing, grouping, completed, cancelled, failed
}

public struct ScanProgress: Sendable {
    public let phase: ScanPhase
    public let currentLocation: URL?
    public let discovered: Int64
    public let analyzed: Int64
    public let candidates: Int64
    public let redundantLogicalBytes: Int64
    public let skipped: Int64
    public let elapsedSeconds: TimeInterval
    /// Nil until a stable denominator is available; no invented overall percentage.
    public let fraction: Double?
    public init(phase: ScanPhase, currentLocation: URL? = nil, discovered: Int64 = 0,
                analyzed: Int64 = 0, candidates: Int64 = 0, redundantLogicalBytes: Int64 = 0,
                skipped: Int64 = 0, elapsedSeconds: TimeInterval = 0, fraction: Double? = nil) {
        self.phase = phase; self.currentLocation = currentLocation; self.discovered = discovered
        self.analyzed = analyzed; self.candidates = candidates
        self.redundantLogicalBytes = redundantLogicalBytes; self.skipped = skipped
        self.elapsedSeconds = elapsedSeconds; self.fraction = fraction
    }
}

public struct ScanIssue: Identifiable, Codable, Sendable {
    public enum Reason: String, Codable, Sendable {
        case inaccessible, protected, symbolicLink, hardLinkAlias, placeholder, changed, disconnected, ioFailure
    }
    public let id: UUID
    public let url: URL
    public let reason: Reason
    public let message: String
    public init(url: URL, reason: Reason, message: String) {
        id = UUID(); self.url = url; self.reason = reason; self.message = message
    }
}

public struct ScanSession: Identifiable, Codable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public let configuration: ScanConfiguration
    public var phase: ScanPhase
    public init(configuration: ScanConfiguration) {
        id = UUID(); startedAt = Date(); self.configuration = configuration; phase = .ready
    }
}

/// Results stay behind a paged store; do not stream millions of records to the UI.
public struct ResultQuery: Sendable {
    public enum Sort: String, CaseIterable, Sendable, Identifiable {
        case wastedSpace, fileSize, name, created, modified, type, location, copies
        public var id: Self { self }
    }
    public var category: FileCategory?
    public var sort: Sort = .wastedSpace
    public var search: String = ""
    public var offset: Int = 0
    public var limit: Int = 100
    public init() {}
}
public enum ScanEvent: Sendable {
    case progress(ScanProgress)
    case issue(ScanIssue)
    case resultsChanged(sessionID: UUID)
    case finished(ScanSession)
}
