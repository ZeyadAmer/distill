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
        static let updateBannerHeight: CGFloat = 32
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
        tv.allowsMultipleSelection = true   // ⌘-click builds a paste stack.

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

    private let stackButton: NSButton = {
        let btn = NSButton(title: "", target: nil, action: nil)
        btn.bezelStyle    = .circular
        btn.isBordered    = false
        let cfg           = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        btn.image         = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: "Paste Stack")?
            .withSymbolConfiguration(cfg)
        btn.contentTintColor = .secondaryLabelColor
        btn.toolTip       = "Paste Stack — ⌘-click several items, then every ⌘V pastes the next one"
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

    // MARK: - Subviews — Update banner

    /// Shown under the Recents/Pinned tabs only when a newer version is on the
    /// App Store. Tapping "Get update" opens the store page. See `UpdateChecker`.
    private lazy var updateBanner: NSView = {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.14).cgColor
        container.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)
        icon.contentTintColor = .controlAccentColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "Update available")
        label.font      = .systemFont(ofSize: 11.5, weight: .medium)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        let getButton = NSButton(title: "Get update", target: self, action: #selector(handleGetUpdate))
        getButton.bezelStyle   = .inline
        getButton.isBordered   = false
        getButton.font         = .systemFont(ofSize: 11.5, weight: .semibold)
        getButton.contentTintColor = .controlAccentColor
        getButton.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(icon)
        container.addSubview(label)
        container.addSubview(getButton)

        NSLayoutConstraint.activate([
            icon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            icon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            getButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            getButton.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
        ])

        return container
    }()

    private var updateBannerHeightConstraint: NSLayoutConstraint?

    /// App Store link resolved by the last update check; nil when up to date.
    private var updatePageURL: URL?

    // MARK: - Data

    /// Flat list of rows that the table renders — a mix of section headers and items.
    private var rows: [RowKind] = []

    /// The full store list filtered by the current search query (or the full list when empty).
    private var filteredItems: [ClipboardItem] = []

    /// Number of recent items fetched per page.
    private let pageSize = 100
    /// How many recent pages are currently loaded.
    private var loadedRecentCount = 0

    /// 0 = Recents, 1 = Pinned, 2 ..< (2 + folders.count) = a folder tab.
    private var currentTab: Int = 0

    /// Cached folder list backing the dynamic folder tabs. Refreshed by `rebuildTabs()`.
    private var folders: [Folder] = []

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
        rebuildTabs()
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
        rebuildTabs()
        currentTab = 0
        tabControl.selectedSegment = 0
        applySearch(query: "")
        selectFirstItem()
        searchField.becomeFirstResponder()
        updateTrialBanner()
        Task { await refreshUpdateBanner() }
    }

    /// Asks `UpdateChecker` whether a newer App Store version exists and shows
    /// or hides the banner accordingly. Best-effort — failures just hide it.
    private func refreshUpdateBanner() async {
        let result = await UpdateChecker.availableUpdate()
        updatePageURL = result?.pageURL
        let show = result != nil
        updateBanner.isHidden = !show
        updateBannerHeightConstraint?.constant = show ? Layout.updateBannerHeight : 0
    }

    @objc private func handleGetUpdate() {
        guard let url = updatePageURL else { return }
        NSWorkspace.shared.open(url)
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
        // Allow dragging items out of the panel into other apps.
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
        let rowMenu = NSMenu()
        rowMenu.delegate = self
        tableView.menu = rowMenu
        scrollView.documentView = tableView

        // ── Toolbar row ───────────────────────────────────────────────────────
        let toolbarRow = NSView()
        toolbarRow.translatesAutoresizingMaskIntoConstraints = false
        toolbarRow.heightAnchor.constraint(equalToConstant: Layout.toolbarRowHeight).isActive = true

        let toolbarStack = NSStackView(views: [pasteButton, transformButton, multiPasteButton, stackButton])
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

        // ── Update banner (hidden until a check finds a newer version) ─────────
        updateBanner.isHidden = true
        let updateConstraint = updateBanner.heightAnchor.constraint(equalToConstant: 0)
        updateConstraint.isActive = true
        updateBannerHeightConstraint = updateConstraint

        // ── Top-level separator ───────────────────────────────────────────────
        let searchSep = separatorView()
        let toolbarSep = separatorView()

        // ── Outer stack ───────────────────────────────────────────────────────
        let outerStack = NSStackView(views: [
            searchRow,
            searchSep,
            tabRow,
            tabSep,
            updateBanner,
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
            updateBanner.widthAnchor.constraint(equalTo: outerStack.widthAnchor),
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

        stackButton.target      = self
        stackButton.action      = #selector(handlePasteStack)

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

        // Resolve the folder for a folder tab, if any (guards array bounds).
        let folderIndex = currentTab - 2
        let activeFolder: Folder? = (folderIndex >= 0 && folderIndex < folders.count)
            ? folders[folderIndex]
            : nil

        if !trimmed.isEmpty {
            // Search spans full history; narrow to the current tab context.
            // Items whose assigned name matches rank first (name-first search).
            let results = Self.rankByRelevance(store.search(query: trimmed), query: trimmed)
            if let folder = activeFolder {
                filteredItems = results.filter { $0.folderID == folder.id }
            } else if currentTab == 1 {
                filteredItems = results.filter { $0.isPinned }
            } else {
                filteredItems = results.filter { !$0.isPinned && $0.folderID == nil }
            }
        } else if let folder = activeFolder {
            filteredItems = store.items(inFolder: folder.id)
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
        stackButton.isEnabled      = !isRestricted
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

    // MARK: - Dynamic tabs

    /// The number of selectable tabs (Recents, Pinned, and each folder) — i.e.
    /// every segment except the trailing "＋" add segment.
    private var selectableTabCount: Int { 2 + folders.count }

    /// The index of the trailing "＋" (add folder) segment.
    private var addSegmentIndex: Int { 2 + folders.count }

    /// Refreshes the cached folders and rebuilds the segmented control to
    /// ["Recents", "Pinned", <folder names…>, "＋"], preserving the current
    /// selection where possible.
    private func rebuildTabs() {
        folders = ClipboardStore.shared.folders

        let labels = ["Recents", "Pinned"] + folders.map { $0.name } + ["\u{FF0B}"]
        tabControl.segmentCount = labels.count
        for (index, label) in labels.enumerated() {
            tabControl.setLabel(label, forSegment: index)
        }
        // The trailing "＋" is a momentary add action, not a real tab; the
        // tooltip gives it an accessible description beyond the glyph label.
        tabControl.setToolTip("Add Folder", forSegment: addSegmentIndex)

        // Keep the current tab selected if it still exists; otherwise fall back
        // to Recents. Never leave the "＋" segment selected.
        let clamped = min(max(currentTab, 0), selectableTabCount - 1)
        currentTab = clamped
        tabControl.selectedSegment = clamped
    }

    // MARK: - Action handlers

    @objc private func handleTabChanged(_ sender: NSSegmentedControl) {
        // The trailing "＋" segment is an add action, not a tab.
        if sender.selectedSegment == addSegmentIndex {
            promptNewFolder()
            return
        }
        currentTab = sender.selectedSegment
        applySearch(query: searchField.stringValue)
        selectFirstItem()
    }

    /// Prompts for a folder name, creates it, rebuilds the tabs, and selects it.
    private func promptNewFolder() {
        let alert = NSAlert()
        alert.messageText     = "New Folder"
        alert.informativeText = "Name this folder so you can group items into it."
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        input.placeholderString = "Folder name"
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        guard runModalKeepingPanel(alert) == .alertFirstButtonReturn else {
            // Cancelled — restore the previously selected tab.
            tabControl.selectedSegment = currentTab
            return
        }
        let name = input.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            tabControl.selectedSegment = currentTab
            return
        }

        let folder = ClipboardStore.shared.createFolder(name: name)
        rebuildTabs()
        if let index = folders.firstIndex(where: { $0.id == folder.id }) {
            switchTab(to: 2 + index)
        } else {
            tabControl.selectedSegment = currentTab
        }
    }

    /// Switches to the given tab index and refreshes the list. Ignores the
    /// trailing "＋" add segment.
    private func switchTab(to index: Int) {
        guard index >= 0, index < selectableTabCount else { return }
        currentTab = index
        tabControl.selectedSegment = index
        applySearch(query: searchField.stringValue)
        selectFirstItem()
    }

    /// Cycles forward across the selectable tabs (Recents, Pinned, folders),
    /// skipping the "＋" add segment (bound to Tab / Shift-Tab).
    private func toggleTab() {
        guard selectableTabCount > 0 else { return }
        let next = (currentTab + 1) % selectableTabCount
        switchTab(to: next)
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
        transformPopover.onApplyStack = { [weak self] transforms in
            self?.pasteSelected(withStack: transforms)
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

    // MARK: - Context menu

    /// The item under the right-click, falling back to the current selection.
    private var contextItem: ClipboardItem? {
        let row = tableView.clickedRow
        if row >= 0, row < rows.count, case .item(let item) = rows[row] { return item }
        return selectedItem
    }

    /// Prompts for a searchable name and stores it on the item.
    @objc private func handleRename() {
        guard let item = contextItem else { return }
        let alert = NSAlert()
        alert.messageText     = "Name This Item"
        alert.informativeText = "Give it a name you can search for later (e.g. \u{201C}supabase\u{201D})."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        input.stringValue = item.label
        input.placeholderString = "Name"
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        guard runModalKeepingPanel(alert) == .alertFirstButtonReturn else { return }
        ClipboardStore.shared.setLabel(id: item.id, label: input.stringValue)
        reload()
    }

    /// Resolves redirects (network) then copies the tracking-free link.
    @objc private func handleCopyCleanLink() {
        guard let item = contextItem,
              let url = URL(string: item.content.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        Task {
            let cleaned = await LinkCleaner.resolveAndClean(url)
            PasteEngine.hotstashedCopy(cleaned.absoluteString)
        }
    }

    /// Assigns the context item to the folder carried in `representedObject`.
    @objc private func handleMoveToFolder(_ sender: NSMenuItem) {
        guard let item = contextItem,
              let folderID = sender.representedObject as? UUID else { return }
        ClipboardStore.shared.assignFolder(itemID: item.id, folderID: folderID)
        rebuildTabs()
        reload()
    }

    /// Prompts for a new folder name, creates it, and assigns the context item.
    @objc private func handleMoveToNewFolder() {
        guard let item = contextItem else { return }
        let alert = NSAlert()
        alert.messageText     = "New Folder"
        alert.informativeText = "Name this folder to move the item into it."
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        input.placeholderString = "Folder name"
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        guard runModalKeepingPanel(alert) == .alertFirstButtonReturn else { return }
        let name = input.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let folder = ClipboardStore.shared.createFolder(name: name)
        ClipboardStore.shared.assignFolder(itemID: item.id, folderID: folder.id)
        rebuildTabs()
        reload()
    }

    /// Removes the context item from its folder.
    @objc private func handleRemoveFromFolder() {
        guard let item = contextItem else { return }
        ClipboardStore.shared.assignFolder(itemID: item.id, folderID: nil)
        rebuildTabs()
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
        // ⌘/⇧-clicks build a multi-selection (paste stack) — don't overwrite
        // the clipboard while the user is still picking items.
        let mods = NSApp.currentEvent?.modifierFlags ?? []
        if mods.contains(.command) || mods.contains(.shift)
            || tableView.selectedRowIndexes.count > 1 {
            return
        }
        copySelected()
    }

    @objc private func handleDoubleClick() {
        guard tableView.clickedRow >= 0,
              tableView.clickedRow < rows.count,
              case .item = rows[tableView.clickedRow] else { return }
        // Select the double-clicked row, then paste it straight into the app
        // that was focused before Hotstash opened.
        tableView.selectRowIndexes(IndexSet(integer: tableView.clickedRow), byExtendingSelection: false)
        pasteSelected()
    }


    @objc private func handleClearAll() {
        let alert = NSAlert()
        alert.messageText     = "Clear All History?"
        alert.informativeText = "This removes all non-pinned items. Pinned items are kept."
        alert.addButton(withTitle: "Clear All")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard runModalKeepingPanel(alert) == .alertFirstButtonReturn else { return }
        ClipboardStore.shared.clearAll()
        reload()
    }

    @objc private func handleGear() {
        let menu = NSMenu()

        // Folder management for the active folder tab.
        if currentTab >= 2, currentTab - 2 < folders.count {
            let renameFolder = NSMenuItem(title: "Rename Folder\u{2026}", action: #selector(handleRenameFolder), keyEquivalent: "")
            renameFolder.target = self
            menu.addItem(renameFolder)

            let deleteFolder = NSMenuItem(title: "Delete Folder", action: #selector(handleDeleteFolder), keyEquivalent: "")
            deleteFolder.target = self
            menu.addItem(deleteFolder)

            menu.addItem(.separator())
        }

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

    /// Renames the folder backing the active folder tab.
    @objc private func handleRenameFolder() {
        guard currentTab >= 2, currentTab - 2 < folders.count else { return }
        let folder = folders[currentTab - 2]

        let alert = NSAlert()
        alert.messageText     = "Rename Folder"
        alert.informativeText = "Give this folder a new name."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        input.stringValue = folder.name
        input.placeholderString = "Folder name"
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        guard runModalKeepingPanel(alert) == .alertFirstButtonReturn else { return }
        let name = input.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        ClipboardStore.shared.renameFolder(id: folder.id, name: name)
        rebuildTabs()
        reload()
    }

    /// Deletes the folder backing the active folder tab after confirmation.
    @objc private func handleDeleteFolder() {
        guard currentTab >= 2, currentTab - 2 < folders.count else { return }
        let folder = folders[currentTab - 2]

        let alert = NSAlert()
        alert.messageText     = "Delete \u{201C}\(folder.name)\u{201D}?"
        alert.informativeText = "The folder is removed. Items inside it stay in your history but are no longer grouped."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard runModalKeepingPanel(alert) == .alertFirstButtonReturn else { return }

        ClipboardStore.shared.deleteFolder(id: folder.id)
        rebuildTabs()
        switchTab(to: 0)
        reload()
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
                runModalKeepingPanel(alert)
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
        PasteEngine.hotstashedCopy(item: item)
    }

    /// Copies the selected item and dismisses the panel (optionally applying a
    /// transform). `plainTextOnly` strips rich representations (⇧Return).
    func pasteSelected(with transform: (any Transform)? = nil, plainTextOnly: Bool = false) {
        guard let item = selectedItem else { return }

        ClipboardStore.shared.recordUse(id: item.id)
        if transform == nil && !item.isPinned {
            ClipboardStore.shared.moveToTop(id: item.id)
        }

        if item.contentType == .image, let data = item.imageData, let transform {
            PasteEngine.hotstashedPasteImage(transform.applyToImageData(data) ?? data)
            return
        }
        if let transform {
            PasteEngine.hotstashedPaste(transform.apply(to: item.content))
            return
        }
        PasteEngine.hotstashedPaste(item: item, plainTextOnly: plainTextOnly)
    }

    /// Applies an ordered stack of transforms to the selected item and pastes the
    /// result. Mirrors the single-transform path in `pasteSelected(with:)`: use is
    /// recorded but the item is not moved to top (matching transform behavior).
    func pasteSelected(withStack transforms: [any Transform]) {
        guard !transforms.isEmpty, let item = selectedItem else { return }

        ClipboardStore.shared.recordUse(id: item.id)

        if item.contentType == .image, let data = item.imageData {
            // Chain image transforms in order; a transform that can't process the
            // data (returns nil) is skipped, preserving the prior result.
            let finalData = transforms.reduce(data) { current, transform in
                transform.applyToImageData(current) ?? current
            }
            PasteEngine.hotstashedPasteImage(finalData)
            return
        }

        let result = transforms.reduce(item.content) { $1.apply(to: $0) }
        PasteEngine.hotstashedPaste(result)
    }

    /// Items currently selected in the table, top-to-bottom (paste stack source).
    private var selectedItems: [ClipboardItem] {
        tableView.selectedRowIndexes.sorted().compactMap { row in
            guard row < rows.count, case .item(let item) = rows[row] else { return nil }
            return item
        }
    }

    /// Starts a paste stack from the current multi-selection (⌘-click items).
    @objc private func handlePasteStack() {
        let items = selectedItems
        guard items.count >= 2 else {
            NSSound.beep()
            return
        }
        guard PasteStackManager.shared.start(items: items) else {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Needed"
            alert.informativeText = "Paste Stack watches for your ⌘V presses so it can stage the next item. Grant Hotstash Accessibility access in System Settings, then try again."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
            if runModalKeepingPanel(alert) == .alertFirstButtonReturn {
                AutoPasteService.openAccessibilitySettings()
            }
            return
        }
        ClipboardPanel.shared.dismiss()
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
        case 36: // Return — ⇧Return pastes plain text
            pasteSelected(plainTextOnly: event.modifierFlags.contains(.shift))
        case 125: // Down arrow
            moveSelection(by: +1)
        case 126: // Up arrow
            moveSelection(by: -1)
        case 48: // Tab
            toggleTab()
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

    /// Runs a modal alert while keeping the clipboard panel visible behind it,
    /// so the user sees the result (e.g. a new name) the moment they save.
    @discardableResult
    private func runModalKeepingPanel(_ alert: NSAlert) -> NSApplication.ModalResponse {
        ClipboardPanel.shared.suppressAutoHide = true
        defer {
            ClipboardPanel.shared.suppressAutoHide = false
            ClipboardPanel.shared.makeKeyAndOrderFront(nil)
        }
        return alert.runModal()
    }

    /// Re-orders search hits so items whose user-assigned name matches rank
    /// first (exact › prefix › contains), then content matches, weighted by
    /// how often an item is used; ties fall back to recency.
    static func rankByRelevance(_ items: [ClipboardItem], query: String) -> [ClipboardItem] {
        items.sorted { a, b in
            let sa = relevanceScore(a, query: query)
            let sb = relevanceScore(b, query: query)
            if sa != sb { return sa > sb }
            return a.timestamp > b.timestamp
        }
    }

    private static func relevanceScore(_ item: ClipboardItem, query: String) -> Int {
        let q = query.lowercased()
        var score = 0
        let label = item.label.lowercased()
        if !label.isEmpty {
            if label == q { score += 10_000 }
            else if label.hasPrefix(q) { score += 5_000 }
            else if label.contains(q) { score += 2_000 }
        }
        let content = item.content.lowercased()
        if content.hasPrefix(q) { score += 800 }
        else if content.contains(q) { score += 300 }
        score += min(item.useCount, 50) * 5
        return score
    }

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
        guard case .item(let item) = rows[row] else { return nil }
        let pbItem = NSPasteboardItem()
        // Internal reorder marker (pinned tab only).
        if currentTab == 1 {
            pbItem.setString(String(row), forType: .hotstashDragRow)
        }
        // Real content so the row can be dragged into other apps.
        switch item.contentType {
        case .image:
            if let data = item.imageData,
               let tiff = NSImage(data: data)?.tiffRepresentation {
                pbItem.setData(tiff, forType: .tiff)
            }
        case .file:
            if let first = item.copiedFiles.first {
                pbItem.setString(URL(fileURLWithPath: first.path).absoluteString,
                                 forType: .fileURL)
            }
            pbItem.setString(item.content, forType: .string)
        default:
            pbItem.setString(item.content, forType: .string)
        }
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
        // isRowSelected (not selectedRow) so every ⌘-clicked row highlights.
        let isSelected = tableView.isRowSelected(row)
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

// MARK: - NSMenuDelegate (row context menu)

extension ClipboardPanelVC: NSMenuDelegate {

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let item = contextItem else { return }

        let renameTitle = item.label.isEmpty ? "Name\u{2026}" : "Rename\u{2026}"
        let rename = NSMenuItem(title: renameTitle, action: #selector(handleRename), keyEquivalent: "")
        rename.target = self
        menu.addItem(rename)

        if item.contentType == .url {
            let clean = NSMenuItem(title: "Copy Clean Link", action: #selector(handleCopyCleanLink), keyEquivalent: "")
            clean.target = self
            menu.addItem(clean)
        }

        menu.addItem(.separator())

        // ── Move to Folder submenu ──────────────────────────────────────────
        let moveItem = NSMenuItem(title: "Move to Folder", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for folder in folders {
            let folderItem = NSMenuItem(title: folder.name, action: #selector(handleMoveToFolder(_:)), keyEquivalent: "")
            folderItem.target = self
            folderItem.representedObject = folder.id
            folderItem.state = (item.folderID == folder.id) ? .on : .off
            submenu.addItem(folderItem)
        }
        if !folders.isEmpty {
            submenu.addItem(.separator())
        }
        let newFolderItem = NSMenuItem(title: "New Folder\u{2026}", action: #selector(handleMoveToNewFolder), keyEquivalent: "")
        newFolderItem.target = self
        submenu.addItem(newFolderItem)
        moveItem.submenu = submenu
        menu.addItem(moveItem)

        if item.folderID != nil {
            let remove = NSMenuItem(title: "Remove from Folder", action: #selector(handleRemoveFromFolder), keyEquivalent: "")
            remove.target = self
            menu.addItem(remove)
        }
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

    /// Routes ↑/↓ to list selection and Return to paste while the search field
    /// keeps first-responder focus — so typing filters but the arrows move the
    /// list selection rather than the text caret.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: +1)
            return true
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            if selectedItem != nil {
                // ⇧Return pastes as plain text (strips RTF/HTML formatting).
                let shiftHeld = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
                pasteSelected(plainTextOnly: shiftHeld)
            }
            return true
        case #selector(NSResponder.insertTab(_:)),
             #selector(NSResponder.insertBacktab(_:)):
            toggleTab()
            return true
        default:
            return false
        }
    }
}
