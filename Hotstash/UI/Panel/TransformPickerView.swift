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

    /// Called on the main actor when the user commits a stack of transforms via
    /// the footer "Apply" button.
    var onApplyStack: (([any Transform]) -> Void)? {
        get { pickerVC.onApplyStack }
        set { pickerVC.onApplyStack = newValue }
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

    /// Called when the user commits an ordered stack of transforms.
    var onApplyStack: (([any Transform]) -> Void)?

    // MARK: Stack selection

    /// The ordered transforms the user has ⌘-clicked (or clicked while stacking).
    private var selection: [any Transform] = []

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
    private let stackView: FlippedStackView = {
        let sv = FlippedStackView()
        sv.orientation  = .vertical
        sv.alignment    = .leading
        sv.distribution = .fill
        sv.spacing      = 0
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    /// Footer bar pinned to the bottom of the popover, visible only while
    /// `selection` is non-empty. Hosts the "Apply" commit button.
    private let footerView: NSView = {
        let v = NSView()
        v.wantsLayer = true
        v.isHidden = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let footerDivider: NSBox = {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        return box
    }()

    private let applyButton: NSButton = {
        let btn = NSButton(title: "Apply", target: nil, action: nil)
        btn.bezelStyle = .rounded
        btn.controlSize = .large
        btn.keyEquivalent = "\r"
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let footerSubtitle: NSTextField = {
        let tf = NSTextField(labelWithString: "")
        tf.font      = .systemFont(ofSize: 10.5, weight: .regular)
        tf.textColor = .secondaryLabelColor
        tf.maximumNumberOfLines = 1
        tf.lineBreakMode = .byTruncatingMiddle
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }()

    /// The row views currently in the stack, keyed by transform id, so a toggle
    /// can flip the matching row's selected state without a full rebuild.
    private var rowsByID: [String: TransformRowView] = [:]

    /// The footer's height constraint, toggled between 0 and `footerHeight`.
    private var footerHeightConstraint: NSLayoutConstraint?

    // MARK: Footer geometry

    private static let footerHeight: CGFloat = 60

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
        // Each opening starts with a fresh, empty stack.
        selection = []
        rebuildRows()
        updateFooter()
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

        // ── Footer bar (Apply stack) ────────────────────────────────────────
        applyButton.target = self
        applyButton.action = #selector(handleApplyStack)

        footerView.addSubview(footerDivider)
        footerView.addSubview(applyButton)
        footerView.addSubview(footerSubtitle)
        view.addSubview(footerView)

        // The scroll view's bottom is pinned to the top of the footer. The footer
        // collapses to zero height when hidden (full-height list) and expands to
        // `footerHeight` when a stack is being built.
        let scrollBottom = scrollView.bottomAnchor.constraint(equalTo: footerView.topAnchor)
        let footerHeight = footerView.heightAnchor.constraint(equalToConstant: 0)
        footerHeightConstraint = footerHeight

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollBottom,
            footerHeight,

            // Stack fills the scroll view's width.
            stackView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: clipView.topAnchor),

            // Footer pinned to the bottom edge, full width.
            footerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            footerDivider.leadingAnchor.constraint(equalTo: footerView.leadingAnchor),
            footerDivider.trailingAnchor.constraint(equalTo: footerView.trailingAnchor),
            footerDivider.topAnchor.constraint(equalTo: footerView.topAnchor),

            applyButton.leadingAnchor.constraint(equalTo: footerView.leadingAnchor, constant: 12),
            applyButton.trailingAnchor.constraint(equalTo: footerView.trailingAnchor, constant: -12),
            applyButton.topAnchor.constraint(equalTo: footerDivider.bottomAnchor, constant: 8),

            footerSubtitle.leadingAnchor.constraint(equalTo: footerView.leadingAnchor, constant: 12),
            footerSubtitle.trailingAnchor.constraint(equalTo: footerView.trailingAnchor, constant: -12),
            footerSubtitle.topAnchor.constraint(equalTo: applyButton.bottomAnchor, constant: 4),
        ])
    }

    // MARK: - Stack commit

    @objc private func handleApplyStack() {
        guard !selection.isEmpty else { return }
        onApplyStack?(selection)
        dismiss(nil)
    }

    // MARK: - Row Construction

    private func rebuildRows() {
        guard isViewLoaded else { return }

        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        rowsByID.removeAll()

        let contentType = sourceItem?.contentType ?? .plainText

        if contentType == .image {
            // Show only image-applicable transforms.
            let imageTransforms = TransformRegistry.shared.all.filter {
                $0.applicableTo.contains(.image)
            }
            if !imageTransforms.isEmpty {
                addSectionHeader(title: "Image Transforms")
                for transform in imageTransforms {
                    addTransformRow(transform, isHighlighted: true)
                }
            }
            updatePreferredContentSize()
            return
        }

        // Suggested section for text items.
        let suggestions = TransformRegistry.shared.suggested(for: contentType)
        let suggestedIDs = Set(suggestions.map { $0.id })
        if !suggestions.isEmpty {
            addSectionHeader(title: "Suggested")
            for transform in suggestions {
                addTransformRow(transform, isHighlighted: true)
            }
            addDivider()
        }

        // All enabled text transforms in user-defined order.
        let ordered = TransformRegistry.shared.enabled
            .filter { !suggestedIDs.contains($0.id) && !$0.applicableTo.contains(.image) }
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
            self?.handleRowTap(transform)
        }
        rowsByID[transform.id] = row
        // Reflect any persisted selection (checkmarks survive rebuilds).
        row.setSelected(selection.contains { $0.id == transform.id })
        stackView.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
    }

    /// Row-click routing:
    /// - Plain click with an empty stack → single apply (today's behavior).
    /// - ⌘-click, or any click while stacking → toggle in the ordered stack.
    private func handleRowTap(_ transform: any Transform) {
        let commandHeld = NSApp.currentEvent?.modifierFlags.contains(.command) == true

        if !commandHeld && selection.isEmpty {
            onSelect?(transform)
            dismiss(nil)
            return
        }
        toggle(transform)
    }

    /// Appends the transform if absent (by id), or removes it if already present.
    /// Updates the matching row's checkmark and refreshes the footer.
    private func toggle(_ transform: any Transform) {
        if let index = selection.firstIndex(where: { $0.id == transform.id }) {
            selection.remove(at: index)
            rowsByID[transform.id]?.setSelected(false)
        } else {
            selection.append(transform)
            rowsByID[transform.id]?.setSelected(true)
        }
        updateFooter()
    }

    // MARK: - Footer

    /// Shows/hides the footer and refreshes its title + ordered subtitle to match
    /// the current stack, then re-measures the popover.
    private func updateFooter() {
        guard isViewLoaded else { return }
        let count = selection.count
        let show = count > 0

        footerView.isHidden = !show
        footerHeightConstraint?.constant = show ? Self.footerHeight : 0

        if show {
            let noun = count == 1 ? "transform" : "transforms"
            applyButton.title = "Apply \(count) \(noun)"
            footerSubtitle.stringValue = selection.map { $0.name }.joined(separator: " \u{2192} ")
        }
        updatePreferredContentSize()
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
        let footerHeight: CGFloat = footerView.isHidden ? 0 : Self.footerHeight
        let listHeight = min(stackView.fittingSize.height, Self.maxHeight - footerHeight)
        preferredContentSize = NSSize(width: Self.width, height: listHeight + footerHeight)
    }
}

