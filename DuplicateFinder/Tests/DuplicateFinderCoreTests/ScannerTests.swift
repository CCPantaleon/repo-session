import Foundation
import Testing
@testable import DuplicateFinderCore
struct ScannerTests {
    func fixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true); return url
    }
    @Test func exactCopiesFiltersLinksAndOverlap() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at:root) }
        let sub = root.appendingPathComponent("sub"); try FileManager.default.createDirectory(at:sub,withIntermediateDirectories:true)
        try Data("same contents".utf8).write(to:root.appendingPathComponent("a.raw"))
        try Data("same contents".utf8).write(to:sub.appendingPathComponent("b.raw"))
        try Data("other content".utf8).write(to:sub.appendingPathComponent("a.raw"))
        try Data().write(to:root.appendingPathComponent("empty"))
        try FileManager.default.createSymbolicLink(at:sub.appendingPathComponent("loop"),withDestinationURL:root)
        try FileManager.default.linkItem(at:root.appendingPathComponent("a.raw"),to:root.appendingPathComponent("alias.raw"))
        let groups = try LocalScanCoordinator.scan(ScanConfiguration(scope:.folders([root,sub])))
        #expect(groups.count == 1); #expect(groups[0].files.count == 2)
        #expect(groups[0].files.allSatisfy { $0.category == .photos })
        var config = ScanConfiguration(scope:.folders([root])); config.minimumBytes = 100
        #expect(try LocalScanCoordinator.scan(config).isEmpty)
    }
    @Test func hashGoldenAndChangedFile() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at:root) }
        let url = root.appendingPathComponent("a"); try Data("abc".utf8).write(to:url)
        let record = FileRecord(url:url,snapshot:try LocalFiles.snapshot(url),category:.other)
        #expect(try LocalFiles.hash(record).digest.sha256 == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        try Data("xyz".utf8).write(to:url)
        #expect(throws: (any Error).self) { try LocalFiles.hash(record) }
    }
    @Test func cancellationAndMissingRoot() throws {
        let c = ScanControl(); c.cancel()
        #expect(throws: CancellationError.self) { try LocalScanCoordinator.scan(ScanConfiguration(scope:.homeFolder),control:c) }
        let root = try fixture(); try FileManager.default.removeItem(at:root)
        var issues = 0
        #expect(try LocalScanCoordinator.scan(ScanConfiguration(scope:.folders([root])),emit:{ if case .issue = $0 { issues += 1 } }).isEmpty)
        #expect(issues > 0)
    }
}
