import Foundation

/// Everything derived from one scan. In memory only.
public struct AnalysisResult: Sendable {
    public let scan: ScanResult
    /// Indexed by record id; `nil` for folders.
    public let classifications: [Classification?]
    public let groups: [FileGroup]
    public let projects: [ProjectInfo]
    public let projectByRecord: [Int: String]
}

/// Runs classification and grouping over a finished (or stopped) scan.
public enum Analyzer {
    public static func analyze(_ scan: ScanResult, classifier: RuleClassifier = RuleClassifier()) -> AnalysisResult {
        var classifications = scan.records.map { classifier.classify($0) }
        let rootName = URL(fileURLWithPath: scan.rootPath).lastPathComponent
        let grouping = GroupingEngine().run(
            records: scan.records, categories: classifications.map { $0?.category }, rootName: rootName)

        // Project context: tag files that sit inside a detected project.
        let projectNames = Dictionary(grouping.projects.map { ($0.relativePath, $0.name) }, uniquingKeysWith: { first, _ in first })
        for (recordID, projectRoot) in grouping.projectByRecord {
            guard recordID < classifications.count, var classification = classifications[recordID] else { continue }
            classification.tags.append("In project “\(projectNames[projectRoot] ?? projectRoot)”")
            if classification.category != .software && !classification.secondary.contains(.software) {
                classification.secondary.append(.software)
            }
            classification.ruleIDs.append("CONTEXT.PROJECT")
            classifications[recordID] = classification
        }

        return AnalysisResult(
            scan: scan, classifications: classifications, groups: grouping.groups,
            projects: grouping.projects, projectByRecord: grouping.projectByRecord)
    }
}
