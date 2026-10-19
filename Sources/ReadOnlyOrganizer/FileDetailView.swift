import SwiftUI
import OrganizerCore

/// Metadata, category rationale, and session-only edits for one entry.
struct FileDetailView: View {
    @ObservedObject var controller: ScanController
    let recordID: Int

    var body: some View {
        if let record = controller.record(recordID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header(record)
                    if let classification = controller.effectiveClassification(for: recordID) {
                        categorySection(classification)
                        editSection
                    }
                    metadataSection(record)
                    groupSection
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func header(_ record: FileRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.name).font(.headline).textSelection(.enabled)
            Text(record.kind.displayName + (record.isHidden ? " · hidden" : ""))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func categorySection(_ classification: Classification) -> some View {
        GroupBox("Suggested category") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(classification.category.displayName).font(.body.weight(.semibold))
                    Text("· \(classification.confidence.displayName) confidence").foregroundStyle(.secondary)
                    if classification.isOverridden {
                        Text("(edited this session)").foregroundStyle(.blue)
                    }
                }
                Text(classification.explanation).font(.callout).textSelection(.enabled)
                if !classification.secondary.isEmpty {
                    DetailLine("Also relates to", classification.secondary.map(\.displayName).joined(separator: ", "))
                }
                if !classification.tags.isEmpty {
                    DetailLine("Tags", classification.tags.joined(separator: ", "))
                }
                if !classification.reviewReasons.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(classification.reviewReasons, id: \.self) { reason in
                            Label(reason, systemImage: "flag").font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                DetailLine("Rules", classification.ruleIDs.joined(separator: ", "))
                    .font(.system(.caption, design: .monospaced))
                Text("Confidence reflects how strong the filename/type rule evidence is. It is not a probability, and contents were not inspected.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private var editSection: some View {
        GroupBox("Your edits") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Category", selection: Binding<FileCategory?>(
                    get: { controller.overrides[recordID] },
                    set: { controller.setCategoryOverride($0, for: recordID) })) {
                    Text("Use rule result (\(controller.baseClassification(for: recordID)?.category.displayName ?? "—"))")
                        .tag(FileCategory?.none)
                    Divider()
                    ForEach(FileCategory.allCases) { Text($0.displayName).tag(FileCategory?.some($0)) }
                }
                Toggle("Review later", isOn: Binding(
                    get: { controller.reviewLater.contains(recordID) },
                    set: { controller.setReviewLater($0, for: recordID) }))
                Text(SafetyPolicy.sessionOnlyNote).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private func metadataSection(_ record: FileRecord) -> some View {
        GroupBox("Metadata (read from the filesystem)") {
            VStack(alignment: .leading, spacing: 4) {
                DetailLine("Full path", record.path, monospaced: true)
                DetailLine("Relative path", record.relativePath, monospaced: true)
                DetailLine("Size", record.size.map(Formatting.sizeWithBytes) ?? "—")
                DetailLine("Created", Formatting.date(record.created))
                DetailLine("Modified", Formatting.date(record.modified))
                DetailLine("Metadata changed", Formatting.date(record.metadataChanged))
                Text("“Metadata changed” is the filesystem status-change time (renames, permission changes). It is not the content modification time.")
                    .font(.caption2).foregroundStyle(.secondary)
                DetailLine("Last accessed", Formatting.date(record.accessed) + " (as reported; may be imprecise)")
                DetailLine("Extension", record.fileExtension.isEmpty ? "none" : "." + record.fileExtension)
                DetailLine("Type", [record.typeDescription, record.typeIdentifier].compactMap { $0 }.joined(separator: " — "))
                if let mime = record.mimeType { DetailLine("MIME type", mime) }
                DetailLine("Access", record.access.displayName)
                if let target = record.symlinkTarget {
                    DetailLine("Link target (not followed)", target, monospaced: true)
                    if record.symlinkPointsOutsideRoot == true {
                        Text("This link points outside the selected folder. It was not followed.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                ForEach(record.notes, id: \.self) { note in
                    Label(note, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    @ViewBuilder
    private var groupSection: some View {
        let groups = controller.groups(containing: recordID)
        if !groups.isEmpty {
            GroupBox("Suggested groups containing this file") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(group.kind.rawValue): \(group.title)").font(.callout.weight(.medium))
                            Text(group.explanation).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }
        }
    }
}

struct DetailLine: View {
    let label: String
    let value: String
    var monospaced = false

    init(_ label: String, _ value: String, monospaced: Bool = false) {
        self.label = label
        self.value = value
        self.monospaced = monospaced
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label + ":").foregroundStyle(.secondary).frame(width: 120, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .font(monospaced ? .system(.callout, design: .monospaced) : .callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
    }
}
