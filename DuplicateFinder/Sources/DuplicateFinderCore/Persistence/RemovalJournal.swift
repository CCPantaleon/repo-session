import Foundation
import Darwin
import SQLite3

public struct RemovalAuditEntry: Codable, Identifiable, Sendable {
    public var id: String { plan.uuidString + ":" + file.id.uuidString }
    public let plan: UUID
    public let file: FileRecord
    public let keepers: [FileRecord]
    public let state: String
    public let result: RemovalItemResult?
    public let date: Date
    public var needsInspection: Bool { state == "intent" }
    public init(plan: UUID, file: FileRecord, keepers: [FileRecord], state: String, result: RemovalItemResult?, date: Date) {
        self.plan = plan; self.file = file; self.keepers = keepers; self.state = state; self.result = result; self.date = date
    }
}
public struct RemovalJournalSnapshot: Sendable {
    public let entries: [RemovalAuditEntry]
    public let unreadableLines: Int
    public let totalCount: Int
    public let unresolvedCount: Int
}
public struct LocalRemovalJournal: Sendable {
    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DuplicateFinder/removal-audit.jsonl")
    }
    public let url: URL
    public var archiveDirectory: URL { url.deletingLastPathComponent().appendingPathComponent("Removal Log Archives") }
    public init(url: URL) { self.url = url }

    /// All app instances serialize appends/reads/compaction through the same stable lock file.
    private func locked<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(url.path + ".lock", O_RDWR | O_CREAT | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw EngineError.storage("Cannot open operation-history lock") }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw EngineError.storage("Cannot lock operation history") }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }
    private func writeAll(_ data: Data, to fd: Int32) throws {
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let n = write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw EngineError.storage("Cannot persist removal audit log") }
                offset += n
            }
        }
    }
    public func append(_ record: RemovalAuditEntry) throws {
        try locked {
            var data = try JSONEncoder().encode(record); data.append(10)
            let fd = open(url.path, O_RDWR | O_CREAT | O_APPEND | O_NOFOLLOW, S_IRUSR | S_IWUSR)
            guard fd >= 0 else { throw EngineError.storage("Cannot open removal audit log") }
            defer { close(fd) }
            var info = stat()
            guard fstat(fd, &info) == 0 else { throw EngineError.storage("Cannot inspect removal audit log") }
            if info.st_size > 0 {
                var last: UInt8 = 0
                guard pread(fd, &last, 1, info.st_size - 1) == 1 else { throw EngineError.storage("Cannot inspect removal audit log") }
                if last != 10 { data.insert(10, at: 0) }
            }
            try writeAll(data, to: fd)
            guard fsync(fd) == 0 else { throw EngineError.storage("Cannot synchronize removal audit log") }
        }
    }
    /// Pages are bounded even when there are many unresolved operations. The full set stays on disk.
    public func read(limit: Int = 200, offset: Int = 0) throws -> RemovalJournalSnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return RemovalJournalSnapshot(entries: [], unreadableLines: 0, totalCount: 0, unresolvedCount: 0)
        }
        return try locked {
            let index = try JournalReadIndex(source: url)
            return RemovalJournalSnapshot(entries: try index.page(limit: min(500, max(0, limit)), offset: max(0, offset)),
                                          unreadableLines: index.unreadableLines, totalCount: try index.count(), unresolvedCount: try index.count(unresolved: true))
        }
    }
    /// A compacted active log is self-contained: every unresolved intent plus recent completed outcomes.
    /// Archives are historical copies, never replayed into the live state (which could resurrect old intents).
    public func compactIfNeeded(maximumBytes: Int64 = 8 * 1024 * 1024, completedToKeep: Int = 1000, archivesToKeep: Int = 3) throws {
        try locked {
            let fm = FileManager.default
            guard fm.fileExists(atPath: url.path),
                  let size = try fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber,
                  size.int64Value > maximumBytes else { return }
            let index = try JournalReadIndex(source: url)
            // Unknown records may contain recovery evidence; never discard or rotate them away.
            guard index.unreadableLines == 0 else { return }
            let temporary = url.deletingLastPathComponent().appendingPathComponent(".audit-snapshot-" + UUID().uuidString)
            defer { try? fm.removeItem(at: temporary) }
            let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
            guard fd >= 0 else { throw EngineError.storage("Cannot prepare operation-history snapshot") }
            do {
                try index.visitSnapshot(completedLimit: max(0, completedToKeep)) { bytes in
                    var line = bytes; line.append(10); try writeAll(line, to: fd)
                }
                guard fsync(fd) == 0 else { throw EngineError.storage("Cannot synchronize operation-history snapshot") }
                close(fd)
            } catch { close(fd); throw error }
            let compactedSize = (try fm.attributesOfItem(atPath: temporary.path)[.size] as? NSNumber)?.int64Value ?? size.int64Value
            // Preserve all unresolved data even if it alone exceeds the target size; avoid pointless rotations.
            guard compactedSize < size.int64Value * 3 / 4 else { return }
            try fm.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
            let stamp = String(format: "%020.0f", Date().timeIntervalSince1970 * 1_000_000)
            let archive = archiveDirectory.appendingPathComponent("audit-" + stamp + "-" + UUID().uuidString + ".jsonl")
            let staging = archive.appendingPathExtension("tmp")
            defer { try? fm.removeItem(at: staging) }
            try fm.copyItem(at: url, to: staging)
            let archived = try FileHandle(forWritingTo: staging)
            try archived.synchronize(); try archived.close()
            try fm.moveItem(at: staging, to: archive)
            guard rename(temporary.path, url.path) == 0 else { throw EngineError.storage("Cannot replace compacted operation history") }
            let parentFD = open(url.deletingLastPathComponent().path, O_RDONLY)
            if parentFD >= 0 { _ = fsync(parentFD); close(parentFD) }
            // Only after the self-contained active snapshot is durable may older archives be removed.
            let archives = try fm.contentsOfDirectory(at: archiveDirectory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                .filter { item in
                    guard item.lastPathComponent.hasPrefix("audit-"), item.pathExtension == "jsonl", let values = try? item.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
                    return values.isRegularFile == true && values.isSymbolicLink != true
                }.sorted { $0.lastPathComponent > $1.lastPathComponent }
            for old in archives.dropFirst(max(1, archivesToKeep)) { try fm.removeItem(at: old) }
        }
    }
}

