import Foundation
import CryptoKit
import UniformTypeIdentifiers
import Darwin

public enum EngineError: Error, LocalizedError {
    case invalid(String), changed, inaccessible(String), storage(String), busy
    public var errorDescription: String? {
        switch self { case .invalid(let s), .inaccessible(let s), .storage(let s): s; case .changed: "File changed since scanning. Rescan before removal."; case .busy: "An operation is already running." }
    }
}
public enum LocalFiles {
    public static func contains(_ folder: URL, _ file: URL) -> Bool {
        file.standardizedFileURL.pathComponents.starts(with:folder.standardizedFileURL.pathComponents)
    }
    public static func snapshot(_ url: URL) throws -> FileSnapshot {
        var s = stat()
        guard lstat(url.path, &s) == 0 else { throw EngineError.inaccessible("Cannot access \(url.path): \(String(cString: strerror(errno)))") }
        guard s.st_flags & UInt32(SF_DATALESS) == 0 else { throw EngineError.invalid("Dataless cloud file skipped") }
        guard s.st_mode & S_IFMT == S_IFREG else { throw EngineError.invalid("Not a regular file: \(url.path)") }
        return snapshot(s)
    }
    static func snapshot(_ s: stat) -> FileSnapshot {
        FileSnapshot(identity: FileIdentity(volumeID: String(s.st_dev), resourceID: String(s.st_ino)), logicalBytes: s.st_size,
          allocatedBytes: Int64(s.st_blocks) * 512, linkCount: UInt64(s.st_nlink),
          modifiedAt: Date(timeIntervalSince1970: Double(s.st_mtimespec.tv_sec) + Double(s.st_mtimespec.tv_nsec) / 1e9),
          metadataChangedAt: Date(timeIntervalSince1970: Double(s.st_ctimespec.tv_sec) + Double(s.st_ctimespec.tv_nsec) / 1e9))
    }
    public static func category(_ url: URL) -> FileCategory {
        let ext = url.pathExtension.lowercased()
        if ["raw","cr2","cr3","nef","arw","dng","orf","raf","rw2"].contains(ext) { return .photos }
        if ["mov","mp4","m4v","avi","mkv","mts","m2ts","webm"].contains(ext) { return .videos }
        if ["jpg","jpeg","png","heic","heif","tif","tiff","gif","webp"].contains(ext) { return .photos }
        if ["mp3","wav","aif","aiff","flac","m4a","aac"].contains(ext) { return .audio }
        if ["txt","pdf","doc","docx","rtf","pages","csv","md"].contains(ext) { return .documents }
        guard let type = UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .image) { return .photos }; if type.conforms(to: .movie) { return .videos }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .text) || type.conforms(to: .pdf) || type.conforms(to: .content) { return .documents }
        return .other
    }
    public static func protected(_ url: URL) -> Bool {
        let p = url.standardizedFileURL.path
        let temp = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        if (p == "/private" || p.hasPrefix("/private/")), !contains(temp,url) { return true }
        let blocked = ["/System","/Library","/Applications","/usr","/bin","/sbin","/dev",NSHomeDirectory()+"/Library"]
        if blocked.contains(where: { p == $0 || p.hasPrefix($0+"/") }) { return true }
        return url.pathComponents.contains { component in
            let s = component.lowercased()
            return s.hasPrefix(".") || ["node_modules","lightroom"].contains(s) || ["app","photoslibrary","photolibrary","lrcat","lrdata","bundle","framework","pkg","backupdb"].contains((s as NSString).pathExtension)
        }
    }
    public static func hash(_ file: FileRecord, checkpoint: () throws -> Void = {}) throws -> HashResult {
        try checkpoint()
        guard !protected(file.url), file.url.resolvingSymlinksInPath().path == file.url.standardizedFileURL.path else { throw EngineError.invalid("Protected or symbolic-link path") }
        let values = try file.url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        if values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus != .current { throw EngineError.invalid("Cloud placeholder skipped") }
        let fd = open(file.url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw EngineError.inaccessible(file.url.path) }; defer { close(fd) }
        var before = stat(); guard fstat(fd,&before) == 0, snapshot(before) == file.snapshot else { throw EngineError.changed }
        var h = SHA256(); var buffer = [UInt8](repeating: 0, count: Int(max(1,min(file.snapshot.logicalBytes,1024*1024))))
        while true {
            try checkpoint()
            let n = read(fd, &buffer, buffer.count)
            if n < 0 { throw EngineError.inaccessible(file.url.path) }; if n == 0 { break }
            h.update(data: Data(buffer.prefix(n)))
        }
        var after = stat()
        guard fstat(fd,&after) == 0, snapshot(after) == file.snapshot, try snapshot(file.url) == file.snapshot else { throw EngineError.changed }
        return HashResult(digest: try ContentDigest(sha256: h.finalize().map { String(format:"%02x", $0) }.joined()), before: snapshot(before), after: snapshot(after))
    }
}

