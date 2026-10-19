import SwiftUI
import OrganizerCore

/// Rule-based group suggestions. Each group states why it exists.
struct GroupingView: View {
    @ObservedObject var controller: ScanController
    /// Jump to a file in the Files tab.
    let showInTable: (Int) -> Void

    @State private var kind: GroupKind = .potentialDuplicates

    private var visibleGroups: [FileGroup] {
        controller.groups.filter { $0.kind == kind }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Group type", selection: $kind) {
                ForEach(GroupKind.allCases) { kind in
                    let count = controller.groups.lazy.filter { $0.kind == kind }.count
                    Text("\(kind.rawValue) (\(count))").tag(kind)
                }
            }
            .frame(maxWidth: 420)

            Text(Self.description(of: kind)).font(.callout).foregroundStyle(.secondary)

            if visibleGroups.isEmpty {
                Text(controller.records.isEmpty ? "Scan a folder to see suggested groups." : "No groups of this type were found.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(visibleGroups) { group in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.explanation).font(.callout)
                            ForEach(group.memberIDs.prefix(300), id: \.self) { id in
                                if let record = controller.record(id) {
                                    HStack {
                                        Text(record.relativePath)
                                            .font(.system(.caption, design: .monospaced))
                                            .textSelection(.enabled)
                                        if let size = record.size {
                                            Text(Formatting.size(size)).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Button("Show in Files") { showInTable(id) }
                                            .buttonStyle(.link)
                                            .font(.caption)
                                    }
                                }
                            }
                            if group.memberIDs.count > 300 {
                                Text("…and \(group.memberIDs.count - 300) more").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    } label: {
                        HStack {
                            Text(group.title).font(.body.weight(.medium))
                            Spacer()
                            Text("\(group.memberIDs.count) items").foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    static func description(of kind: GroupKind) -> String {
        switch kind {
        case .potentialDuplicates:
            return "Files with the same name (ignoring “(1)”/“copy”) and the same size in bytes. Contents are not compared, so these are possible duplicates only — review before deciding anything."
        case .versionCluster:
            return "Files in the same folder whose names differ only by markers such as final, v2, draft, revised or copy."
        case .sameStem:
            return "Files in the same folder with the same name but different formats, such as report.docx and report.pdf."
        case .project:
            return "Folders containing software project files (package.json, pyproject.toml, Cargo.toml, .git, …). Keep these intact."
        case .sharedPrefix:
            return "Three or more files in the same folder whose names start with the same two words."
        case .keywordRelated:
            return "Files in different folders whose names contain exactly the same set of keywords."
        case .sameDay:
            return "Three or more files in the same folder, same category, modified on the same day, with a shared name pattern."
        case .folderTheme:
            return "Folders where at least 80% of the files (5 or more) share one category."
        }
    }
}
