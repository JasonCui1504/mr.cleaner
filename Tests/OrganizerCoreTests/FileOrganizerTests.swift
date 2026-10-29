import Foundation
import XCTest
@testable import OrganizerCore

final class FileOrganizerTests: XCTestCase {
    private var roots: [URL] = []

    override func tearDown() {
        for root in roots { Fixture.remove(root) }
        roots = []
        super.tearDown()
    }

    private func makeRoot(_ name: String = #function) throws -> URL {
        let root = try Fixture.makeRoot(name.replacingOccurrences(of: "()", with: ""))
        roots.append(root)
        return root
    }

    private func exists(_ url: URL) -> Bool { LStat(url: url) != nil }

    func testCreatesFolderAndMovesKeepingNameAndContents() throws {
        let root = try makeRoot()
        let past = Date(timeIntervalSince1970: 1_600_000_000)
        let file = try Fixture.file(root, "Downloads/invoice.pdf", bytes: 123, modified: past)
        let organizer = try FileOrganizer(root: root)

        let move = try organizer.move(file, intoFolderNamed: "Financial & Tax")
        let destination = root.appendingPathComponent("Financial & Tax/invoice.pdf")
        XCTAssertFalse(exists(file))
        XCTAssertTrue(exists(destination))
        XCTAssertEqual(try Data(contentsOf: destination).count, 123)
        let info = try XCTUnwrap(LStat(url: destination))
        XCTAssertEqual(info.modifiedTime?.timeIntervalSince1970 ?? 0, past.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(move.name, "invoice.pdf")
        XCTAssertEqual(move.fromPath, file.standardizedFileURL.path)
    }

    func testNeverOverwrites() throws {
        let root = try makeRoot()
        let source = try Fixture.file(root, "a/report.pdf", bytes: 10)
        try Fixture.file(root, "Trash/report.pdf", bytes: 99)
        let organizer = try FileOrganizer(root: root)
        XCTAssertThrowsError(try organizer.move(source, intoFolderNamed: "Trash")) { error in
            guard case FileOrganizer.OrganizeError.alreadyExists = error else { return XCTFail("\(error)") }
        }
        XCTAssertTrue(exists(source))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Trash/report.pdf")).count, 99)
    }

    func testRefusesSourcesOutsideRoot() throws {
        let root = try makeRoot()
        let outside = try makeRoot("outside")
        let file = try Fixture.file(outside, "secret.txt", bytes: 1)
        let organizer = try FileOrganizer(root: root)
        XCTAssertThrowsError(try organizer.move(file, intoFolderNamed: "Trash"))
        XCTAssertTrue(exists(file))
        XCTAssertThrowsError(try organizer.move(root.appendingPathComponent("../\(outside.lastPathComponent)/secret.txt"), intoFolderNamed: "Trash"))
        XCTAssertTrue(exists(file))
    }

    func testFolderNameValidation() throws {
        let root = try makeRoot()
        let organizer = try FileOrganizer(root: root)
        for bad in ["", ".hidden", "a/b", "..", "x:y", " padded "] {
            XCTAssertFalse(FileOrganizer.isValidFolderName(bad), bad)
            XCTAssertThrowsError(try organizer.ensureFolder(named: bad), bad)
        }
        XCTAssertTrue(FileOrganizer.isValidFolderName("Uncategorized - Review"))
        XCTAssertTrue(FileOrganizer.isValidFolderName("Financial & Tax"))
    }

    func testDestinationMustBeARealFolder() throws {
        let root = try makeRoot()
        let outside = try makeRoot("linktarget")
        try Fixture.file(root, "Trash", bytes: 1)                     // a file named Trash
        try Fixture.symlink(root, "Work & Career", to: outside.path)   // a link named like a folder
        let source = try Fixture.file(root, "doc.txt", bytes: 1)
        let organizer = try FileOrganizer(root: root)
        XCTAssertThrowsError(try organizer.move(source, intoFolderNamed: "Trash"))
        XCTAssertThrowsError(try organizer.move(source, intoFolderNamed: "Work & Career"))
        XCTAssertTrue(exists(source))
        XCTAssertFalse(exists(outside.appendingPathComponent("doc.txt")))
    }

    func testFolderCannotMoveIntoItself() throws {
        let root = try makeRoot()
        try Fixture.file(root, "Trash/inner.txt", bytes: 1)
        let organizer = try FileOrganizer(root: root)
        XCTAssertThrowsError(try organizer.move(root.appendingPathComponent("Trash"), intoFolderNamed: "Trash"))
        XCTAssertTrue(exists(root.appendingPathComponent("Trash/inner.txt")))
    }

    func testMovingFoldersAndUndo() throws {
        let root = try makeRoot()
        try Fixture.file(root, "old stuff/a.txt", bytes: 1)
        let organizer = try FileOrganizer(root: root)
        let move = try organizer.move(root.appendingPathComponent("old stuff"), intoFolderNamed: "Trash")
        XCTAssertTrue(exists(root.appendingPathComponent("Trash/old stuff/a.txt")))

        _ = try organizer.undo(move)
        XCTAssertTrue(exists(root.appendingPathComponent("old stuff/a.txt")))
        XCTAssertFalse(exists(root.appendingPathComponent("Trash/old stuff")))
    }

    func testUndoRefusesWhenOriginalSpotIsTaken() throws {
        let root = try makeRoot()
        let file = try Fixture.file(root, "x.txt", bytes: 1)
        let organizer = try FileOrganizer(root: root)
        let move = try organizer.move(file, intoFolderNamed: "Trash")
        try Fixture.file(root, "x.txt", bytes: 5)
        XCTAssertThrowsError(try organizer.undo(move))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("x.txt")).count, 5)
        XCTAssertTrue(exists(root.appendingPathComponent("Trash/x.txt")))
    }

    func testNothingIsDeleted() throws {
        let root = try makeRoot()
        for name in ["a.pdf", "b.jpg", "c.txt"] { try Fixture.file(root, "in/\(name)", bytes: 3) }
        let organizer = try FileOrganizer(root: root)
        for name in ["a.pdf", "b.jpg", "c.txt"] {
            _ = try organizer.move(root.appendingPathComponent("in/\(name)"), intoFolderNamed: "Trash")
        }
        let remaining = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Trash").path).sorted()
        XCTAssertEqual(remaining, ["a.pdf", "b.jpg", "c.txt"])
        XCTAssertTrue(exists(root.appendingPathComponent("in")), "source folders are left in place, even when empty")
    }
}

