import Foundation

/// The only code in the app that changes the filesystem, and only in two ways:
///
/// 1. Create a new, empty folder directly inside the selected root.
/// 2. Move an existing item, keeping its exact name, into such a folder
///    (or, for Undo, back to where it came from).
///
/// Nothing else exists: no delete, rename, copy, overwrite, or content edit.
/// A move whose destination name is taken is refused, never renamed or
/// overwritten. Moves across volumes are refused, because the system would
/// implement them as copy-then-delete. The "Trash" folder is an ordinary folder
/// inside the root; emptying it is left to the user.
public struct FileOrganizer: Sendable {
    public static let trashFolderName = "Trash"

    public let root: URL

    public enum OrganizeError: Error, LocalizedError, Equatable {
        case invalidFolderName(String)
        case outsideRoot(String)
        case alreadyExists(String)
        case notAFolder(String)
        case sourceMissing(String)
        case wouldMoveIntoItself(String)
        case differentVolume(String)
        case protectedItem(String)
        case failed(String)

        public var errorDescription: String? {
            switch self {
            case .invalidFolderName(let name): return "“\(name)” is not an allowed folder name."
            case .outsideRoot(let path): return "Outside the selected folder: \(path)"
            case .alreadyExists(let path): return "Skipped: an item named “\(URL(fileURLWithPath: path).lastPathComponent)” already exists there (nothing is ever overwritten or renamed)."
            case .notAFolder(let path): return "Not a folder: \(path)"
            case .sourceMissing(let path): return "No longer exists: \(path)"
            case .wouldMoveIntoItself(let path): return "A folder cannot be moved into itself: \(path)"
            case .differentVolume(let path): return "Skipped: on a different disk, where a move would require copy + delete: \(path)"
            case .protectedItem(let path): return "This item cannot be moved: \(path)"
            case .failed(let message): return message
            }
        }
    }

    /// One completed move, kept in memory so it can be undone.
    public struct Move: Identifiable, Sendable, Hashable {
        public let id: UUID
        public let rootPath: String
        public let fromPath: String
        public let toPath: String
        public let date: Date

        public var name: String { URL(fileURLWithPath: toPath).lastPathComponent }
    }

    private let rootDevice: Int64

    public init(root: URL) throws {
        let standardized = root.standardizedFileURL
        guard let info = LStat(url: standardized), info.kind == .directory else {
            throw OrganizeError.notAFolder(standardized.path)
        }
        self.root = standardized
        self.rootDevice = info.device
    }

    // MARK: Validation

    public static func isValidFolderName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed == name && name.utf8.count <= 255
            && !name.hasPrefix(".") && !name.contains("/") && !name.contains(":") && !name.contains("\u{0}")
    }

    /// Lexical containment on standardized paths.
    private func isInsideRoot(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return path.hasPrefix(rootPath)
    }

    /// Every component from the root down to `folder` must be a real folder
    /// (not a symbolic link, not a package) on the root's volume.
    private func verifyRealFolderChain(_ folder: URL) throws {
        let standardized = folder.standardizedFileURL
        guard standardized.path == root.path || isInsideRoot(standardized) else {
            throw OrganizeError.outsideRoot(standardized.path)
        }
        let relative = standardized.path.dropFirst(root.path.count).split(separator: "/")
        var current = root
        for component in relative {
            current = current.appendingPathComponent(String(component), isDirectory: true)
            guard let info = LStat(url: current), info.kind == .directory else {
                throw OrganizeError.notAFolder(current.path)
            }
            guard info.device == rootDevice else { throw OrganizeError.differentVolume(current.path) }
        }
    }

    // MARK: Operations

    /// Returns the folder `root/name`, creating it (empty) if it does not exist.
    @discardableResult
    public func ensureFolder(named name: String) throws -> URL {
        guard Self.isValidFolderName(name) else { throw OrganizeError.invalidFolderName(name) }
        let folder = root.appendingPathComponent(name, isDirectory: true)
        if let info = LStat(url: folder) {
            guard info.kind == .directory else { throw OrganizeError.notAFolder(folder.path) }
            try verifyRealFolderChain(folder)
            return folder
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: nil)
        } catch {
            throw OrganizeError.failed("Could not create folder “\(name)”: \(error.localizedDescription)")
        }
        return folder
    }

    /// Moves `source` (keeping its name) into the folder `root/folderName`,
    /// creating that folder if needed.
    public func move(_ source: URL, intoFolderNamed folderName: String) throws -> Move {
        let folder = try ensureFolder(named: folderName)
        return try performMove(source, to: folder.appendingPathComponent(source.lastPathComponent))
    }

    /// Moves an item back to where it was before `move`. This is itself a move
    /// under the same rules (nothing is overwritten).
    public func undo(_ move: Move) throws -> Move {
        try performMove(URL(fileURLWithPath: move.toPath), to: URL(fileURLWithPath: move.fromPath))
    }

    private func performMove(_ source: URL, to destination: URL) throws -> Move {
        let source = source.standardizedFileURL
        let destination = destination.standardizedFileURL
        guard isInsideRoot(source) else { throw OrganizeError.outsideRoot(source.path) }
        guard isInsideRoot(destination) else { throw OrganizeError.outsideRoot(destination.path) }
        guard source.lastPathComponent == destination.lastPathComponent else {
            throw OrganizeError.protectedItem("renaming is not allowed: \(source.path)")
        }
        guard let sourceInfo = LStat(url: source) else { throw OrganizeError.sourceMissing(source.path) }
        guard sourceInfo.device == rootDevice else { throw OrganizeError.differentVolume(source.path) }
        try verifyRealFolderChain(source.deletingLastPathComponent())
        try verifyRealFolderChain(destination.deletingLastPathComponent())
        if destination.path.hasPrefix(source.path + "/") { throw OrganizeError.wouldMoveIntoItself(source.path) }
        if source.path == destination.path { throw OrganizeError.alreadyExists(destination.path) }
        guard LStat(url: destination) == nil else { throw OrganizeError.alreadyExists(destination.path) }
        do {
            // On the same volume this is a single rename(2) of the directory
            // entry: contents and dates of the item are untouched. It fails
            // rather than replaces if the destination appeared meanwhile.
            try FileManager.default.moveItem(at: source, to: destination)
        } catch {
            throw OrganizeError.failed("Could not move “\(source.lastPathComponent)”: \(error.localizedDescription)")
        }
        return Move(id: UUID(), rootPath: root.path, fromPath: source.path, toPath: destination.path, date: Date())
    }
}
