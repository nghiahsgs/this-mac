import AppKit
import ThisMacCore

final class DetailsTableView: NSTableView {
    weak var browser: BrowserWindowController?

    override func keyDown(with event: NSEvent) {
        let command = event.modifierFlags.contains(.command)
        switch event.keyCode {
        case 36, 76: // Return, Enter
            browser?.openSelection(nil)
        case 125 where command: // ⌘↓
            browser?.openSelection(nil)
        case 51: // Backspace
            if command { browser?.moveToTrash(nil) } else { browser?.goUp(nil) }
        case 117: // Forward delete (fn⌫)
            browser?.moveToTrash(nil)
        case 120: // F2
            browser?.renameSelection(nil)
        case 96: // F5
            browser?.refresh(nil)
        default:
            super.keyDown(with: event)
        }
    }
}

/// The Details List: the Items of the current Folder, Folders always first.
final class DetailsListController: NSViewController, NSTableViewDataSource, NSTableViewDelegate,
    NSTextFieldDelegate, NSMenuDelegate {
    weak var browser: BrowserWindowController?

    let tableView = DetailsTableView()
    private(set) var entries: [FileEntry] = []
    private var sortKey: SortKey = .name
    private var ascending = true
    private var folder: URL?
    private var isApplyingSort = false

    private let messageStack = NSStackView()
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let settingsButton = NSButton(title: "Open Privacy Settings", target: nil, action: nil)

    private let columns: [(id: String, title: String, width: CGFloat)] = [
        ("name", "Name", 250), ("modified", "Date Modified", 145), ("added", "Date Added", 145),
        ("kind", "Kind", 110), ("size", "Size", 70),
    ]

    override func loadView() {
        for spec in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(spec.id))
            column.title = spec.title
            column.width = spec.width
            column.minWidth = 60
            column.sortDescriptorPrototype = NSSortDescriptor(key: spec.id, ascending: true)
            if spec.id == "size" { column.headerCell.alignment = .right }
            tableView.addTableColumn(column)
        }
        tableView.browser = browser
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsMultipleSelection = true
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.style = .fullWidth
        tableView.rowHeight = 22
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.target = self
        tableView.doubleAction = #selector(doubleClicked)
        tableView.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        let menu = NSMenu()
        menu.delegate = self
        tableView.menu = menu

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        messageLabel.alignment = .center
        messageLabel.textColor = .secondaryLabelColor
        settingsButton.target = self
        settingsButton.action = #selector(openPrivacySettings)
        messageStack.orientation = .vertical
        messageStack.spacing = 10
        messageStack.addArrangedSubview(messageLabel)
        messageStack.addArrangedSubview(settingsButton)
        messageStack.translatesAutoresizingMaskIntoConstraints = false
        messageStack.isHidden = true

        let container = NSView()
        container.addSubview(scroll)
        container.addSubview(messageStack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: container.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            messageStack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            messageStack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            messageLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
        ])
        view = container
    }

    // MARK: - Content

    var isRenaming: Bool { tableView.currentEditor() != nil }

    /// Switches to the sort order remembered for this Folder.
    func useSort(for folder: URL) {
        self.folder = folder
        let saved = Settings.sort(for: folder)
        sortKey = saved.key
        ascending = saved.ascending
        isApplyingSort = true
        tableView.sortDescriptors = [NSSortDescriptor(key: saved.key.rawValue, ascending: saved.ascending)]
        isApplyingSort = false
    }

    func show(_ newEntries: [FileEntry], select urls: [URL]? = nil) {
        let keep = Set(urls ?? selectedEntries().map(\.url))
        entries = DirectoryLister.sorted(newEntries, by: sortKey, ascending: ascending)
        tableView.reloadData()
        selectURLs(keep)
        if entries.isEmpty {
            showMessage("This folder is empty.", withSettingsButton: false)
        } else {
            messageStack.isHidden = true
        }
    }

    func showUnreadable(_ reason: String) {
        entries = []
        tableView.reloadData()
        showMessage(
            "This Mac cannot read this folder.\n\(reason)\n\nTo browse every folder, turn on Full Disk Access for This Mac in System Settings.",
            withSettingsButton: true)
    }

    private func showMessage(_ text: String, withSettingsButton: Bool) {
        messageLabel.stringValue = text
        settingsButton.isHidden = !withSettingsButton
        messageStack.isHidden = false
    }

    func selectURLs(_ urls: Set<URL>) {
        let rows = IndexSet(entries.indices.filter { urls.contains(entries[$0].url) })
        tableView.selectRowIndexes(rows, byExtendingSelection: false)
        if let first = rows.first { tableView.scrollRowToVisible(first) }
    }

    func selectedEntries() -> [FileEntry] {
        tableView.selectedRowIndexes.filter { $0 < entries.count }.map { entries[$0] }
    }

    /// The Items an action applies to: the row under a right click, or else the selection.
    func targetEntries() -> [FileEntry] {
        let clicked = tableView.clickedRow
        if clicked >= 0, clicked < entries.count, !tableView.selectedRowIndexes.contains(clicked) {
            return [entries[clicked]]
        }
        return selectedEntries()
    }

    func refreshCutAppearance() {
        tableView.reloadData(
            forRowIndexes: IndexSet(integersIn: 0..<entries.count), columnIndexes: IndexSet(integer: 0))
    }

    func beginRename(_ entry: FileEntry) {
        guard let row = entries.firstIndex(of: entry) else { return }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        view.window?.makeFirstResponder(tableView)
        tableView.editColumn(0, row: row, with: nil, select: true)
        // Select the name without its extension, as File Explorer does.
        if !entry.isFolder, let editor = tableView.currentEditor() {
            let base = (entry.name as NSString).deletingPathExtension as NSString
            if base.length > 0 { editor.selectedRange = NSRange(location: 0, length: base.length) }
        }
    }

    // MARK: - NSTableViewDataSource and NSTableViewDelegate

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn, row < entries.count else { return nil }
        let entry = entries[row]
        let identifier = column.identifier
        let isName = identifier.rawValue == "name"
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            ?? makeCell(identifier, isName: isName)
        switch identifier.rawValue {
        case "name":
            cell.textField?.stringValue = entry.name
            cell.imageView?.image = Icons.forFile(entry.url)
            cell.alphaValue = CutState.contains(entry.url) ? 0.4 : (entry.isHidden ? 0.6 : 1)
        case "modified":
            cell.textField?.stringValue = Format.date(entry.modified)
        case "added":
            cell.textField?.stringValue = Format.date(entry.added)
        case "kind":
            cell.textField?.stringValue = entry.kind
        default:
            cell.textField?.stringValue = Format.bytes(entry.size)
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let descriptor = tableView.sortDescriptors.first,
              let key = descriptor.key.flatMap(SortKey.init(rawValue:))
        else { return }
        if isApplyingSort { return }
        sortKey = key
        ascending = descriptor.ascending
        if let folder { Settings.setSort(key, ascending: ascending, for: folder) }
        show(entries)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        browser?.selectionChanged()
    }

    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        row < entries.count ? entries[row].name : nil
    }

    @objc private func doubleClicked() {
        guard tableView.clickedRow >= 0 else { return }
        browser?.openSelection(nil)
    }

    @objc private func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Rename

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        let row = tableView.row(for: field)
        guard row >= 0, row < entries.count else { return }
        let entry = entries[row]
        let newName = field.stringValue
        if newName == entry.name { return }
        field.stringValue = entry.name
        // Leave the field editor before the list reloads.
        DispatchQueue.main.async { [weak self] in
            self?.browser?.rename(entry, to: newName)
        }
    }

    // MARK: - Context menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        browser?.fillContextMenu(menu, for: targetEntries())
    }

    private func makeCell(_ identifier: NSUserInterfaceItemIdentifier, isName: Bool) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = isName ? .byTruncatingMiddle : .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label
        if isName {
            label.isEditable = true
            label.delegate = self
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
            label.textColor = .secondaryLabelColor
            if identifier.rawValue == "size" { label.alignment = .right }
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2).isActive = true
        }
        NSLayoutConstraint.activate([
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}
