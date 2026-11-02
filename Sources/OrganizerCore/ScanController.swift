import Foundation
import Combine

/// Main-actor state for the UI. Scanning and analysis run on a background
/// task; only small progress updates and the final result hop to the main
/// actor, so the UI stays responsive.
///
/// Everything here is in memory. Session edits (category overrides, "review
/// later") are discarded when the app quits and are never written anywhere.
/// The one exception is the list of "Your folders" names per selected folder,
/// which is remembered through `FolderListStore` when one is given.
///
/// Organize mode (off by default, every launch) is the only way to change the
/// filesystem, and it is limited to what `FileOrganizer` allows: creating
/// folders directly inside the selected folder and moving items into them.
@MainActor
public final class ScanController: ObservableObject {

    public enum Phase: Equatable {
        case idle
        case ready
        case scanning
        case analyzing
        case finished
        case stopped
        case organizing
        case failed(String)

        public var isBusy: Bool { self == .scanning || self == .analyzing || self == .organizing }
    }

    @Published public private(set) var rootURL: URL?
    @Published public private(set) var phase: Phase = .idle
    @Published public private(set) var progress = ScanProgress()
    @Published public private(set) var records: [FileRecord] = []
    @Published public private(set) var issues: [ScanIssue] = []
    @Published public private(set) var groups: [FileGroup] = []
    @Published public private(set) var projects: [ProjectInfo] = []
    @Published public private(set) var rows: [FileRow] = []
    /// Increments whenever `rows` changes, for cheap change detection in views.
    @Published public private(set) var rowsVersion = 0
    @Published public private(set) var summary = ScanSummary()
    @Published public private(set) var plan: [PlannedFolder] = []
    @Published public private(set) var overrides: [Int: FileCategory] = [:]
    @Published public private(set) var reviewLater: Set<Int> = []
    @Published public private(set) var lastScanDuration: TimeInterval?

    /// Off at every launch. While off, no folder is created and nothing is moved.
    @Published public var organizeModeEnabled = false
    /// Moves made this session (newest last), for Undo. In memory only.
    @Published public private(set) var moveLog: [FileOrganizer.Move] = []
    @Published public private(set) var lastOrganizeReport: OrganizeReport?
    /// Folders shown as one-click "move here" buttons on every row. Names only;
    /// the folders themselves live inside the selected folder. Remembered per
    /// selected folder when a `FolderListStore` was given, else in memory.
    @Published public private(set) var quickFolders: [String] = [FileOrganizer.trashFolderName] {
        didSet { saveQuickFolders() }
    }
    /// Folders that already exist directly inside the selected folder (listed
    /// when it is chosen, updated by each scan or refresh), e.g. ones made in
    /// an earlier session. They can be added to `quickFolders` and are
    /// offered as move destinations.
    @Published public private(set) var existingFolders: [String] = []

    @Published public var options = ScanOptions()
    @Published public var thresholds = SummaryThresholds() {
        didSet { if thresholds != oldValue { recomputeSummary() } }
    }

    private var baseClassifications: [Classification?] = []
    private var projectByRecord: [Int: String] = [:]
    private var groupsByRecord: [Int: [Int]] = [:]
    private var scanTask: Task<Void, Never>?
    private var resultsArePartial = false
    private var cancellation: CancellationFlag?
    private let folderStore: FolderListStore?

    /// - Parameter folderStore: where "Your folders" is remembered between
    ///   launches; `nil` keeps it in memory only (used by tests).
    public init(folderStore: FolderListStore? = nil) {
        self.folderStore = folderStore
    }

    // MARK: Folder selection

    public func select(root: URL) {
        guard !phase.isBusy else { return }
        clearResults()
        let root = root.standardizedFileURL
        rootURL = root
        if let folderStore {
            quickFolders = Self.withTrashFirst(folderStore.folders(forRoot: root.path))
        }
        existingFolders = FolderScanner.topLevelFolderNames(in: root).filter(FileOrganizer.isValidFolderName)
        phase = .ready
    }

    // MARK: Scanning

