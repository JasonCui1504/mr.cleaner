import Foundation
import UniformTypeIdentifiers
#if canImport(Darwin)
import Darwin
#endif

/// Options for one scan. Held in memory only.
public struct ScanOptions: Sendable, Equatable {
    /// List hidden entries (dotfiles and entries with the hidden flag).
    public var includeHidden = true
    /// List `.git`, `.svn`, `.hg` folders themselves but not their internals.
    public var skipVersionControlInternals = true
    /// Sum the sizes inside packages (.app, .key, .fcpbundle…) by reading
    /// metadata of their contents. Contents are still never opened.
    public var measurePackageSizes = false
    /// How many records to collect before reporting progress.
    public var batchSize = 500

    public init() {}
}

public struct ScanProgress: Sendable, Equatable {
    public var files = 0
    public var folders = 0
    public var otherEntries = 0
    public var issues = 0
    public var currentFolder = ""

    public init() {}

    public var totalEntries: Int { files + folders + otherEntries }
}

public struct ScanResult: Sendable {
    public let rootPath: String
    public let records: [FileRecord]
    public let issues: [ScanIssue]
    public let wasCancelled: Bool
    public let startedAt: Date
    public let finishedAt: Date
}

/// Thread-safe cancellation flag shared between the UI and a running scan.
public final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

/// Enumerates the selected folder and reads metadata only.
///
/// Filesystem calls used here (and nowhere else in the app):
/// - `FileManager.contentsOfDirectory(at:includingPropertiesForKeys:options:)` — list a folder
/// - `lstat` — size, timestamps, type and flags without following links
/// - `URL.resourceValues(forKeys:)` — hidden/readable/package/type/cloud status
/// - `FileManager.destinationOfSymbolicLink(atPath:)` — read a link's target text (not followed)
///
/// It never opens, reads, hashes, or writes file contents, never follows
/// symbolic links, never descends into packages or cloud placeholder
/// folders, and never leaves the selected root.
public struct FolderScanner: Sendable {
    public var options: ScanOptions

    public init(options: ScanOptions = ScanOptions()) {
        self.options = options
    }

    static let resourceKeys: [URLResourceKey] = [
        .isHiddenKey, .isReadableKey, .isPackageKey, .contentTypeKey,
        .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
    ]

    private static let versionControlFolders: Set<String> = [".git", ".svn", ".hg"]

    // st_flags bits (sys/stat.h); defined here to avoid depending on macro import.
    static let flagHidden: UInt32 = 0x0000_8000      // UF_HIDDEN
    static let flagDataless: UInt32 = 0x4000_0000    // SF_DATALESS (cloud placeholder)

    public enum ScanError: Error, LocalizedError {
        case rootNotAccessible(String)
        case rootNotDirectory(String)
        case rootIsSymbolicLink(String)

        public var errorDescription: String? {
            switch self {
            case .rootNotAccessible(let path): return "The selected folder could not be accessed: \(path)"
            case .rootNotDirectory(let path): return "The selected item is not a folder: \(path)"
            case .rootIsSymbolicLink(let path): return "The selected item is a symbolic link. Choose the folder it points to directly: \(path)"
            }
        }
    }

    /// Validates the root without reading its contents.
    public static func validateRoot(_ root: URL) throws {
        guard let info = LStat(url: root) else { throw ScanError.rootNotAccessible(root.path) }
        if info.kind == .symbolicLink { throw ScanError.rootIsSymbolicLink(root.path) }
        guard info.kind == .directory else { throw ScanError.rootNotDirectory(root.path) }
    }

