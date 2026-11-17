import Foundation

/// Where deleted Items go. A protocol so tests never touch the user's real Trash.
public protocol Trasher: Sendable {
    func trash(_ url: URL) throws
}

/// Moves Items to the macOS Trash, from where the user can restore them.
public struct SystemTrasher: Trasher {
    public init() {}

    public func trash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }
}

public enum TransferMode: Sendable {
    case copy
    /// Completes a Cut: the source is removed once the Item is at its destination.
    case move
}

public enum ConflictChoice: Sendable {
    case replace, keepBoth, skip
}

public enum FileOperationError: LocalizedError, Equatable {
    case destinationInsideSource(String)
    case nameTaken(String)
    case invalidName(String)

    public var errorDescription: String? {
        switch self {
        case .destinationInsideSource(let name):
            return "“\(name)” cannot be placed inside itself."
        case .nameTaken(let name):
            return "The name “\(name)” is already taken in this folder."
        case .invalidName(let name):
            return "“\(name)” is not a valid name."
        }
    }
}

public struct TransferFailure {
    public let source: URL
    public let error: Error
}

public struct TransferResult {
    public var completed: [URL] = []
    public var skipped: [URL] = []
    public var failures: [TransferFailure] = []
}

public struct FileOperations {
    private let trasher: Trasher
    private let sameDrive: @Sendable (URL, URL) -> Bool
    private var fm: FileManager { .default }

    public init(trasher: Trasher = SystemTrasher(), sameDrive: (@Sendable (URL, URL) -> Bool)? = nil) {
        self.trasher = trasher
        self.sameDrive = sameDrive ?? Self.defaultSameDrive
    }

    /// Completes a Paste of `sources` into `folder`.
    /// `resolve` is asked once for every Conflict and receives the Item that is already there.
    public func transfer(
        _ sources: [URL], to folder: URL, mode: TransferMode,
        resolve: (URL) -> ConflictChoice
    ) -> TransferResult {
        var result = TransferResult()
        for source in sources {
            do {
                if let target = try transferOne(source, to: folder, mode: mode, resolve: resolve) {
                    result.completed.append(target)
                } else {
                    result.skipped.append(source)
                }
            } catch {
                result.failures.append(TransferFailure(source: source, error: error))
            }
        }
        return result
    }

    /// Returns the new URL, or `nil` when the Item was skipped.
    private func transferOne(
        _ source: URL, to folder: URL, mode: TransferMode,
        resolve: (URL) -> ConflictChoice
    ) throws -> URL? {
        let name = source.lastPathComponent
        if isSameOrInside(folder, ancestor: source) {
            throw FileOperationError.destinationInsideSource(name)
        }

        var target = folder.appendingPathComponent(name)
        let sourceParent = source.deletingLastPathComponent()
        if canonicalPath(sourceParent) == canonicalPath(folder) {
            // Paste into the folder the Item already lives in.
            if mode == .move { return nil }
            target = freeName(for: name, in: folder)
        } else if itemExists(target) {
            switch resolve(target) {
            case .skip:
                return nil
            case .keepBoth:
                target = freeName(for: name, in: folder)
            case .replace:
                // The old Item goes to Trash first, so a failed copy loses nothing.
                try trasher.trash(target)
            }
        }

        switch mode {
        case .copy:
            try fm.copyItem(at: source, to: target)
        case .move:
            if sameDrive(source, folder) {
                try fm.moveItem(at: source, to: target)
            } else {
                // Remove the source only after the copy has succeeded.
                try fm.copyItem(at: source, to: target)
                try fm.removeItem(at: source)
            }
        }
        return target
    }

    public func newFolder(in folder: URL, name: String = "New Folder") throws -> URL {
        var target = folder.appendingPathComponent(name)
        var counter = 2
        while itemExists(target) {
            target = folder.appendingPathComponent("\(name) \(counter)")
            counter += 1
        }
        try fm.createDirectory(at: target, withIntermediateDirectories: false)
        return target
    }

    public func rename(_ url: URL, to newName: String) throws -> URL {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "." || trimmed == ".." || trimmed.contains("/") {
            throw FileOperationError.invalidName(newName)
        }
        if trimmed == url.lastPathComponent { return url }
        let target = url.deletingLastPathComponent().appendingPathComponent(trimmed)
        // A change of letter case only is the same Item on a case-insensitive Drive.
        let caseChangeOnly = trimmed.lowercased() == url.lastPathComponent.lowercased()
        if itemExists(target) && !caseChangeOnly {
            throw FileOperationError.nameTaken(trimmed)
        }
        try fm.moveItem(at: url, to: target)
        return target
    }

    /// Moves Items to Trash and returns the ones that could not be moved.
    public func trash(_ urls: [URL]) -> [TransferFailure] {
        var failures: [TransferFailure] = []
        for url in urls {
            do { try trasher.trash(url) } catch {
                failures.append(TransferFailure(source: url, error: error))
            }
        }
        return failures
    }

    // MARK: - Helpers

    /// "note.txt" becomes "note copy.txt", then "note copy 2.txt".
    private func freeName(for name: String, in folder: URL) -> URL {
        let nsName = name as NSString
        let ext = nsName.pathExtension
        let base = ext.isEmpty ? name : nsName.deletingPathExtension
        var counter = 1
        while true {
            let suffix = counter == 1 ? " copy" : " copy \(counter)"
            let candidate = ext.isEmpty ? base + suffix : base + suffix + "." + ext
            let url = folder.appendingPathComponent(candidate)
            if !itemExists(url) { return url }
            counter += 1
        }
    }

    /// True for anything at that path, including a symlink whose target is gone.
    private func itemExists(_ url: URL) -> Bool {
        (try? fm.attributesOfItem(atPath: url.path)) != nil
    }

    private func canonicalPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func isSameOrInside(_ url: URL, ancestor: URL) -> Bool {
        let path = canonicalPath(url)
        let ancestorPath = canonicalPath(ancestor)
        return path == ancestorPath || path.hasPrefix(ancestorPath.hasSuffix("/") ? ancestorPath : ancestorPath + "/")
    }

    private static let defaultSameDrive: @Sendable (URL, URL) -> Bool = { a, b in
        let first = try? a.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        let second = try? b.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        guard let first, let second else { return true }
        return first.isEqual(second)
    }
}
