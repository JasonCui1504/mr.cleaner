import Foundation

public enum FileKind: String, Sendable, Hashable, CaseIterable {
    case file
    case directory
    case symbolicLink
    case package
    case other

    public var displayName: String {
        switch self {
        case .file: return "File"
        case .directory: return "Folder"
        case .symbolicLink: return "Symbolic link"
        case .package: return "Package"
        case .other: return "Other"
        }
    }

    /// Files and packages are the things a user "organizes"; folders and
    /// links are structure.
    public var isFileLike: Bool { self == .file || self == .package }
}

public enum AccessStatus: Sendable, Hashable {
    case readable
    case notReadable
    /// Stored only in the cloud (iCloud / File Provider). Never touched further.
    case cloudPlaceholder
    case error(String)

    public var displayName: String {
        switch self {
        case .readable: return "Readable"
        case .notReadable: return "Not readable (permission)"
        case .cloudPlaceholder: return "Cloud placeholder (not downloaded; skipped)"
        case .error(let message): return "Error: \(message)"
        }
    }
}

/// In-memory description of one directory entry. Built from metadata only.
public struct FileRecord: Identifiable, Sendable, Hashable {
    /// Sequential index assigned by the scanner; equals the position in
    /// `ScanResult.records`.
    public let id: Int
    public let name: String
    /// Lowercased extension without the dot ("" when none). Compound archive
    /// extensions such as "tar.gz" are kept together.
    public let fileExtension: String
    public let kind: FileKind
    public let path: String
    public let relativePath: String
    /// Relative path of the containing folder ("" for the selected root).
    public let parentRelativePath: String
    public let depth: Int
    /// Logical size in bytes. `nil` for folders, and for packages unless
    /// package measuring was enabled.
    public let size: Int64?
    /// Filesystem birth time. `nil` when the filesystem does not report it.
    public let created: Date?
    /// Last content modification (st_mtime).
    public let modified: Date?
    /// Last metadata/status change (st_ctime). Not a content modification.
    public let metadataChanged: Date?
    /// Last access (st_atime) as reported; informational only.
    public let accessed: Date?
    public let isHidden: Bool
    public let access: AccessStatus
    public let typeIdentifier: String?
    public let typeDescription: String?
    public let mimeType: String?
    /// Text of the link (not resolved, not followed).
    public let symlinkTarget: String?
    public let symlinkPointsOutsideRoot: Bool?
    /// Human-readable notes, e.g. "Contents not scanned: package".
    public let notes: [String]

    public init(
        id: Int, name: String, fileExtension: String, kind: FileKind, path: String,
        relativePath: String, parentRelativePath: String, depth: Int, size: Int64?,
        created: Date?, modified: Date?, metadataChanged: Date?, accessed: Date?,
        isHidden: Bool, access: AccessStatus, typeIdentifier: String?,
        typeDescription: String?, mimeType: String?, symlinkTarget: String?,
        symlinkPointsOutsideRoot: Bool?, notes: [String]
    ) {
        self.id = id
        self.name = name
        self.fileExtension = fileExtension
        self.kind = kind
        self.path = path
        self.relativePath = relativePath
        self.parentRelativePath = parentRelativePath
        self.depth = depth
        self.size = size
        self.created = created
        self.modified = modified
        self.metadataChanged = metadataChanged
        self.accessed = accessed
        self.isHidden = isHidden
        self.access = access
        self.typeIdentifier = typeIdentifier
        self.typeDescription = typeDescription
        self.mimeType = mimeType
        self.symlinkTarget = symlinkTarget
        self.symlinkPointsOutsideRoot = symlinkPointsOutsideRoot
        self.notes = notes
    }

    /// Name without extension.
    public var stem: String { NameAnalysis.splitExtension(name).stem }

    /// The same entry at a new location (after a move in Organize mode). The
    /// name and all metadata are kept; only the path fields change.
    func relocated(toPath newPath: String, rootPath: String) -> FileRecord {
        let relative = String(newPath.dropFirst(rootPath.count + 1))
        let components = relative.split(separator: "/")
        return FileRecord(
            id: id, name: name, fileExtension: fileExtension, kind: kind, path: newPath,
            relativePath: relative, parentRelativePath: components.dropLast().joined(separator: "/"),
            depth: components.count, size: size, created: created, modified: modified,
            metadataChanged: metadataChanged, accessed: accessed, isHidden: isHidden, access: access,
            typeIdentifier: typeIdentifier, typeDescription: typeDescription, mimeType: mimeType,
            symlinkTarget: symlinkTarget, symlinkPointsOutsideRoot: symlinkPointsOutsideRoot, notes: notes)
    }
}

/// A problem encountered while scanning (permission denied, vanished entry…).
public struct ScanIssue: Identifiable, Sendable, Hashable {
    public let id: Int
    public let relativePath: String
    public let message: String

    public init(id: Int, relativePath: String, message: String) {
        self.id = id
        self.relativePath = relativePath
        self.message = message
    }
}
