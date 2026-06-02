import AppKit

// MARK: - Row kind

/// Discriminates between section-header rows and item rows in the table.
private enum RowKind {
    case sectionHeader(String)
    case item(ClipboardItem)
}

// MARK: - ClipboardPanelVC

/// The root view controller for the clipboard history panel.
///
/// Visual structure (top → bottom):
/// ```
/// ┌──────────────────────────────────────────────────┐
/// │  🔍 Search…                                  [✕] │  ← search row
/// ├──────────────────────────────────────────────────┤
/// │  NSScrollView > NSTableView                       │  ← item list
/// ├──────────────────────────────────────────────────┤
/// │  [Paste]  [Transform ▾]  [Pin]  [⌫]              │  ← toolbar
/// │  (Trial banner when trial is expired)             │
/// └──────────────────────────────────────────────────┘
/// ```
@MainActor
final class ClipboardPanelVC: NSViewController {

    // MARK: - Constants

    private enum Layout {
        static let searchRowHeight:   CGFloat = 44
        static let tabRowHeight:      CGFloat = 38
        static let toolbarRowHeight:  CGFloat = 44
        static let trialBannerHeight: CGFloat = 36
        static let horizontalPadding: CGFloat = 12
    }

    // MARK: - Subviews — Tab bar

    private let tabControl: NSSegmentedControl = {
        let sc = NSSegmentedControl(labels: ["Recents", "Pinned"], trackingMode: .selectOne, target: nil, action: nil)
        sc.selectedSegment = 0
        sc.segmentStyle    = .automatic
        sc.translatesAutoresizingMaskIntoConstraints = false
        return sc
    }()

    // MARK: - Subviews — Search row

    private let searchField: NSSearchField = {
        let sf = NSSearchField()
        sf.placeholderString = "Search clipboard history…"
        sf.bezelStyle = .roundedBezel
        sf.translatesAutoresizingMaskIntoConstraints = false
        return sf
    }()

