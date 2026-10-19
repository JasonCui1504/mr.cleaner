import Foundation
import XCTest
@testable import OrganizerCore

final class ScannerTests: XCTestCase {
    private var roots: [URL] = []

    override func tearDown() {
        for root in roots {
            // Restore permissions changed by tests before cleanup.
            if let enumerator = FileManager.default.enumerator(atPath: root.path) {
                for case let relative as String in enumerator {
                    try? Fixture.setPermissions(root.appendingPathComponent(relative), 0o755)
                }
            }
            Fixture.remove(root)
        }
        roots = []
        super.tearDown()
    }

    private func makeRoot(_ name: String = #function) throws -> URL {
        let root = try Fixture.makeRoot(name.replacingOccurrences(of: "()", with: ""))
        roots.append(root)
        return root
    }

    private func scan(_ root: URL, options: ScanOptions = ScanOptions()) throws -> ScanResult {
        try FolderScanner(options: options).scan(root: root)
    }

    private func record(_ result: ScanResult, _ relativePath: String) -> FileRecord? {
        result.records.first { $0.relativePath == relativePath }
    }

    func testEmptyFolder() throws {
        let root = try makeRoot()
        let result = try scan(root)
        XCTAssertTrue(result.records.isEmpty)
        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertFalse(result.wasCancelled)
    }

    func testRootMustBeAFolder() throws {
        let root = try makeRoot()
        let file = try Fixture.file(root, "file.txt", bytes: 3)
        XCTAssertThrowsError(try FolderScanner().scan(root: file))
        XCTAssertThrowsError(try FolderScanner().scan(root: root.appendingPathComponent("missing")))
    }

    func testRootSymlinkIsRejected() throws {
        let root = try makeRoot()
        try Fixture.folder(root, "real")
        try Fixture.symlink(root, "alias", to: root.appendingPathComponent("real").path)
        XCTAssertThrowsError(try FolderScanner().scan(root: root.appendingPathComponent("alias"))) { error in
            guard case FolderScanner.ScanError.rootIsSymbolicLink = error else { return XCTFail("Unexpected error \(error)") }
        }
    }

    func testSmallMixedFolderSizesAndTotals() throws {
        let root = try makeRoot()
        try Fixture.file(root, "invoice.pdf", bytes: 1_234)
        try Fixture.file(root, "photo.JPG", bytes: 10)
        try Fixture.file(root, "notes.txt", bytes: 0)
        try Fixture.file(root, "data.csv", bytes: 999)
        let result = try scan(root)
        XCTAssertEqual(result.records.count, 4)
        XCTAssertEqual(record(result, "invoice.pdf")?.size, 1_234)
        XCTAssertEqual(record(result, "photo.JPG")?.fileExtension, "jpg")
        XCTAssertEqual(record(result, "notes.txt")?.size, 0)
        XCTAssertEqual(result.records.compactMap(\.size).reduce(0, +), 1_234 + 10 + 0 + 999)
        XCTAssertTrue(result.records.allSatisfy { $0.kind == .file && $0.access == .readable })
        // ids equal positions
        XCTAssertEqual(result.records.map(\.id), Array(0..<4))
    }

    func testNestedFolders() throws {
        let root = try makeRoot()
        try Fixture.file(root, "a/b/c/deep.txt", bytes: 5)
        try Fixture.file(root, "a/top.txt", bytes: 1)
        let result = try scan(root)
        XCTAssertEqual(Set(result.records.map(\.relativePath)), ["a", "a/b", "a/b/c", "a/b/c/deep.txt", "a/top.txt"])
        let deep = try XCTUnwrap(record(result, "a/b/c/deep.txt"))
        XCTAssertEqual(deep.parentRelativePath, "a/b/c")
        XCTAssertEqual(deep.depth, 4)
        XCTAssertEqual(record(result, "a/b")?.kind, .directory)
        XCTAssertNil(record(result, "a/b")?.size)
    }