@MainActor
final class OrganizeModeControllerTests: XCTestCase {
    private var roots: [URL] = []

    override func tearDown() async throws {
        for root in roots { Fixture.remove(root) }
        roots = []
    }

    private func scanned(_ name: String, files: [String]) async throws -> (ScanController, URL) {
        let root = try Fixture.makeRoot(name)
        roots.append(root)
        for file in files { try Fixture.file(root, file, bytes: 4) }
        let controller = ScanController()
        controller.select(root: root)
        controller.startScan()
        await controller.waitForScan()
        return (controller, root)
    }

    private func waitUntilIdle(_ controller: ScanController) async throws {
        for _ in 0..<500 where controller.phase.isBusy { try await Task.sleep(nanoseconds: 10_000_000) }
        await controller.waitForScan()
    }

    func testReadOnlyByDefault() async throws {
        let (controller, root) = try await scanned("readonly", files: ["invoice.pdf"])
        XCTAssertFalse(controller.organizeModeEnabled)
        controller.move(recordIDs: [0], toFolderNamed: "Trash")
        controller.applyPlan(folders: Set(controller.plan.map(\.name)))
        try await waitUntilIdle(controller)
        XCTAssertNil(LStat(url: root.appendingPathComponent("Trash")))
        XCTAssertNil(LStat(url: root.appendingPathComponent("Financial & Tax")))
        XCTAssertNotNil(LStat(url: root.appendingPathComponent("invoice.pdf")))
    }

