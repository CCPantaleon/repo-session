import Foundation
import Darwin
import Testing
@testable import DuplicateFinderCore
struct ScaleTests {
    @Test func fiveThousandFiles() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        for n in 0..<5000 { try Data(String(format:"%08d",n).utf8).write(to:root.appendingPathComponent("file-\(n).txt")) }
        try FileManager.default.copyItem(at:root.appendingPathComponent("file-0.txt"),to:root.appendingPathComponent("copy.txt"))
        let start = Date()
        let groups = try LocalScanCoordinator.scan(ScanConfiguration(scope:.folders([root])))
        #expect(groups.count == 1); #expect(groups[0].files.count == 2)
        var usage = rusage(); getrusage(RUSAGE_SELF,&usage)
        print("PROFILE: 5001 files, scan seconds \(Date().timeIntervalSince(start)), process peak RSS bytes \(usage.ru_maxrss)")
    }
}