    /// Scans synchronously. Call from a background thread. `onBatch` is called
    /// on the scanning thread with each new batch of records.
    public func scan(
        root: URL,
        cancellation: CancellationFlag = CancellationFlag(),
        onBatch: (([FileRecord], ScanProgress) -> Void)? = nil
    ) throws -> ScanResult {
        let started = Date()
        let rootURL = root.standardizedFileURL
        try Self.validateRoot(rootURL)

        let fileManager = FileManager.default
        var records: [FileRecord] = []
        var issues: [ScanIssue] = []
        var pending: [FileRecord] = []
        var progress = ScanProgress()
        let listOptions: FileManager.DirectoryEnumerationOptions = options.includeHidden ? [] : [.skipsHiddenFiles]

        func addIssue(_ relativePath: String, _ message: String) {
            issues.append(ScanIssue(id: issues.count, relativePath: relativePath, message: message))
            progress.issues = issues.count
        }

        func flush(force: Bool) {
            guard !pending.isEmpty, force || pending.count >= options.batchSize else { return }
            onBatch?(pending, progress)
            pending.removeAll(keepingCapacity: true)
        }

        // Depth-first walk with an explicit stack: (url, relative path, depth).
        var stack: [(URL, String, Int)] = [(rootURL, "", 0)]
        while let next = stack.popLast() {
            let (folderURL, folderRelative, depth) = next
            if cancellation.isCancelled { break }
            progress.currentFolder = folderRelative.isEmpty ? "/" : folderRelative

            let entries: [URL]
            do {
                entries = try fileManager.contentsOfDirectory(
                    at: folderURL, includingPropertiesForKeys: Self.resourceKeys, options: listOptions)
            } catch {
                addIssue(folderRelative.isEmpty ? "/" : folderRelative, "Folder could not be listed: \(Self.describe(error))")
                continue
            }

            // Sorted for deterministic results; reversed push keeps alphabetical traversal.
            let sorted = entries.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            var subfolders: [(URL, String, Int)] = []

            for entryURL in sorted {
                if cancellation.isCancelled { break }
                let name = entryURL.lastPathComponent
                let relative = folderRelative.isEmpty ? name : folderRelative + "/" + name

                guard let info = LStat(url: entryURL) else {
                    addIssue(relative, "Metadata unavailable (entry may have been removed during the scan).")
                    continue
                }

                let (record, descend) = makeRecord(
                    id: records.count, url: entryURL, name: name, relative: relative,
                    parentRelative: folderRelative, depth: depth + 1, info: info, rootURL: rootURL,
                    cancellation: cancellation)
                records.append(record)
                pending.append(record)
                switch record.kind {
                case .directory: progress.folders += 1
                case .file, .package: progress.files += 1
                default: progress.otherEntries += 1
                }
                if descend { subfolders.append((entryURL, relative, depth + 1)) }
                flush(force: false)
            }
            stack.append(contentsOf: subfolders.reversed())
        }

        flush(force: true)
        return ScanResult(
            rootPath: rootURL.path, records: records, issues: issues,
            wasCancelled: cancellation.isCancelled, startedAt: started, finishedAt: Date())
    }

    // MARK: Record construction

    private func makeRecord(
        id: Int, url: URL, name: String, relative: String, parentRelative: String, depth: Int,
        info: LStat, rootURL: URL, cancellation: CancellationFlag
    ) -> (FileRecord, Bool) {
        let values = try? url.resourceValues(forKeys: Set(Self.resourceKeys))
        let (_, ext) = NameAnalysis.splitExtension(name)
        var notes: [String] = []

        var kind = info.kind
        if kind == .directory, values?.isPackage == true { kind = .package }

        let isDataless = info.flags & Self.flagDataless != 0
        let downloadStatus = values?.ubiquitousItemDownloadingStatus
        let isCloudOnly = isDataless || (values?.isUbiquitousItem == true && downloadStatus == .notDownloaded)

        var access: AccessStatus = .readable
        if isCloudOnly {
            access = .cloudPlaceholder
        } else if values?.isReadable == false {
            access = .notReadable
        } else if values == nil {
            access = .error("Some metadata unavailable")
        }

        let isHidden = values?.isHidden == true || name.hasPrefix(".") || info.flags & Self.flagHidden != 0

        // Type information comes from the extension via the system type
        // database; it does not open the file.
        let contentType: UTType? = values?.contentType ?? (ext.isEmpty ? nil : UTType(filenameExtension: ext))

        var size: Int64? = nil
        var descend = false
        var symlinkTarget: String?
        var pointsOutside: Bool?

        switch kind {
        case .file, .other:
            size = info.size
        case .directory:
            if isCloudOnly {
                notes.append("Contents not scanned: cloud placeholder folder (listing it could trigger a download).")
            } else if options.skipVersionControlInternals && Self.versionControlFolders.contains(name) {
                notes.append("Contents not listed: version-control internals (can be changed in Scan Options).")
            } else {
                descend = true
            }
        case .package:
            if isCloudOnly {
                notes.append("Package is a cloud placeholder; size not measured.")
            } else if options.measurePackageSizes {
                size = Self.measurePackage(url, cancellation: cancellation)
                notes.append("Package contents were measured (metadata only) but are not listed.")
            } else {
                notes.append("Package: treated as one item; contents not scanned and size not measured.")
            }
        case .symbolicLink:
            size = info.size
            symlinkTarget = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)
            if let target = symlinkTarget {
                pointsOutside = Self.linkPointsOutside(target: target, linkFolder: url.deletingLastPathComponent(), root: rootURL)
            }
            notes.append("Symbolic link: not followed; its target is not scanned.")
        }

