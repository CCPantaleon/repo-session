import Foundation
import Testing
@testable import DuplicateFinderCore
struct StressTests {
    @Test func largeVideoAndMutationDuringHash() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let a = root.appendingPathComponent("a.mov"), b = root.appendingPathComponent("b.mov")
        let handleURL = a
        FileManager.default.createFile(atPath:handleURL.path,contents:nil)
        let h = try FileHandle(forWritingTo:a)
        for _ in 0..<32 { try h.write(contentsOf:Data(repeating:7,count:1024*1024)) }; try h.close()
        try FileManager.default.copyItem(at:a,to:b)
        let groups = try LocalScanCoordinator.scan(ScanConfiguration(scope:.folders([root])))
        #expect(groups.count == 1); #expect(groups[0].files[0].category == .videos)
        let record = FileRecord(url:a,snapshot:try LocalFiles.snapshot(a),category:.videos)
        var chunks = 0
        #expect(throws:(any Error).self) {
            try LocalFiles.hash(record,checkpoint:{
                chunks += 1
                if chunks == 3 { let h = try FileHandle(forWritingTo:a); try h.write(contentsOf:Data([9])); try h.close() }
            })
        }
        let fresh = FileRecord(url:b,snapshot:try LocalFiles.snapshot(b),category:.videos)
        let control = ScanControl(); var count = 0
        #expect(throws:CancellationError.self) { try LocalFiles.hash(fresh,checkpoint:{ count += 1; if count == 3 { control.cancel() }; try control.check() }) }
    }
    @Test func emptyFilesAndExclusionsAndPackages() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        for name in ["one","two"] { try Data().write(to:root.appendingPathComponent(name)) }
        var config = ScanConfiguration(scope:.folders([root])); config.minimumBytes = 0
        #expect(try LocalScanCoordinator.scan(config).count == 1)
        config.excludedFolders = [root]
        #expect(try LocalScanCoordinator.scan(config).isEmpty)
    }
}