    /// Starts a scan of the selected folder and returns immediately.
    public func startScan() {
        guard let root = rootURL, !phase.isBusy else { return }
        clearResults()
        phase = .scanning
        let flag = CancellationFlag()
        cancellation = flag
        let scanner = FolderScanner(options: options)

        // The controller lives for the whole app session, so a strong capture is fine.
        scanTask = Task.detached(priority: .userInitiated) {
            let outcome: Result<AnalysisResult, Error>
            do {
                let scan = try scanner.scan(root: root, cancellation: flag) { _, progress in
                    Task { @MainActor in self.updateProgress(progress) }
                }
                await MainActor.run { self.phase = .analyzing }
                outcome = .success(Analyzer.analyze(scan))
            } catch {
                outcome = .failure(error)
            }
            await MainActor.run { self.finish(outcome) }
        }
    }

    /// Requests cancellation. Records found so far are kept and analyzed.
    public func stopScan() {
        cancellation?.cancel()
    }

    /// Waits for the running scan (if any) to finish. Used by tests.
    public func waitForScan() async {
        await scanTask?.value
    }

    private func updateProgress(_ newProgress: ScanProgress) {
        guard phase == .scanning else { return }
        progress = newProgress
    }

    private func finish(_ outcome: Result<AnalysisResult, Error>, isRefresh: Bool = false) {
        scanTask = nil
        switch outcome {
        case .failure(let error):
            phase = .failed(error.localizedDescription)
        case .success(let analysis):
            let scan = analysis.scan
            records = scan.records
            issues = scan.issues
            baseClassifications = analysis.classifications
            groups = analysis.groups
            projects = analysis.projects
            projectByRecord = analysis.projectByRecord
            var index: [Int: [Int]] = [:]
            for (groupIndex, group) in groups.enumerated() {
                for member in group.memberIDs { index[member, default: []].append(groupIndex) }
            }
            groupsByRecord = index
            if !isRefresh { lastScanDuration = scan.finishedAt.timeIntervalSince(scan.startedAt) }
            resultsArePartial = scan.wasCancelled
            var final = ScanProgress()
            final.files = records.filter { $0.kind.isFileLike }.count
            final.folders = records.filter { $0.kind == .directory }.count
            final.otherEntries = records.count - final.files - final.folders
            final.issues = issues.count
            progress = final
            existingFolders = Self.topLevelFolderNames(in: records)
            rebuildRows()
            recomputeSummary()
            rebuildPlan()
            phase = scan.wasCancelled ? .stopped : .finished
        }
    }

    private func clearResults() {
        records = []
        issues = []
        groups = []
        projects = []
        rows = []
        rowsVersion += 1
        summary = ScanSummary()
        plan = []
        overrides = [:]
        reviewLater = []
        baseClassifications = []
        projectByRecord = [:]
        groupsByRecord = [:]
        progress = ScanProgress()
        lastScanDuration = nil
    }

    // MARK: Session-only edits

    public func baseClassification(for id: Int) -> Classification? {
        id < baseClassifications.count ? baseClassifications[id] : nil
    }

    public func effectiveClassification(for id: Int) -> Classification? {
        guard let base = baseClassification(for: id) else { return nil }
        if let override = overrides[id] { return base.overridden(with: override) }
        return base
    }

    /// Sets (or with `nil`, clears) a session-only category for a file.
    public func setCategoryOverride(_ category: FileCategory?, for id: Int) {
        guard let base = baseClassification(for: id) else { return }
        if let category, category != base.category {
            overrides[id] = category
        } else {
            overrides[id] = nil
        }
        refreshRow(id)
        recomputeSummary()
        rebuildPlan()
    }

    public func setReviewLater(_ flag: Bool, for id: Int) {
        guard id < records.count else { return }
        if flag { reviewLater.insert(id) } else { reviewLater.remove(id) }
        refreshRow(id)
        recomputeSummary()
    }

    public func groups(containing id: Int) -> [FileGroup] {
        (groupsByRecord[id] ?? []).map { groups[$0] }
    }