        let record = FileRecord(
            id: id, name: name, fileExtension: ext, kind: kind, path: url.path,
            relativePath: relative, parentRelativePath: parentRelative, depth: depth, size: size,
            created: info.birthTime, modified: info.modifiedTime, metadataChanged: info.statusChangeTime,
            accessed: info.accessTime, isHidden: isHidden, access: access,
            typeIdentifier: contentType?.identifier, typeDescription: contentType?.localizedDescription,
            mimeType: contentType?.preferredMIMEType, symlinkTarget: symlinkTarget,
            symlinkPointsOutsideRoot: pointsOutside, notes: notes)
        return (record, descend)
    }

    /// Lexical check only — the target is never resolved or visited.
    static func linkPointsOutside(target: String, linkFolder: URL, root: URL) -> Bool {
        let resolved = target.hasPrefix("/")
            ? URL(fileURLWithPath: target).standardizedFileURL
            : linkFolder.appendingPathComponent(target).standardizedFileURL
        let rootPath = root.standardizedFileURL.path
        let path = resolved.path
        return !(path == rootPath || path.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/"))
    }

    /// Sums logical sizes inside a package using `lstat` only. Does not follow
    /// links and skips cloud placeholders.
    static func measurePackage(_ url: URL, cancellation: CancellationFlag) -> Int64? {
        var total: Int64 = 0
        var stack = [url]
        while let folder = stack.popLast() {
            if cancellation.isCancelled { return nil }
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil, options: []) else { continue }
            for entry in entries {
                guard let info = LStat(url: entry) else { continue }
                if info.flags & flagDataless != 0 { continue }
                switch info.kind {
                case .directory, .package: stack.append(entry)
                case .file: total += info.size
                default: break
                }
            }
        }
        return total
    }

    static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoPermissionError {
            return "permission denied"
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError, underlying.domain == NSPOSIXErrorDomain {
            return String(cString: strerror(Int32(underlying.code)))
        }
        return nsError.localizedDescription
    }
}

/// Result of `lstat(2)`: metadata of the entry itself, never a link target.
struct LStat {
    let kind: FileKind
    let size: Int64
    let flags: UInt32
    let birthTime: Date?
    let modifiedTime: Date?
    let statusChangeTime: Date?
    let accessTime: Date?

    init?(url: URL) {
        var info = stat()
        let status = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return lstat(path, &info)
        }
        guard status == 0 else { return nil }

        switch info.st_mode & S_IFMT {
        case S_IFDIR: kind = .directory
        case S_IFREG: kind = .file
        case S_IFLNK: kind = .symbolicLink
        default: kind = .other
        }
        size = Int64(info.st_size)
        flags = UInt32(info.st_flags)
        birthTime = LStat.creationDate(fromBirthTime: LStat.date(info.st_birthtimespec))
        modifiedTime = LStat.date(info.st_mtimespec)
        statusChangeTime = LStat.date(info.st_ctimespec)
        accessTime = LStat.date(info.st_atimespec)
    }

    static func date(_ spec: timespec) -> Date {
        Date(timeIntervalSince1970: TimeInterval(spec.tv_sec) + TimeInterval(spec.tv_nsec) / 1_000_000_000)
    }

    /// Filesystems without birth-time support report 0 (or a negative value).
    /// Those are shown as "Unavailable" instead of a fabricated 1970 date, and
    /// the modification date is never substituted.
    static func creationDate(fromBirthTime date: Date?) -> Date? {
        guard let date, date.timeIntervalSince1970 > 0 else { return nil }
        return date
    }
}
