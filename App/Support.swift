import AppKit
import ThisMacCore

/// What a window is showing: the This Mac page or one Folder.
enum Location: Equatable {
    case thisMac
    case folder(URL)

    var title: String {
        switch self {
        case .thisMac: return "This Mac"
        case .folder(let url):
            return url.path == "/" ? Location.name(of: url) : url.lastPathComponent
        }
    }

    static func name(of url: URL) -> String {
        FileManager.default.displayName(atPath: url.path)
    }
}

/// A Folder listed under Quick Access.
struct QuickFolder: Hashable {
    let title: String
    let url: URL

    static func all() -> [QuickFolder] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var folders = [
            QuickFolder(title: "Home", url: home),
            QuickFolder(title: "Desktop", url: home.appendingPathComponent("Desktop")),
            QuickFolder(title: "Documents", url: home.appendingPathComponent("Documents")),
            QuickFolder(title: "Downloads", url: home.appendingPathComponent("Downloads")),
        ]
        let iCloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if fm.fileExists(atPath: iCloud.path) {
            folders.append(QuickFolder(title: "iCloud Drive", url: iCloud))
        }
        return folders.filter { fm.fileExists(atPath: $0.url.path) }
    }
}

/// Remembers which Items are pending a Cut. The file URLs themselves live on the system pasteboard.
enum CutState {
    static var changeCount = -1
    static var urls: Set<URL> = []

    static var isActive: Bool { NSPasteboard.general.changeCount == changeCount }

    static func contains(_ url: URL) -> Bool { isActive && urls.contains(url) }

    static func clear() {
        changeCount = -1
        urls = []
    }
}

enum Settings {
    private static let defaults = UserDefaults.standard

    static var showHidden: Bool {
        get { defaults.bool(forKey: "showHidden") }
        set { defaults.set(newValue, forKey: "showHidden") }
    }

    /// Off by default, as in File Explorer: the Folder Tree only opens branches the user opens.
    static var expandTree: Bool {
        get { defaults.bool(forKey: "expandTree") }
        set { defaults.set(newValue, forKey: "expandTree") }
    }

    static var showPreview: Bool {
        get { defaults.object(forKey: "showPreview") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showPreview") }
    }
}

enum Format {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func date(_ date: Date?) -> String {
        date.map(dateFormatter.string(from:)) ?? ""
    }

    static func bytes(_ bytes: Int64?) -> String {
        guard let bytes else { return "" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

enum Icons {
    static func forFile(_ url: URL) -> NSImage {
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    static var computer: NSImage {
        let image = NSImage(named: NSImage.computerName) ?? NSImage()
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    static func symbol(_ name: String, _ description: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: description) ?? NSImage()
    }
}

/// Calls back shortly after the content of one Folder changes on disk.
final class FolderWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    func watch(_ url: URL?, onChange: @escaping () -> Void) {
        stop()
        guard let url else { return }
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .rename, .delete, .extend, .attrib], queue: .main)
        source.setEventHandler { [weak self] in
            self?.pending?.cancel()
            let work = DispatchWorkItem(block: onChange)
            self?.pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    func stop() {
        pending?.cancel()
        pending = nil
        source?.cancel()
        source = nil
    }

    deinit { stop() }
}
