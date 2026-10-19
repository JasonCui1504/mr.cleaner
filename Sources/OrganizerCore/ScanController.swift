import Foundation
import Combine

/// Main-actor state for the UI. Scanning and analysis run on a background
/// task; only small progress updates and the final result hop to the main
/// actor, so the UI stays responsive.
///
/// Everything here is in memory. Session edits (category overrides, "review
/// later") are discarded when the app quits and are never written anywhere.
@MainActor
public final class ScanController: ObservableObject {

    public enum Phase: Equatable {
        case idle
        case ready
        case scanning
        case analyzing
        case finished
        case stopped
        case failed(String)

        public var isBusy: Bool { self == .scanning || self == .analyzing }
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

    @Published public var options = ScanOptions()
    @Published public var thresholds = SummaryThresholds() {
        didSet { if thresholds != oldValue { recomputeSummary() } }
    }

    private var baseClassifications: [Classification?] = []
    private var projectByRecord: [Int: String] = [:]
    private var groupsByRecord: [Int: [Int]] = [:]
    private var scanTask: Task<Void, Never>?
    private var cancellation: CancellationFlag?

    public init() {}

    // MARK: Folder selection

    public func select(root: URL) {
        guard !phase.isBusy else { return }
        clearResults()
        rootURL = root.standardizedFileURL
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

    private func finish(_ outcome: Result<AnalysisResult, Error>) {
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
            lastScanDuration = scan.finishedAt.timeIntervalSince(scan.startedAt)
            var final = ScanProgress()
            final.files = records.filter { $0.kind.isFileLike }.count
            final.folders = records.filter { $0.kind == .directory }.count
            final.otherEntries = records.count - final.files - final.folders
            final.issues = issues.count
            progress = final
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
