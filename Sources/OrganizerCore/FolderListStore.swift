import Foundation

/// The one thing the app remembers between launches: the names in "Your
/// folders" for each folder you selected. Nothing else (scan results, edits,
/// the move log, settings) is saved.
///
/// Stored as a dictionary of selected-folder path → folder names in the
/// preferences domain `suiteName` (a small plist under ~/Library/Preferences).
/// This is the only file in the app that writes preferences (`SafetyTests`).
/// Delete everything with `defaults delete local.readonly.fileorganizer.folders`.
public final class FolderListStore {
    public static let suiteName = "local.readonly.fileorganizer.folders"
    private static let key = "yourFoldersByRoot"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The app's store, or `nil` if the preferences domain can't be opened.
    public convenience init?(suiteName: String = FolderListStore.suiteName) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
        self.init(defaults: defaults)
    }

    public func folders(forRoot rootPath: String) -> [String] {
        all[rootPath] ?? []
    }

    /// Saves `folders` for `rootPath`; an empty list removes the entry.
    public func save(_ folders: [String], forRoot rootPath: String) {
        var stored = all
        stored[rootPath] = folders.isEmpty ? nil : folders
        defaults.set(stored, forKey: Self.key)
    }

    private var all: [String: [String]] {
        defaults.dictionary(forKey: Self.key) as? [String: [String]] ?? [:]
    }
}