    private let closeButton: NSButton = {
        let btn = NSButton()
        btn.title          = ""
        btn.bezelStyle     = .circular
        btn.isBordered     = false
        let cfg            = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        btn.image          = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")?
            .withSymbolConfiguration(cfg)
        btn.contentTintColor = .secondaryLabelColor
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    // MARK: - Subviews — Table

    private lazy var scrollView: NSScrollView = {
        let sv = NSScrollView()
        sv.hasVerticalScroller   = true
        sv.autohidesScrollers    = true
        sv.hasHorizontalScroller = false
        sv.drawsBackground       = false
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private lazy var tableView: NSTableView = {
        let tv = NSTableView()
        tv.headerView    = nil
        tv.backgroundColor = .clear
        tv.intercellSpacing = NSSize(width: 0, height: 0)
        tv.selectionHighlightStyle = .none  // We draw our own.
        tv.focusRingType = .none
        tv.rowHeight = ClipboardItemCell.rowHeight

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        col.isEditable = false
        tv.addTableColumn(col)

        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    // MARK: - Subviews — Toolbar

    private let pasteButton: NSButton = {
        let btn = NSButton(title: "Copy", target: nil, action: nil)
        btn.bezelStyle       = .rounded
        btn.keyEquivalent    = "\r"
        btn.toolTip          = "Copy to Clipboard (Return)"
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let transformButton: NSButton = {
        let btn = NSButton(title: "Transform ▾", target: nil, action: nil)
        btn.bezelStyle = .rounded
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let multiPasteButton: NSButton = {
        let btn = NSButton(title: "", target: nil, action: nil)
        btn.bezelStyle    = .circular
        btn.isBordered    = false
        let cfg           = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        btn.image         = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "Paste Multiple")?
            .withSymbolConfiguration(cfg)
        btn.contentTintColor = .secondaryLabelColor
        btn.toolTip       = "Paste Multiple Items (⌘⇧L)"
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let pinButton: NSButton = {
        let btn = NSButton(title: "", target: nil, action: nil)
        btn.bezelStyle   = .circular
        btn.isBordered   = false
        let cfg          = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        btn.image        = NSImage(systemSymbolName: "pin", accessibilityDescription: "Pin")?
            .withSymbolConfiguration(cfg)
        btn.contentTintColor = .secondaryLabelColor
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let deleteButton: NSButton = {
        let btn = NSButton(title: "", target: nil, action: nil)
        btn.bezelStyle   = .circular
        btn.isBordered   = false
        let cfg          = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        btn.image        = NSImage(systemSymbolName: "delete.left", accessibilityDescription: "Delete")?
            .withSymbolConfiguration(cfg)
        btn.contentTintColor = .secondaryLabelColor
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let clearAllButton: NSButton = {
        let btn = NSButton(title: "", target: nil, action: nil)
        btn.bezelStyle       = .circular
        btn.isBordered       = false
        let cfg              = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        btn.image            = NSImage(systemSymbolName: "trash.circle", accessibilityDescription: "Clear All")?
            .withSymbolConfiguration(cfg)
        btn.contentTintColor = .secondaryLabelColor
        btn.toolTip          = "Clear All History"
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let gearButton: NSButton = {
        let btn = NSButton(title: "", target: nil, action: nil)
        btn.bezelStyle   = .circular
        btn.isBordered   = false
        let cfg          = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        btn.image        = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")?
            .withSymbolConfiguration(cfg)
        btn.contentTintColor = .secondaryLabelColor
        btn.toolTip      = "Settings"
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    // MARK: - Subviews — Trial banner

    private lazy var trialBanner: NSView = {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.15).cgColor
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "Trial expired — ")
        label.font      = .systemFont(ofSize: 11.5, weight: .medium)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        let buyButton = NSButton(title: "Unlock Hotstash", target: self, action: #selector(handleBuy))
        buyButton.bezelStyle   = .inline
        buyButton.isBordered   = false
        buyButton.font         = .systemFont(ofSize: 11.5, weight: .semibold)
        buyButton.contentTintColor = .controlAccentColor
        buyButton.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(label)
        container.addSubview(buyButton)

        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            buyButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            buyButton.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 2),
        ])

        return container
    }()

    private var trialBannerHeightConstraint: NSLayoutConstraint?

    // MARK: - Data

    /// Flat list of rows that the table renders — a mix of section headers and items.
    private var rows: [RowKind] = []

    /// The full store list filtered by the current search query (or the full list when empty).
    private var filteredItems: [ClipboardItem] = []

    /// Number of recent items fetched per page.
    private let pageSize = 100
    /// How many recent pages are currently loaded.
    private var loadedRecentCount = 0

    /// 0 = Recents, 1 = Pinned.
    private var currentTab: Int = 0

    /// The row currently under the mouse cursor (-1 = none).
    private var hoveredRow: Int = -1 {
        didSet {
            guard oldValue != hoveredRow else { return }
            var dirty = IndexSet()
            if oldValue >= 0 { dirty.insert(oldValue) }
            if hoveredRow >= 0 { dirty.insert(hoveredRow) }
            if !dirty.isEmpty {
                tableView.reloadData(forRowIndexes: dirty, columnIndexes: IndexSet(integer: 0))
            }
        }
    }

    /// The transform popover; created lazily and reused across openings.
    private lazy var transformPopover = TransformPickerPopover()

    // MARK: - Derived selection

    private var selectedItem: ClipboardItem? {
        let row = tableView.selectedRow
        guard row >= 0, row < rows.count else { return nil }
        if case .item(let item) = rows[row] { return item }
        return nil
    }

    // MARK: - View lifecycle

    override func loadView() {
        view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildLayout()
        wireTargetActions()
        subscribeToNotifications()
        reload()
        installHoverTracking()
    }

    private func installHoverTracking() {
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        tableView.addTrackingArea(area)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = tableView.convert(event.locationInWindow, from: nil)
        let row = tableView.row(at: point)
        hoveredRow = row
    }

    override func mouseExited(with event: NSEvent) {
        hoveredRow = -1
    }

    // MARK: - Public interface (called by ClipboardPanel)

    /// Called just before the panel becomes visible so the view can reset state.
    func panelWillShow() {
        searchField.stringValue = ""
        currentTab = 0
        tabControl.selectedSegment = 0
        applySearch(query: "")
        selectFirstItem()
        searchField.becomeFirstResponder()
        updateTrialBanner()
    }

    // MARK: - Layout Construction

    private func buildLayout() {
        // ── Search row ────────────────────────────────────────────────────────
        let searchRow = NSView()
        searchRow.translatesAutoresizingMaskIntoConstraints = false
        searchRow.heightAnchor.constraint(equalToConstant: Layout.searchRowHeight).isActive = true

        searchRow.addSubview(searchField)
        searchRow.addSubview(closeButton)

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: searchRow.leadingAnchor, constant: Layout.horizontalPadding),
            searchField.centerYAnchor.constraint(equalTo: searchRow.centerYAnchor),
            searchField.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -6),

            closeButton.trailingAnchor.constraint(equalTo: searchRow.trailingAnchor, constant: -Layout.horizontalPadding),
            closeButton.centerYAnchor.constraint(equalTo: searchRow.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 22),
            closeButton.heightAnchor.constraint(equalToConstant: 22),
        ])

        // ── Tab bar ───────────────────────────────────────────────────────────
        let tabRow = NSView()
        tabRow.translatesAutoresizingMaskIntoConstraints = false
        tabRow.heightAnchor.constraint(equalToConstant: Layout.tabRowHeight).isActive = true
        tabRow.addSubview(tabControl)
        NSLayoutConstraint.activate([
            tabControl.centerXAnchor.constraint(equalTo: tabRow.centerXAnchor),
            tabControl.centerYAnchor.constraint(equalTo: tabRow.centerYAnchor),
        ])
        let tabSep = separatorView()

        // ── Scroll + table ────────────────────────────────────────────────────
        tableView.delegate   = self
        tableView.dataSource = self
        tableView.registerForDraggedTypes([.hotstashDragRow])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)
        scrollView.documentView = tableView

        // ── Toolbar row ───────────────────────────────────────────────────────
        let toolbarRow = NSView()
        toolbarRow.translatesAutoresizingMaskIntoConstraints = false
        toolbarRow.heightAnchor.constraint(equalToConstant: Layout.toolbarRowHeight).isActive = true

        let toolbarStack = NSStackView(views: [pasteButton, transformButton, multiPasteButton])
        toolbarStack.spacing     = 6
        toolbarStack.orientation = .horizontal
        toolbarStack.translatesAutoresizingMaskIntoConstraints = false

        let rightStack = NSStackView(views: [pinButton, deleteButton, clearAllButton, gearButton])
        rightStack.spacing     = 4
        rightStack.orientation = .horizontal
        rightStack.translatesAutoresizingMaskIntoConstraints = false

        toolbarRow.addSubview(toolbarStack)
        toolbarRow.addSubview(rightStack)

        NSLayoutConstraint.activate([
            toolbarStack.leadingAnchor.constraint(equalTo: toolbarRow.leadingAnchor, constant: Layout.horizontalPadding),
            toolbarStack.centerYAnchor.constraint(equalTo: toolbarRow.centerYAnchor),

            rightStack.trailingAnchor.constraint(equalTo: toolbarRow.trailingAnchor, constant: -Layout.horizontalPadding),
            rightStack.centerYAnchor.constraint(equalTo: toolbarRow.centerYAnchor),
        ])

        // ── Trial banner ──────────────────────────────────────────────────────
        let isRestricted = TrialManager.shared.isRestricted
        let bannerHeight: CGFloat = isRestricted ? Layout.trialBannerHeight : 0
        trialBanner.isHidden = !isRestricted
        let bannerHeightConstraint = trialBanner.heightAnchor.constraint(equalToConstant: bannerHeight)
        bannerHeightConstraint.isActive = true
        trialBannerHeightConstraint = bannerHeightConstraint

        // ── Top-level separator ───────────────────────────────────────────────
        let searchSep = separatorView()
        let toolbarSep = separatorView()

        // ── Outer stack ───────────────────────────────────────────────────────
        let outerStack = NSStackView(views: [
            searchRow,
            searchSep,
            tabRow,
            tabSep,
            scrollView,
            toolbarSep,
            toolbarRow,
            trialBanner,
        ])
        outerStack.orientation  = .vertical
        outerStack.spacing      = 0
        outerStack.distribution = .fill
        outerStack.alignment    = .leading
        outerStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(outerStack)

        NSLayoutConstraint.activate([
            outerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            outerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            outerStack.topAnchor.constraint(equalTo: view.topAnchor),
            outerStack.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Search and toolbar rows fill width.
            searchRow.widthAnchor.constraint(equalTo: outerStack.widthAnchor),
            toolbarRow.widthAnchor.constraint(equalTo: outerStack.widthAnchor),
            trialBanner.widthAnchor.constraint(equalTo: outerStack.widthAnchor),
            searchSep.widthAnchor.constraint(equalTo: outerStack.widthAnchor),
            toolbarSep.widthAnchor.constraint(equalTo: outerStack.widthAnchor),

            // Table column fills the scroll view's clip view.
            tableView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])
    }

