import SwiftUI
import OrganizerCore

/// Suggested folder structure. In read-only mode it is a preview only; in
/// Organize mode a confirmed action can create the folders and move files in.
struct OrganizationView: View {
    @ObservedObject var controller: ScanController
    @State private var showingApplySheet = false

    /// Keeps an expanded folder responsive on very large scans.
    private static let itemLimit = 2_000

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PreviewOnlyBanner(organizeMode: controller.organizeModeEnabled)
            if controller.organizeModeEnabled && !controller.plan.isEmpty {
                HStack {
                    Button {
                        showingApplySheet = true
                    } label: {
                        Label("Create Folders and Move Files…", systemImage: "folder.badge.plus")
                    }
                    .disabled(controller.phase.isBusy)
                    Text("You choose which folders on the next screen. Nothing moves until you confirm.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if controller.plan.isEmpty {
                Text("Scan a folder to see a suggested structure.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(controller.plan) { folder in
                    DisclosureGroup {
                        ForEach(folder.items.prefix(Self.itemLimit)) { item in
                            PlannedItemRow(item: item)
                        }
                        if folder.items.count > Self.itemLimit {
                            Text("…and \(folder.items.count - Self.itemLimit) more. Use the Files tab with a category filter to see them all.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "folder.badge.questionmark").foregroundStyle(.secondary)
                            Text(folder.name + "/").font(.body.weight(.medium))
                            Text("(suggested)").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text("\(folder.items.count) items").foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingApplySheet) {
            ApplyPlanSheet(controller: controller, isPresented: $showingApplySheet)
        }
    }
}


struct PlannedItemRow: View {
    let item: PlannedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text("Suggested:").font(.caption).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                Text(item.suggestedPath)
                    .font(.system(.callout, design: .monospaced))
                    .italic()
                    .textSelection(.enabled)
                if item.hasNameCollision {
                    Text("name collision").font(.caption2)
                        .padding(.horizontal, 4)
                        .background(Capsule().fill(Color.orange.opacity(0.2)))
                        .help("Another file would get the same suggested path.")
                }
            }
            HStack(spacing: 6) {
                Text("Currently:").font(.caption).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                Text(item.currentRelativePath)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
            }
            Text(item.reason).font(.caption).foregroundStyle(.secondary).lineLimit(3)
        }
        .padding(.vertical, 3)
    }
}

struct PreviewOnlyBanner: View {
    let organizeMode: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "eye").font(.title2).foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 4) {
                Text(organizeMode ? "SUGGESTIONS: nothing moves until you confirm" : "PREVIEW ONLY: nothing has been moved")
                    .font(.headline)
                Text(organizeMode
                     ? "Use “Create Folders and Move Files…” to apply some or all of these, or move items one by one from the Files tab."
                     : SafetyPolicy.suggestionNote)
                    .font(.callout)
                Text("Each file still lives at its “Currently” path. The “Suggested” paths are hypothetical and shown in italics.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .foregroundStyle(Color.blue.opacity(0.7)))
    }
}