    public func record(_ id: Int) -> FileRecord? {
        id >= 0 && id < records.count ? records[id] : nil
    }

    /// Extensions present in the results, for the type filter.
    public var availableExtensions: [String] {
        Array(Set(records.lazy.filter { $0.kind != .directory }.map(\.fileExtension).filter { !$0.isEmpty })).sorted()
    }

    // MARK: Organize mode (create folders + move only)

    /// Folders offered as move destinations: the Trash folder plus every
    /// suggested category folder.
    public var destinationFolderNames: [String] {
        [FileOrganizer.trashFolderName] + FileCategory.allCases.map(\.suggestedFolderName)
    }

    /// Moves the given records (keeping their names) into `root/folderName`.
    /// With several records, see `movableSources` for what is left out.
    public func move(recordIDs: [Int], toFolderNamed folderName: String) {
        let sources = movableSources(recordIDs: recordIDs, toFolderNamed: folderName)
        runOrganize(description: "Move to “\(folderName)”") { organizer in
            sources.map { source in
                OrganizeReport.Outcome(path: source.path, result: Result { try organizer.move(source, intoFolderNamed: folderName) })
            }
        }
    }

    /// The items a move of `recordIDs` actually needs to move: each record
    /// once, without items inside another selected folder (they travel with
    /// that folder), the destination folder itself, and items already in it.
    public func movableSources(recordIDs: [Int], toFolderNamed folderName: String) -> [URL] {
        var seen = Set<Int>()
        let selected = recordIDs.filter { seen.insert($0).inserted }.compactMap { self.record($0) }
        let selectedFolders = selected.filter { $0.kind == .directory }.map { $0.path + "/" }
        return selected.filter { record in
            record.relativePath != folderName && record.parentRelativePath != folderName
                && !selectedFolders.contains { record.path.hasPrefix($0) }
        }.map { URL(fileURLWithPath: $0.path) }
    }

    /// Plan items that "apply plan" would move for the given folders: not in
    /// a software project, a file or package, and not already in place.
    public func movablePlanItems(inFolders folders: Set<String>) -> [PlannedItem] {
        plan.filter { folders.contains($0.name) }.flatMap(\.items).filter { item in
            guard !item.isInProject, let record = self.record(item.id), record.kind.isFileLike else { return false }
            return record.parentRelativePath != item.folderName
        }
    }

    /// Creates the chosen suggested folders and moves their files into them.
    public func applyPlan(folders: Set<String>) {
        let moves = movablePlanItems(inFolders: folders).compactMap { item -> (URL, String)? in
            guard let record = self.record(item.id) else { return nil }
            return (URL(fileURLWithPath: record.path), item.folderName)
        }
        runOrganize(description: "Move files into suggested folders") { organizer in
            moves.map { source, folder in
                OrganizeReport.Outcome(path: source.path, result: Result { try organizer.move(source, intoFolderNamed: folder) })
            }
        }
    }

    /// Moves an item back to its original location (nothing is overwritten).
    public func undo(_ moves: [FileOrganizer.Move]) {
        let ordered = Array(moves.reversed())
        runOrganize(description: "Undo", undoing: Set(ordered.map(\.id))) { _ in
            ordered.map { move in
                OrganizeReport.Outcome(path: move.toPath, result: Result {
                    try FileOrganizer(root: URL(fileURLWithPath: move.rootPath)).undo(move)
                })
            }
        }
    }

    private func runOrganize(
        description: String,
        undoing: Set<UUID> = [],
        _ work: @escaping @Sendable (FileOrganizer) -> [OrganizeReport.Outcome]
    ) {
        guard organizeModeEnabled, let root = rootURL, !phase.isBusy else { return }
        phase = .organizing
        Task.detached(priority: .userInitiated) {
            let outcomes: [OrganizeReport.Outcome]
            do {
                let organizer = try FileOrganizer(root: root)
                outcomes = work(organizer)
            } catch {
                outcomes = [OrganizeReport.Outcome(path: root.path, result: .failure(error))]
            }
            await MainActor.run { self.finishOrganize(description: description, outcomes: outcomes, undoing: undoing) }
        }
    }

