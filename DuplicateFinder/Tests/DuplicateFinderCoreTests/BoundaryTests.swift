import Foundation
import Testing
@testable import DuplicateFinderCore

struct BoundaryTests {
    @Test func unavailableScannerCannotReportSuccess() async {
        do {
            _ = try await UnavailableScanCoordinator().start(ScanConfiguration(scope: .homeFolder))
            Issue.record("Placeholder scanner must throw")
        } catch { #expect(error as? FeatureUnavailable == .scanning) }
    }
    @Test func unavailableVolumesDoNotPretendNoDrivesExist() async {
        do {
            _ = try await UnavailableVolumeDiscovery().externalVolumes()
            Issue.record("Unavailable is not an empty list of volumes")
        } catch { #expect(error as? FeatureUnavailable == .volumes) }
    }
    @Test func unavailableSelectionCannotSuggestRemoval() async {
        do {
            _ = try await UnavailableSelection().suggest(.allRedundant, groups: [], current: SelectionState())
            Issue.record("Placeholder must not produce a selection")
        } catch { #expect(error as? FeatureUnavailable == .selection) }
    }
    @Test func unavailableRemovalLeavesTemporaryFilesUnchanged() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Test fixture cleanup only. Production has no permanent deletion API.
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = Data("temporary identical bytes".utf8)
        let hash = try ContentDigest(sha256: String(repeating: "a", count: 64)) // Fixture digest, not a hashing test.
        var records: [FileRecord] = []
        for name in ["one", "two"] {
            let url = directory.appendingPathComponent(name)
            try bytes.write(to: url)
            records.append(FileRecord(url: url,
                snapshot: FileSnapshot(identity: FileIdentity(volumeID: "fixture", resourceID: name),
                                       logicalBytes: Int64(bytes.count), modifiedAt: Date(), metadataChangedAt: Date()),
                category: .documents, verification: .exact(hash, verifiedAt: Date())))
        }
        let group = try DuplicateGroup(files: records, digest: hash)
        let plan = try RemovalPlan(groups: [group], removalIDs: [records[0].id])
        do { _ = try await UnavailableSafeRemoval().execute(plan); Issue.record("Removal must be unavailable") }
        catch { #expect(error as? FeatureUnavailable == .removal) }
        for record in records { #expect(try Data(contentsOf: record.url) == bytes) }
    }
}
