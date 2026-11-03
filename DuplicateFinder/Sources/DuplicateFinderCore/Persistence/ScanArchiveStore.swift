import Foundation

public struct ScanArchiveStore: Sendable {
    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DuplicateFinder/Scans")
    }
    public let directory: URL
    public init(directory: URL = Self.defaultDirectory) { self.directory = directory }
    /// Deletes only UUID-named app indexes and their SQLite sidecars, never scanned originals.
    /// Call only while no scan or history reader is active.
    public func retainOnly(_ urls: Set<URL>) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return }
        guard directory.resolvingSymlinksInPath().path == directory.standardizedFileURL.path else {
            throw EngineError.storage("Saved scan folder is a symbolic link. No files were removed.")
        }
        let retained = Set(urls.map { $0.standardizedFileURL.path })
        let children = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        for url in children {
            let name = url.lastPathComponent
            guard let marker = name.range(of: ".sqlite"), UUID(uuidString: String(name[..<marker.lowerBound])) != nil,
                  ["", "-journal", "-wal", "-shm"].contains(String(name[marker.upperBound...])) else { continue }
            let database = directory.appendingPathComponent(String(name[...name.index(before: marker.upperBound)]))
            guard !retained.contains(database.standardizedFileURL.path) else { continue }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true, values.isRegularFile == true else { continue }
            try fm.removeItem(at: url)
        }
    }
}