    private func finishOrganize(description: String, outcomes: [OrganizeReport.Outcome], undoing: Set<UUID>) {
        let completed = outcomes.compactMap(\.move)
        if undoing.isEmpty {
            moveLog += completed
        } else {
            // Drop log entries whose undo succeeded (matched by original destination).
            let undoneSources = Set(completed.map(\.fromPath))
            moveLog.removeAll { undoing.contains($0.id) && undoneSources.contains($0.toPath) }
        }
        lastOrganizeReport = OrganizeReport(title: description, outcomes: outcomes)
        phase = .finished
        refreshAfterChanges(moves: completed, newFolders: [])
    }

    // MARK: Quick folders

    /// Adds a folder to the row buttons and, in Organize mode, creates it
    /// directly inside the selected folder (if it doesn't exist yet).
    public func addQuickFolder(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard FileOrganizer.isValidFolderName(name) else {
            lastOrganizeReport = OrganizeReport(title: "Create folder", outcomes: [
                OrganizeReport.Outcome(path: name, error: FileOrganizer.OrganizeError.invalidFolderName(name)),
            ])
            return
        }
        if !quickFolders.contains(name) { quickFolders.append(name) }
        guard organizeModeEnabled, let root = rootURL, !phase.isBusy else { return }
        phase = .organizing
        Task.detached(priority: .userInitiated) {
            let outcome: OrganizeReport.Outcome
            do {
                let folder = try FileOrganizer(root: root).ensureFolder(named: name)
                outcome = OrganizeReport.Outcome(path: folder.path, error: nil)
            } catch {
                outcome = OrganizeReport.Outcome(path: root.appendingPathComponent(name).path, error: error)
            }
            await MainActor.run {
                self.lastOrganizeReport = OrganizeReport(title: "Create folder “\(name)”", outcomes: [outcome])
                self.phase = .finished
                self.refreshAfterChanges(moves: [], newFolders: outcome.errorMessage == nil ? [outcome.path] : [])
            }
        }
    }

    /// Removes a folder from the row buttons only. The folder on disk is untouched.
    public func removeQuickFolder(_ name: String) {
        quickFolders.removeAll { $0 == name }
    }

    /// Adds or removes a folder that already exists in the selected folder
    /// from the row buttons. Never touches the disk, so it works with
    /// Organize mode off too.
    public func setQuickFolder(_ name: String, included: Bool) {
        if included {
            guard FileOrganizer.isValidFolderName(name), !quickFolders.contains(name) else { return }
            quickFolders.append(name)
        } else if name != FileOrganizer.trashFolderName {
            removeQuickFolder(name)
        }
    }

    private func saveQuickFolders() {
        guard let folderStore, let root = rootURL else { return }
        folderStore.save(quickFolders.filter { $0 != FileOrganizer.trashFolderName }, forRoot: root.path)
    }

    /// `Trash` followed by the valid, distinct names in `names`.
    private static func withTrashFirst(_ names: [String]) -> [String] {
        var result = [FileOrganizer.trashFolderName]
        for name in names where FileOrganizer.isValidFolderName(name) && !result.contains(name) {
            result.append(name)
        }
        return result
    }

    /// Adds every folder that already exists in the selected folder.
    public func includeAllExistingFolders() {
        existingFolders.forEach { setQuickFolder($0, included: true) }
    }

