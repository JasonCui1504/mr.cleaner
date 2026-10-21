import SwiftUI
import OrganizerCore

struct FileTableView: View {
    @ObservedObject var controller: ScanController
    @Binding var selection: Set<Int>

    @State private var criteria = FilterCriteria()
    @State private var sortOrder: [KeyPathComparator<FileRow>] = [KeyPathComparator(\FileRow.relativePath)]
    @State private var displayed: [FileRow] = []
    /// Row under the mouse, to reveal its move buttons.
    @State private var hoveredRowID: Int?
    /// In Organize mode, leave out items moved this session and anything
    /// already inside the folders you sort into.
    @State private var hideMovedItems = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FilterBar(criteria: $criteria, extensions: controller.availableExtensions)
            if controller.organizeModeEnabled {
                QuickFolderBar(controller: controller)
                HStack(spacing: 10) {
                    MoveMenu(controller: controller, ids: selectedIDs) { selectNext(after: selectedIDs) }
                    Text(selection.isEmpty
                         ? "Hover a row and click a folder button to move it there, or select several rows (⌘-click / ⇧-click) and use this menu."
                         : "\(selection.count) selected. Items keep their names; nothing is overwritten.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Toggle("Hide sorted items", isOn: $hideMovedItems)
                        .help("Hides items you moved this session and everything already inside Trash, your folder buttons and the suggested folders, including from earlier sessions. Turn off to see them.")
                }
            }
            HSplitView {
                // Table is backed by NSTableView: rows are rendered lazily, so
                // very large result sets stay responsive.
                Table(displayed, selection: $selection, sortOrder: $sortOrder) {
                    TableColumn("Name", value: \.name) { row in
                        Label {
                            Text(row.name).fontWeight(row.isFolder ? .semibold : .regular)
                        } icon: {
                            Image(systemName: row.symbolName)
                                .foregroundStyle(row.isFolder ? Color.accentColor : Color.secondary)
                        }
                        .help(row.relativePath)
                        .rowHover(row.id, $hoveredRowID)
                    }
                    .width(min: 160, ideal: 260)
                    TableColumn("Move to") { row in
                        QuickMoveButtons(
                            controller: controller, recordID: row.id,
                            highlighted: hoveredRowID == row.id || selection.contains(row.id),
                            onMove: { selectNext(after: [row.id]) })
                            .rowHover(row.id, $hoveredRowID)
                    }
                    .width(min: 60, ideal: 240)
                    TableColumn("Category", value: \.categoryName) { row in
                        HStack(spacing: 4) {
                            Text(row.categoryName)
                            if row.needsReview {
                                Image(systemName: "flag.fill").foregroundStyle(.orange).help("Review candidate")
                            }
                        }
                        .rowHover(row.id, $hoveredRowID)
                    }
                    .width(min: 120, ideal: 180)
                    TableColumn("Type", value: \.typeName)
                        .width(min: 50, ideal: 70)
                    TableColumn("Size", value: \.sizeKey) { row in
                        Text(row.sizeText).monospacedDigit()
                    }
                    .width(min: 60, ideal: 80)
                    TableColumn("Created", value: \.createdKey) { row in
                        Text(row.createdText).monospacedDigit()
                            .foregroundStyle(row.record.created == nil ? Color.secondary : Color.primary)
                    }
                    .width(min: 120, ideal: 170)
                    TableColumn("Modified", value: \.modifiedKey) { row in
                        Text(row.modifiedText).monospacedDigit()
                    }
                    .width(min: 120, ideal: 170)
                    TableColumn("Relative Path", value: \.relativePath) { row in
                        Text(row.relativePath).rowHover(row.id, $hoveredRowID)
                    }
                    .width(min: 160, ideal: 300)
                    TableColumn("Confidence", value: \.confidenceRank) { row in
                        Text(row.confidenceText)
                    }
                    .width(min: 60, ideal: 80)
                }
                .frame(minWidth: 600)

                Group {
                    if selection.count == 1, let id = selection.first, controller.record(id) != nil {
                        FileDetailView(controller: controller, recordID: id)
                    } else if selection.count > 1 {
                        Text("\(selection.count) items selected.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Text("Select a row to see details and the reason for its category.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 300, idealWidth: 360, maxWidth: 520)
            }
            HStack {
                Text("\(displayed.count.formatted()) of \(controller.rows.count.formatted()) entries shown")
                Spacer()
                Text("Folders are shown in bold with a folder icon. Sizes and dates sort by their underlying values.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onAppear(perform: refresh)
        .onChange(of: criteria) { _ in refresh() }
        .onChange(of: sortOrder) { _ in refresh() }
        .onChange(of: controller.rowsVersion) { _ in refresh() }
        .onChange(of: hideMovedItems) { _ in refresh() }
        .onChange(of: controller.organizeModeEnabled) { _ in refresh() }
        .onChange(of: controller.quickFolders) { _ in refresh() }
        .onChange(of: controller.phase) { phase in
            // A rescan renumbers records, so an old selection would point at other files.
            if phase == .scanning { selection = [] }
        }
    }

    /// Selected records, in table order.
    private var selectedIDs: [Int] {
        displayed.map(\.id).filter { selection.contains($0) }
    }

    private func refresh() {
        var effective = criteria
        if controller.organizeModeEnabled && hideMovedItems {
            effective.excludedRelativePaths = controller.movedRelativePaths
            effective.collapsedFolders = controller.organizedFolderNames
        }
        displayed = effective.apply(to: controller.rows, sortedBy: sortOrder)
        // Don't keep hidden (just moved) rows selected.
        let visible = Set(displayed.map(\.id))
        if !selection.isSubset(of: visible) { selection.formIntersection(visible) }
    }

    /// After moving rows, select the row below them so the next item is ready
    /// for its folder button without another click.
    private func selectNext(after movedIDs: [Int]) {
        let moved = Set(movedIDs)
        guard let last = displayed.lastIndex(where: { moved.contains($0.id) }) else { return }
        let next = displayed[(last + 1)...].first { !moved.contains($0.id) }
            ?? displayed[..<last].last { !moved.contains($0.id) }
        hoveredRowID = nil
        if let next { selection = [next.id] } else { selection = [] }
    }
}

struct FilterBar: View {
    @Binding var criteria: FilterCriteria
    let extensions: [String]

    @State private var minMB = ""
    @State private var maxMB = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                TextField("Search names and paths", text: $criteria.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 220)
                Picker("Category", selection: $criteria.category) {
                    Text("All categories").tag(FileCategory?.none)
                    ForEach(FileCategory.allCases) { Text($0.displayName).tag(FileCategory?.some($0)) }
                }
                .frame(maxWidth: 260)
                Picker("Type", selection: $criteria.fileType) {
                    Text("All types").tag("")
                    ForEach(extensions, id: \.self) { Text("." + $0).tag($0) }
                }
                .frame(maxWidth: 160)
                Picker("Show", selection: $criteria.kind) {
                    ForEach(KindFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(maxWidth: 200)
            }
            HStack(spacing: 10) {
                Picker("Hidden", selection: $criteria.hidden) {
                    ForEach(HiddenFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(maxWidth: 220)
                Toggle("Needs review only", isOn: $criteria.reviewOnly)
                OptionalDatePicker(title: "Modified from", date: $criteria.modifiedFrom)
                OptionalDatePicker(title: "to", date: $criteria.modifiedTo)
                Text("Size (MB)")
                TextField("min", text: $minMB).frame(width: 60).textFieldStyle(.roundedBorder)
                TextField("max", text: $maxMB).frame(width: 60).textFieldStyle(.roundedBorder)
                Spacer()
                Button("Reset Filters") {
                    criteria = FilterCriteria()
                    minMB = ""
                    maxMB = ""
                }
            }
        }
        .onChange(of: minMB) { criteria.minBytes = Self.bytes(fromMB: $0) }
        .onChange(of: maxMB) { criteria.maxBytes = Self.bytes(fromMB: $0) }
    }

    private static func bytes(fromMB text: String) -> Int64? {
        guard let value = Double(text.trimmingCharacters(in: .whitespaces)), value >= 0 else { return nil }
        return Int64(value * 1_000_000)
    }
}

/// A date filter that can be switched off.
struct OptionalDatePicker: View {
    let title: String
    @Binding var date: Date?

    var body: some View {
        HStack(spacing: 4) {
            Toggle(title, isOn: Binding(
                get: { date != nil },
                set: { date = $0 ? (date ?? Date()) : nil }))
            if let current = date {
                DatePicker("", selection: Binding(get: { current }, set: { date = $0 }), displayedComponents: .date)
                    .labelsHidden()
                    .frame(width: 110)
            }
        }
    }
}

private extension View {
    /// Fills the cell and reports when the mouse is over this row.
    func rowHover(_ id: Int, _ hovered: Binding<Int?>) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside {
                    hovered.wrappedValue = id
                } else if hovered.wrappedValue == id {
                    hovered.wrappedValue = nil
                }
            }
    }
}
