import Foundation
import Testing
@testable import DuplicateFinderCore
struct SQLiteIndexTests {
    @Test func persistsAndReopensVerifiedResults() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let db = root.appendingPathComponent("index.sqlite")
        let digest = try ContentDigest(sha256:String(repeating:"a",count:64))
        do {
            let index = try SQLiteScanIndex(url:db)
            for n in 0..<2 {
                let file = FileRecord(url:root.appendingPathComponent("\(n)"),snapshot:FileSnapshot(identity:FileIdentity(volumeID:"v",resourceID:"\(n)"),logicalBytes:8,modifiedAt:Date(),metadataChangedAt:Date()),category:.documents,verification:.exact(digest,verifiedAt:Date()))
                #expect(try index.insert(file)); #expect(try !index.insert(file))
                try index.verified(file,digest:digest)
            }
            #expect(try index.candidateCount() == 2)
            #expect(try index.groups(checkpoint:{}).count == 1)
        }
        let reopened = try SQLiteScanIndex(url:db)
        let groups = try reopened.groups(checkpoint:{})
        #expect(groups.count == 1); #expect(groups[0].files.count == 2)
    }
    @Test func indexesMoreThanPreviousScanLimit() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let index = try SQLiteScanIndex(url:root.appendingPathComponent("index.sqlite"))
        let date = Date()
        for n in 0..<100_001 {
            let file = FileRecord(url:root.appendingPathComponent("\(n)"),snapshot:FileSnapshot(identity:FileIdentity(volumeID:"v",resourceID:"\(n)"),logicalBytes:Int64(n),modifiedAt:date,metadataChangedAt:date),category:.other)
            _ = try index.insert(file)
        }
        #expect(try index.candidateCount() == 0)
    }
}
