import AppKit

// MARK: - ClipboardItemCell

/// A table cell view that displays a single `ClipboardItem`.
///
/// Layout (left to right):
/// ```
/// [type icon] | [preview text (main)] | [timestamp (trailing)]
///             | [content-type badge]  |
/// ```
@MainActor
final class ClipboardItemCell: NSTableCellView {

    // MARK: Reuse identifier

    static let reuseIdentifier = NSUserInterfaceItemIdentifier("ClipboardItemCell")

    // MARK: Row height

    static let rowHeight: CGFloat = 64
    static let imageRowHeight: CGFloat = 80

    // MARK: - Subviews

    private let typeIconView: NSImageView = {
        let iv = NSImageView()
        iv.imageScaling         = .scaleProportionallyUpOrDown
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let previewLabel: NSTextField = {
        let tf = NSTextField(labelWithString: "")
        tf.maximumNumberOfLines = 2
        tf.lineBreakMode        = .byTruncatingTail
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }()

    private let imagePreview: NSImageView = {
        let iv = NSImageView()
        iv.imageScaling         = .scaleProportionallyUpOrDown
        iv.wantsLayer           = true
        iv.layer?.cornerRadius  = 4
        iv.layer?.masksToBounds = true
        iv.isHidden             = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let timestampLabel: NSTextField = {
        let tf = NSTextField(labelWithString: "")
        tf.maximumNumberOfLines = 1
        tf.alignment            = .right
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }()

    private let badgeLabel: NSTextField = {
        let tf = NSTextField(labelWithString: "")
        tf.maximumNumberOfLines = 1
        tf.alignment            = .center
        tf.isBordered           = false
        tf.isEditable           = false
        tf.isSelectable         = false
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }()

    private let badgeBackground: NSView = {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.cornerRadius = 4
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let hotkeyLabel: NSTextField = {
        let tf = NSTextField(labelWithString: "")
        tf.maximumNumberOfLines = 1
        tf.alignment = .right
        tf.isHidden = true
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }()

    private let selectionBackground: NSView = {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.cornerRadius = 7
        v.isHidden = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    // MARK: Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        buildLayout()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildLayout()
    }

    // MARK: - Layout

    private func buildLayout() {
        addSubview(selectionBackground)
        addSubview(typeIconView)
        addSubview(previewLabel)
        addSubview(imagePreview)
        addSubview(timestampLabel)
        addSubview(hotkeyLabel)
        badgeBackground.addSubview(badgeLabel)
        addSubview(badgeBackground)

        NSLayoutConstraint.activate([
            // Selection background — inset slightly for breathing room.
            selectionBackground.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            selectionBackground.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            selectionBackground.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            selectionBackground.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),

            // Type icon — left side, vertically centred.
            typeIconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            typeIconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            typeIconView.widthAnchor.constraint(equalToConstant: 22),
            typeIconView.heightAnchor.constraint(equalToConstant: 22),

            // Timestamp — right side, pinned to top-right.
            timestampLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            timestampLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            timestampLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 80),

            // Hotkey hint — right side, below timestamp.
            hotkeyLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            hotkeyLabel.topAnchor.constraint(equalTo: timestampLabel.bottomAnchor, constant: 3),
            hotkeyLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 40),

            // Preview label — between icon and timestamp, top area.
            previewLabel.leadingAnchor.constraint(equalTo: typeIconView.trailingAnchor, constant: 10),
            previewLabel.trailingAnchor.constraint(equalTo: timestampLabel.leadingAnchor, constant: -8),
            previewLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),

            // Image preview — same position as preview label, shown for image items.
            imagePreview.leadingAnchor.constraint(equalTo: typeIconView.trailingAnchor, constant: 10),
            imagePreview.trailingAnchor.constraint(equalTo: timestampLabel.leadingAnchor, constant: -8),
            imagePreview.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            imagePreview.bottomAnchor.constraint(equalTo: badgeBackground.topAnchor, constant: -4),

            // Badge — below preview, left-aligned.
            badgeBackground.leadingAnchor.constraint(equalTo: previewLabel.leadingAnchor),
            badgeBackground.topAnchor.constraint(equalTo: previewLabel.bottomAnchor, constant: 4),
            badgeBackground.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8),

            // Badge label inside badge background.
            badgeLabel.leadingAnchor.constraint(equalTo: badgeBackground.leadingAnchor, constant: 5),
            badgeLabel.trailingAnchor.constraint(equalTo: badgeBackground.trailingAnchor, constant: -5),
            badgeLabel.topAnchor.constraint(equalTo: badgeBackground.topAnchor, constant: 1),
            badgeLabel.bottomAnchor.constraint(equalTo: badgeBackground.bottomAnchor, constant: -1),
        ])
    }

    // MARK: - Configuration

    /// Populates the cell with the given clipboard item.
    func configure(with item: ClipboardItem, isSelected: Bool, isHovered: Bool = false, hotkey: Int? = nil) {
        configurePreview(for: item)
        configureTypeIcon(for: item.contentType)
        configureBadge(for: item.contentType)
        configureTimestamp(item.timestamp)
        configureHotkey(hotkey)
        configureSelection(isSelected, isHovered: isHovered)
    }

    // MARK: - Private configuration helpers

    private func configurePreview(for item: ClipboardItem) {
        if item.contentType == .image, let data = item.imageData {
            previewLabel.isHidden  = true
            imagePreview.isHidden  = false
            imagePreview.image     = NSImage(data: data)
            return
        }

        previewLabel.isHidden  = false
        imagePreview.isHidden  = true

        let maxChars = 120
        let raw = item.content
        let truncated = raw.count > maxChars
            ? String(raw.prefix(maxChars)) + "…"
            : raw

        let usesMonospace = item.contentType == .json || item.contentType == .code
        let font: NSFont = usesMonospace
            ? .monospacedSystemFont(ofSize: 11.5, weight: .regular)
            : .systemFont(ofSize: 12.5, weight: .regular)

        previewLabel.font        = font
        previewLabel.textColor   = .labelColor
        previewLabel.stringValue = truncated
    }

    private func configureTypeIcon(for type: ContentType) {
        let symbolName: String
        switch type {
        case .json:      symbolName = "curlybraces"
        case .url:       symbolName = "link"
        case .code:      symbolName = "chevron.left.forwardslash.chevron.right"
        case .list:      symbolName = "list.bullet"
        case .image:     symbolName = "photo"
        case .plainText: symbolName = "doc.text"
        }

        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        typeIconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: type.displayName)?
            .withSymbolConfiguration(config)
        typeIconView.contentTintColor = .secondaryLabelColor
    }

    private func configureBadge(for type: ContentType) {
        let color = type.badgeColor

        badgeBackground.layer?.backgroundColor = color.withAlphaComponent(0.18).cgColor

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9.5, weight: .semibold),
            .foregroundColor: color,
        ]
        badgeLabel.attributedStringValue = NSAttributedString(
            string: type.displayName.uppercased(),
            attributes: attributes
        )
    }

    private func configureTimestamp(_ date: Date) {
        timestampLabel.font       = .systemFont(ofSize: 10.5, weight: .regular)
        timestampLabel.textColor  = .tertiaryLabelColor
        timestampLabel.stringValue = Self.relativeTimestamp(from: date)
    }

    private func configureHotkey(_ position: Int?) {
        guard let n = position else {
            hotkeyLabel.isHidden = true
            return
        }
        hotkeyLabel.isHidden = false
        hotkeyLabel.font = .systemFont(ofSize: 9.5, weight: .regular)
        hotkeyLabel.textColor = .quaternaryLabelColor
        hotkeyLabel.stringValue = "⌘\(n)"
    }

    private func configureSelection(_ isSelected: Bool, isHovered: Bool) {
        if isSelected {
            selectionBackground.isHidden = false
            selectionBackground.layer?.backgroundColor =
                NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
        } else if isHovered {
            selectionBackground.isHidden = false
            selectionBackground.layer?.backgroundColor =
                NSColor.labelColor.withAlphaComponent(0.07).cgColor
        } else {
            selectionBackground.isHidden = true
            selectionBackground.layer?.backgroundColor = nil
        }
    }

    // MARK: - Relative timestamp

    private static func relativeTimestamp(from date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)

        if seconds < 60       { return "just now" }
        if seconds < 3_600    { return "\(Int(seconds / 60))m ago" }
        if seconds < 86_400   { return "\(Int(seconds / 3_600))h ago" }
        if seconds < 172_800  { return "yesterday" }

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
