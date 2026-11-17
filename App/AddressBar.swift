import AppKit

/// Shows the Address as clickable segments, and turns into a text field for typing one.
final class AddressBar: NSView, NSTextFieldDelegate {
    var onNavigate: ((Location) -> Void)?
    var onCopy: (() -> Void)?

    private let box = NSBox()
    private let pathControl = NSPathControl()
    private let textField = NSTextField()
    private let copyButton = NSButton()
    private var location: Location = .thisMac

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func build() {
        box.boxType = .custom
        box.cornerRadius = 6
        box.borderWidth = 1
        box.borderColor = .separatorColor
        box.fillColor = .textBackgroundColor
        box.contentViewMargins = .zero
        box.translatesAutoresizingMaskIntoConstraints = false
        addSubview(box)

        pathControl.pathStyle = .standard
        pathControl.isEditable = false
        pathControl.focusRingType = .none
        pathControl.target = self
        pathControl.action = #selector(pathClicked)
        pathControl.translatesAutoresizingMaskIntoConstraints = false
        pathControl.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        pathControl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        pathControl.toolTip = "Click a segment to go there. Click the empty space or press ⌘L to type an address."

        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: NSFont.systemFontSize)
        textField.lineBreakMode = .byTruncatingHead
        textField.usesSingleLineMode = true
        textField.delegate = self
        textField.target = self
        textField.action = #selector(addressEntered)
        textField.isHidden = true
        textField.translatesAutoresizingMaskIntoConstraints = false

        copyButton.image = Icons.symbol("doc.on.doc", "Copy address")
        copyButton.isBordered = false
        copyButton.target = self
        copyButton.action = #selector(copyClicked)
        copyButton.toolTip = "Copy this address"
        copyButton.translatesAutoresizingMaskIntoConstraints = false

        for view in [pathControl, textField, copyButton] { addSubview(view) }

        NSLayoutConstraint.activate([
            box.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            box.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            box.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            box.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),

            pathControl.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 6),
            pathControl.trailingAnchor.constraint(lessThanOrEqualTo: copyButton.leadingAnchor, constant: -6),
            pathControl.centerYAnchor.constraint(equalTo: box.centerYAnchor),

            textField.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 8),
            textField.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -6),
            textField.centerYAnchor.constraint(equalTo: box.centerYAnchor),

            copyButton.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -6),
            copyButton.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            copyButton.widthAnchor.constraint(equalToConstant: 20),
        ])
    }

    func show(_ location: Location) {
        self.location = location
        switch location {
        case .thisMac:
            let item = NSPathControlItem()
            item.title = "This Mac"
            item.image = Icons.computer
            pathControl.url = nil
            pathControl.pathItems = [item]
            copyButton.isHidden = true
        case .folder(let url):
            pathControl.url = url
            copyButton.isHidden = false
        }
        endEditing()
    }

    /// Switches to the text field so the user can type or copy the full Address.
    func beginEditing() {
        if case .folder(let url) = location {
            textField.stringValue = url.path
        } else {
            textField.stringValue = ""
        }
        textField.placeholderString = "Type an address, for example ~/Documents"
        textField.isHidden = false
        pathControl.isHidden = true
        window?.makeFirstResponder(textField)
        textField.currentEditor()?.selectAll(nil)
    }

    private func endEditing() {
        textField.isHidden = true
        pathControl.isHidden = false
    }

    override func mouseDown(with event: NSEvent) {
        beginEditing()
    }

    @objc private func pathClicked() {
        if case .thisMac = location { return }
        guard let url = pathControl.clickedPathItem?.url else { return }
        onNavigate?(.folder(url))
    }

    @objc private func copyClicked() {
        onCopy?()
    }

    @objc private func addressEntered() {
        let typed = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !textField.isHidden, !typed.isEmpty else { return }
        endEditing()
        if typed.caseInsensitiveCompare("This Mac") == .orderedSame {
            onNavigate?(.thisMac)
        } else {
            let path = (typed as NSString).expandingTildeInPath
            onNavigate?(.folder(URL(fileURLWithPath: path)))
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        endEditing()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            endEditing()
            window?.makeFirstResponder(nil)
            return true
        }
        return false
    }
}
