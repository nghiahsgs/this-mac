import AppKit
import Quartz

/// The Preview Pane: shows the selected Item with Quick Look, without opening it.
final class PreviewController: NSViewController {
    private var preview: QLPreviewView?
    private let placeholder = NSTextField(labelWithString: "Select a file to preview it here.")

    override func loadView() {
        let container = NSView()
        placeholder.textColor = .secondaryLabelColor
        placeholder.alignment = .center
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(placeholder)

        if let preview = QLPreviewView(frame: .zero, style: .normal) {
            preview.translatesAutoresizingMaskIntoConstraints = false
            preview.autostarts = false
            preview.isHidden = true
            container.addSubview(preview)
            NSLayoutConstraint.activate([
                preview.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                preview.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                preview.topAnchor.constraint(equalTo: container.topAnchor),
                preview.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
            self.preview = preview
        }
        NSLayoutConstraint.activate([
            placeholder.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            placeholder.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 12),
        ])
        view = container
    }

    func show(_ url: URL?) {
        _ = view
        preview?.previewItem = url.map { $0 as NSURL }
        preview?.isHidden = url == nil
        placeholder.isHidden = url != nil
    }

    func shutDown() {
        preview?.close()
        preview = nil
    }
}
