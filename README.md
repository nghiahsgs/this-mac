# This Mac

A file browser for macOS that works like Windows File Explorer. It shows the whole machine as one tree, so you can always see where a folder sits.

Status: early version, built for personal use. Use it at your own risk.

## What it does

- **This Mac page**: every drive with its free space, and quick access to Home, Desktop, Documents and Downloads.
- **Folder tree**: one root, then drives, then the real folders from `/`.
  It opens only the branches you open. Turn on View, Expand Tree to Current Folder to make it follow you.
- **Address bar**: shows the full path. Click a segment to go there, or press `⌘L` to type or copy a path.
- **Details list**: name, date modified, kind and size. Folders are always on top.
- **Preview pane**: select a file to read it on the right, without opening it.
- **File actions**: open, new folder, rename, cut, copy, paste and move to Trash.
- **Hidden items**: a switch in the View menu of the toolbar.
- **Live refresh**: the list updates when files change on disk.

Deleting always moves items to the macOS Trash. On a name conflict, paste asks you to replace, keep both or skip.

## Keyboard shortcuts

Press `⌘/` in the app to see the full list. The main ones follow Windows, with `⌘` in place of Ctrl.

- `↩` open
- `⌫` go up to the parent folder
- `F2` rename
- `⌘⌫` or `fn⌫` move to Trash
- `⌘X`, `⌘C`, `⌘V` cut, copy, paste
- `⌘L` type an address
- `⇧⌘.` show or hide hidden items

## Build and run

You need macOS 15 or later, Xcode 16 or later, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
make test   # run the core tests
make run    # build the app and open it
```

The app is not sandboxed and is not signed with a developer certificate. To browse every folder, turn on Full Disk Access for This Mac in System Settings, Privacy & Security.

## Layout

- `Packages/ThisMacCore`: listing folders, drives and file operations. No UI, covered by tests.
- `App`: the macOS app. AppKit for the window, tree and list. SwiftUI for the This Mac page and the shortcuts sheet.
- `GLOSSARY.md`: the words this project uses.
- `docs/adr`: decisions that are hard to reverse.

## License

MIT
