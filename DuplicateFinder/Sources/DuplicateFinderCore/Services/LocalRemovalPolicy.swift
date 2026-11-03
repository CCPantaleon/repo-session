import Foundation

public enum LocalRemovalPolicy {
    public static func restriction(for url: URL) -> String? {
        do {
            let values = try url.resourceValues(forKeys: [.volumeIsLocalKey, .volumeIsInternalKey, .volumeIsReadOnlyKey])
            return restriction(isLocal: values.volumeIsLocal, isInternal: values.volumeIsInternal, isReadOnly: values.volumeIsReadOnly)
        } catch { return "Scan only: this volume is unavailable or its removal support could not be checked." }
    }
    public static func restriction(isLocal: Bool?, isInternal: Bool?, isReadOnly: Bool?) -> String? {
        guard isLocal == true, isInternal == true else {
            return "Scan only: removal is supported on internal local drives. External and network files are left in place."
        }
        guard isReadOnly == false else { return "Scan only: this volume is read-only or its write support is unknown." }
        return nil
    }
}
