import Foundation

/// Anything listed inside a Folder: a file, a Package or another Folder.
public struct FileEntry: Hashable, Sendable {
    public let url: URL
    public let name: String
    /// A container the user can navigate into. A Package is not a Folder.
    public let isFolder: Bool
    public let isPackage: Bool
    public let isHidden: Bool
    public let isSymlink: Bool
    /// `nil` for Folders: their size is not computed.
    public let size: Int64?
    public let modified: Date?
    /// When the Item was put into its Folder. This is what "newest download" means.
    public let added: Date?
    public let kind: String
}

public enum SortKey: String, Sendable {
    case name, modified, added, kind, size

    /// Sorting by a date mixes Folders with other Items, so the newest Item is on top.
    public var keepsFoldersFirst: Bool { self != .modified && self != .added }
}

public struct DirectoryLister: Sendable {
    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .isHiddenKey, .isSymbolicLinkKey,
        .fileSizeKey, .contentModificationDateKey, .addedToDirectoryDateKey, .localizedTypeDescriptionKey,
    ]

    public init() {}

    /// Lists the Items of a Folder, Folders first, then by name.
    /// Throws when the Folder cannot be read, so callers can tell "empty" from "no permission".
    public func list(_ folder: URL, showHidden: Bool) throws -> [FileEntry] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: Self.keys, options: [])
        let entries = urls.compactMap(entry(for:)).filter { showHidden || !$0.isHidden }
        return Self.sorted(entries, by: .name, ascending: true)
    }

    public func entry(for url: URL) -> FileEntry? {
        guard let values = try? url.resourceValues(forKeys: Set(Self.keys)) else { return nil }
        let isSymlink = values.isSymbolicLink ?? false
        var isDirectory = values.isDirectory ?? false
        if isSymlink {
            // Resource values describe the link itself. Ask where it points.
            var target: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &target) {
                isDirectory = target.boolValue
            }
        }
        let isPackage = values.isPackage ?? false
        let isFolder = isDirectory && !isPackage
        return FileEntry(
            url: url,
            name: url.lastPathComponent,
            isFolder: isFolder,
            isPackage: isPackage,
            isHidden: values.isHidden ?? false,
            isSymlink: isSymlink,
            size: isFolder ? nil : values.fileSize.map(Int64.init),
            modified: values.contentModificationDate,
            added: values.addedToDirectoryDate,
            kind: values.localizedTypeDescription ?? (isFolder ? "Folder" : "Document"))
    }

    /// Folders come before other Items, except when sorting by a date.
    public static func sorted(_ entries: [FileEntry], by key: SortKey, ascending: Bool) -> [FileEntry] {
        entries.sorted { a, b in
            if key.keepsFoldersFirst, a.isFolder != b.isFolder { return a.isFolder }
            let order = compare(a, b, by: key)
            if order == .orderedSame {
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
    }

    private static func compare(_ a: FileEntry, _ b: FileEntry, by key: SortKey) -> ComparisonResult {
        switch key {
        case .name:
            return a.name.localizedStandardCompare(b.name)
        case .kind:
            return a.kind.localizedStandardCompare(b.kind)
        case .modified:
            return order(a.modified ?? .distantPast, b.modified ?? .distantPast)
        case .added:
            return order(a.added ?? a.modified ?? .distantPast, b.added ?? b.modified ?? .distantPast)
        case .size:
            return order(a.size ?? -1, b.size ?? -1)
        }
    }

    private static func order<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame)
    }
}
