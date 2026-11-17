import AppKit
import SwiftUI
import ThisMacCore

private extension NSToolbarItem.Identifier {
    static let back = NSToolbarItem.Identifier("back")
    static let forward = NSToolbarItem.Identifier("forward")
    static let up = NSToolbarItem.Identifier("up")
    static let newFolder = NSToolbarItem.Identifier("newFolder")
    static let viewMenu = NSToolbarItem.Identifier("viewMenu")
    static let preview = NSToolbarItem.Identifier("preview")
    static let shortcuts = NSToolbarItem.Identifier("shortcuts")
}

/// One browser window: Folder Tree, Details List or This Mac page, and Preview Pane.
final class BrowserWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate,
    NSMenuItemValidation, NSToolbarItemValidation {
    var onClose: (() -> Void)?
    private(set) var location: Location = .thisMac

    private let lister = DirectoryLister()
    private let operations = FileOperations()
    private let watcher = FolderWatcher()

    private let tree = FolderTreeController()
    private let details = DetailsListController()
    private let preview = PreviewController()
    private let addressBar = AddressBar(frame: NSRect(x: 0, y: 0, width: 600, height: 36))
    private let contentController = NSViewController()
    private var homeHost: NSHostingView<HomeView>?
    private var previewItem: NSSplitViewItem!

    private var backStack: [Location] = []
    private var forwardStack: [Location] = []
    private var observers: [NSObjectProtocol] = []

    init(startAt start: Location) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.minSize = NSSize(width: 720, height: 420)
        window.tabbingMode = .disallowed
        window.center()
        super.init(window: window)
        window.delegate = self

        tree.browser = self
        details.browser = self
        buildContent()
        buildToolbar()
        observeDrives()

        location = .thisMac
        applyLocation()
        if start != .thisMac { navigate(to: start, recordHistory: false) }
        // The tree only keeps expansion and selection once its view is on screen.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.tree.reveal(self.location)
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Layout

    private func buildContent() {
        let container = NSView()
        let detailsView = details.view
        detailsView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(detailsView)
        let home = NSHostingView(rootView: makeHomeView())
        home.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(home)
        for view in [detailsView, home] {
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                view.topAnchor.constraint(equalTo: container.topAnchor),
                view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }
        homeHost = home
        contentController.view = container
        contentController.addChild(details)

        let split = NSSplitViewController()
        let treeItem = NSSplitViewItem(sidebarWithViewController: tree)
        treeItem.minimumThickness = 180
        treeItem.maximumThickness = 420
        treeItem.canCollapse = false
        let contentItem = NSSplitViewItem(viewController: contentController)
        contentItem.minimumThickness = 320
        previewItem = NSSplitViewItem(viewController: preview)
        previewItem.minimumThickness = 240
        previewItem.canCollapse = true
        previewItem.holdingPriority = .defaultLow + 1
        previewItem.isCollapsed = !Settings.showPreview
        split.addSplitViewItem(treeItem)
        split.addSplitViewItem(contentItem)
        split.addSplitViewItem(previewItem)
        split.view.frame = NSRect(x: 0, y: 0, width: 1180, height: 720)
        window?.contentViewController = split
        window?.setContentSize(NSSize(width: 1180, height: 720))
        split.splitView.setPosition(230, ofDividerAt: 0)
        split.splitView.setPosition(880, ofDividerAt: 1)

        addressBar.onNavigate = { [weak self] in self?.navigate(to: $0) }
        addressBar.onCopy = { [weak self] in self?.copyCurrentAddress() }
        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = addressBar
        accessory.layoutAttribute = .bottom
        window?.addTitlebarAccessoryViewController(accessory)
    }

    private func makeHomeView() -> HomeView {
        HomeView(drives: Drives.mounted(), quickFolders: QuickFolder.all()) { [weak self] url in
            self?.navigate(to: .folder(url))
        }
    }

    private func buildToolbar() {
        let toolbar = NSToolbar(identifier: "browser")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window?.toolbar = toolbar
        window?.toolbarStyle = .unified
    }

    private func observeDrives() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.drivesChanged()
            })
        }
    }

    private func drivesChanged() {
        tree.rebuild()
        homeHost?.rootView = makeHomeView()
        if case .folder(let url) = location, !FileManager.default.fileExists(atPath: url.path) {
            navigate(to: .thisMac)
        } else {
            tree.reveal(location)
        }
    }

    func windowWillClose(_ notification: Notification) {
        watcher.stop()
        preview.shutDown()
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        onClose?()
    }

    // MARK: - Navigation

    func navigate(to target: Location, recordHistory: Bool = true) {
        var destination = target
        var selectAfter: URL?
        if case .folder(let raw) = target {
            let url = raw.standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                showError("This Mac cannot find “\(url.path)”.", detail: "Check the spelling of the address and try again.")
                addressBar.show(location)
                return
            }
            if isDirectory.boolValue {
                destination = .folder(url)
            } else {
                // The address of a file: go to its Folder and select it.
                destination = .folder(url.deletingLastPathComponent())
                selectAfter = url
            }
        }
        if destination != location {
            if recordHistory {
                backStack.append(location)
                forwardStack.removeAll()
            }
            location = destination
        }
        applyLocation()
        if let selectAfter { details.selectURLs([selectAfter]) }
    }

    private func applyLocation() {
        window?.title = location.title
        addressBar.show(location)
        switch location {
        case .thisMac:
            homeHost?.rootView = makeHomeView()
            homeHost?.isHidden = false
            details.view.isHidden = true
            watcher.stop()
            preview.show(nil)
        case .folder(let url):
            homeHost?.isHidden = true
            details.view.isHidden = false
            loadFolder(url, select: [])
            watcher.watch(url) { [weak self] in self?.folderChangedOnDisk() }
            window?.makeFirstResponder(details.tableView)
        }
        tree.reveal(location)
        window?.toolbar?.validateVisibleItems()
    }

    private func loadFolder(_ url: URL, select: [URL]?) {
        do {
            details.show(try lister.list(url, showHidden: Settings.showHidden), select: select)
        } catch {
            details.showUnreadable(error.localizedDescription)
        }
        selectionChanged()
    }

    /// Reloads the current Folder. `select` chooses the Items to select, `nil` keeps the selection.
    func reloadCurrentFolder(select: [URL]? = nil) {
        guard case .folder(let url) = location else {
            homeHost?.rootView = makeHomeView()
            return
        }
        loadFolder(url, select: select)
        tree.refreshChildren(of: url)
    }

    private func folderChangedOnDisk() {
        guard case .folder(let url) = location else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            goUp(nil)
            return
        }
        if details.isRenaming { return }
        reloadCurrentFolder()
    }

    func selectionChanged() {
        guard Settings.showPreview else { return }
        let selected = details.selectedEntries()
        if selected.count == 1, let entry = selected.first, !entry.isFolder {
            preview.show(entry.url)
        } else {
            preview.show(nil)
        }
    }

    func describeTree() -> String { tree.describeRows() }

    func selectItem(named name: String) {
        let urls = details.entries.filter { $0.name == name }.map(\.url)
        details.selectURLs(Set(urls))
    }

    private var currentFolder: URL? {
        if case .folder(let url) = location { return url }
        return nil
    }

    private func parentLocation() -> Location? {
        guard let url = currentFolder else { return nil }
        let isDriveRoot = Drives.mounted().contains { $0.url.standardizedFileURL.path == url.path }
        if isDriveRoot || url.path == "/" { return .thisMac }
        return .folder(url.deletingLastPathComponent())
    }

    // MARK: - Go actions

    @objc func goBack(_ sender: Any?) {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(location)
        location = previous
        applyLocation()
    }

    @objc func goForward(_ sender: Any?) {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(location)
        location = next
        applyLocation()
    }

    @objc func goUp(_ sender: Any?) {
        guard let parent = parentLocation() else { return }
        let child = currentFolder
        navigate(to: parent)
        if let child { details.selectURLs([child]) }
    }

    @objc func goThisMac(_ sender: Any?) { navigate(to: .thisMac) }

    @objc func goHome(_ sender: Any?) {
        navigate(to: .folder(FileManager.default.homeDirectoryForCurrentUser))
    }

    @objc func focusAddress(_ sender: Any?) { addressBar.beginEditing() }

    @objc func refresh(_ sender: Any?) {
        if currentFolder == nil { tree.rebuild(); tree.reveal(location) }
        reloadCurrentFolder()
    }

    // MARK: - View actions

    @objc func toggleHidden(_ sender: Any?) {
        Settings.showHidden.toggle()
        tree.rebuild()
        reloadCurrentFolder()
        tree.reveal(location)
    }

    @objc func toggleExpandTree(_ sender: Any?) {
        Settings.expandTree.toggle()
        tree.reveal(location)
    }

    @objc func togglePreview(_ sender: Any?) {
        Settings.showPreview.toggle()
        previewItem.animator().isCollapsed = !Settings.showPreview
        if Settings.showPreview { selectionChanged() } else { preview.show(nil) }
        window?.toolbar?.validateVisibleItems()
    }

    @objc func showShortcuts(_ sender: Any?) {
        guard let host = window?.contentViewController else { return }
        let sheet = NSHostingController(rootView: ShortcutsView(close: {}))
        sheet.rootView = ShortcutsView(close: { [weak host, weak sheet] in
            if let sheet { host?.dismiss(sheet) }
        })
        host.presentAsSheet(sheet)
    }

    // MARK: - File actions

    @objc func openSelection(_ sender: Any?) {
        let targets = details.targetEntries()
        if targets.count == 1, let entry = targets.first, entry.isFolder {
            navigate(to: .folder(entry.url))
            return
        }
        for entry in targets where !entry.isFolder {
            NSWorkspace.shared.open(entry.url)
        }
    }

    @objc func openWith(_ sender: NSMenuItem) {
        guard let application = sender.representedObject as? URL else { return }
        let urls = details.targetEntries().map(\.url)
        NSWorkspace.shared.open(urls, withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc func newFolder(_ sender: Any?) {
        guard let folder = currentFolder else { return }
        do {
            let created = try operations.newFolder(in: folder)
            reloadCurrentFolder(select: [created])
            if let entry = details.entries.first(where: { $0.url == created }) {
                details.beginRename(entry)
            }
        } catch {
            showError("The folder could not be created.", detail: error.localizedDescription)
        }
    }

    @objc func renameSelection(_ sender: Any?) {
        guard let entry = details.targetEntries().first else { return }
        details.beginRename(entry)
    }

    func rename(_ entry: FileEntry, to newName: String) {
        do {
            let renamed = try operations.rename(entry.url, to: newName)
            reloadCurrentFolder(select: [renamed])
        } catch {
            showError("“\(entry.name)” could not be renamed.", detail: error.localizedDescription)
            reloadCurrentFolder()
        }
    }

    @objc func moveToTrash(_ sender: Any?) {
        let urls = details.targetEntries().map(\.url)
        guard !urls.isEmpty else { return }
        let failures = operations.trash(urls)
        reloadCurrentFolder(select: [])
        report(failures, summary: "Some items could not be moved to Trash.")
    }

    @objc func cut(_ sender: Any?) { writeSelectionToPasteboard(cut: true) }

    @objc func copy(_ sender: Any?) { writeSelectionToPasteboard(cut: false) }

    private func writeSelectionToPasteboard(cut: Bool) {
        let urls = details.targetEntries().map(\.url)
        guard !urls.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
        if cut {
            CutState.changeCount = pasteboard.changeCount
            CutState.urls = Set(urls)
        } else {
            CutState.clear()
        }
        details.refreshCutAppearance()
    }

    private func pasteboardFileURLs() -> [URL] {
        let objects = NSPasteboard.general.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        return (objects as? [URL]) ?? []
    }

    @objc func paste(_ sender: Any?) {
        guard let folder = currentFolder else { return }
        let sources = pasteboardFileURLs()
        guard !sources.isEmpty else { return }
        let mode: TransferMode = CutState.isActive ? .move : .copy
        let operations = self.operations
        let window = self.window

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var remembered: ConflictChoice?
            let result = operations.transfer(sources, to: folder, mode: mode) { existing in
                if let remembered { return remembered }
                var choice = ConflictChoice.skip
                DispatchQueue.main.sync {
                    let answer = Self.askAboutConflict(existing, in: window)
                    choice = answer.choice
                    if answer.applyToAll { remembered = answer.choice }
                }
                return choice
            }
            DispatchQueue.main.async {
                guard let self else { return }
                if mode == .move {
                    CutState.clear()
                    NSPasteboard.general.clearContents()
                }
                if self.currentFolder == folder {
                    self.reloadCurrentFolder(select: result.completed)
                }
                self.report(result.failures, summary: "Some items could not be pasted.")
            }
        }
    }

    private static func askAboutConflict(_ existing: URL, in window: NSWindow?) -> (choice: ConflictChoice, applyToAll: Bool) {
        let alert = NSAlert()
        alert.messageText = "An item named “\(existing.lastPathComponent)” already exists here."
        alert.informativeText = "Replace moves the existing item to Trash. Keep Both adds “copy” to the new name."
        alert.addButton(withTitle: "Keep Both")
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Skip")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Do this for all conflicts"
        let response = alert.runModal()
        let choice: ConflictChoice
        switch response {
        case .alertFirstButtonReturn: choice = .keepBoth
        case .alertSecondButtonReturn: choice = .replace
        default: choice = .skip
        }
        return (choice, alert.suppressionButton?.state == .on)
    }

    @objc func copyPath(_ sender: Any?) {
        let urls = details.targetEntries().map(\.url)
        if urls.isEmpty {
            copyCurrentAddress()
        } else {
            copyText(urls.map(\.path).joined(separator: "\n"))
        }
    }

    private func copyCurrentAddress() {
        if let folder = currentFolder { copyText(folder.path) }
    }

    private func copyText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        CutState.clear()
        details.refreshCutAppearance()
    }

    /// The Folder a "here" action applies to: the one selected Folder, or else the current Folder.
    private func contextFolder() -> URL? {
        let targets = details.targetEntries()
        if targets.count == 1, let entry = targets.first, entry.isFolder { return entry.url }
        return currentFolder
    }

    @objc func openInTerminal(_ sender: Any?) {
        guard let folder = contextFolder(),
              let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
        else { return }
        NSWorkspace.shared.open([folder], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc func revealInFinder(_ sender: Any?) {
        let urls = details.targetEntries().map(\.url)
        if !urls.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        } else if let folder = currentFolder {
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        }
    }

    // MARK: - Context menu

    func fillContextMenu(_ menu: NSMenu, for targets: [FileEntry]) {
        func add(_ title: String, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        if !targets.isEmpty {
            add("Open", #selector(openSelection(_:)))
            if targets.allSatisfy({ !$0.isFolder }), let first = targets.first {
                let applications = NSWorkspace.shared.urlsForApplications(toOpen: first.url).prefix(12)
                if !applications.isEmpty {
                    let parent = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
                    let submenu = NSMenu()
                    for application in applications {
                        let item = NSMenuItem(
                            title: Location.name(of: application), action: #selector(openWith(_:)), keyEquivalent: "")
                        item.target = self
                        item.representedObject = application
                        item.image = Icons.forFile(application)
                        submenu.addItem(item)
                    }
                    parent.submenu = submenu
                    menu.addItem(parent)
                }
            }
            menu.addItem(.separator())
            add("Cut", #selector(cut(_:)))
            add("Copy", #selector(copy(_:)))
        }
        add("Paste", #selector(paste(_:)))
        menu.addItem(.separator())
        add("Copy Address", #selector(copyPath(_:)))
        if !targets.isEmpty {
            add("Rename", #selector(renameSelection(_:)))
            add("Move to Trash", #selector(moveToTrash(_:)))
        }
        menu.addItem(.separator())
        add("New Folder", #selector(newFolder(_:)))
        add("Open in Terminal", #selector(openInTerminal(_:)))
        add("Reveal in Finder", #selector(revealInFinder(_:)))
    }

    // MARK: - Validation

    private func isEnabled(_ action: Selector?) -> Bool {
        guard let action else { return true }
        let inFolder = currentFolder != nil
        let hasTargets = inFolder && !details.targetEntries().isEmpty
        switch action {
        case #selector(goBack(_:)): return !backStack.isEmpty
        case #selector(goForward(_:)): return !forwardStack.isEmpty
        case #selector(goUp(_:)): return inFolder
        case #selector(newFolder(_:)), #selector(openInTerminal(_:)), #selector(revealInFinder(_:)),
             #selector(copyPath(_:)):
            return inFolder
        case #selector(paste(_:)):
            return inFolder && !pasteboardFileURLs().isEmpty
        case #selector(cut(_:)), #selector(copy(_:)), #selector(moveToTrash(_:)),
             #selector(openSelection(_:)), #selector(openWith(_:)):
            return hasTargets
        case #selector(renameSelection(_:)):
            return inFolder && details.targetEntries().count == 1
        default:
            return true
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleHidden(_:)): menuItem.state = Settings.showHidden ? .on : .off
        case #selector(togglePreview(_:)): menuItem.state = Settings.showPreview ? .on : .off
        case #selector(toggleExpandTree(_:)): menuItem.state = Settings.expandTree ? .on : .off
        default: break
        }
        return isEnabled(menuItem.action)
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        isEnabled(item.action)
    }

    // MARK: - Toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.back, .forward, .up, .space, .newFolder, .flexibleSpace, .viewMenu, .preview, .shortcuts]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch identifier {
        case .back:
            return button(identifier, "chevron.left", "Back", "Back (⌘[)", #selector(goBack(_:)))
        case .forward:
            return button(identifier, "chevron.right", "Forward", "Forward (⌘])", #selector(goForward(_:)))
        case .up:
            return button(identifier, "arrow.up", "Up", "Up to the parent folder (⌫ or ⌘↑)", #selector(goUp(_:)))
        case .newFolder:
            return button(identifier, "folder.badge.plus", "New Folder", "New folder (⇧⌘N)", #selector(newFolder(_:)))
        case .preview:
            return button(identifier, "sidebar.right", "Preview", "Show or hide the preview pane (⌥⌘P)", #selector(togglePreview(_:)))
        case .shortcuts:
            return button(identifier, "keyboard", "Shortcuts", "Keyboard shortcuts (⌘/)", #selector(showShortcuts(_:)))
        case .viewMenu:
            let item = NSMenuToolbarItem(itemIdentifier: identifier)
            item.image = Icons.symbol("eye", "View")
            item.label = "View"
            item.toolTip = "View options: hidden items (⇧⌘.) and preview pane (⌥⌘P)"
            item.showsIndicator = true
            let menu = NSMenu()
            for (title, action) in [
                ("Hidden Items", #selector(toggleHidden(_:))),
                ("Preview Pane", #selector(togglePreview(_:))),
                ("Expand Tree to Current Folder", #selector(toggleExpandTree(_:))),
            ] {
                let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
                entry.target = self
                menu.addItem(entry)
            }
            menu.addItem(.separator())
            let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refresh(_:)), keyEquivalent: "")
            refreshItem.target = self
            menu.addItem(refreshItem)
            item.menu = menu
            return item
        default:
            return nil
        }
    }

    private func button(
        _ identifier: NSToolbarItem.Identifier, _ symbol: String, _ label: String, _ toolTip: String,
        _ action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.image = Icons.symbol(symbol, label)
        item.label = label
        item.toolTip = toolTip
        item.target = self
        item.action = action
        item.isBordered = true
        return item
    }

    // MARK: - Messages

    private func showError(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = detail
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    private func report(_ failures: [TransferFailure], summary: String) {
        guard !failures.isEmpty else { return }
        let lines = failures.prefix(8).map { "\($0.source.lastPathComponent): \($0.error.localizedDescription)" }
        let more = failures.count > 8 ? "\nand \(failures.count - 8) more." : ""
        showError(summary, detail: lines.joined(separator: "\n") + more)
    }
}