    func testHiddenFiles() throws {
        let root = try makeRoot()
        try Fixture.file(root, ".hidden-config", bytes: 2)
        try Fixture.file(root, "visible.txt", bytes: 2)
        let result = try scan(root)
        XCTAssertEqual(record(result, ".hidden-config")?.isHidden, true)
        XCTAssertEqual(record(result, "visible.txt")?.isHidden, false)

        var options = ScanOptions()
        options.includeHidden = false
        let withoutHidden = try scan(root, options: options)
        XCTAssertEqual(withoutHidden.records.map(\.name), ["visible.txt"])
    }

    func testUnicodeAndUnusualNames() throws {
        let root = try makeRoot()
        let names = [
            "Résumé – 2024 最终版 🎉.pdf",
            "file with  spaces & (parens) [brackets] #1.txt",
            "emoji 🗂️📁.md",
            String(repeating: "long", count: 60) + ".txt",   // 244 characters
            "-leading-dash.txt",
            "semi;colon,comma'quote.txt",
        ]
        for name in names { try Fixture.file(root, name, bytes: 7) }
        let result = try scan(root)
        XCTAssertEqual(Set(result.records.map(\.name)), Set(names))
        XCTAssertTrue(result.records.allSatisfy { $0.size == 7 })
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testCreationAndModificationDatesAreDistinct() throws {
        let root = try makeRoot()
        let past = Date(timeIntervalSince1970: 1_577_880_000)   // 2020-01-01
        try Fixture.file(root, "old.txt", bytes: 1, modified: past)
        let result = try scan(root)
        let old = try XCTUnwrap(record(result, "old.txt"))
        let modified = try XCTUnwrap(old.modified)
        XCTAssertEqual(modified.timeIntervalSince1970, past.timeIntervalSince1970, accuracy: 1)
        // Created just now; must not be substituted with the modification date.
        if let created = old.created {
            XCTAssertGreaterThan(created.timeIntervalSince(modified), 86_400)
            XCTAssertEqual(created.timeIntervalSinceNow, 0, accuracy: 600)
        }
        // Status change time is a separate field.
        XCTAssertNotNil(old.metadataChanged)
    }

    func testUnavailableCreationDateIsNotFabricated() {
        XCTAssertNil(LStat.creationDate(fromBirthTime: Date(timeIntervalSince1970: 0)))
        XCTAssertNil(LStat.creationDate(fromBirthTime: Date(timeIntervalSince1970: -1)))
        XCTAssertNil(LStat.creationDate(fromBirthTime: nil))
        let real = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(LStat.creationDate(fromBirthTime: real), real)
        XCTAssertEqual(Formatting.date(nil), "Unavailable")
    }

    func testPermissionDeniedFolderIsSkippedAndScanContinues() throws {
        try XCTSkipIf(getuid() == 0, "Permission checks do not apply when running as root.")
        let root = try makeRoot()
        try Fixture.file(root, "locked/secret.txt", bytes: 1)
        try Fixture.file(root, "open/readable.txt", bytes: 1)
        try Fixture.setPermissions(root.appendingPathComponent("locked"), 0o000)
        let result = try scan(root)
        XCTAssertNotNil(record(result, "locked"))
        XCTAssertNil(record(result, "locked/secret.txt"))
        XCTAssertNotNil(record(result, "open/readable.txt"))
        XCTAssertTrue(result.issues.contains { $0.relativePath == "locked" })
    }

    func testSymbolicLinksAreNotFollowed() throws {
        let root = try makeRoot()
        let outside = try makeRoot("outside")
        try Fixture.file(outside, "outside-secret.txt", bytes: 3)
        try Fixture.file(root, "inside.txt", bytes: 3)
        try Fixture.symlink(root, "to-outside", to: outside.path)
        try Fixture.symlink(root, "loop", to: ".")
        try Fixture.symlink(root, "relative-file", to: "inside.txt")

        let result = try scan(root)
        XCTAssertEqual(Set(result.records.map(\.relativePath)), ["inside.txt", "loop", "relative-file", "to-outside"])
        let link = try XCTUnwrap(record(result, "to-outside"))
        XCTAssertEqual(link.kind, .symbolicLink)
        XCTAssertEqual(link.symlinkTarget, outside.path)
        XCTAssertEqual(link.symlinkPointsOutsideRoot, true)
        XCTAssertEqual(record(result, "relative-file")?.symlinkPointsOutsideRoot, false)
        XCTAssertFalse(result.records.contains { $0.name == "outside-secret.txt" })
        XCTAssertTrue(result.records.allSatisfy { $0.path.hasPrefix(root.standardizedFileURL.path) })
    }

    func testVersionControlInternalsSkippedByDefault() throws {
        let root = try makeRoot()
        try Fixture.file(root, "repo/.git/HEAD", bytes: 1)
        try Fixture.file(root, "repo/main.py", bytes: 1)
        let result = try scan(root)
        XCTAssertNotNil(record(result, "repo/.git"))
        XCTAssertNil(record(result, "repo/.git/HEAD"))

        var options = ScanOptions()
        options.skipVersionControlInternals = false
        XCTAssertNotNil(record(try scan(root, options: options), "repo/.git/HEAD"))
    }

    func testPackagesAreNotDescended() throws {
        let root = try makeRoot()
        try Fixture.file(root, "Tool.app/Contents/Info.plist", bytes: 40)
        try Fixture.file(root, "Tool.app/Contents/MacOS/tool", bytes: 60)
        let result = try scan(root)
        let package = try XCTUnwrap(record(result, "Tool.app"))
        XCTAssertEqual(package.kind, .package)
        XCTAssertNil(package.size)
        XCTAssertFalse(result.records.contains { $0.relativePath.hasPrefix("Tool.app/") })

        var options = ScanOptions()
        options.measurePackageSizes = true
        let measured = try scan(root, options: options)
        XCTAssertEqual(record(measured, "Tool.app")?.size, 100)
        XCTAssertFalse(measured.records.contains { $0.relativePath.hasPrefix("Tool.app/") })
    }

    func testCancellationReturnsPartialResults() throws {
        let root = try makeRoot()
        for folder in 0..<10 {
            for index in 0..<200 { try Fixture.file(root, "f\(folder)/file\(index).txt") }
        }
        var options = ScanOptions()
        options.batchSize = 100
        let flag = CancellationFlag()
        var batches = 0
        let result = try FolderScanner(options: options).scan(root: root, cancellation: flag) { _, _ in
            batches += 1
            flag.cancel()
        }
        XCTAssertTrue(result.wasCancelled)
        XCTAssertGreaterThan(result.records.count, 0)
        XCTAssertLessThan(result.records.count, 2_010)
        XCTAssertGreaterThanOrEqual(batches, 1)
    }

    func testLargeSyntheticDirectoryPerformance() throws {
        let root = try makeRoot()
        for folder in 0..<100 {
            for index in 0..<200 { try Fixture.file(root, "dir\(folder)/item_\(index).dat") }
        }
        let start = Date()
        let result = try scan(root)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(result.records.count, 20_100)
        XCTAssertLessThan(elapsed, 60, "Scanning 20k entries took \(elapsed)s")

        let analysisStart = Date()
        let analysis = Analyzer.analyze(result)
        XCTAssertEqual(analysis.classifications.count, 20_100)
        XCTAssertLessThan(Date().timeIntervalSince(analysisStart), 60)
    }

    func testScanChangesNothingInTheFixture() throws {
        let root = try makeRoot()
        try Fixture.file(root, "Financial/invoice 2024.pdf", bytes: 2_048, modified: Date(timeIntervalSince1970: 1_600_000_000))
        try Fixture.file(root, "Photos/IMG_0001.HEIC", bytes: 512)
        try Fixture.file(root, ".hidden", bytes: 1)
        try Fixture.file(root, "proj/package.json", bytes: 20)
        try Fixture.symlink(root, "link", to: "Photos")
        let before = try Fixture.snapshot(root)
        var options = ScanOptions()
        options.measurePackageSizes = true
        _ = Analyzer.analyze(try scan(root, options: options))
        let after = try Fixture.snapshot(root)
        XCTAssertEqual(before, after, "A scan must not create, remove, or modify any entry")
    }
}