    /// Names of the real folders directly inside the root, in Finder order.
    private static func topLevelFolderNames(in records: [FileRecord]) -> [String] {
        let names = records.lazy
            .filter { $0.kind == .directory && $0.parentRelativePath.isEmpty && FileOrganizer.isValidFolderName($0.name) }
            .map(\.name)
        return Set(names).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    // MARK: Refresh after organizing

    /// Updates the in-memory records to match completed moves (paths only;
    /// ids stay stable so selections and edits survive), adds records for new
    /// folders, then re-runs classification and grouping in the background.
    private func refreshAfterChanges(moves: [FileOrganizer.Move], newFolders: [String]) {
        guard let root = rootURL, !records.isEmpty || !newFolders.isEmpty || !moves.isEmpty else { return }
        let rootPath = root.path
        var updated = records
        var index = Dictionary(updated.map { ($0.path, $0.id) }, uniquingKeysWith: { first, _ in first })
        let scanner = FolderScanner(options: options)

        func ensureFolderRecord(_ path: String) {
            guard path != rootPath, path.hasPrefix(rootPath + "/"), index[path] == nil,
                  let record = scanner.record(at: URL(fileURLWithPath: path), id: updated.count, root: root) else { return }
            updated.append(record)
            index[record.path] = record.id
        }

        newFolders.forEach(ensureFolderRecord)
        for move in moves {
            ensureFolderRecord(URL(fileURLWithPath: move.toPath).deletingLastPathComponent().path)
            guard let id = index[move.fromPath] else { continue }
            if updated[id].kind == .directory {
                let oldPrefix = move.fromPath + "/"
                for i in updated.indices where updated[i].path == move.fromPath || updated[i].path.hasPrefix(oldPrefix) {
                    let newPath = move.toPath + updated[i].path.dropFirst(move.fromPath.count)
                    index[updated[i].path] = nil
                    updated[i] = updated[i].relocated(toPath: newPath, rootPath: rootPath)
                    index[newPath] = i
                }
            } else {
                index[move.fromPath] = nil
                updated[id] = updated[id].relocated(toPath: move.toPath, rootPath: rootPath)
                index[move.toPath] = id
            }
        }

        phase = .analyzing
        let scan = ScanResult(rootPath: rootPath, records: updated, issues: issues,
                              wasCancelled: resultsArePartial, startedAt: Date(), finishedAt: Date())
        scanTask = Task.detached(priority: .userInitiated) {
            let analysis = Analyzer.analyze(scan)
            await MainActor.run { self.finish(.success(analysis), isRefresh: true) }
        }
    }

    // MARK: Derived data

    private var effectiveClassifications: [Classification?] {
        guard !overrides.isEmpty else { return baseClassifications }
        var result = baseClassifications
        for (id, category) in overrides where id < result.count {
            result[id] = result[id]?.overridden(with: category)
        }
        return result
    }

    private func makeRow(_ id: Int) -> FileRow {
        FileRow(record: records[id], classification: effectiveClassification(for: id), reviewLater: reviewLater.contains(id))
    }

    private func rebuildRows() {
        rows = records.indices.map(makeRow)
        rowsVersion += 1
    }

    private func refreshRow(_ id: Int) {
        guard id < rows.count, rows[id].id == id else { rebuildRows(); return }
        rows[id] = makeRow(id)
        rowsVersion += 1
    }

    private func recomputeSummary() {
        summary = ScanSummary.compute(
            records: records, classifications: effectiveClassifications, reviewLater: reviewLater,
            groups: groups, issueCount: issues.count, thresholds: thresholds)
    }

    private func rebuildPlan() {
        plan = OrganizationPlan.build(
            records: records, classifications: effectiveClassifications,
            projects: projects, projectByRecord: projectByRecord)
    }
}

/// Result of one organize action, shown in the Changes tab.
public struct OrganizeReport: Sendable {
    public struct Outcome: Sendable, Identifiable {
        public let id = UUID()
        public let path: String
        public let move: FileOrganizer.Move?
        public let errorMessage: String?

        public init(path: String, error: Error?) {
            self.path = path
            self.move = nil
            self.errorMessage = error?.localizedDescription
        }

        public init(path: String, result: Result<FileOrganizer.Move, Error>) {
            self.path = path
            switch result {
            case .success(let move):
                self.move = move
                self.errorMessage = nil
            case .failure(let error):
                self.move = nil
                self.errorMessage = error.localizedDescription
            }
        }
    }

    public let title: String
    public let outcomes: [Outcome]
    public let date = Date()

    public var movedCount: Int { outcomes.filter { $0.move != nil }.count }
    public var skipped: [Outcome] { outcomes.filter { $0.errorMessage != nil } }
}