/// A temporary SQLite index keeps reading and compaction memory bounded by a page and a single record.
/// It is discarded after each operation; the durable JSONL file remains the source of truth.
private final class JournalReadIndex {
    private var db: OpaquePointer?
    private let temporary: URL
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private(set) var unreadableLines = 0
    init(source: URL) throws {
        temporary = FileManager.default.temporaryDirectory.appendingPathComponent("DuplicateFinderAudit-" + UUID().uuidString + ".sqlite")
        guard sqlite3_open(temporary.path, &db) == SQLITE_OK else { throw EngineError.storage("Cannot index operation history") }
        try execute("PRAGMA journal_mode=OFF; PRAGMA synchronous=OFF; PRAGMA cache_size=-1024; PRAGMA temp_store=FILE; CREATE TABLE entries(id TEXT PRIMARY KEY,state TEXT NOT NULL,date REAL NOT NULL,record BLOB NOT NULL); BEGIN;")
        let insert = try statement("INSERT INTO entries VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET state=excluded.state,date=excluded.date,record=excluded.record")
        defer { sqlite3_finalize(insert) }
        let fd = open(source.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw EngineError.storage("Cannot read operation history") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        let decoder = JSONDecoder()
        var pending = Data(), discardingOversizedLine = false
        let maximumLineBytes = 16 * 1024 * 1024
        func consume(_ data: Data) throws {
            guard !data.isEmpty else { return }
            guard let entry = try? decoder.decode(RemovalAuditEntry.self, from: data) else { unreadableLines += 1; return }
            sqlite3_reset(insert); sqlite3_clear_bindings(insert)
            guard sqlite3_bind_text(insert, 1, entry.id, -1, transient) == SQLITE_OK,
                  sqlite3_bind_text(insert, 2, entry.state, -1, transient) == SQLITE_OK,
                  sqlite3_bind_double(insert, 3, entry.date.timeIntervalSince1970) == SQLITE_OK else { throw failure() }
            let rc = data.withUnsafeBytes { sqlite3_bind_blob(insert, 4, $0.baseAddress, Int32($0.count), transient) }
            guard rc == SQLITE_OK, sqlite3_step(insert) == SQLITE_DONE else { throw failure() }
        }
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            pending.append(chunk)
            while let newline = pending.firstIndex(of: 10) {
                let count = pending.distance(from: pending.startIndex, to: newline)
                if discardingOversizedLine { discardingOversizedLine = false }
                else if count > maximumLineBytes { unreadableLines += 1 }
                else { try consume(Data(pending[..<newline])) }
                pending.removeSubrange(...newline)
            }
            if pending.count > maximumLineBytes || discardingOversizedLine {
                if !discardingOversizedLine { unreadableLines += 1 }
                pending.removeAll(keepingCapacity: false); discardingOversizedLine = true
            }
        }
        if !pending.isEmpty && !discardingOversizedLine { try consume(pending) }
        try execute("COMMIT; CREATE INDEX entries_state_date ON entries(state,date);")
    }
    deinit { sqlite3_close(db); try? FileManager.default.removeItem(at: temporary) }
    private func failure() -> EngineError { .storage("Operation history: " + String(cString: sqlite3_errmsg(db))) }
    private func execute(_ sql: String) throws { guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw failure() } }
    private func statement(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw failure() }; return stmt
    }
    func count(unresolved: Bool = false) throws -> Int {
        let stmt = try statement("SELECT count(*) FROM entries" + (unresolved ? " WHERE state='intent'" : "")); defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { throw failure() }; return Int(sqlite3_column_int64(stmt, 0))
    }
    func page(limit: Int, offset: Int) throws -> [RemovalAuditEntry] {
        let stmt = try statement("SELECT record FROM entries ORDER BY (state='intent') DESC,date DESC,id LIMIT ? OFFSET ?"); defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(limit)); sqlite3_bind_int64(stmt, 2, Int64(offset))
        var entries: [RemovalAuditEntry] = [], rc = sqlite3_step(stmt)
        while rc == SQLITE_ROW {
            let data = Data(bytes: sqlite3_column_blob(stmt, 0)!, count: Int(sqlite3_column_bytes(stmt, 0)))
            entries.append(try JSONDecoder().decode(RemovalAuditEntry.self, from: data)); rc = sqlite3_step(stmt)
        }
        guard rc == SQLITE_DONE else { throw failure() }; return entries
    }
    func visitSnapshot(completedLimit: Int, visit: (Data) throws -> Void) throws {
        let stmt = try statement("SELECT record FROM entries WHERE state='intent' UNION ALL SELECT record FROM (SELECT record FROM entries WHERE state!='intent' ORDER BY date DESC,id LIMIT ?)")
        defer { sqlite3_finalize(stmt) }; sqlite3_bind_int64(stmt, 1, Int64(completedLimit))
        var rc = sqlite3_step(stmt)
        while rc == SQLITE_ROW {
            try visit(Data(bytes: sqlite3_column_blob(stmt, 0)!, count: Int(sqlite3_column_bytes(stmt, 0)))); rc = sqlite3_step(stmt)
        }
        guard rc == SQLITE_DONE else { throw failure() }
    }
}