/// One utility worker owns blocking filesystem I/O. Condition checks bound cancellation to read chunks.
public final class ScanControl: @unchecked Sendable {
    private let condition = NSCondition(); private var cancelled = false; private var paused = false
    public init() {}
    public func cancel() { condition.lock(); cancelled = true; condition.broadcast(); condition.unlock() }
    public func pause(_ value: Bool) { condition.lock(); paused = value; condition.broadcast(); condition.unlock() }
    public func check() throws {
        condition.lock(); defer { condition.unlock() }
        while paused && !cancelled { condition.wait() }
        if cancelled { throw CancellationError() }
    }
}

public actor LocalScanCoordinator: ScanCoordinator {
    private var control: ScanControl?
    private var results: [DuplicateGroup] = []
    private var databaseURL: URL?
    public func persistedDatabase() -> URL? { databaseURL }
    public typealias RemovalPolicy = @Sendable (URL) -> String?
    private let storageDirectory: URL
    private let removalPolicy: RemovalPolicy
    public init(storageDirectory: URL = ScanArchiveStore.defaultDirectory,
                removalPolicy: @escaping RemovalPolicy = { LocalRemovalPolicy.restriction(for: $0) }) {
        self.storageDirectory = storageDirectory; self.removalPolicy = removalPolicy
    }
    public func groups() -> [DuplicateGroup] { results }
    public func start(_ configuration: ScanConfiguration) async throws -> AsyncThrowingStream<ScanEvent, Error> {
        guard control == nil else { throw EngineError.busy }
        guard configuration.minimumBytes >= 0, !configuration.categories.isEmpty else { throw EngineError.invalid("Choose valid file filters") }
        let c = ScanControl(); control = c; results = []
        let directory = storageDirectory
        let indexURL = directory.appendingPathComponent(UUID().uuidString+".sqlite")
        databaseURL = indexURL
        let removalPolicy = self.removalPolicy
        return AsyncThrowingStream(bufferingPolicy:.bufferingNewest(64)) { continuation in
            continuation.onTermination = { @Sendable _ in c.cancel() }
            DispatchQueue.global(qos: .utility).async {
                do {
                    let groups = try Self.scan(configuration, control: c, databaseURL:indexURL, removalPolicy: removalPolicy, emit: { continuation.yield($0) })
                    Task { await self.complete(groups); continuation.yield(.resultsChanged(sessionID: UUID())); continuation.finish() }
                } catch { Task { await self.complete([]); continuation.finish(throwing: error) } }
            }
        }
    }
    private func complete(_ groups: [DuplicateGroup]) { results = groups; control = nil }
    public func pause() { control?.pause(true) }
    public func resume() { control?.pause(false) }
    public func cancel() async {
        control?.cancel()
        while control != nil { try? await Task.sleep(for: .milliseconds(25)) }
    }
    public static func scan(_ config: ScanConfiguration, control: ScanControl = ScanControl(), databaseURL: URL? = nil, removalPolicy: RemovalPolicy = { LocalRemovalPolicy.restriction(for: $0) }, emit: @escaping (ScanEvent) -> Void = { _ in }) throws -> [DuplicateGroup] {
        var roots: [URL]
        switch config.scope {
        case .folders(let urls), .externalVolumes(let urls): roots = urls
        case .homeFolder: roots = [FileManager.default.homeDirectoryForCurrentUser]
        case .accessibleUserLocations: roots = ["Desktop","Documents","Downloads","Pictures","Movies","Music"].map { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent($0) }
        }
        guard !roots.isEmpty else { throw EngineError.invalid("Choose at least one folder") }
        roots = Array(Set(roots.map { $0.standardizedFileURL })).sorted { $0.path < $1.path }
        roots = roots.filter { root in !roots.contains { $0 != root && LocalFiles.contains($0,root) } }
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("DuplicateFinder-"+UUID().uuidString+".sqlite")
        let indexURL = databaseURL ?? scratch
        let index = try SQLiteScanIndex(url:indexURL)
        // Only app-created scratch metadata is cleaned up; user file data is never removed here.
        defer { if databaseURL == nil { try? FileManager.default.removeItem(at:scratch) } }
        var discovered: Int64 = 0; var analyzed: Int64 = 0; var skipped: Int64 = 0; let started = Date()
        func issue(_ url: URL, _ reason: ScanIssue.Reason, _ text: String) { skipped += 1; emit(.issue(ScanIssue(url:url, reason:reason, message:text))) }
        func progress(_ phase: ScanPhase, _ url: URL?, _ candidates: Int64 = 0, _ bytes: Int64 = 0) {
            emit(.progress(ScanProgress(phase:phase,currentLocation:url,discovered:discovered,analyzed:analyzed,candidates:candidates,redundantLogicalBytes:bytes,skipped:skipped,elapsedSeconds:Date().timeIntervalSince(started))))
        }
        for root in roots {
            try control.check()
            guard !LocalFiles.protected(root), root.resolvingSymlinksInPath().path == root.path else { issue(root,.protected,"Protected root skipped: \(root.path)"); continue }
            var rootStat = stat()
            guard lstat(root.path,&rootStat) == 0, rootStat.st_mode & S_IFMT == S_IFDIR,
                  (try? root.resourceValues(forKeys:[.isPackageKey]).isPackage) != true else { issue(root,.inaccessible,"Root is unavailable or is a protected package"); continue }
            guard FileManager.default.isReadableFile(atPath:root.path), let enumerator = FileManager.default.enumerator(at:root, includingPropertiesForKeys:[.isDirectoryKey,.isPackageKey,.isSymbolicLinkKey,.isAliasFileKey,.isUbiquitousItemKey,.ubiquitousItemDownloadingStatusKey], options:[.skipsHiddenFiles], errorHandler:{ url,error in issue(url,.inaccessible,error.localizedDescription); return true }) else { issue(root,.inaccessible,"Cannot enumerate \(root.path)"); continue }
            while let url = enumerator.nextObject() as? URL {
                try control.check()
                do {
                    let v = try url.resourceValues(forKeys:[.isDirectoryKey,.isPackageKey,.isSymbolicLinkKey,.isAliasFileKey,.isUbiquitousItemKey,.ubiquitousItemDownloadingStatusKey])
                    if LocalFiles.protected(url) || v.isPackage == true || config.excludedFolders.contains(where:{ LocalFiles.contains($0,url) }) { enumerator.skipDescendants(); continue }
                    if v.isSymbolicLink == true || v.isAliasFile == true { enumerator.skipDescendants(); issue(url,.symbolicLink,"Link skipped"); continue }
                    if v.isDirectory == true {
                        var entry = stat()
                        if lstat(url.path,&entry) != 0 || entry.st_dev != rootStat.st_dev { enumerator.skipDescendants(); issue(url,.disconnected,"Unselected mount or unavailable directory skipped") }
                        continue
                    }
                    if v.isUbiquitousItem == true && v.ubiquitousItemDownloadingStatus != .current { issue(url,.placeholder,"Cloud placeholder skipped"); continue }
                    let snapshot = try LocalFiles.snapshot(url); discovered += 1
                    let category = LocalFiles.category(url)
                    guard snapshot.logicalBytes >= config.minimumBytes, config.categories.contains(category), config.extensions.isEmpty || config.extensions.contains(url.pathExtension.lowercased()) else { continue }
                    let created = try? url.resourceValues(forKeys:[.creationDateKey]).creationDate
                    if try !index.insert(FileRecord(url:url,snapshot:snapshot,createdAt:created,category:category,removalRestriction:removalPolicy(url))) { issue(url,.hardLinkAlias,"Hard-link alias skipped") }
                    if discovered % 100 == 0 { progress(.enumerating,url) }
                } catch EngineError.storage(let text) { throw EngineError.storage(text) }
                  catch { issue(url,.inaccessible,error.localizedDescription) }
            }
        }
        let candidates = try index.candidateCount()
        progress(.hashing,nil,candidates)
        try index.candidates { file in
            try control.check()
            do {
                let result = try LocalFiles.hash(file,checkpoint:control.check)
                let verified = FileRecord(id:file.id,url:file.url,snapshot:file.snapshot,createdAt:file.createdAt,category:file.category,verification:.exact(result.digest,verifiedAt:Date()),removalRestriction:file.removalRestriction)
                try index.verified(verified,digest:result.digest)
            } catch is CancellationError { throw CancellationError() }
              catch EngineError.storage(let text) { throw EngineError.storage(text) }
              catch { issue(file.url,.changed,error.localizedDescription) }
            analyzed += 1
            if analyzed % 25 == 0 || analyzed == candidates { progress(.hashing,file.url,candidates) }
        }
        let groups = try index.groups(checkpoint:control.check)
        progress(.completed,nil,candidates,groups.reduce(0){$0 + $1.redundantLogicalBytes})
        return groups
    }
}
public struct LocalVolumes: VolumeDiscoveryService {
    public init() {}
    public func externalVolumes() async throws -> [StorageVolume] {
        try (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys:[.volumeIsInternalKey,.volumeIsLocalKey,.volumeIsReadOnlyKey,.volumeNameKey],options:[]) ?? []).compactMap { url in
            let v = try url.resourceValues(forKeys:[.volumeIsInternalKey,.volumeIsLocalKey,.volumeIsReadOnlyKey,.volumeNameKey])
            guard v.volumeIsInternal == false, v.volumeIsLocal == true else { return nil }
            return StorageVolume(id:url.path,name:v.volumeName ?? url.lastPathComponent,url:url,isWritable:v.volumeIsReadOnly != true)
        }
    }
}

public enum SavedScanReader {
    public static func read(_ url: URL, directory folder: URL = ScanArchiveStore.defaultDirectory) async throws -> [DuplicateGroup] {
        guard LocalFiles.contains(folder,url), url.pathExtension == "sqlite", url.resolvingSymlinksInPath().path == url.standardizedFileURL.path,
              FileManager.default.fileExists(atPath:url.path) else { throw EngineError.invalid("Saved scan is unavailable") }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos:.utility).async {
                do { let index = try SQLiteScanIndex(url:url); continuation.resume(returning:try index.groups(checkpoint:{})) }
                catch { continuation.resume(throwing:error) }
            }
        }
    }
}
