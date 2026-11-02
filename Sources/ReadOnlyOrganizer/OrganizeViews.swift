import SwiftUI
import OrganizerCore

/// Switch for Organize mode. Turning it on asks for confirmation every time.
struct OrganizeModeToggle: View {
    @ObservedObject var controller: ScanController
    @State private var confirming = false

    var body: some View {
        Toggle(isOn: Binding(
            get: { controller.organizeModeEnabled },
            set: { on in
                if on { confirming = true } else { controller.organizeModeEnabled = false }
            })) {
            Label("Organize mode", systemImage: controller.organizeModeEnabled ? "lock.open" : "lock")
        }
        .toggleStyle(.switch)
        .disabled(controller.phase.isBusy)
        .help("Allow creating folders and moving items into them. Never deletes, renames or edits.")
        .alert("Turn on Organize mode?", isPresented: $confirming) {
            Button("Turn On") { controller.organizeModeEnabled = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(SafetyPolicy.organizeModeExplanation)
        }
    }
}

/// Move destinations in menu order: your folders (Trash first), other
/// folders already inside the selected folder, then suggested category
/// folders that aren't listed yet.
struct MoveDestinations {
    let yours: [String]
    let existing: [String]
    let suggested: [String]

    @MainActor
    init(controller: ScanController) {
        yours = controller.quickFolders
        existing = controller.existingFolders.filter { !controller.quickFolders.contains($0) }
        let listed = Set(yours + existing)
        suggested = FileCategory.allCases.map(\.suggestedFolderName).filter { !listed.contains($0) }
    }
}

/// Menu items for every destination; shared by "Move to…" and the table's
/// right-click menu.
struct MoveDestinationItems: View {
    let destinations: MoveDestinations
    let move: (String) -> Void

    var body: some View {
        Section("Your folders") {
            ForEach(destinations.yours, id: \.self) { folder in
                Button {
                    move(folder)
                } label: {
                    if folder == FileOrganizer.trashFolderName {
                        Label("“\(folder)” folder (you empty it yourself)", systemImage: "trash")
                    } else {
                        Label(folder, systemImage: "folder")
                    }
                }
            }
        }
        if !destinations.existing.isEmpty {
            Section("Already in this folder") {
                ForEach(destinations.existing, id: \.self) { folder in
                    Button { move(folder) } label: { Label(folder, systemImage: "folder") }
                }
            }
        }
        if !destinations.suggested.isEmpty {
            Section("Suggested folders") {
                ForEach(destinations.suggested, id: \.self) { folder in
                    Button(folder) { move(folder) }
                }
            }
        }
    }
}

/// "Move to…" menu for the selected rows: any destination, or a new folder.
struct MoveMenu: View {
    @ObservedObject var controller: ScanController
    let ids: [Int]

    @State private var askingForName = false
    @State private var newFolderName = ""

    private var trimmedName: String { newFolderName.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Menu {
            MoveDestinationItems(destinations: MoveDestinations(controller: controller)) { folder in
                controller.move(recordIDs: ids, toFolderNamed: folder)
            }
            Divider()
            Button("New Folder…") {
                newFolderName = ""
                askingForName = true
            }
        } label: {
            Label(ids.count == 1 ? "Move to…" : "Move \(ids.count) items to…", systemImage: "folder.badge.plus")
        }
        .fixedSize()
        .disabled(ids.isEmpty || controller.phase.isBusy || !controller.organizeModeEnabled)
        .alert("Move into a new folder", isPresented: $askingForName) {
            TextField("Folder name", text: $newFolderName)
            Button("Move") {
                controller.move(recordIDs: ids, toFolderNamed: trimmedName)
            }
            .disabled(!FileOrganizer.isValidFolderName(trimmedName))
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The folder is created directly inside the selected folder if it doesn't exist. Items keep their names, and nothing is overwritten.")
        }
    }
}

/// Session log of moves with Undo, plus the result of the last action.
struct ChangesView: View {
    @ObservedObject var controller: ScanController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let report = controller.lastOrganizeReport {
                GroupBox("Last action: \(report.title)") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Moved \(report.movedCount) item(s). Skipped \(report.skipped.count).")
                        ForEach(report.skipped.prefix(200)) { outcome in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(outcome.path).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                Text(outcome.errorMessage ?? "").font(.caption).foregroundStyle(.orange)
                            }
                        }
                        if report.skipped.count > 200 {
                            Text("…and \(report.skipped.count - 200) more").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }
            }

            HStack {
                Text("Moves this session (\(controller.moveLog.count))").font(.headline)
                Spacer()
                Button("Undo All Moves") { controller.undo(controller.moveLog) }
                    .disabled(controller.moveLog.isEmpty || controller.phase.isBusy || !controller.organizeModeEnabled)
            }
            Text("Undo moves items back to where they were (if that spot is still free). This list is kept in memory only. After you quit, move things back in Finder if needed.")
                .font(.caption).foregroundStyle(.secondary)

            if controller.moveLog.isEmpty {
                Text(controller.organizeModeEnabled
                     ? "No moves yet. Use “Move to…” in the Files tab, or the Suggested Organization tab."
                     : "Organize mode is off, so the app is read-only. Turn it on in the toolbar to create folders and move items.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(Array(controller.moveLog.reversed())) { move in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(move.name).font(.body.weight(.medium))
                            Text("from  \(move.fromPath)").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                            Text("to    \(move.toPath)").font(.system(.caption, design: .monospaced))
                        }
                        .textSelection(.enabled)
                        Spacer()
                        Button("Undo") { controller.undo([move]) }
                            .disabled(controller.phase.isBusy || !controller.organizeModeEnabled)
                    }
                }
            }
        }
    }
}