    func testMoveToTrashThenUndoAll() async throws {
        let (controller, root) = try await scanned("trash", files: ["dup.jpg", "keep.txt"])
        controller.organizeModeEnabled = true
        let id = try XCTUnwrap(controller.records.first { $0.name == "dup.jpg" }?.id)
        controller.move(recordIDs: [id], toFolderNamed: FileOrganizer.trashFolderName)
        try await waitUntilIdle(controller)
        XCTAssertNotNil(LStat(url: root.appendingPathComponent("Trash/dup.jpg")))
        XCTAssertEqual(controller.moveLog.count, 1)
        XCTAssertEqual(controller.lastOrganizeReport?.movedCount, 1)
        XCTAssertTrue(controller.records.contains { $0.relativePath == "Trash/dup.jpg" }, "results are refreshed")

        controller.undo(controller.moveLog)
        try await waitUntilIdle(controller)
        XCTAssertNotNil(LStat(url: root.appendingPathComponent("dup.jpg")))
        XCTAssertTrue(controller.moveLog.isEmpty)
    }

    func testQuickFoldersCreateFoldersAndMovesKeepRowIdentity() async throws {
        let (controller, root) = try await scanned("quick", files: ["a/photo.jpg", "a/notes.txt"])
        controller.organizeModeEnabled = true
        controller.addQuickFolder(named: "Keep")
        try await waitUntilIdle(controller)
        XCTAssertEqual(controller.quickFolders, ["Trash", "Keep"])
        XCTAssertNotNil(LStat(url: root.appendingPathComponent("Keep")))
        XCTAssertTrue(controller.records.contains { $0.relativePath == "Keep" && $0.kind == .directory })

        let id = try XCTUnwrap(controller.records.first { $0.name == "photo.jpg" }?.id)
        controller.setReviewLater(true, for: id)
        controller.move(recordIDs: [id], toFolderNamed: "Keep")
        try await waitUntilIdle(controller)
        XCTAssertEqual(controller.record(id)?.relativePath, "Keep/photo.jpg", "same row id, new location")
        XCTAssertTrue(controller.reviewLater.contains(id), "session edits survive a move")
        XCTAssertNotNil(LStat(url: root.appendingPathComponent("Keep/photo.jpg")))

        controller.removeQuickFolder("Keep")
        XCTAssertEqual(controller.quickFolders, ["Trash"])
        XCTAssertNotNil(LStat(url: root.appendingPathComponent("Keep")), "removing a button never touches the disk")
    }

    func testMovingAFolderUpdatesItsChildren() async throws {
        let (controller, _) = try await scanned("folder-move", files: ["old/x.txt", "old/sub/y.txt"])
        controller.organizeModeEnabled = true
        let folderID = try XCTUnwrap(controller.records.first { $0.relativePath == "old" }?.id)
        let childID = try XCTUnwrap(controller.records.first { $0.name == "y.txt" }?.id)
        controller.move(recordIDs: [folderID], toFolderNamed: "Trash")
        try await waitUntilIdle(controller)
        XCTAssertEqual(controller.record(folderID)?.relativePath, "Trash/old")
        XCTAssertEqual(controller.record(childID)?.relativePath, "Trash/old/sub/y.txt")
        XCTAssertEqual(controller.record(childID)?.parentRelativePath, "Trash/old/sub")
    }

