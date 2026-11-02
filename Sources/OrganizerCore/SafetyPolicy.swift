import Foundation

/// Central statement of the app's read-only, offline, no-AI guarantees.
///
/// This type contains no behavior that touches the filesystem. It exists so
/// that the guarantees are written down in one place in the source, shown in
/// the UI, and checked by `SafetyTests` (which scans every file under
/// `Sources/` for mutating or networking APIs).
///
/// Rules enforced by construction:
/// - Reading: directory listing, `lstat`, URL resource-value lookups, and
///   reading a symbolic link's target text, all in `FolderScanner.swift`.
/// - Changing (Organize mode only, off by default): creating a folder directly
///   inside the selected folder and moving an item into it with its name
///   unchanged, both in `FileOrganizer.swift`. No delete, rename, copy,
///   overwrite or content edit exists anywhere.
/// - No file contents are ever opened or read; nothing is hashed.
/// - Symbolic links are never followed; packages and cloud placeholder
///   folders are not descended into.
/// - Results live in memory only. Nothing is cached, logged or exported, and
///   category edits are session-only. The only saved data is the "Your
///   folders" name list per selected folder, in `FolderListStore.swift`.
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
    Suggestions only. Nothing has been moved. To create these folders and move \
    files into them, turn on Organize mode in the toolbar.
    """

    public static let organizeHeadline = "Organize mode · create folders & move only"

    public static let organizeBannerText = """
    Organize mode is ON. The app may create new folders inside the selected folder and \
    move items into them, keeping their names. It never deletes, renames, copies, \
    overwrites or edits anything. Items you move to “Trash” stay there until you delete \
    that folder yourself in Finder. Every move can be undone from the Changes tab.
    """

    public static let organizeModeExplanation = """
    While Organize mode is on, the app can do exactly two things, and only inside the folder you selected:

    • create new folders directly inside it, and
    • move items into those folders, keeping their names.

    It cannot delete, rename, copy, overwrite or edit files. If a name is already taken in the destination, the item is skipped. “Trash” is an ordinary folder you empty yourself. Moves can be undone during this session. Organize mode turns off when you quit.
    """

    public static let sessionOnlyNote = "Session only: not saved, never written to the file."
}
