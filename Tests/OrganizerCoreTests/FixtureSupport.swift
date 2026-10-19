import Foundation
import XCTest
@testable import OrganizerCore

/// Creates synthetic fixtures. Every path is confined to
/// `Tests/Fixtures/Generated/` inside this repository; anything else is a
/// test failure. Real user folders are never touched.
///
/// Note: this is test-harness code. Writing here is how fixtures are built;
/// the app sources under `Sources/` contain no writing APIs (see SafetyTests).
enum Fixture {
    static let testsDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // OrganizerCoreTests
        .deletingLastPathComponent()   // Tests

    static let generatedRoot = testsDirectory
        .appendingPathComponent("Fixtures", isDirectory: true)
        .appendingPathComponent("Generated", isDirectory: true)
        .standardizedFileURL

    static var repositoryRoot: URL { testsDirectory.deletingLastPathComponent() }

    private static func assertConfined(_ url: URL, file: StaticString = #filePath, line: UInt = #line) throws {
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(generatedRoot.path + "/") else {
            XCTFail("Refusing to touch a path outside the fixture folder: \(path)", file: file, line: line)
            throw CocoaError(.fileWriteNoPermission)
        }
    }

    /// A fresh, empty fixture folder.
    static func makeRoot(_ name: String) throws -> URL {
        let url = generatedRoot.appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try assertConfined(url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    static func file(_ root: URL, _ relativePath: String, bytes: Int = 0, modified: Date? = nil) throws -> URL {
        let url = root.appendingPathComponent(relativePath)
        try assertConfined(url)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x61, count: bytes).write(to: url)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
        return url
    }

    static func folder(_ root: URL, _ relativePath: String) throws {
        let url = root.appendingPathComponent(relativePath, isDirectory: true)
        try assertConfined(url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    static func symlink(_ root: URL, _ relativePath: String, to destination: String) throws {
        let url = root.appendingPathComponent(relativePath)
        try assertConfined(url)
        try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: destination)
    }

    static func setPermissions(_ url: URL, _ mode: Int) throws {
        try assertConfined(url)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }

    static func remove(_ url: URL) {
        guard (try? assertConfined(url)) != nil else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Names, kinds, sizes, timestamps and content bytes of every entry under
    /// `root` (not following links). Used to prove a scan changed nothing.
    static func snapshot(_ root: URL) throws -> [String: String] {
        var result: [String: String] = [:]
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .creationDateKey, .isSymbolicLinkKey, .isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: []) else {
            return result
        }
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            var entry = "size=\(values.fileSize ?? -1) mod=\(values.contentModificationDate?.timeIntervalSince1970 ?? 0) "
                + "created=\(values.creationDate?.timeIntervalSince1970 ?? 0) link=\(values.isSymbolicLink ?? false)"
            if values.isDirectory != true, values.isSymbolicLink != true {
                entry += " bytes=\((try? Data(contentsOf: url))?.hashValue ?? 0)"
            }
            result[url.path.replacingOccurrences(of: root.path, with: "")] = entry
        }
        return result
    }
}

/// Builds a record without touching the filesystem (for grouping/summary tests).
func makeRecord(
    _ id: Int, _ relativePath: String, kind: FileKind = .file, size: Int64? = 100,
    created: Date? = Date(timeIntervalSince1970: 1_600_000_000),
    modified: Date? = Date(timeIntervalSince1970: 1_700_000_000), hidden: Bool = false
) -> FileRecord {
    let name = String(relativePath.split(separator: "/").last ?? "")
    let parent = relativePath.split(separator: "/").dropLast().joined(separator: "/")
    return FileRecord(
        id: id, name: name, fileExtension: NameAnalysis.splitExtension(name).ext, kind: kind,
        path: "/fixture/" + relativePath, relativePath: relativePath, parentRelativePath: parent,
        depth: relativePath.split(separator: "/").count, size: kind == .directory ? nil : size,
        created: created, modified: modified, metadataChanged: modified, accessed: nil, isHidden: hidden,
        access: .readable, typeIdentifier: nil, typeDescription: nil, mimeType: nil,
        symlinkTarget: nil, symlinkPointsOutsideRoot: nil, notes: [])
}
