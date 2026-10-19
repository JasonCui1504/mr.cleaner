import SwiftUI
import OrganizerCore

struct ContentView: View {
    @ObservedObject var controller: ScanController
    @State private var tab: Tab = .summary
    /// Shared between the file table and the other tabs ("show in table").
    @State private var selectedRecordID: Int?

    enum Tab: Hashable { case summary, files, groups, organization }

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(controller: controller)
            SafetyBanner()
            Divider()
            TabView(selection: $tab) {
                SummaryView(controller: controller)
                    .tabItem { Text("Dashboard") }
                    .tag(Tab.summary)
                FileTableView(controller: controller, selection: $selectedRecordID)
                    .tabItem { Text("Files") }
                    .tag(Tab.files)
                GroupingView(controller: controller) { id in
                    selectedRecordID = id
                    tab = .files
                }
                .tabItem { Text("Groups") }
                .tag(Tab.groups)
                OrganizationView(controller: controller)
                    .tabItem { Text("Suggested Organization (Preview)") }
                    .tag(Tab.organization)
            }
            .padding(12)
        }
        .frame(minWidth: 1000, minHeight: 650)
    }
}

struct HeaderBar: View {
    @ObservedObject var controller: ScanController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    if let url = FolderPicker.chooseFolder() { controller.select(root: url) }
                } label: {
                    Label("Choose Folder…", systemImage: "folder")
                }
                .disabled(controller.phase.isBusy)

                Button {
                    controller.startScan()
                } label: {
                    Label("Scan Folder", systemImage: "magnifyingglass")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(controller.rootURL == nil || controller.phase.isBusy)

                if controller.phase == .scanning {
                    Button(role: .cancel) {
                        controller.stopScan()
                    } label: {
                        Label("Stop Scan", systemImage: "stop.circle")
                    }
                }

                Menu {
                    Toggle("Include hidden files", isOn: $controller.options.includeHidden)
                    Toggle("Skip contents of .git / .svn / .hg folders", isOn: $controller.options.skipVersionControlInternals)
                    Toggle("Measure package sizes (metadata only)", isOn: $controller.options.measurePackageSizes)
                } label: {
                    Label("Scan Options", systemImage: "slider.horizontal.3")
                }
                .fixedSize()
                .disabled(controller.phase.isBusy)

                Spacer()
                StatusBadge()
            }

            HStack(spacing: 6) {
                Text("Selected folder:").foregroundStyle(.secondary)
                Text(controller.rootURL?.path ?? "None — choose a folder to begin")
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer()
                StatusLine(controller: controller)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

struct StatusLine: View {
    @ObservedObject var controller: ScanController

    var body: some View {
        HStack(spacing: 6) {
            switch controller.phase {
            case .idle:
                Text("No folder selected").foregroundStyle(.secondary)
            case .ready:
                Text("Ready — press Scan Folder").foregroundStyle(.secondary)
            case .scanning:
                ProgressView().controlSize(.small)
                Text("Scanning… \(controller.progress.files) files, \(controller.progress.folders) folders · \(controller.progress.currentFolder)")
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: 420, alignment: .trailing)
            case .analyzing:
                ProgressView().controlSize(.small)
                Text("Categorizing \(controller.progress.totalEntries) entries…")
            case .finished:
                Text("Scan complete: \(controller.progress.files) files, \(controller.progress.folders) folders"
                     + (controller.lastScanDuration.map { String(format: " in %.1fs", $0) } ?? ""))
            case .stopped:
                Text("Scan stopped — showing partial results (\(controller.progress.totalEntries) entries)")
                    .foregroundStyle(.orange)
            case .failed(let message):
                Text(message).foregroundStyle(.red).lineLimit(2)
            }
        }
        .font(.callout)
    }
}

struct StatusBadge: View {
    var body: some View {
        Label(SafetyPolicy.headline, systemImage: "lock.shield")
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.green.opacity(0.15)))
            .overlay(Capsule().stroke(Color.green.opacity(0.6)))
            .help(SafetyPolicy.readEffectsNote)
    }
}

struct SafetyBanner: View {
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.shield").foregroundStyle(.green)
                Text(SafetyPolicy.bannerText).font(.callout)
                Spacer()
                Button(expanded ? "Less" : "About reads") { expanded.toggle() }
                    .buttonStyle(.link)
            }
            if expanded {
                Text(SafetyPolicy.readEffectsNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 26)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.green.opacity(0.07))
    }
}
