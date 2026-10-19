import SwiftUI
import OrganizerCore

struct SummaryView: View {
    @ObservedObject var controller: ScanController

    private var summary: ScanSummary { controller.summary }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if controller.records.isEmpty {
                    EmptyStateView(phase: controller.phase)
                } else {
                    if controller.phase == .stopped {
                        Label("The scan was stopped. These numbers cover only the entries found before stopping.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    tiles
                    HStack(alignment: .top, spacing: 12) {
                        categoryBreakdown
                        fileTypes
                    }
                    HStack(alignment: .top, spacing: 12) {
                        recordList("Largest files", ids: summary.largestFileIDs) { record in
                            Formatting.size(record.size ?? 0)
                        }
                        recordList("Recently modified", ids: summary.recentlyModifiedIDs) { record in
                            Formatting.date(record.modified)
                        }
                    }
                    thresholdsEditor
                    issuesList
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var tiles: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], alignment: .leading, spacing: 12) {
            StatTile(title: "Files", value: summary.files.formatted(),
                     detail: summary.packages > 0 ? "incl. \(summary.packages) packages" : nil)
            StatTile(title: "Folders", value: summary.folders.formatted())
            StatTile(title: "Total size", value: Formatting.size(summary.totalBytes),
                     detail: "\(summary.totalBytes.formatted()) bytes")
            StatTile(title: "Needs review", value: summary.needsReview.formatted(),
                     detail: "low confidence, ambiguous, or marked by you")
            StatTile(title: "Potential duplicate groups", value: summary.potentialDuplicateGroups.formatted(),
                     detail: "\(summary.potentialDuplicateFiles) files · same name + size, not content-verified")
            StatTile(title: "Large files", value: summary.largeFiles.formatted(),
                     detail: "≥ \(Formatting.size(controller.thresholds.largeFileBytes))")
            StatTile(title: "Old files", value: summary.oldFiles.formatted(),
                     detail: "modified more than \(controller.thresholds.oldFileDays) days ago")
            StatTile(title: "Recent files", value: summary.recentFiles.formatted(),
                     detail: "modified in the last \(controller.thresholds.recentFileDays) days")
            StatTile(title: "Creation date unavailable", value: summary.unavailableCreationDates.formatted(),
                     detail: "filesystem did not report a birth time")
            StatTile(title: "Symbolic links", value: summary.symbolicLinks.formatted(), detail: "not followed")
            StatTile(title: "Hidden entries", value: summary.hiddenEntries.formatted())
            StatTile(title: "Not readable / cloud-only", value: "\(summary.notReadable) / \(summary.cloudPlaceholders)",
                     detail: "skipped, metadata only")
        }
    }

    private var thresholdsEditor: some View {
        GroupBox("Thresholds (this session only)") {
            HStack(spacing: 24) {
                Stepper(value: Binding(
                    get: { Int(controller.thresholds.largeFileBytes / 1_000_000) },
                    set: { controller.thresholds.largeFileBytes = Int64(max($0, 1)) * 1_000_000 }),
                        in: 1...100_000, step: 50) {
                    Text("Large file: \(Formatting.size(controller.thresholds.largeFileBytes))")
                }
                Stepper(value: $controller.thresholds.oldFileDays, in: 7...3650, step: 30) {
                    Text("Old: > \(controller.thresholds.oldFileDays) days")
                }
                Stepper(value: $controller.thresholds.recentFileDays, in: 1...365) {
                    Text("Recent: ≤ \(controller.thresholds.recentFileDays) days")
                }
            }
            .padding(6)
        }
    }

    private var categoryBreakdown: some View {
        GroupBox("Files by primary category") {
            let total = max(summary.countsByCategory.values.reduce(0, +), 1)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Category.allCases) { category in
                    let count = summary.countsByCategory[category] ?? 0
                    if count > 0 {
                        HStack {
                            Text(category.displayName).frame(width: 220, alignment: .leading)
                            GeometryReader { proxy in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.accentColor.opacity(0.7))
                                    .frame(width: max(2, proxy.size.width * CGFloat(count) / CGFloat(total)))
                            }
                            .frame(height: 12)
                            Text(count.formatted()).monospacedDigit().frame(width: 80, alignment: .trailing)
                        }
                    }
                }
                Text("Categories are suggestions from filename and type rules. File contents were not inspected.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(6)
        }
    }

    private var fileTypes: some View {
        GroupBox("Top file types") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(summary.extensionStats) { stat in
                    HStack {
                        Text(stat.fileExtension == "(none)" ? "(no extension)" : "." + stat.fileExtension)
                            .font(.system(.callout, design: .monospaced))
                        Spacer()
                        Text(stat.count.formatted()).monospacedDigit()
                        Text(Formatting.size(stat.bytes)).monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .trailing)
                    }
                }
            }
            .padding(6)
        }
        .frame(width: 300)
    }

    /// A short list of records with one value column.
    private func recordList(_ title: String, ids: [Int], value: @escaping (FileRecord) -> String) -> some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(ids, id: \.self) { id in
                    if let record = controller.record(id) {
                        HStack {
                            Text(record.relativePath)
                                .font(.system(.callout, design: .monospaced))
                                .lineLimit(1).truncationMode(.middle)
                                .help(record.relativePath)
                            Spacer()
                            Text(value(record)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
                if ids.isEmpty {
                    Text("None").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    @ViewBuilder
    private var issuesList: some View {
        if !controller.issues.isEmpty {
            GroupBox("Skipped or inaccessible (\(controller.issues.count))") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(controller.issues.prefix(200)) { issue in
                        HStack(alignment: .top) {
                            Text(issue.relativePath).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            Text("— \(issue.message)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if controller.issues.count > 200 {
                        Text("…and \(controller.issues.count - 200) more").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
            if let detail {
                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }
}

struct EmptyStateView: View {
    let phase: ScanController.Phase

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How it works").font(.title3.weight(.semibold))
            Text("1. Click “Choose Folder…” and pick any folder you can open.")
            Text("2. Click “Scan Folder”. Only that folder and its subfolders are listed; symbolic links are not followed.")
            Text("3. Review the summary, the file table, suggested groups, and the suggested (virtual) organization.")
            Text("Nothing is changed on disk and nothing is saved. Results disappear when you quit.")
                .foregroundStyle(.secondary)
            if phase.isBusy {
                ProgressView("Working…").padding(.top, 8)
            }
        }
        .padding()
    }
}
