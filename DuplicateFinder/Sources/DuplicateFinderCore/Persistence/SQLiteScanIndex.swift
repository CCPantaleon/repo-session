import Foundation
import SQLite3

/// Confined to the scan's single utility worker. File contents never enter this database.
final class SQLiteScanIndex {
    private var database: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let transient = unsafeBitCast(-1,to:sqlite3_destructor_type.self)
    init(url: URL) throws {
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        guard sqlite3_open_v2(url.path,&database,SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE,nil) == SQLITE_OK else { throw EngineError.storage("Cannot open scan database") }
        let version = try statement("PRAGMA user_version")
        let validVersion = sqlite3_step(version) == SQLITE_ROW && sqlite3_column_int(version,0) <= 1
        sqlite3_finalize(version)
        guard validVersion else { sqlite3_close(database); database = nil; throw EngineError.storage("This scan database requires a newer app version") }
        try execute("PRAGMA journal_mode=DELETE; PRAGMA synchronous=FULL; CREATE TABLE IF NOT EXISTS files (id TEXT PRIMARY KEY, volume TEXT NOT NULL, resource TEXT NOT NULL, size INTEGER NOT NULL, record TEXT NOT NULL, digest TEXT, UNIQUE(volume,resource)); CREATE INDEX IF NOT EXISTS files_size ON files(size); CREATE INDEX IF NOT EXISTS files_digest ON files(digest); PRAGMA user_version=1;")
        try execute("BEGIN IMMEDIATE")
    }
    deinit { sqlite3_exec(database,"ROLLBACK",nil,nil,nil); sqlite3_close(database) }
    private func flush() throws { try execute("COMMIT; BEGIN IMMEDIATE") }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database,sql,nil,nil,nil) == SQLITE_OK else { throw failure() }
    }
    private func failure() -> EngineError { .storage("Scan database: \(String(cString:sqlite3_errmsg(database)))") }
    private func statement(_ sql: String) throws -> OpaquePointer {
        var s: OpaquePointer?
        guard sqlite3_prepare_v2(database,sql,-1,&s,nil) == SQLITE_OK, let s else { throw failure() }; return s
    }
    private func bind(_ value: String,_ position: Int32,_ s: OpaquePointer) throws {
        guard sqlite3_bind_text(s,position,value,-1,transient) == SQLITE_OK else { throw failure() }
    }
    func insert(_ file: FileRecord) throws -> Bool {
        let s = try statement("INSERT OR IGNORE INTO files(id,volume,resource,size,record) VALUES(?,?,?,?,?)"); defer { sqlite3_finalize(s) }
        try bind(file.id.uuidString,1,s); try bind(file.snapshot.identity.volumeID,2,s); try bind(file.snapshot.identity.resourceID,3,s)
        sqlite3_bind_int64(s,4,file.snapshot.logicalBytes)
        try bind(String(decoding:try encoder.encode(file),as:UTF8.self),5,s)
        guard sqlite3_step(s) == SQLITE_DONE else { throw failure() }
        return sqlite3_changes(database) == 1
    }
    func candidateCount() throws -> Int64 {
        try flush()
        let s = try statement("SELECT count(*) FROM files WHERE size IN (SELECT size FROM files GROUP BY size HAVING count(*) > 1)"); defer { sqlite3_finalize(s) }
        guard sqlite3_step(s) == SQLITE_ROW else { throw failure() }; return sqlite3_column_int64(s,0)
    }
    func candidates(_ visit: (FileRecord) throws -> Void) throws {
        let s = try statement("SELECT record FROM files WHERE size IN (SELECT size FROM files GROUP BY size HAVING count(*) > 1) ORDER BY rowid"); defer { sqlite3_finalize(s) }
        var rc = sqlite3_step(s)
        while rc == SQLITE_ROW {
            let record = try decoder.decode(FileRecord.self,from:Data(String(cString:sqlite3_column_text(s,0)).utf8))
            try visit(record); rc = sqlite3_step(s)
        }
        guard rc == SQLITE_DONE else { throw failure() }
    }
    func verified(_ file: FileRecord,digest: ContentDigest) throws {
        let s = try statement("UPDATE files SET digest=?,record=? WHERE id=?"); defer { sqlite3_finalize(s) }
        try bind(digest.sha256,1,s); try bind(String(decoding:try encoder.encode(file),as:UTF8.self),2,s); try bind(file.id.uuidString,3,s)
        guard sqlite3_step(s) == SQLITE_DONE else { throw failure() }
    }
    func groups(checkpoint: () throws -> Void) throws -> [DuplicateGroup] {
        try flush()
        let s = try statement("SELECT digest FROM files WHERE digest IS NOT NULL GROUP BY digest,size HAVING count(*) > 1"); defer { sqlite3_finalize(s) }
        var groups: [DuplicateGroup] = []
        var rc = sqlite3_step(s)
        while rc == SQLITE_ROW {
            try checkpoint()
            let digest = try ContentDigest(sha256:String(cString:sqlite3_column_text(s,0)))
            let members = try statement("SELECT record FROM files WHERE digest=? ORDER BY id"); defer { sqlite3_finalize(members) }
            try bind(digest.sha256,1,members)
            var records: [FileRecord] = []; var memberRC = sqlite3_step(members)
            while memberRC == SQLITE_ROW {
                try checkpoint()
                records.append(try decoder.decode(FileRecord.self,from:Data(String(cString:sqlite3_column_text(members,0)).utf8)))
                memberRC = sqlite3_step(members)
            }
            guard memberRC == SQLITE_DONE else { throw failure() }
            groups.append(try DuplicateGroup(files:records,digest:digest)); rc = sqlite3_step(s)
        }
        guard rc == SQLITE_DONE else { throw failure() }
        return groups.sorted { $0.redundantLogicalBytes > $1.redundantLogicalBytes }
    }
}
