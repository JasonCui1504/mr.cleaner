import Foundation

/// One table row: a record plus its effective (possibly session-edited)
/// classification, with numeric/chronological sort keys.
public struct FileRow: Identifiable, Sendable, Hashable {
    public let record: FileRecord
    public let classification: Classification?
    public let reviewLater: Bool

    public init(record: FileRecord, classification: Classification?, reviewLater: Bool) {
        self.record = record
        self.classification = classification
        self.reviewLater = reviewLater
    }

    public var id: Int { record.id }
    public var name: String { record.name }
    public var relativePath: String { record.relativePath }
    public var isFolder: Bool { record.kind == .directory }

    public var categoryName: String {
        guard let classification else { return record.kind == .directory ? "Folder" : "—" }
        return classification.category.displayName + (classification.isOverridden ? " (edited)" : "")
    }

    public var typeName: String {
        switch record.kind {
        case .directory: return "Folder"
        case .symbolicLink: return "Symbolic link"
        default: return record.fileExtension.isEmpty ? (record.typeDescription ?? "—") : record.fileExtension.uppercased()
        }
    }

    /// Bytes; folders sort first (-1).
    public var sizeKey: Int64 { record.size ?? -1 }
    public var sizeText: String { record.size.map(Formatting.size) ?? "—" }

    /// Seconds since 1970; unavailable dates sort first.
    public var createdKey: Double { record.created?.timeIntervalSince1970 ?? -Double.greatestFiniteMagnitude }
    public var modifiedKey: Double { record.modified?.timeIntervalSince1970 ?? -Double.greatestFiniteMagnitude }
    public var createdText: String { Formatting.date(record.created) }
    public var modifiedText: String { Formatting.date(record.modified) }

    public var confidenceRank: Int { classification?.confidence.rawValue ?? -1 }
    public var confidenceText: String { classification?.confidence.displayName ?? "—" }

    public var needsReview: Bool { reviewLater || (classification?.needsReview ?? false) }

    public var symbolName: String {
        switch record.kind {
        case .directory: return "folder"
        case .package: return "shippingbox"
        case .symbolicLink: return "arrowshape.turn.up.right"
        case .other: return "questionmark.square.dashed"
        case .file: return "doc"
        }
    }
}

public enum KindFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "Files & folders"
    case files = "Files only"
    case folders = "Folders only"
    public var id: String { rawValue }
}

public enum HiddenFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "Hidden & visible"
    case visibleOnly = "Visible only"
    case hiddenOnly = "Hidden only"
    public var id: String { rawValue }
}

public struct FilterCriteria: Equatable, Sendable {
    public var searchText = ""
    public var category: FileCategory?
    /// Lowercased extension, "" = any.
    public var fileType = ""
    public var kind: KindFilter = .all
    public var modifiedFrom: Date?
    public var modifiedTo: Date?
    public var minBytes: Int64?
    public var maxBytes: Int64?
    public var hidden: HiddenFilter = .all
    public var reviewOnly = false
    /// Relative paths to leave out, together with everything inside them.
    /// Used to hide items already moved into a folder in Organize mode.
    public var excludedRelativePaths: Set<String> = []
    /// Folders whose contents are left out; the folder row itself stays.
    public var collapsedFolders: Set<String> = []

    public init() {}

    public func matches(_ row: FileRow) -> Bool {
        let record = row.record
        if !(excludedRelativePaths.isEmpty && collapsedFolders.isEmpty) && isExcluded(record.relativePath) { return false }
        switch kind {
        case .all: break
        case .files: if record.kind == .directory { return false }
        case .folders: if record.kind != .directory { return false }
        }
        if let category, row.classification?.category != category { return false }
        if !fileType.isEmpty, record.fileExtension != fileType { return false }
        switch hidden {
        case .all: break
        case .visibleOnly: if record.isHidden { return false }
        case .hiddenOnly: if !record.isHidden { return false }
        }
        if reviewOnly && !row.needsReview { return false }
        if modifiedFrom != nil || modifiedTo != nil {
            guard let modified = record.modified else { return false }
            if let modifiedFrom, modified < modifiedFrom { return false }
            if let modifiedTo, modified > modifiedTo { return false }
        }
        if minBytes != nil || maxBytes != nil {
            guard let size = record.size else { return false }
            if let minBytes, size < minBytes { return false }
            if let maxBytes, size > maxBytes { return false }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
            if record.relativePath.range(of: query, options: options) == nil { return false }
        }
        return true
    }

    /// True when `relativePath` or one of its parent folders is excluded, or
    /// one of its parent folders is collapsed.
    private func isExcluded(_ relativePath: String) -> Bool {
        var path = Substring(relativePath)
        var isSelf = true
        while !path.isEmpty {
            let current = String(path)
            if excludedRelativePaths.contains(current) { return true }
            if !isSelf && collapsedFolders.contains(current) { return true }
            guard let slash = path.lastIndex(of: "/") else { break }
            path = path[..<slash]
            isSelf = false
        }
        return false
    }

    public func apply(to rows: [FileRow], sortedBy comparators: [KeyPathComparator<FileRow>]) -> [FileRow] {
        let filtered = rows.filter(matches)
        return comparators.isEmpty ? filtered : filtered.sorted(using: comparators)
    }
}
