# AppKit for the window, Folder Tree and Details List; SwiftUI for pages

SwiftUI is the newer and quicker toolkit, so a reader would expect the whole app to use it. We build the window, toolbar, Folder Tree (`NSOutlineView`) and Details List (`NSTableView`) in AppKit, because a file browser must stay smooth with tens of thousands of rows, lazy tree loading, inline rename and precise keyboard handling, and AppKit gives direct control over all of these. SwiftUI is used only for self-contained pages with little data: the This Mac page and the keyboard shortcuts sheet.

## Consequences

The app target uses Swift language mode 5, because AppKit delegates fight strict concurrency checking. The core package stays in Swift 6 mode.
