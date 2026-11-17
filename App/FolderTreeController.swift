import AppKit
import ThisMacCore

final class TreeNode: NSObject {
    enum Kind {
        case quickAccessHeader
        case quickFolder
        case thisMac
        case drive
        case folder
    }

    let kind: Kind
    let title: String
    let url: URL?
    /// `nil` until the node is expanded for the first time.
    var children: [TreeNode]?

    init(kind: Kind, title: String, url: URL?) {
        self.kind = kind
        self.title = title
        self.url = url
    }

    var isExpandable: Bool {
        switch kind {
        case .quickFolder: return false
        default: return true
        }
    }
}

/// The Folder Tree: Quick Access on top, then This Mac, its Drives and their Folders.
final class FolderTreeController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    weak var browser: BrowserWindowController?

    private let outline = NSOutlineView()
    private let lister = DirectoryLister()
    private let quickAccess = TreeNode(kind: .quickAccessHeader, title: "Quick Access", url: nil)
    private let thisMac = TreeNode(kind: .thisMac, title: "This Mac", url: nil)
    private var isSyncing = false

    override func loadView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("tree"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.style = .sourceList
        outline.rowSizeStyle = .default
        outline.autoresizesOutlineColumn = false
        outline.dataSource = self
        outline.delegate = self

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        view = scroll
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        rebuild()
    }

    /// Drops everything that was loaded and builds the tree again, for example after Hidden Items changes.
    func rebuild() {
        quickAccess.children = QuickFolder.all().map {
            TreeNode(kind: .quickFolder, title: $0.title, url: $0.url)
        }
        thisMac.children = Drives.mounted().map {
            TreeNode(kind: .drive, title: $0.name, url: $0.url)
        }
        outline.reloadData()
        outline.expandItem(quickAccess)
        outline.expandItem(thisMac)
    }

    /// Development aid: the visible rows as text, with the selected row marked.
    func describeRows() -> String {
        (0..<outline.numberOfRows).map { row in
            let node = outline.item(atRow: row) as? TreeNode
            let indent = String(repeating: "  ", count: outline.level(forRow: row))
            return (row == outline.selectedRow ? "> " : "  ") + indent + (node?.title ?? "?")
        }.joined(separator: "\n")
    }

    // MARK: - Following the current Location

    func reveal(_ location: Location) {
        isSyncing = true
        defer { isSyncing = false }
        outline.expandItem(quickAccess)
        outline.expandItem(thisMac)
        switch location {
        case .thisMac:
            select(thisMac)
        case .folder(let url):
            let target = url.standardizedFileURL
            if Settings.expandTree {
                expandAndSelect(target)
                return
            }
            // Keep the selection where the user clicked.
            if let current = outline.item(atRow: outline.selectedRow) as? TreeNode,
               current.url?.standardizedFileURL == target {
                return
            }
            if let node = loadedNode(for: target), outline.row(forItem: node) >= 0 {
                select(node)
            } else if let quick = quickAccess.children?.first(where: { $0.url?.standardizedFileURL == target }) {
                select(quick)
            } else {
                outline.deselectAll(nil)
            }
        }
    }

    /// Opens every branch down to the Folder, as File Explorer does with "Expand to open folder".
    private func expandAndSelect(_ url: URL) {
        guard let drive = driveNode(containing: url), let driveURL = drive.url else {
            outline.deselectAll(nil)
            return
        }
        var node = drive
        let remaining = url.pathComponents.dropFirst(driveURL.standardizedFileURL.pathComponents.count)
        for component in remaining {
            outline.expandItem(node)
            guard let next = loadChildren(of: node).first(where: { $0.url?.lastPathComponent == component })
            else { break }
            node = next
        }
        select(node)
    }

    /// Reloads the Folders under one node, if that node is already loaded in the tree.
    func refreshChildren(of url: URL) {
        guard let node = loadedNode(for: url), let old = node.children else { return }
        let fresh = folderNodes(in: url, reusing: old)
        if fresh.map(\.url) == old.map(\.url) { return }
        node.children = fresh
        isSyncing = true
        outline.reloadItem(node, reloadChildren: true)
        isSyncing = false
    }

    private func select(_ node: TreeNode) {
        let row = outline.row(forItem: node)
        guard row >= 0 else {
            outline.deselectAll(nil)
            return
        }
        outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        outline.scrollRowToVisible(row)
    }

    private func driveNode(containing url: URL) -> TreeNode? {
        let path = url.standardizedFileURL.path
        return (thisMac.children ?? [])
            .filter { node in
                guard let drivePath = node.url?.standardizedFileURL.path else { return false }
                return path == drivePath || path.hasPrefix(drivePath == "/" ? "/" : drivePath + "/")
            }
            .max { ($0.url?.path.count ?? 0) < ($1.url?.path.count ?? 0) }
    }

    private func loadedNode(for url: URL) -> TreeNode? {
        guard let drive = driveNode(containing: url), let driveURL = drive.url else { return nil }
        var node = drive
        let remaining = url.standardizedFileURL.pathComponents
            .dropFirst(driveURL.standardizedFileURL.pathComponents.count)
        for component in remaining {
            guard let next = node.children?.first(where: { $0.url?.lastPathComponent == component })
            else { return nil }
            node = next
        }
        return node
    }

    private func loadChildren(of node: TreeNode) -> [TreeNode] {
        if let children = node.children { return children }
        let children = node.url.map { folderNodes(in: $0, reusing: []) } ?? []
        node.children = children
        return children
    }

    private func folderNodes(in url: URL, reusing old: [TreeNode]) -> [TreeNode] {
        let entries = (try? lister.list(url, showHidden: Settings.showHidden)) ?? []
        return entries.filter(\.isFolder).map { entry in
            old.first { $0.url == entry.url } ?? TreeNode(kind: .folder, title: entry.name, url: entry.url)
        }
    }

    // MARK: - NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? TreeNode else { return 2 }
        return loadChildren(of: node).count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let node = item as? TreeNode else { return index == 0 ? quickAccess : thisMac }
        return loadChildren(of: node)[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? TreeNode)?.isExpandable ?? false
    }

    // MARK: - NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        (item as? TreeNode)?.kind == .quickAccessHeader
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        (item as? TreeNode)?.kind != .quickAccessHeader
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? TreeNode else { return nil }
        let identifier = NSUserInterfaceItemIdentifier(node.kind == .quickAccessHeader ? "header" : "row")
        let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            ?? makeCell(identifier, withIcon: node.kind != .quickAccessHeader)
        cell.textField?.stringValue = node.title
        cell.toolTip = node.url?.path
        switch node.kind {
        case .quickAccessHeader:
            break
        case .thisMac:
            cell.imageView?.image = Icons.computer
        default:
            cell.imageView?.image = node.url.map(Icons.forFile)
        }
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !isSyncing, let node = outline.item(atRow: outline.selectedRow) as? TreeNode else { return }
        switch node.kind {
        case .thisMac:
            browser?.navigate(to: .thisMac)
        case .quickAccessHeader:
            break
        default:
            if let url = node.url { browser?.navigate(to: .folder(url)) }
        }
    }

    private func makeCell(_ identifier: NSUserInterfaceItemIdentifier, withIcon: Bool) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label
        if withIcon {
            let icon = NSImageView()
            icon.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(icon)
            cell.imageView = icon
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 16),
                icon.heightAnchor.constraint(equalToConstant: 16),
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            ])
        } else {
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2).isActive = true
        }
        NSLayoutConstraint.activate([
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}
