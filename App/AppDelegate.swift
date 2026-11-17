import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controllers: [BrowserWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
        openWindow(at: launchLocation())
        NSApp.activate(ignoringOtherApps: true)
        scheduleSnapshotIfAsked()
    }

    /// Development aid: `--snapshot <file.png>` saves a picture of the first window, then quits.
    /// `--select <name>` selects one Item first, and `--shortcuts` opens the shortcuts sheet.
    private func scheduleSnapshotIfAsked() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count else { return }
        let output = URL(fileURLWithPath: arguments[index + 1])
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let controller = self?.controllers.first else { return }
            if let nameIndex = arguments.firstIndex(of: "--select"), nameIndex + 1 < arguments.count {
                controller.selectItem(named: arguments[nameIndex + 1])
            }
            if arguments.contains("--shortcuts") { controller.showShortcuts(nil) }
            if arguments.contains("--view") { controller.viewSelection(nil) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let controller = self?.controllers.first, let window = controller.window else { return }
            print(controller.describeTree())
            let target = window.attachedSheet ?? window
            if let frameView = target.contentView?.superview,
               let bitmap = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) {
                frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: output)
            }
            exit(0)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.isFileURL {
            openWindow(at: .folder(url))
        }
    }

    @objc func newWindow(_ sender: Any?) {
        let current = (NSApp.keyWindow?.windowController as? BrowserWindowController)?.location
        openWindow(at: current ?? .thisMac)
    }

    /// `--open <path>` starts in that Folder. Without it the app starts on This Mac.
    private func launchLocation() -> Location {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--open"), index + 1 < arguments.count {
            let path = (arguments[index + 1] as NSString).expandingTildeInPath
            return .folder(URL(fileURLWithPath: path))
        }
        return .thisMac
    }

    private func openWindow(at location: Location) {
        let controller = BrowserWindowController(startAt: location)
        controller.onClose = { [weak self, weak controller] in
            self?.controllers.removeAll { $0 === controller }
        }
        if let previous = controllers.last?.window, let window = controller.window {
            let origin = previous.frame.origin
            window.setFrameOrigin(NSPoint(x: origin.x + 28, y: origin.y - 28))
        }
        controllers.append(controller)
        controller.showWindow(nil)
    }
}
