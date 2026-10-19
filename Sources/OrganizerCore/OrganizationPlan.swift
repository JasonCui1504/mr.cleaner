import Foundation

/// A purely virtual destination for one file. Nothing is ever created or moved.
public struct PlannedItem: Identifiable, Sendable, Hashable {
    public let id: Int
    public let suggestedPath: String
    public let currentRelativePath: String
    public let reason: String
    /// Another planned item would have the same suggested path.
    public var hasNameCollision: Bool
    /// Top-level suggested folder this item belongs to.
    public var folderName: String = ""
    /// Inside a detected software project. Organize mode never moves these
    /// individually, so projects stay intact.
    public var isInProject = false
}

public struct PlannedFolder: Identifiable, Sendable, Hashable {
    public var id: String { name }
    public let name: String
    public let category: FileCategory
    public let items: [PlannedItem]
}

public enum OrganizationPlan {

    /// Builds the hypothetical folder structure.
    ///
    /// - Files inside a detected software project stay together under
    ///   "Software & Development/<project>/<path inside project>".
    /// - Every other file goes to "<Category folder>/<filename>".
    public static func build(
        records: [FileRecord],
        classifications: [Classification?],
        projects: [ProjectInfo],
        projectByRecord: [Int: String]
    ) -> [PlannedFolder] {
        let projectNames = Dictionary(projects.map { ($0.relativePath, $0.name) }, uniquingKeysWith: { first, _ in first })
        var itemsByCategory: [FileCategory: [PlannedItem]] = [:]

        for record in records where record.kind.isFileLike || record.kind == .symbolicLink {
            guard record.id < classifications.count, let classification = classifications[record.id] else { continue }
            if let projectRoot = projectByRecord[record.id], let projectName = projectNames[projectRoot] {
                let inside = projectRoot.isEmpty ? record.relativePath : String(record.relativePath.dropFirst(projectRoot.count + 1))
                let path = "\(FileCategory.software.suggestedFolderName)/\(projectName)/\(inside)"
                itemsByCategory[.software, default: []].append(PlannedItem(
                    id: record.id, suggestedPath: path, currentRelativePath: record.relativePath,
                    reason: "Part of the software project “\(projectName)”; projects are kept intact. (File category: \(classification.category.displayName).)",
                    hasNameCollision: false, folderName: FileCategory.software.suggestedFolderName, isInProject: true))
            } else {
                let category = classification.category
                let path = "\(category.suggestedFolderName)/\(record.name)"
                let reason = classification.isOverridden
                    ? "Category set by you for this session."
                    : "\(classification.confidence.displayName) confidence: \(classification.explanation)"
                itemsByCategory[category, default: []].append(PlannedItem(
                    id: record.id, suggestedPath: path, currentRelativePath: record.relativePath,
                    reason: reason, hasNameCollision: false, folderName: category.suggestedFolderName))
            }
        }

        return itemsByCategory.keys.sorted().map { category -> PlannedFolder in
            var items = itemsByCategory[category] ?? []
            var counts: [String: Int] = [:]
            for item in items { counts[NameAnalysis.fold(item.suggestedPath), default: 0] += 1 }
            for index in items.indices where (counts[NameAnalysis.fold(items[index].suggestedPath)] ?? 0) > 1 {
                items[index].hasNameCollision = true
            }
            items.sort { $0.suggestedPath.localizedStandardCompare($1.suggestedPath) == .orderedAscending }
            return PlannedFolder(name: category.suggestedFolderName, category: category, items: items)
        }
    }
}