// MARK: - FlippedStackView

private final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
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

    private let checkmarkView: NSImageView = {
        let iv = NSImageView()
        let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        iv.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Selected")?
            .withSymbolConfiguration(cfg)
        iv.contentTintColor = .controlAccentColor
        iv.isHidden = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    // MARK: State

    private var isHovering = false
    private var isStackSelected = false

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
        addSubview(checkmarkView)

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
            nameLabel.trailingAnchor.constraint(equalTo: checkmarkView.leadingAnchor, constant: -6),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            checkmarkView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            checkmarkView.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkmarkView.widthAnchor.constraint(equalToConstant: 14),
            checkmarkView.heightAnchor.constraint(equalToConstant: 14),
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
        // A stack-selected row keeps a subtle persistent tint; hover deepens it.
        let showHighlight = isHovering || isStackSelected
        highlightView.isHidden = !showHighlight

        let color: CGColor?
        if isStackSelected {
            color = NSColor.controlAccentColor
                .withAlphaComponent(isHovering ? 0.20 : 0.13).cgColor
        } else if isHovering {
            color = NSColor.labelColor.withAlphaComponent(0.07).cgColor
        } else {
            color = .none
        }
        highlightView.layer?.backgroundColor = color
    }

    // MARK: - Stack selection

    /// Shows/hides the trailing checkmark and the persistent selected tint.
    func setSelected(_ selected: Bool) {
        isStackSelected = selected
        checkmarkView.isHidden = !selected
        updateHoverState()
    }
}