    // MARK: - Wire Target/Actions

    private func wireTargetActions() {
        tabControl.target      = self
        tabControl.action      = #selector(handleTabChanged(_:))

        closeButton.target     = self
        closeButton.action     = #selector(handleClose)

        pasteButton.target     = self
        pasteButton.action     = #selector(handlePaste)

        transformButton.target = self
        transformButton.action = #selector(handleTransformButtonTapped(_:))

        multiPasteButton.target = self
        multiPasteButton.action = #selector(handleMultiPaste)

        pinButton.target       = self
        pinButton.action       = #selector(handlePin)

        deleteButton.target    = self
        deleteButton.action    = #selector(handleDelete)

        clearAllButton.target  = self
        clearAllButton.action  = #selector(handleClearAll)

        gearButton.target      = self
        gearButton.action      = #selector(handleGear)

        tableView.target       = self
        tableView.action       = #selector(handleSingleClick)
        tableView.doubleAction = #selector(handleDoubleClick)

        searchField.delegate   = self
    }

    // MARK: - Notifications

    private func subscribeToNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleClipboardUpdate),
            name: .clipboardDidUpdate,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePurchaseStateChanged),
            name: .purchaseStateChanged,
            object: nil
        )
    }

    @objc private func handleClipboardUpdate() {
        reload()
    }

    @objc private func handlePurchaseStateChanged() {
        updateTrialBanner()
    }

    // MARK: - Data Reload

    /// Rebuilds `filteredItems` from the store (or from the current search query)
    /// and reloads the table.
    private func reload() {
        let query = searchField.stringValue
        applySearch(query: query)
    }

    /// Filters items by `query` and rebuilds the `rows` array.
    private func applySearch(query: String) {
        let store = ClipboardStore.shared
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        if !trimmed.isEmpty {
            // Search spans full history; split by current tab below.
            let results = store.search(query: trimmed)
            filteredItems = currentTab == 0
                ? results.filter { !$0.isPinned }
                : results.filter {  $0.isPinned }
        } else if currentTab == 1 {
            filteredItems = store.pinnedItems
        } else {
            loadedRecentCount = pageSize
            filteredItems = store.recentItems(limit: loadedRecentCount)
        }

        if TrialManager.shared.isRestricted {
            filteredItems = Array(filteredItems.prefix(TrialManager.freeHistoryLimit))
        }

        rebuildRows()
        tableView.reloadData()
        updateToolbarState()
    }

    /// Appends the next page of recent items (recent tab, no active search).
    private func loadMoreIfNeeded(currentRow: Int) {
        guard currentTab == 0,
              searchField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty,
              !TrialManager.shared.isRestricted,
              currentRow >= rows.count - 10,
              filteredItems.count >= loadedRecentCount  // a full page was returned
        else { return }
        loadedRecentCount += pageSize
        filteredItems = ClipboardStore.shared.recentItems(limit: loadedRecentCount)
        rebuildRows()
        // Defer to the next run-loop turn: this runs inside viewFor(row:), and
        // reloadData() must not be called reentrantly during that callback.
        DispatchQueue.main.async { [weak self] in
            self?.tableView.reloadData()
        }
    }

    /// Converts `filteredItems` into a flat `[RowKind]` for the active tab.
    private func rebuildRows() {
        rows = filteredItems.map { .item($0) }
    }

    // MARK: - Selection

    private func selectFirstItem() {
        let firstItemRow = rows.firstIndex(where: {
            if case .item = $0 { return true }
            return false
        })
        if let row = firstItemRow {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        } else {
            tableView.deselectAll(nil)
        }
        updateToolbarState()
    }

    // MARK: - Toolbar state

    private func updateToolbarState() {
        let hasSelection = selectedItem != nil
        let isRestricted = TrialManager.shared.isRestricted
        pasteButton.isEnabled      = hasSelection
        transformButton.isEnabled  = hasSelection && !isRestricted
        multiPasteButton.isEnabled = !isRestricted
        pinButton.isEnabled       = hasSelection
        deleteButton.isEnabled    = hasSelection
        clearAllButton.isEnabled  = currentTab == 0 && ClipboardStore.shared.recentCount > 0

        // Update the pin button icon depending on item state.
        if let item = selectedItem {
            let symbolName = item.isPinned ? "pin.slash" : "pin"
            let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            pinButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: item.isPinned ? "Unpin" : "Pin")?
                .withSymbolConfiguration(cfg)
        }
    }

    private func updateTrialBanner() {
        let isRestricted = TrialManager.shared.isRestricted
        let targetHeight: CGFloat = isRestricted ? Layout.trialBannerHeight : 0

        trialBanner.isHidden = !isRestricted
        trialBannerHeightConstraint?.constant = targetHeight
        updateToolbarState()
    }

    // MARK: - Action handlers

    @objc private func handleTabChanged(_ sender: NSSegmentedControl) {
        currentTab = sender.selectedSegment
        applySearch(query: searchField.stringValue)
        selectFirstItem()
    }

    @objc private func handleClose() {
        ClipboardPanel.shared.dismiss()
    }

    @objc private func handlePaste() {
        pasteSelected()
    }

    @objc private func handleTransformButtonTapped(_ sender: NSButton) {
        guard let item = selectedItem else { return }
        transformPopover.sourceItem = item
        transformPopover.onSelect = { [weak self] transform in
            self?.pasteSelected(with: transform)
        }
        transformPopover.show(
            relativeTo: sender.bounds,
            of: sender,
            preferredEdge: .maxY
        )
    }

    @objc private func handlePin() {
        guard let item = selectedItem else { return }
        let store = ClipboardStore.shared
        if item.isPinned {
            store.unpin(id: item.id)
        } else {
            store.pin(id: item.id)
        }
        reload()
    }

    @objc private func handleDelete() {
        guard let item = selectedItem else { return }
        ClipboardStore.shared.remove(id: item.id)
        reload()
    }

    @objc private func handleMultiPaste() {
        if MultiPastePanel.shared.isVisible {
            MultiPastePanel.shared.hide()
        } else {
            MultiPastePanel.shared.show()
        }
    }

    @objc private func handleSingleClick() {
        guard tableView.clickedRow >= 0,
              tableView.clickedRow < rows.count,
              case .item = rows[tableView.clickedRow] else { return }
        copySelected()
    }

    @objc private func handleDoubleClick() {
        guard tableView.clickedRow >= 0,
              tableView.clickedRow < rows.count,
              case .item = rows[tableView.clickedRow] else { return }
        ClipboardPanel.shared.dismiss()
    }


    @objc private func handleClearAll() {
        let alert = NSAlert()
        alert.messageText     = "Clear All History?"
        alert.informativeText = "This removes all non-pinned items. Pinned items are kept."
        alert.addButton(withTitle: "Clear All")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        ClipboardStore.shared.clearAll()
        reload()
    }

    @objc private func handleGear() {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Settings\u{2026}", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Hotstash", action: #selector(quitApp), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: gearButton.bounds.maxY + 4), in: gearButton)
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func handleBuy() {
        Task {
            do {
                try await PurchaseManager.shared.purchase()
            } catch {
                let alert = NSAlert()
                alert.messageText     = "Purchase Unavailable"
                alert.informativeText = "Unable to complete the purchase. Please check your internet connection and try again.\n\n\(error.localizedDescription)"
                alert.alertStyle      = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    // MARK: - Paste

    /// Copies the selected item to the clipboard. Panel stays open.
    private func copySelected() {
        guard let item = selectedItem else { return }
        ClipboardStore.shared.recordUse(id: item.id)
        if !item.isPinned {
            ClipboardStore.shared.moveToTop(id: item.id)
        }
        if item.contentType == .image, let data = item.imageData {
            PasteEngine.hotstashedCopyImage(data)
        } else {
            PasteEngine.hotstashedCopy(item.content)
        }
    }

    /// Copies the selected item and dismisses the panel (optionally applying a transform).
    func pasteSelected(with transform: (any Transform)? = nil) {
        guard let item = selectedItem else { return }

        ClipboardStore.shared.recordUse(id: item.id)
        if transform == nil && !item.isPinned {
            ClipboardStore.shared.moveToTop(id: item.id)
        }

        if item.contentType == .image, let data = item.imageData {
            let outputData = transform?.applyToImageData(data) ?? data
            PasteEngine.hotstashedPasteImage(outputData)
            return
        }

        let text: String = transform?.apply(to: item.content) ?? item.content
        PasteEngine.hotstashedPaste(text)
    }

    // MARK: - Position paste (⌘1–⌘9)

    func pasteItemAtPosition(_ position: Int) {
        var count = 0
        for (index, row) in rows.enumerated() {
            if case .item = row {
                count += 1
                if count == position {
                    MultiPastePanel.shared.hide()
                    tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                    tableView.scrollRowToVisible(index)
                    pasteSelected()
                    return
                }
            }
        }
    }

    // MARK: - Keyboard navigation

    // Physical key codes for 1–9 on a US keyboard layout.
    private static let numberKeyCodes: [UInt16: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5,
        22: 6, 26: 7, 28: 8, 25: 9,
    ]

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           let position = Self.numberKeyCodes[event.keyCode] {
            pasteItemAtPosition(position)
            return
        }
        switch event.keyCode {
        case 125: // Down arrow
            moveSelection(by: +1)
        case 126: // Up arrow
            moveSelection(by: -1)
        default:
            super.keyDown(with: event)
        }
    }

    private func moveSelection(by delta: Int) {
        let current = tableView.selectedRow
        var candidate = current + delta

        // Skip section-header rows.
        while candidate >= 0 && candidate < rows.count {
            if case .item = rows[candidate] { break }
            candidate += delta
        }

        guard candidate >= 0 && candidate < rows.count else { return }
        tableView.selectRowIndexes(IndexSet(integer: candidate), byExtendingSelection: false)
        tableView.scrollRowToVisible(candidate)
        updateToolbarState()
    }

    // MARK: - Helpers

    private func separatorView() -> NSView {
        let box = NSBox()
        box.boxType   = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return box
    }
}

// MARK: - NSTableViewDataSource

extension ClipboardPanelVC: NSTableViewDataSource {

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        guard currentTab == 1, case .item = rows[row] else { return nil }
        let pbItem = NSPasteboardItem()
        pbItem.setString(String(row), forType: .hotstashDragRow)
        return pbItem
    }

    func tableView(_ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard currentTab == 1, dropOperation == .above else { return [] }
        return .move
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let pbItem = info.draggingPasteboard.pasteboardItems?.first,
              let rowStr = pbItem.string(forType: .hotstashDragRow),
              let sourceRow = Int(rowStr) else { return false }
        let dest = row > sourceRow ? row - 1 : row
        guard dest != sourceRow else { return false }
        ClipboardStore.shared.reorderPinned(from: sourceRow, to: dest)
        reload()
        return true
    }
}

// MARK: - NSTableViewDelegate

extension ClipboardPanelVC: NSTableViewDelegate {

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        switch rows[row] {
        case .sectionHeader:
            return 24
        case .item(let item):
            return item.contentType == .image
                ? ClipboardItemCell.imageRowHeight
                : ClipboardItemCell.rowHeight
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        loadMoreIfNeeded(currentRow: row)
        switch rows[row] {
        case .sectionHeader(let title):
            return makeSectionHeaderView(title: title, for: tableView)
        case .item(let item):
            return makeItemCell(for: item, row: row, in: tableView)
        }
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rv = NSTableRowView()
        rv.isEmphasized = false
        return rv
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tv = notification.object as? NSTableView else { return }

        let selectedRow = tv.selectedRow
        if selectedRow >= 0, case .sectionHeader = rows[selectedRow] {
            moveSelection(by: +1)
            return
        }

        // Reload visible rows to update highlight.
        let visibleRange = tv.rows(in: tv.visibleRect)
        let indexSet = IndexSet(integersIn: visibleRange.location ..< (visibleRange.location + visibleRange.length))
        tv.reloadData(forRowIndexes: indexSet, columnIndexes: IndexSet(integer: 0))
        updateToolbarState()
    }

    // MARK: - Cell factories

    private func makeSectionHeaderView(title: String, for tableView: NSTableView) -> NSView {
        let identifier = NSUserInterfaceItemIdentifier("SectionHeader")
        if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTextField {
            reused.stringValue = title
            return reused
        }
        let label = NSTextField(labelWithString: title)
        label.identifier = identifier
        label.font       = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor  = .tertiaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let container = NSView()
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
        ])
        return container
    }

    private func makeItemCell(for item: ClipboardItem, row: Int, in tableView: NSTableView) -> ClipboardItemCell {
        let cell = (tableView.makeView(withIdentifier: ClipboardItemCell.reuseIdentifier, owner: nil) as? ClipboardItemCell)
            ?? ClipboardItemCell()
        cell.identifier = ClipboardItemCell.reuseIdentifier
        let isSelected = tableView.selectedRow == row
        let isHovered  = hoveredRow == row && !isSelected

        var itemCount = 0
        for kind in rows.prefix(row + 1) {
            if case .item = kind { itemCount += 1 }
        }
        let hotkey: Int? = itemCount <= 9 ? itemCount : nil

        cell.configure(with: item, isSelected: isSelected, isHovered: isHovered, hotkey: hotkey, showsDragHandle: currentTab == 1)
        return cell
    }
}

// MARK: - Pasteboard type

private extension NSPasteboard.PasteboardType {
    static let hotstashDragRow = NSPasteboard.PasteboardType("com.zeyadamer.hotstash.dragRow")
}

// MARK: - NSSearchFieldDelegate

extension ClipboardPanelVC: NSSearchFieldDelegate {

    func controlTextDidChange(_ obj: Notification) {
        guard let sf = obj.object as? NSSearchField else { return }
        applySearch(query: sf.stringValue)
    }
}
