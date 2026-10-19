import Foundation

/// Central statement of the app's read-only, offline, no-AI guarantees.
///
/// This type contains no behavior that touches the filesystem. It exists so
/// that the guarantees are written down in one place in the source, shown in
/// the UI, and checked by `SafetyTests` (which scans every file under
/// `Sources/` for mutating or networking APIs).
///
/// Rules enforced by construction:
/// - The only filesystem calls in `Sources/` are directory listing,
///   `lstat`, URL resource-value lookups, and reading a symbolic link's
///   target text. All live in `FolderScanner.swift`.
/// - No file contents are ever opened or read; nothing is hashed.
/// - Symbolic links are never followed; packages and cloud placeholder
///   folders are not descended into.
/// - Results live in memory only. Nothing is saved, cached, logged or
///   exported. Category edits are session-only.
/// - There is no networking code and no network-capable framework is imported.
/// - Classification is a fixed, documented rule table (see `CategoryRules`).
public enum SafetyPolicy {
    public static let headline = "Read-only · Offline · No AI"

    public static let bannerText = """
    This app never changes, moves, renames, deletes or creates files. It lists \
    folder entries and reads filesystem metadata (names, sizes, dates) only. \
    File contents are not opened. Results stay in memory and are discarded when you quit.
    """

    /// Honest note about reads: not writing is not the same as having zero
    /// filesystem side effects.
    public static let readEffectsNote = """
    Not writing is different from having no effect at all. Listing a folder and \
    reading metadata does not change files, but macOS itself may update a folder's \
    access time, and the system folder picker may remember its last location. \
    The app never opens file contents, so it does not trigger downloads of \
    iCloud or other cloud-only files; cloud placeholder folders are skipped.
    """

    public static let suggestionNote = """
    Suggestions only. None of these folders exist and nothing has been moved. \
    This version has no way to apply them.
    """

    public static let sessionOnlyNote = "Session only: not saved, never written to the file."
}
