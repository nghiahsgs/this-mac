import Foundation

/// A local storage volume that is currently mounted.
public struct Drive: Hashable, Sendable {
    public let url: URL
    public let name: String
    public let totalBytes: Int64
    public let availableBytes: Int64
    public let isInternal: Bool

    public var usedBytes: Int64 { max(0, totalBytes - availableBytes) }

    public var usedFraction: Double {
        totalBytes > 0 ? min(1, Double(usedBytes) / Double(totalBytes)) : 0
    }
}

public enum Drives {
    private static let keys: [URLResourceKey] = [
        .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
        .volumeAvailableCapacityForImportantUsageKey, .volumeIsInternalKey, .volumeIsLocalKey,
    ]

    /// Every local Drive the user can browse. Network volumes are left out.
    public static func mounted() -> [Drive] {
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsLocal ?? true
            else { return nil }
            let important = values.volumeAvailableCapacityForImportantUsage ?? 0
            let available = important > 0 ? important : Int64(values.volumeAvailableCapacity ?? 0)
            return Drive(
                url: url,
                name: values.volumeName ?? url.lastPathComponent,
                totalBytes: Int64(values.volumeTotalCapacity ?? 0),
                availableBytes: available,
                isInternal: values.volumeIsInternal ?? false)
        }
    }
}
