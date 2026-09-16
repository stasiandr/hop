import AppKit
import HopCore

struct Item {
    var title: String
    var subtitle: String?
    var terms: [String]
    var icon: NSImage?
    /// Built-in commands stay out of the default (empty query) list.
    var hiddenWhenEmpty = false
    var run: () -> Void
    /// ⌘Return; falls back to `run`.
    var altRun: (() -> Void)? = nil
}

/// The floating search panel: a text field on top, results below.
final class LauncherPanel: NSPanel, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private static let fieldHeight: CGFloat = 52
    private static let rowHeight: CGFloat = 44
    private static let padding: CGFloat = 8

    private let field = NSTextField()
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let errorLabel = NSTextField(labelWithString: "")

    private var allItems: [Item] = []
    private var results: [Item] = []
    private var width: CGFloat = 640
    private var maxResults = 8

    var error: String? {
        didSet {
            errorLabel.stringValue = error ?? ""
            errorLabel.isHidden = error == nil
            if isVisible { layoutForResults() }
        }
    }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 640, height: Self.fieldHeight),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.state = .active
        background.blendingMode = .behindWindow
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        contentView = background

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 24, weight: .light)
        field.placeholderString = "hop to…"
        field.delegate = self
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true

        errorLabel.textColor = .systemRed
        errorLabel.font = .systemFont(ofSize: 12)
        errorLabel.lineBreakMode = .byTruncatingTail
        errorLabel.isHidden = true

        let column = NSTableColumn(identifier: .init("item"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = Self.rowHeight
        table.intercellSpacing = .zero
        table.backgroundColor = .clear
        table.style = .plain
        table.selectionHighlightStyle = .regular
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clickedRow)
        table.refusesFirstResponder = true

        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false

        for view in [field, errorLabel, scroll] { background.addSubview(view) }
    }

    override var canBecomeKey: Bool { true }

    func apply(config: Config, items: [Item]) {
        width = config.width
        maxResults = config.maxResults
        allItems = items
        refresh()
    }

    func present() {
        field.stringValue = ""
        refresh()
        positionOnActiveScreen()
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Queries are app names: only Latin layouts, so a Russian (or any
        // non-Roman) layout left active elsewhere doesn't produce "ыфа".
        // The previous layout comes back once the panel loses focus.
        (fieldEditor(true, for: field) as? NSTextView)?.inputContext?.allowedInputSourceLocales =
            [NSAllRomanInputSourcesLocaleIdentifier]
        makeFirstResponder(field)
    }

    func dismiss() {
        orderOut(nil)
        NSApp.hide(nil) // hand focus back to the previous app
    }

    override func resignKey() {
        super.resignKey()
        if isVisible { orderOut(nil) }
    }

    // MARK: - Search

    private func refresh() {
        let query = field.stringValue
        let pool = query.isEmpty ? allItems.filter { !$0.hiddenWhenEmpty } : allItems
        results = Array(Matcher.rank(pool, query: query, terms: \.terms).prefix(maxResults))
        table.reloadData()
        if !results.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }
        layoutForResults()
    }

    private func layoutForResults() {
        let errorHeight: CGFloat = errorLabel.isHidden ? 0 : 20
        let listHeight = results.isEmpty ? 0 : CGFloat(results.count) * Self.rowHeight + Self.padding
        let height = Self.fieldHeight + errorHeight + listHeight

        // Keep the top edge fixed while the list grows or shrinks.
        var frame = self.frame
        let top = frame.maxY
        frame.size = NSSize(width: width, height: height)
        frame.origin.y = top - height
        setFrame(frame, display: true)

        let p = Self.padding * 2
        field.frame = NSRect(x: p, y: height - Self.fieldHeight + 10, width: width - p * 2, height: 32)
        errorLabel.frame = NSRect(x: p, y: height - Self.fieldHeight - errorHeight + 2, width: width - p * 2, height: 16)
        scroll.frame = NSRect(x: Self.padding, y: Self.padding / 2, width: width - Self.padding * 2, height: listHeight)
        table.tableColumns.first?.width = scroll.frame.width
    }

    private func positionOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let x = visible.midX - width / 2
        let top = visible.maxY - visible.height * 0.22
        setFrame(NSRect(x: x, y: top - frame.height, width: width, height: frame.height), display: false)
        layoutForResults()
    }

    private func runSelected(alt: Bool = false) {
        let row = table.selectedRow
        guard results.indices.contains(row) else { return }
        let item = results[row]
        // Run while hop is still active: macOS only lets the active app hand
        // over focus, so hiding first would leave running apps in the background.
        (alt ? item.altRun ?? item.run : item.run)()
        orderOut(nil)
    }

    @objc private func clickedRow() {
        guard table.clickedRow >= 0 else { return }
        table.selectRowIndexes([table.clickedRow], byExtendingSelection: false)
        runSelected()
    }

    private func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        let row = (table.selectedRow + delta + results.count) % results.count
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) { refresh() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)), #selector(NSResponder.insertTab(_:)): moveSelection(1)
        case #selector(NSResponder.moveUp(_:)), #selector(NSResponder.insertBacktab(_:)): moveSelection(-1)
        case #selector(NSResponder.insertNewline(_:)): runSelected()
        case #selector(NSResponder.cancelOperation(_:)):
            if field.stringValue.isEmpty { dismiss() } else { field.stringValue = ""; refresh() }
        default: return false
        }
        return true
    }

    // Cmd+Return runs the alternative action; Cmd+1…9 runs the nth result.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods == .command, event.keyCode == 36 || event.keyCode == 76 { // Return, keypad Enter
            runSelected(alt: true)
            return true
        }
        if mods == .command,
           let n = event.charactersIgnoringModifiers.flatMap(Int.init), (1...9).contains(n), n <= results.count {
            table.selectRowIndexes([n - 1], byExtendingSelection: false)
            runSelected()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: ResultCell.id, owner: nil) as? ResultCell ?? ResultCell()
        cell.configure(results[row], index: row)
        return cell
    }
}

private final class ResultCell: NSTableCellView {
    static let id = NSUserInterfaceItemIdentifier("ResultCell")

    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")
    private let shortcut = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        identifier = Self.id
        title.font = .systemFont(ofSize: 14, weight: .medium)
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingMiddle
        shortcut.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        shortcut.textColor = .tertiaryLabelColor
        shortcut.alignment = .right

        let text = NSStackView(views: [title, subtitle])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1

        for v in [icon, text, shortcut] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 30),
            icon.heightAnchor.constraint(equalToConstant: 30),
            text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.trailingAnchor.constraint(lessThanOrEqualTo: shortcut.leadingAnchor, constant: -8),
            shortcut.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            shortcut.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(_ item: Item, index: Int) {
        icon.image = item.icon
        title.stringValue = item.title
        subtitle.stringValue = item.subtitle ?? ""
        subtitle.isHidden = item.subtitle == nil
        shortcut.stringValue = index < 9 ? "⌘\(index + 1)" : ""
    }
}
