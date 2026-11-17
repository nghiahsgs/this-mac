import AppKit

/// One row of the keyboard shortcuts sheet.
struct Shortcut: Identifiable {
    let keys: String
    let action: String
    var id: String { keys + action }
}

struct ShortcutGroup: Identifiable {
    let title: String
    let shortcuts: [Shortcut]
    var id: String { title }
}

enum Shortcuts {
    static let groups: [ShortcutGroup] = [
        ShortcutGroup(title: "Navigate", shortcuts: [
            Shortcut(keys: "↩", action: "Open the selected item"),
            Shortcut(keys: "⌫", action: "Go up to the parent folder"),
            Shortcut(keys: "⌘[", action: "Back"),
            Shortcut(keys: "⌘]", action: "Forward"),
            Shortcut(keys: "⌘↑", action: "Go up to the parent folder"),
            Shortcut(keys: "⌘↓", action: "Open the selected item"),
            Shortcut(keys: "⌘L", action: "Type an address"),
            Shortcut(keys: "⇧⌘C", action: "Go to This Mac"),
            Shortcut(keys: "⇧⌘H", action: "Go to your home folder"),
        ]),
        ShortcutGroup(title: "Files", shortcuts: [
            Shortcut(keys: "⌘X", action: "Cut"),
            Shortcut(keys: "⌘C", action: "Copy"),
            Shortcut(keys: "⌘V", action: "Paste"),
            Shortcut(keys: "F2", action: "Rename"),
            Shortcut(keys: "⌘⌫ or fn⌫", action: "Move to Trash"),
            Shortcut(keys: "⇧⌘N", action: "New folder"),
            Shortcut(keys: "⌥⌘C", action: "Copy the address of the selected item"),
            Shortcut(keys: "⌘A", action: "Select all"),
        ]),
        ShortcutGroup(title: "View", shortcuts: [
            Shortcut(keys: "⇧⌘.", action: "Show or hide hidden items"),
            Shortcut(keys: "⌥⌘P", action: "Show or hide the preview pane"),
            Shortcut(keys: "F5 or ⌘R", action: "Refresh"),
            Shortcut(keys: "⌘N", action: "New window"),
            Shortcut(keys: "⌘/", action: "Show this list"),
        ]),
    ]
}

enum MainMenu {
    static func functionKey(_ code: Int) -> String {
        String(Character(UnicodeScalar(UInt32(code))!))
    }

    static func build() -> NSMenu {
        let main = NSMenu()

        let appMenu = submenu(in: main, title: "This Mac")
        appMenu.addItem(withTitle: "About This Mac App", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide This Mac", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit This Mac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let file = submenu(in: main, title: "File")
        add(file, "New Window", #selector(AppDelegate.newWindow(_:)), "n")
        add(file, "New Folder", #selector(BrowserWindowController.newFolder(_:)), "n", [.command, .shift])
        file.addItem(.separator())
        add(file, "Open", #selector(BrowserWindowController.openSelection(_:)), "o")
        add(file, "Rename", #selector(BrowserWindowController.renameSelection(_:)), functionKey(NSF2FunctionKey), [])
        add(file, "Move to Trash", #selector(BrowserWindowController.moveToTrash(_:)), "\u{8}")
        file.addItem(.separator())
        add(file, "Copy Address", #selector(BrowserWindowController.copyPath(_:)), "c", [.command, .option])
        add(file, "Open in Terminal", #selector(BrowserWindowController.openInTerminal(_:)), "")
        add(file, "Reveal in Finder", #selector(BrowserWindowController.revealInFinder(_:)), "")
        file.addItem(.separator())
        add(file, "Close Window", #selector(NSWindow.performClose(_:)), "w")

        let edit = submenu(in: main, title: "Edit")
        add(edit, "Undo", Selector(("undo:")), "z")
        add(edit, "Redo", Selector(("redo:")), "z", [.command, .shift])
        edit.addItem(.separator())
        add(edit, "Cut", #selector(NSText.cut(_:)), "x")
        add(edit, "Copy", #selector(NSText.copy(_:)), "c")
        add(edit, "Paste", #selector(NSText.paste(_:)), "v")
        add(edit, "Select All", #selector(NSText.selectAll(_:)), "a")

        let view = submenu(in: main, title: "View")
        add(view, "Hidden Items", #selector(BrowserWindowController.toggleHidden(_:)), ".", [.command, .shift])
        add(view, "Preview Pane", #selector(BrowserWindowController.togglePreview(_:)), "p", [.command, .option])
        add(view, "Expand Tree to Current Folder", #selector(BrowserWindowController.toggleExpandTree(_:)), "")
        view.addItem(.separator())
        add(view, "Refresh", #selector(BrowserWindowController.refresh(_:)), functionKey(NSF5FunctionKey), [])
        let refreshAlternate = add(view, "Refresh", #selector(BrowserWindowController.refresh(_:)), "r")
        refreshAlternate.isHidden = true
        refreshAlternate.allowsKeyEquivalentWhenHidden = true

        let go = submenu(in: main, title: "Go")
        add(go, "Back", #selector(BrowserWindowController.goBack(_:)), "[")
        add(go, "Forward", #selector(BrowserWindowController.goForward(_:)), "]")
        add(go, "Up", #selector(BrowserWindowController.goUp(_:)), functionKey(NSUpArrowFunctionKey))
        go.addItem(.separator())
        add(go, "This Mac", #selector(BrowserWindowController.goThisMac(_:)), "c", [.command, .shift])
        add(go, "Home", #selector(BrowserWindowController.goHome(_:)), "h", [.command, .shift])
        add(go, "Type an Address…", #selector(BrowserWindowController.focusAddress(_:)), "l")

        let window = submenu(in: main, title: "Window")
        add(window, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        add(window, "Zoom", #selector(NSWindow.performZoom(_:)), "")
        NSApp.windowsMenu = window

        let help = submenu(in: main, title: "Help")
        add(help, "Keyboard Shortcuts", #selector(BrowserWindowController.showShortcuts(_:)), "/")

        return main
    }

    private static func submenu(in main: NSMenu, title: String) -> NSMenu {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        item.submenu = menu
        main.addItem(item)
        return menu
    }

    @discardableResult
    private static func add(
        _ menu: NSMenu, _ title: String, _ action: Selector, _ key: String,
        _ modifiers: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        menu.addItem(item)
        return item
    }
}
