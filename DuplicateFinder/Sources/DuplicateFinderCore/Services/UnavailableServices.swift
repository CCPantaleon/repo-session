import Foundation

public actor UnavailableScanCoordinator: ScanCoordinator {
    public init() {}
    public func start(_ configuration: ScanConfiguration) async throws -> AsyncThrowingStream<ScanEvent, Error> {
        throw FeatureUnavailable.scanning
    }
    public func pause() async throws { throw FeatureUnavailable.scanning }
    public func resume() async throws { throw FeatureUnavailable.scanning }
    public func cancel() async { /* No task exists in this placeholder. */ }
}
public struct UnavailableVolumeDiscovery: VolumeDiscoveryService {
    public init() {}
    public func externalVolumes() async throws -> [StorageVolume] { throw FeatureUnavailable.volumes }
}
public actor UnavailableSafeRemoval: SafeRemovalService {
    public init() {}
    public func execute(_ plan: RemovalPlan) async throws -> RemovalResult { throw FeatureUnavailable.removal }
    public func cancelRemaining() async { /* No operation exists in this placeholder. */ }
}
public struct UnavailableSelection: SelectionService {
    public init() {}
    public func suggest(_ rule: SelectionRule, groups: [DuplicateGroup], current: SelectionState) async throws -> SelectionState {
        throw FeatureUnavailable.selection
    }
    public func plan(groups: [DuplicateGroup], selection: SelectionState) async throws -> RemovalPlan {
        throw FeatureUnavailable.selection
    }
}
