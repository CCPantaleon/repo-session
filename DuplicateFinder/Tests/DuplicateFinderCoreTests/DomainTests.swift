import Foundation
import Testing
@testable import DuplicateFinderCore

private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
private func digest(_ character: Character = "a") throws -> ContentDigest {
    try ContentDigest(sha256: String(repeating: String(character), count: 64))
}
private func file(_ name: String, identity: String? = nil, bytes: Int64 = 12,
                  verification: VerificationStatus? = nil) throws -> FileRecord {
    FileRecord(url: URL(fileURLWithPath: "/test-fixtures/\(name)"),
               snapshot: FileSnapshot(identity: FileIdentity(volumeID: "test-volume", resourceID: identity ?? name),
                                      logicalBytes: bytes, modifiedAt: fixedDate, metadataChangedAt: fixedDate),
               category: .documents, verification: try verification ?? .exact(digest(), verifiedAt: fixedDate))
}

struct DomainTests {
    @Test func digestRequiresCanonicalSHA256() throws {
        #expect(throws: DomainError.invalidDigest) { try ContentDigest(sha256: "abc") }
        #expect(throws: DomainError.invalidDigest) { try ContentDigest(sha256: String(repeating: "Z", count: 64)) }
        #expect(try digest().sha256.count == 64)
    }
    @Test func decodingCannotBypassDigestValidation() {
        let malformed = Data(#"{"sha256":"invalid"}"#.utf8)
        #expect(throws: DomainError.invalidDigest) { try JSONDecoder().decode(ContentDigest.self, from: malformed) }
    }
    @Test func differentNamesCanBelongToExactGroup() throws {
        let group = try DuplicateGroup(files: [file("one.raw"), file("two.bin")], digest: digest())
        #expect(group.files.count == 2)
        #expect(group.redundantLogicalBytes == 12)
    }
    @Test func hardLinkIdentityCannotCountAsAnotherCopy() throws {
        let files = try [file("one", identity: "same-inode"), file("two", identity: "same-inode")]
        #expect(throws: DomainError.invalidGroup) { try DuplicateGroup(files: files, digest: digest()) }
    }
    @Test func unverifiedOrChangedFilesAreRejected() throws {
        for status in [VerificationStatus.unverified, .changed] {
            let files = try [file("one"), file("two", verification: status)]
            #expect(throws: DomainError.invalidGroup) { try DuplicateGroup(files: files, digest: digest()) }
        }
    }
    @Test func differingHashesAndSizesAreRejected() throws {
        let differentHash = try [file("one"), file("two", verification: .exact(digest("b"), verifiedAt: fixedDate))]
        #expect(throws: DomainError.invalidGroup) { try DuplicateGroup(files: differentHash, digest: digest()) }
        let differentSize = try [file("one"), file("two", bytes: 99)]
        #expect(throws: DomainError.invalidGroup) { try DuplicateGroup(files: differentSize, digest: digest()) }
    }
    @Test func byteEstimatesCannotOverflow() throws {
        let files = try [file("one", bytes: .max), file("two", bytes: .max), file("three", bytes: .max)]
        #expect(throws: DomainError.sizeOverflow) { try DuplicateGroup(files: files, digest: digest()) }
    }
    @Test func reviewAlwaysRetainsOneCopy() throws {
        let group = try DuplicateGroup(files: [file("one"), file("two")], digest: digest())
        #expect(throws: DomainError.noRetainedCopy) {
            try RemovalPlan(groups: [group], removalIDs: Set(group.files.map(\.id)))
        }
        let plan = try RemovalPlan(groups: [group], removalIDs: [group.files[0].id])
        #expect(plan.retainedFiles.map(\.id) == [group.files[1].id])
        #expect(plan.estimatedLogicalBytes == 12)
    }
    @Test func invalidAndCrossGroupSelectionsAreRejected() throws {
        let group = try DuplicateGroup(files: [file("one"), file("two")], digest: digest())
        #expect(throws: DomainError.invalidSelection) { try RemovalPlan(groups: [group], removalIDs: [UUID()]) }
        #expect(throws: DomainError.invalidSelection) { try RemovalPlan(groups: [group], removalIDs: []) }
        #expect(throws: DomainError.invalidSelection) { try RemovalPlan(groups: [group, group], removalIDs: [group.files[0].id]) }
    }
}
