import Foundation

/// Primary categories, in documentation order. See docs/CATEGORY_RULES.md.
public enum FileCategory: String, Sendable, Hashable, CaseIterable, Identifiable, Comparable {
    case financial = "Financial & Tax"
    case travel = "Travel & Reservations"
    case academic = "Academic & Coursework"
    case research = "Research & Scientific"
    case work = "Work & Career"
    case presentations = "Presentations"
    case spreadsheets = "Spreadsheets & Data"
    case software = "Software & Development"
    case images = "Images & Photography"
    case media = "Video & Audio"
    case archives = "Archives & Installers"
    case notes = "Notes & Writing"
    case design = "Design & Creative"
    case ebooks = "E-books & Reference"
    case uncategorized = "Uncategorized / Review"

    public var id: String { rawValue }
    public var displayName: String { rawValue }

    /// Name of the hypothetical folder shown in the suggestion preview.
    public var suggestedFolderName: String {
        self == .uncategorized ? "Uncategorized - Review" : rawValue
    }

    public var order: Int { FileCategory.allCases.firstIndex(of: self) ?? 0 }

    public static func < (lhs: FileCategory, rhs: FileCategory) -> Bool { lhs.order < rhs.order }
}

/// Strength of the rule evidence. Not a probability and not a model score.
public enum Confidence: Int, Sendable, Hashable, Comparable, CaseIterable {
    case low = 0
    case medium = 1
    case high = 2

    public var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    public var lowered: Confidence { Confidence(rawValue: max(rawValue - 1, 0)) ?? .low }

    public static func < (lhs: Confidence, rhs: Confidence) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Result of the deterministic classifier for one file.
public struct Classification: Sendable, Hashable {
    public var category: FileCategory
    public var secondary: [FileCategory]
    public var tags: [String]
    public var confidence: Confidence
    public var explanation: String
    public var reviewReasons: [String]
    public var ruleIDs: [String]
    /// True when the user picked a different category for this session.
    public var isOverridden: Bool

    public init(
        category: FileCategory, secondary: [FileCategory] = [], tags: [String] = [],
        confidence: Confidence, explanation: String, reviewReasons: [String] = [],
        ruleIDs: [String] = [], isOverridden: Bool = false
    ) {
        self.category = category
        self.secondary = secondary
        self.tags = tags
        self.confidence = confidence
        self.explanation = explanation
        self.reviewReasons = reviewReasons
        self.ruleIDs = ruleIDs
        self.isOverridden = isOverridden
    }

    public var needsReview: Bool { !reviewReasons.isEmpty }

    /// Copy with a session-only category chosen by the user.
    public func overridden(with newCategory: FileCategory) -> Classification {
        guard newCategory != category else { return self }
        var copy = self
        copy.secondary.removeAll { $0 == newCategory }
        copy.category = newCategory
        copy.isOverridden = true
        copy.explanation = "You set this category for this session (rule result was “\(category.displayName)”). Rule explanation: " + explanation
        return copy
    }
}