    func testMovingSeveralItemsAtOnce() async throws {
        let (controller, root) = try await scanned("multi", files: [
            "a.txt", "b.jpg", "old/c.txt", "old/sub/d.txt", "Keep/already.txt",
        ])
        controller.organizeModeEnabled = true
        let ids = controller.records.map(\.id)
        // Everything selected: the folder's children travel with "old", the
        // destination itself and items already in it are left out.
        let sources = controller.movableSources(recordIDs: ids + ids, toFolderNamed: "Keep").map(\.lastPathComponent)
        XCTAssertEqual(Set(sources), ["a.txt", "b.jpg", "old"])
        XCTAssertEqual(sources.count, 3)

        controller.move(recordIDs: ids, toFolderNamed: "Keep")
        try await waitUntilIdle(controller)
        XCTAssertEqual(controller.lastOrganizeReport?.movedCount, 3)
        XCTAssertEqual(controller.lastOrganizeReport?.skipped.count, 0)
        for path in ["Keep/a.txt", "Keep/b.jpg", "Keep/old/sub/d.txt", "Keep/already.txt"] {
            XCTAssertNotNil(LStat(url: root.appendingPathComponent(path)), path)
        }
        XCTAssertEqual(controller.moveLog.count, 3)
    }

    func testExistingFoldersCanBeChosenAsButtons() async throws {
        let (controller, root) = try await scanned("existing", files: [
            "Receipts/r.pdf", "Photos 2024/p.jpg", "Photos 2024/inner/q.jpg", "loose.txt",
        ])
        XCTAssertEqual(controller.existingFolders, ["Photos 2024", "Receipts"], "top-level folders only")
        XCTAssertEqual(controller.quickFolders, ["Trash"])

        // Works with Organize mode off: it only changes the in-memory list.
        controller.setQuickFolder("Receipts", included: true)
        controller.setQuickFolder("Receipts", included: true)
        XCTAssertEqual(controller.quickFolders, ["Trash", "Receipts"])
        controller.includeAllExistingFolders()
        XCTAssertEqual(controller.quickFolders, ["Trash", "Receipts", "Photos 2024"])
        controller.setQuickFolder("Receipts", included: false)
        controller.setQuickFolder("Trash", included: false)
        XCTAssertEqual(controller.quickFolders, ["Trash", "Photos 2024"], "Trash always stays")
        XCTAssertNotNil(LStat(url: root.appendingPathComponent("Receipts")))
        XCTAssertNil(LStat(url: root.appendingPathComponent("Trash")), "nothing created")

        controller.organizeModeEnabled = true
        controller.addQuickFolder(named: "New One")
        try await waitUntilIdle(controller)
        XCTAssertEqual(controller.existingFolders, ["New One", "Photos 2024", "Receipts"], "refreshed after creating")
    }

    func testInvalidQuickFolderNameIsRejected() async throws {
        let (controller, root) = try await scanned("badname", files: ["f.txt"])
        controller.organizeModeEnabled = true
        controller.addQuickFolder(named: "../escape")
        try await waitUntilIdle(controller)
        XCTAssertEqual(controller.quickFolders, ["Trash"])
        XCTAssertNotNil(controller.lastOrganizeReport?.skipped.first)
        XCTAssertNil(LStat(url: root.deletingLastPathComponent().appendingPathComponent("escape")))
    }

    func testApplyPlanSkipsProjectsAndExistingNames() async throws {
        let (controller, root) = try await scanned("apply", files: [
            "invoice.pdf", "Downloads/IMG_0001.jpg", "app/package.json", "app/src/index.js",
            "Images & Photography/IMG_0001.jpg",
        ])
        controller.organizeModeEnabled = true
        let folders: Set<String> = ["Financial & Tax", "Images & Photography", "Software & Development"]
        controller.applyPlan(folders: folders)
        try await waitUntilIdle(controller)

        XCTAssertNotNil(LStat(url: root.appendingPathComponent("Financial & Tax/invoice.pdf")))
        XCTAssertNotNil(LStat(url: root.appendingPathComponent("Downloads/IMG_0001.jpg")), "name taken → skipped, not renamed")
        XCTAssertNotNil(LStat(url: root.appendingPathComponent("app/package.json")), "projects stay intact")
        XCTAssertNil(LStat(url: root.appendingPathComponent("Software & Development")))
        XCTAssertEqual(controller.lastOrganizeReport?.movedCount, 1)
        XCTAssertEqual(controller.lastOrganizeReport?.skipped.count, 1)
    }
}
