import XCTest
@testable import OrganizerCore

@MainActor
final class ControllerTests: XCTestCase {
    private var roots: [URL] = []

    override func tearDown() async throws {
        for root in roots { Fixture.remove(root) }
        roots = []
    }

    private func makeLargeFixture(_ name: String, folders: Int, filesPerFolder: Int) throws -> URL {
        let root = try Fixture.makeRoot(name)
        roots.append(root)
        for folder in 0..<folders {
            for index in 0..<filesPerFolder {
                try Fixture.file(root, "batch\(folder)/invoice_\(index).pdf", bytes: 1)
            }
        }
        return root
    }

    func testScanDoesNotBlockTheMainActor() async throws {
        let root = try makeLargeFixture("nonblocking", folders: 50, filesPerFolder: 200)
        let controller = ScanController()
        controller.select(root: root)
        XCTAssertEqual(controller.phase, .ready)

        let start = Date()
        controller.startScan()
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.25, "startScan must return immediately")
        XCTAssertEqual(controller.phase, .scanning)

        // While the scan runs, this main-actor loop keeps getting scheduled.
        // A scan on the main thread would make that impossible.
        var mainActorTurns = 0
        while controller.phase.isBusy {
            mainActorTurns += 1
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertGreaterThan(mainActorTurns, 0)
        XCTAssertEqual(controller.phase, .finished)
        XCTAssertEqual(controller.records.count, 10_050)
        XCTAssertEqual(controller.rows.count, 10_050)
        XCTAssertEqual(controller.summary.countsByCategory[.financial], 10_000)
    }

    func testStopScanKeepsPartialResults() async throws {
        let root = try makeLargeFixture("stop", folders: 100, filesPerFolder: 200)
        let controller = ScanController()
        controller.options.batchSize = 50
        controller.select(root: root)
        controller.startScan()
        controller.stopScan()
        await controller.waitForScan()
        XCTAssertEqual(controller.phase, .stopped)
        XCTAssertLessThan(controller.records.count, 20_100)
        XCTAssertEqual(controller.rows.count, controller.records.count)
    }

    func testSessionEditsAffectOnlyMemory() async throws {
        let root = try Fixture.makeRoot("edits")
        roots.append(root)
        try Fixture.file(root, "invoice.pdf", bytes: 3)
        let before = try Fixture.snapshot(root)

        let controller = ScanController()
        controller.select(root: root)
        controller.startScan()
        await controller.waitForScan()
        let id = try XCTUnwrap(controller.records.first?.id)

        XCTAssertEqual(controller.effectiveClassification(for: id)?.category, .financial)
        controller.setCategoryOverride(.work, for: id)
        XCTAssertEqual(controller.effectiveClassification(for: id)?.category, .work)
        XCTAssertEqual(controller.rows[id].categoryName, "Work & Career (edited)")
        XCTAssertEqual(controller.summary.countsByCategory[.work], 1)
        XCTAssertEqual(controller.plan.first?.items.first?.suggestedPath, "Work & Career/invoice.pdf")

        controller.setReviewLater(true, for: id)
        XCTAssertEqual(controller.summary.needsReview, 1)
        controller.setCategoryOverride(nil, for: id)
        XCTAssertEqual(controller.effectiveClassification(for: id)?.category, .financial)

        // A new scan starts clean: edits are not retained anywhere.
        controller.startScan()
        await controller.waitForScan()
        XCTAssertTrue(controller.overrides.isEmpty)
        XCTAssertTrue(controller.reviewLater.isEmpty)
        XCTAssertEqual(try Fixture.snapshot(root), before)
    }

    func testFailedScanReportsError() async throws {
        let controller = ScanController()
        controller.select(root: Fixture.generatedRoot.appendingPathComponent("does-not-exist-\(UUID().uuidString)"))
        controller.startScan()
        await controller.waitForScan()
        guard case .failed = controller.phase else { return XCTFail("Expected failure, got \(controller.phase)") }
    }
}