/// Confirmation sheet for moving files into the suggested folders.
struct ApplyPlanSheet: View {
    @ObservedObject var controller: ScanController
    @Binding var isPresented: Bool

    @State private var selected: Set<String>
    private let counts: [String: Int]

    @MainActor
    init(controller: ScanController, isPresented: Binding<Bool>) {
        self._controller = ObservedObject(wrappedValue: controller)
        self._isPresented = isPresented
        var counts: [String: Int] = [:]
        for folder in controller.plan {
            counts[folder.name] = controller.movablePlanItems(inFolders: [folder.name]).count
        }
        self.counts = counts
        // Uncategorized starts unchecked: those files deserve a manual look.
        let defaults = controller.plan.map(\.name).filter {
            $0 != FileCategory.uncategorized.suggestedFolderName && (counts[$0] ?? 0) > 0
        }
        self._selected = State(initialValue: Set(defaults))
    }

    private var total: Int { selected.reduce(0) { $0 + (counts[$1] ?? 0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create folders and move files").font(.title2.weight(.semibold))
            Text("Each checked folder is created directly inside “\(controller.rootURL?.lastPathComponent ?? "")” if it doesn't exist, and its files are moved in with their names unchanged. Files in software projects and files already in place stay where they are. If a name is already taken in the destination, that file is skipped. Nothing is deleted, renamed, copied or overwritten, and you can undo from the Changes tab.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            List {
                ForEach(controller.plan) { folder in
                    let count = counts[folder.name] ?? 0
                    Toggle(isOn: Binding(
                        get: { selected.contains(folder.name) },
                        set: { if $0 { selected.insert(folder.name) } else { selected.remove(folder.name) } })) {
                        HStack {
                            Text(folder.name + "/")
                            Spacer()
                            Text("\(count) file(s)").foregroundStyle(.secondary)
                        }
                    }
                    .disabled(count == 0)
                }
            }
            .frame(minHeight: 280)
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Move \(total) File(s)") {
                    controller.applyPlan(folders: selected)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(total == 0)
            }
        }
        .padding(20)
        .frame(width: 600)
    }
}

/// "Your folders" bar: add folders that already exist (e.g. made in an
/// earlier session), create new ones, and remove buttons. The list is
/// remembered for each selected folder. Row buttons appear in Organize mode.
struct QuickFolderBar: View {
    @ObservedObject var controller: ScanController
    @State private var newFolderName = ""

    private var trimmedName: String { newFolderName.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        HStack(spacing: 8) {
            Text("Your folders:").font(.callout.weight(.medium))
            ExistingFolderMenu(controller: controller)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(controller.quickFolders, id: \.self) { folder in
                        HStack(spacing: 4) {
                            Image(systemName: folder == FileOrganizer.trashFolderName ? "trash" : "folder")
                            Text(folder)
                            if folder != FileOrganizer.trashFolderName {
                                Button {
                                    controller.removeQuickFolder(folder)
                                } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Remove this button (the folder on disk is not touched)")
                            }
                        }
                        .font(.callout)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                    }
                }
            }
            TextField(controller.organizeModeEnabled ? "New folder name" : "Organize mode creates folders",
                      text: $newFolderName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .onSubmit(create)
                .disabled(!controller.organizeModeEnabled)
            Button("Create Folder", action: create)
                .disabled(!canCreate)
        }
    }

    private var canCreate: Bool {
        controller.organizeModeEnabled && FileOrganizer.isValidFolderName(trimmedName) && !controller.phase.isBusy
    }

    private func create() {
        guard canCreate else { return }
        controller.addQuickFolder(named: trimmedName)
        newFolderName = ""
    }
}

/// Checklist of the folders already inside the selected folder; checked ones
/// join "Your folders". Only changes the list, never the disk, so it works
/// with Organize mode off too.
struct ExistingFolderMenu: View {
    @ObservedObject var controller: ScanController

    var body: some View {
        Menu {
            if controller.existingFolders.isEmpty {
                Text("There are no folders inside the selected folder yet.")
            } else {
                Button("Add All") { controller.includeAllExistingFolders() }
                Divider()
                ForEach(controller.existingFolders, id: \.self) { folder in
                    Toggle(folder, isOn: Binding(
                        get: { controller.quickFolders.contains(folder) },
                        set: { controller.setQuickFolder(folder, included: $0) }))
                    .disabled(folder == FileOrganizer.trashFolderName)
                }
            }
        } label: {
            Label("Add Existing Folder", systemImage: "plus.circle")
        }
        .fixedSize()
        .help("Add folders that are already inside the selected folder to Your folders")
    }
}

/// One-click "move here" buttons for a row, one per folder in the bar.
/// Takes plain values (no observed controller, no hover or selection state)
/// so table cells don't change while rows are being selected.
struct QuickMoveButtons: View {
    let record: FileRecord
    let folders: [String]
    let enabled: Bool
    let move: (String) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(folders, id: \.self) { folder in
                Button {
                    move(folder)
                } label: {
                    if folder == FileOrganizer.trashFolderName {
                        Label(folder, systemImage: "trash")
                    } else {
                        Text(folder)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!enabled || record.parentRelativePath == folder || record.relativePath == folder)
            }
        }
    }
}
