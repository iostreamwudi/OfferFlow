import AppKit
import SwiftUI

/// A fixed-height, view-based table keeps the cost of laying out thousands of
/// records proportional to the visible rows. Full record text stays in detail.
struct LiveJobsTable: NSViewRepresentable {
    let jobs: [LiveJobListing]
    let positions: [String: Int]
    let revision: Int
    let favorites: Set<String>
    @Binding var selectedID: String?
    @Binding var selectedIDs: Set<String>

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selectedID, selections: $selectedIDs) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 405, height: 0))
        table.autoresizingMask = [.width]
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("job"))
        column.minWidth = 250
        column.width = 405
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 104
        table.usesAutomaticRowHeights = false
        table.intercellSpacing = NSSize(width: 0, height: 1)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.style = .plain
        table.backgroundColor = .white
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.setAccessibilityLabel("招聘信息列表")

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.backgroundColor = .white
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let table = scroll.documentView as? NSTableView else { return }
        let coordinator = context.coordinator
        coordinator.selection = $selectedID
        coordinator.selections = $selectedIDs
        coordinator.applyingUpdate = true
        defer { coordinator.applyingUpdate = false }

        // SwiftUI also calls this for progress/status updates. Only a changed
        // result set should invalidate native rows or scan the record array.
        let contentChanged = coordinator.revision != revision
        let favoritesChanged = coordinator.favorites != favorites
        let previousSelection = coordinator.jobs.indices.contains(table.selectedRow) ? coordinator.jobs[table.selectedRow].id : nil
        coordinator.favorites = favorites
        if contentChanged {
            let topRow = table.row(at: NSPoint(x: 1, y: table.visibleRect.minY + 1))
            let anchor = coordinator.jobs.indices.contains(topRow) ? coordinator.jobs[topRow].id : nil
            let offset = topRow >= 0 ? table.visibleRect.minY - table.rect(ofRow: topRow).minY : 0
            coordinator.jobs = jobs
            coordinator.positions = positions
            coordinator.revision = revision
            table.reloadData()
            if let anchor, let row = positions[anchor] {
                // Preserve the first visible record when updated source rows
                // have been inserted above it. No row-height measurement needed.
                scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, table.rect(ofRow: row).minY + offset)))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        } else if favoritesChanged {
            let visible = table.rows(in: table.visibleRect)
            if visible.location != NSNotFound {
                for row in visible.location..<min(NSMaxRange(visible), coordinator.jobs.count) {
                    if let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? LiveJobTableCell {
                        let job = coordinator.jobs[row]
                        cell.setFavorite(favorites.contains(job.id))
                    }
                }
            }
        }

        let rows = IndexSet(selectedIDs.compactMap { coordinator.positions[$0] })
        if rows != table.selectedRowIndexes {
            table.selectRowIndexes(rows, byExtendingSelection: false)
            if rows.count == 1, let row = rows.first, previousSelection != selectedID { table.scrollRowToVisible(row) }
        }
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var jobs: [LiveJobListing] = []
        var positions: [String: Int] = [:]
        var favorites: Set<String> = []
        var revision = -1
        var selection: Binding<String?>
        var selections: Binding<Set<String>>
        var applyingUpdate = false

        init(selection: Binding<String?>, selections: Binding<Set<String>>) { self.selection = selection; self.selections = selections }

        func numberOfRows(in tableView: NSTableView) -> Int { jobs.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard jobs.indices.contains(row) else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("live-job-row")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? LiveJobTableCell
                ?? LiveJobTableCell(frame: .zero)
            cell.identifier = identifier
            let job = jobs[row]
            cell.configure(job, isFavorite: favorites.contains(job.id))
            return cell
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            LiveJobTableRow()
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !applyingUpdate, let table = notification.object as? NSTableView else { return }
            let ids = Set(table.selectedRowIndexes.compactMap { jobs.indices.contains($0) ? jobs[$0].id : nil })
            if selections.wrappedValue != ids { selections.wrappedValue = ids }
            let row = table.selectedRowIndexes.contains(table.clickedRow) ? table.clickedRow : table.selectedRow
            let value = jobs.indices.contains(row) ? jobs[row].id : nil
            if selection.wrappedValue != value { selection.wrappedValue = value }
        }
    }
}

private final class LiveJobTableRow: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        NSColor(red: 0.08, green: 0.43, blue: 0.36, alpha: 0.09).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 3), xRadius: 8, yRadius: 8).fill()
    }
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
}

private final class LiveJobTableCell: NSTableCellView {
    private let company = NSTextField(labelWithString: "")
    private let title = NSTextField(wrappingLabelWithString: "")
    private let city = NSTextField(labelWithString: "")
    private let deadline = NSTextField(labelWithString: "")
    private let bookmark = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        company.font = .systemFont(ofSize: 14, weight: .semibold)
        title.font = .systemFont(ofSize: 12)
        city.font = .systemFont(ofSize: 10)
        deadline.font = .systemFont(ofSize: 10)
        company.textColor = NSColor(red: 0.13, green: 0.18, blue: 0.17, alpha: 1)
        title.textColor = company.textColor
        city.textColor = .secondaryLabelColor
        deadline.textColor = .secondaryLabelColor
        title.maximumNumberOfLines = 2
        title.lineBreakMode = .byTruncatingTail
        for field in [company, city, deadline] {
            field.maximumNumberOfLines = 1
            field.lineBreakMode = .byTruncatingTail
        }
        deadline.alignment = .right
        bookmark.image = NSImage(systemSymbolName: "bookmark.fill", accessibilityDescription: "已收藏")
        bookmark.contentTintColor = NSColor(red: 0.08, green: 0.43, blue: 0.36, alpha: 1)
        for view in [company, title, city, deadline, bookmark] { addSubview(view) }
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let width = max(0, bounds.width - 40)
        company.frame = NSRect(x: 20, y: 13, width: max(0, width - 23), height: 19)
        bookmark.frame = NSRect(x: bounds.width - 34, y: 15, width: 13, height: 14)
        title.frame = NSRect(x: 20, y: 36, width: width, height: 33)
        let dateWidth = min(115, width * 0.4)
        city.frame = NSRect(x: 20, y: 80, width: max(0, width - dateWidth - 12), height: 15)
        deadline.frame = NSRect(x: bounds.width - 20 - dateWidth, y: 80, width: dateWidth, height: 15)
    }

    func configure(_ job: LiveJobListing, isFavorite: Bool) {
        // Bound only the row preview: an announcement can contain thousands of
        // title characters; neither the search index nor detail is truncated.
        company.stringValue = preview(job.company, length: 100)
        title.stringValue = preview(job.title, length: 300)
        city.stringValue = preview(job.city, length: 100)
        deadline.stringValue = job.deadline.isEmpty ? "截止时间未注明" : "截止 " + preview(job.deadline, length: 30)
        setFavorite(isFavorite)
        setAccessibilityLabel([company.stringValue, title.stringValue, city.stringValue, deadline.stringValue].joined(separator: "，"))
        needsLayout = true
    }

    func setFavorite(_ value: Bool) { bookmark.isHidden = !value }

    private func preview(_ value: String, length: Int) -> String {
        String(value.prefix(length)).replacingOccurrences(of: "\n", with: " ")
    }
}
