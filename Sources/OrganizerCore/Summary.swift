import Foundation

/// Adjustable in the UI; held in memory only.
public struct SummaryThresholds: Sendable, Equatable {
    public var largeFileBytes: Int64 = 500 * 1_000_000
    public var oldFileDays = 365
    public var recentFileDays = 7

    public init() {}
}

/// Count and total size of one extension, for the dashboard.
public struct ExtensionStat: Sendable, Equatable, Identifiable {
    public let fileExtension: String
    public let count: Int
    public let bytes: Int64
    public var id: String { fileExtension }
}

public struct ScanSummary: Sendable, Equatable {
    public var files = 0
    public var folders = 0
    public var packages = 0
    public var symbolicLinks = 0
    public var otherEntries = 0
    public var totalBytes: Int64 = 0
    public var countsByCategory: [FileCategory: Int] = [:]
    public var unavailableCreationDates = 0
    public var needsReview = 0
    public var potentialDuplicateGroups = 0
    public var potentialDuplicateFiles = 0
    public var largeFiles = 0
    public var oldFiles = 0
    public var recentFiles = 0
    public var notReadable = 0
    public var cloudPlaceholders = 0
    public var hiddenEntries = 0
    public var issues = 0
    /// Dashboard lists (record ids), at most `listLimit` each.
    public var largestFileIDs: [Int] = []
    public var recentlyModifiedIDs: [Int] = []
    public var extensionStats: [ExtensionStat] = []

    public static let listLimit = 10

    public init() {}

    public static func compute(
        records: [FileRecord],
        classifications: [Classification?],
        reviewLater: Set<Int>,
        groups: [FileGroup],
        issueCount: Int,
        thresholds: SummaryThresholds,
        now: Date = Date()
    ) -> ScanSummary {
        var summary = ScanSummary()
        let oldCutoff = now.addingTimeInterval(-Double(thresholds.oldFileDays) * 86_400)
        let recentCutoff = now.addingTimeInterval(-Double(thresholds.recentFileDays) * 86_400)

        for record in records {
            if record.isHidden { summary.hiddenEntries += 1 }
            switch record.access {
            case .notReadable: summary.notReadable += 1
            case .cloudPlaceholder: summary.cloudPlaceholders += 1
            default: break
            }
            switch record.kind {
            case .directory:
                summary.folders += 1
                continue
            case .symbolicLink: summary.symbolicLinks += 1
            case .other: summary.otherEntries += 1
            case .package: summary.packages += 1; summary.files += 1
            case .file: summary.files += 1
            }
            if record.kind.isFileLike {
                let size = record.size ?? 0
                summary.totalBytes += size
                if size >= thresholds.largeFileBytes { summary.largeFiles += 1 }
                if record.created == nil { summary.unavailableCreationDates += 1 }
                if let modified = record.modified {
                    if modified < oldCutoff { summary.oldFiles += 1 }
                    if modified >= recentCutoff { summary.recentFiles += 1 }
                }
            }
            if record.id < classifications.count, let classification = classifications[record.id] {
                summary.countsByCategory[classification.category, default: 0] += 1
                if classification.needsReview || reviewLater.contains(record.id) { summary.needsReview += 1 }
            } else if reviewLater.contains(record.id) {
                summary.needsReview += 1
            }
        }
        let fileLike = records.filter { $0.kind.isFileLike }
        summary.largestFileIDs = fileLike.filter { ($0.size ?? 0) > 0 }
            .sorted { ($0.size ?? 0) > ($1.size ?? 0) }
            .prefix(listLimit).map(\.id)
        summary.recentlyModifiedIDs = fileLike.filter { $0.modified != nil }
            .sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
            .prefix(listLimit).map(\.id)
        var byExtension: [String: (count: Int, bytes: Int64)] = [:]
        for record in fileLike {
            let key = record.fileExtension.isEmpty ? "(none)" : record.fileExtension
            byExtension[key, default: (0, 0)].count += 1
            byExtension[key, default: (0, 0)].bytes += record.size ?? 0
        }
        summary.extensionStats = byExtension
            .map { ExtensionStat(fileExtension: $0.key, count: $0.value.count, bytes: $0.value.bytes) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.fileExtension < $1.fileExtension }
            .prefix(12).map { $0 }

        let duplicates = groups.filter { $0.kind == .potentialDuplicates }
        summary.potentialDuplicateGroups = duplicates.count
        summary.potentialDuplicateFiles = duplicates.reduce(0) { $0 + $1.memberIDs.count }
        summary.issues = issueCount
        return summary
    }
}
