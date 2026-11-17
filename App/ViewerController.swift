import AppKit
import Quartz

/// The Viewer: shows one Item across the whole window, without leaving the app.
final class ViewerController: NSViewController {
    var onClose: (() -> Void)?
    var onToggleFullScreen: (() -> Void)?
    var onOpenExternally: ((URL) -> Void)?

    private var preview: QLPreviewView?
    private let titleLabel = NSTextField(labelWithString: "")
    private var keyMonitor: Any?
    private(set) var url: URL?

    override func loadView() {
        let container = NSView()

        let background = NSBox()
        background.boxType = .custom
        background.borderWidth = 0
        background.fillColor = .windowBackgroundColor
        background.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(background)

        let closeButton = barButton("Back to list", symbol: "chevron.left", action: #selector(closeClicked))
        closeButton.toolTip = "Back to the list (esc)"
        let openButton = barButton("Open in Default App", symbol: "arrow.up.forward.app", action: #selector(openClicked))
        openButton.toolTip = "Open this file in its own app"
        let fullScreenButton = barButton(
            "Full Screen", symbol: "arrow.up.left.and.arrow.down.right", action: #selector(fullScreenClicked))
        fullScreenButton.toolTip = "Enter or leave full screen (⌃⌘F)"

        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.alignment = .center
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let bar = NSStackView(views: [closeButton, titleLabel, openButton, fullScreenButton])
        bar.orientation = .horizontal
        bar.distribution = .fill
        bar.spacing = 10
        bar.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        bar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(bar)

        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            background.topAnchor.constraint(equalTo: container.topAnchor),
            background.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bar.topAnchor.constraint(equalTo: container.topAnchor),
            bar.heightAnchor.constraint(equalToConstant: 40),
        ])

        if let preview = QLPreviewView(frame: .zero, style: .normal) {
            preview.translatesAutoresizingMaskIntoConstraints = false
            preview.autostarts = true
            container.addSubview(preview)
            NSLayoutConstraint.activate([
                preview.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                preview.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                preview.topAnchor.constraint(equalTo: bar.bottomAnchor),
                preview.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
            self.preview = preview
        }
        view = container
    }

    private func barButton(_ title: String, symbol: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.image = Icons.symbol(symbol, title)
        button.imagePosition = .imageLeading
        button.bezelStyle = .rounded
        return button
    }

    func show(_ url: URL) {
        _ = view
        self.url = url
        titleLabel.stringValue = url.lastPathComponent
        preview?.previewItem = url as NSURL
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window === self.view.window, event.keyCode == 53 else { return event }
                self.onClose?() // esc
                return nil
            }
        }
    }

    func hide() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        preview?.previewItem = nil
        url = nil
    }

    func shutDown() {
        hide()
        preview?.close()
        preview = nil
    }

    @objc private func closeClicked() { onClose?() }

    @objc private func fullScreenClicked() { onToggleFullScreen?() }

    @objc private func openClicked() {
        if let url { onOpenExternally?(url) }
    }
}
