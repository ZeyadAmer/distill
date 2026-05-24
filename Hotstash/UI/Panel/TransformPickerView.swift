import AppKit

// MARK: - TransformPickerPopover

/// A slim `NSPopover` that lists available transforms grouped by category.
///
/// Usage:
/// ```swift
/// let popover = TransformPickerPopover()
/// popover.onSelect = { transform in ... }
/// popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
/// ```
@MainActor
final class TransformPickerPopover: NSPopover {

    // MARK: Callback

    /// Called on the main actor when the user taps a transform row.
    var onSelect: ((any Transform) -> Void)? {
        get { pickerVC.onSelect }
        set { pickerVC.onSelect = newValue }
    }

    /// The clipboard item whose content type drives the "Suggested" section.
    var sourceItem: ClipboardItem? {
        get { pickerVC.sourceItem }
        set { pickerVC.sourceItem = newValue }
    }

    // MARK: Private

    private let pickerVC = TransformPickerVC()

    // MARK: Init

    override init() {
        super.init()
        contentViewController = pickerVC
        behavior = .transient
        animates = true
    }

    required init?(coder: NSCoder) {
        fatalError("Use init()")
    }
}

// MARK: - TransformPickerVC

/// The view controller embedded inside `TransformPickerPopover`.
///
/// Renders a vertically-scrollable list with:
/// - A "Suggested" section showing up to 3 context-aware transforms.
/// - One section per `TransformCategory` with every transform in that category.
@MainActor
final class TransformPickerVC: NSViewController {

    // MARK: Callback

    var onSelect: ((any Transform) -> Void)?

    // MARK: Content state

    /// The clipboard item used to derive suggestions; set before the popover is shown.
    var sourceItem: ClipboardItem? {
        didSet { rebuildRows() }
    }

    // MARK: View geometry

    private static let width: CGFloat   = 240
    private static let maxHeight: CGFloat = 400

    // MARK: Subviews

    private let scrollView = NSScrollView()
    private let stackView: NSStackView = {
        let sv = NSStackView()
        sv.orientation  = .vertical
        sv.alignment    = .leading
        sv.distribution = .fill
        sv.spacing      = 0
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    // MARK: View lifecycle

    override func loadView() {
        view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildLayout()
        rebuildRows()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        updatePreferredContentSize()
        scrollView.documentView?.scroll(.zero)
    }

    // MARK: - Layout

    private func buildLayout() {
        scrollView.hasVerticalScroller   = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers    = true
        scrollView.drawsBackground       = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let clipView = scrollView.contentView
        clipView.documentView = stackView

        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Stack fills the scroll view's width.
            stackView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: clipView.topAnchor),
        ])
    }

    // MARK: - Row Construction

    private func rebuildRows() {
        guard isViewLoaded else { return }

        // Remove all existing rows.
        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        // Suggested section.
        let contentType = sourceItem?.contentType ?? .plainText
        let suggestions = TransformRegistry.shared.suggested(for: contentType)
        let suggestedIDs = Set(suggestions.map { $0.id })
        if !suggestions.isEmpty {
            addSectionHeader(title: "Suggested")
            for transform in suggestions {
                addTransformRow(transform, isHighlighted: true)
            }
            addDivider()
        }

        // All enabled transforms in user-defined order (skip ones already in Suggested).
        let ordered = TransformRegistry.shared.enabled.filter { !suggestedIDs.contains($0.id) }
        for transform in ordered {
            addTransformRow(transform, isHighlighted: false)
        }

        updatePreferredContentSize()
    }

    // MARK: - Section header

    private func addSectionHeader(title: String) {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalToConstant: 26).isActive = true

        let label = NSTextField(labelWithString: title.uppercased())
        label.font      = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .tertiaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
        ])

        stackView.addArrangedSubview(container)
        container.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
    }

    // MARK: - Transform row

    private func addTransformRow(_ transform: any Transform, isHighlighted: Bool) {
        let row = TransformRowView(transform: transform, isHighlighted: isHighlighted)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.onTap = { [weak self] in
            self?.onSelect?(transform)
            self?.dismiss(nil)
        }
        stackView.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
    }

    // MARK: - Divider

    private func addDivider() {
        let divider = NSBox()
        divider.boxType  = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        stackView.addArrangedSubview(divider)
        divider.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
    }

    // MARK: - Content size

    private func updatePreferredContentSize() {
        view.layoutSubtreeIfNeeded()
        let totalHeight = stackView.fittingSize.height
        let clampedHeight = min(totalHeight, Self.maxHeight)
        preferredContentSize = NSSize(width: Self.width, height: clampedHeight)
    }
}

// MARK: - TransformRowView

/// A single tappable row inside the transform picker.
@MainActor
private final class TransformRowView: NSView {

    // MARK: Callback

    var onTap: (() -> Void)?

    // MARK: Subviews

    private let iconView: NSImageView = {
        let iv = NSImageView()
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let nameLabel: NSTextField = {
        let tf = NSTextField(labelWithString: "")
        tf.maximumNumberOfLines = 1
        tf.lineBreakMode = .byTruncatingTail
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }()

    private let highlightView: NSView = {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.cornerRadius = 5
        v.isHidden = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    // MARK: State

    private var isHovering = false

    // MARK: Init

    init(transform: any Transform, isHighlighted: Bool) {
        super.init(frame: .zero)
        heightAnchor.constraint(equalToConstant: 32).isActive = true
        buildLayout(transform: transform, isHighlighted: isHighlighted)
        addClickGesture()
        addTrackingArea()
    }

    required init?(coder: NSCoder) {
        fatalError("Use init(transform:isHighlighted:)")
    }

    // MARK: - Layout

    private func buildLayout(transform: any Transform, isHighlighted: Bool) {
        addSubview(highlightView)
        addSubview(iconView)
        addSubview(nameLabel)

        NSLayoutConstraint.activate([
            highlightView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            highlightView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            highlightView.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            highlightView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),

            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        // Icon.
        let symConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        iconView.image = NSImage(systemSymbolName: transform.icon, accessibilityDescription: transform.name)?
            .withSymbolConfiguration(symConfig)
        iconView.contentTintColor = isHighlighted ? .controlAccentColor : .secondaryLabelColor

        // Name label.
        nameLabel.font      = .systemFont(ofSize: 12.5, weight: isHighlighted ? .medium : .regular)
        nameLabel.textColor = isHighlighted ? .controlAccentColor : .labelColor
        nameLabel.stringValue = transform.name
    }

    // MARK: - Interaction

    private func addClickGesture() {
        let recognizer = NSClickGestureRecognizer(target: self, action: #selector(handleClick))
        addGestureRecognizer(recognizer)
    }

    @objc private func handleClick() {
        onTap?()
    }

    private func addTrackingArea() {
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateHoverState()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateHoverState()
    }

    private func updateHoverState() {
        highlightView.isHidden = !isHovering
        highlightView.layer?.backgroundColor = isHovering
            ? NSColor.labelColor.withAlphaComponent(0.07).cgColor
            : .none
    }
}
