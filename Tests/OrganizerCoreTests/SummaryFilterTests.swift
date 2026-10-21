import XCTest
@testable import OrganizerCore

final class SummaryFilterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func rows(_ records: [FileRecord]) -> [FileRow] {
        let classifier = RuleClassifier()
        return records.map { FileRow(record: $0, classification: classifier.classify($0), reviewLater: false) }
    }

    func testSummaryCountsAndThresholds() {
        let records = [
            makeRecord(0, "Docs", kind: .directory),
            makeRecord(1, "Docs/invoice.pdf", size: 600_000_000, modified: now.addingTimeInterval(-86_400)),
            makeRecord(2, "Docs/old.txt", size: 10, created: nil, modified: now.addingTimeInterval(-400 * 86_400)),
            makeRecord(3, "mystery.xyz", size: 5, modified: now.addingTimeInterval(-30 * 86_400)),
            makeRecord(4, "link", kind: .symbolicLink, size: 4),
        ]
        let classifications = records.map { RuleClassifier().classify($0) }
        var thresholds = SummaryThresholds()
        let summary = ScanSummary.compute(
            records: records, classifications: classifications, reviewLater: [2], groups: [],
            issueCount: 1, thresholds: thresholds, now: now)
        XCTAssertEqual(summary.files, 3)
        XCTAssertEqual(summary.folders, 1)
        XCTAssertEqual(summary.symbolicLinks, 1)
        XCTAssertEqual(summary.totalBytes, 600_000_015)
        XCTAssertEqual(summary.largeFiles, 1)
        XCTAssertEqual(summary.oldFiles, 1)
        XCTAssertEqual(summary.recentFiles, 1)
        XCTAssertEqual(summary.unavailableCreationDates, 1)
        XCTAssertEqual(summary.countsByCategory[.financial], 1)
        XCTAssertEqual(summary.countsByCategory[.uncategorized], 2)   // mystery + link
        XCTAssertEqual(summary.needsReview, 3)                         // old.txt (marked), mystery, link
        XCTAssertEqual(summary.issues, 1)

        thresholds.largeFileBytes = 1
        thresholds.oldFileDays = 7
        thresholds.recentFileDays = 60
        let adjusted = ScanSummary.compute(
            records: records, classifications: classifications, reviewLater: [], groups: [],
            issueCount: 0, thresholds: thresholds, now: now)
        XCTAssertEqual(adjusted.largeFiles, 3)
        XCTAssertEqual(adjusted.oldFiles, 2)
        XCTAssertEqual(adjusted.recentFiles, 2)
    }

    func testDashboardLists() {
        let records = [
            makeRecord(0, "Docs", kind: .directory),
            makeRecord(1, "a.pdf", size: 50, modified: now.addingTimeInterval(-10)),
            makeRecord(2, "b.pdf", size: 5_000, modified: now.addingTimeInterval(-1_000)),
            makeRecord(3, "c.mov", size: 900, modified: now),
            makeRecord(4, "empty.txt", size: 0, modified: nil),
            makeRecord(5, "Makefile", size: 1, modified: now.addingTimeInterval(-5)),
        ]
        let summary = ScanSummary.compute(
            records: records, classifications: records.map { RuleClassifier().classify($0) },
            reviewLater: [], groups: [], issueCount: 0, thresholds: SummaryThresholds(), now: now)
        XCTAssertEqual(summary.largestFileIDs, [2, 3, 1, 5])     // zero-byte files and folders excluded
        XCTAssertEqual(summary.recentlyModifiedIDs, [3, 5, 1, 2]) // missing dates excluded
        XCTAssertEqual(summary.extensionStats.first, ExtensionStat(fileExtension: "pdf", count: 2, bytes: 5_050))
        XCTAssertTrue(summary.extensionStats.contains { $0.fileExtension == "(none)" && $0.count == 1 })
        XCTAssertEqual(summary.extensionStats.count, 4)
    }

    func testSizesSortNumericallyNotAsText() {
        let data = rows([
            makeRecord(0, "a.txt", size: 9),
            makeRecord(1, "b.txt", size: 100),
            makeRecord(2, "c.txt", size: 10),
            makeRecord(3, "folder", kind: .directory),
        ])
        let sorted = FilterCriteria().apply(to: data, sortedBy: [KeyPathComparator(\FileRow.sizeKey)])
        XCTAssertEqual(sorted.map(\.id), [3, 0, 2, 1])
        let descending = FilterCriteria().apply(to: data, sortedBy: [KeyPathComparator(\FileRow.sizeKey, order: .reverse)])
        XCTAssertEqual(descending.map(\.id), [1, 2, 0, 3])
    }

    func testDatesSortChronologicallyAndUnavailableFirst() {
        let data = rows([
            makeRecord(0, "new.txt", created: Date(timeIntervalSince1970: 2_000_000_000)),
            makeRecord(1, "unknown.txt", created: nil),
            makeRecord(2, "old.txt", created: Date(timeIntervalSince1970: 100)),
        ])
        let sorted = FilterCriteria().apply(to: data, sortedBy: [KeyPathComparator(\FileRow.createdKey)])
        XCTAssertEqual(sorted.map(\.id), [1, 2, 0])
        XCTAssertEqual(data[1].createdText, "Unavailable")
    }

    func testFilters() {
        let data = rows([
            makeRecord(0, "Taxes", kind: .directory),
            makeRecord(1, "Taxes/invoice.pdf", size: 2_000_000, modified: now),
            makeRecord(2, "Taxes/.secret", size: 10, modified: now, hidden: true),
            makeRecord(3, "Photos/IMG_0001.jpg", size: 500, modified: now.addingTimeInterval(-90 * 86_400)),
            makeRecord(4, "mystery.xyz", size: 5, modified: now),
        ])
        var criteria = FilterCriteria()
        XCTAssertEqual(criteria.apply(to: data, sortedBy: []).count, 5)

        criteria.searchText = "taxes/INV"
        XCTAssertEqual(criteria.apply(to: data, sortedBy: []).map(\.id), [1])

        criteria = FilterCriteria()
        criteria.category = .images
        XCTAssertEqual(criteria.apply(to: data, sortedBy: []).map(\.id), [3])

        criteria = FilterCriteria()
        criteria.fileType = "pdf"
        XCTAssertEqual(criteria.apply(to: data, sortedBy: []).map(\.id), [1])

        criteria = FilterCriteria()
        criteria.kind = .folders
        XCTAssertEqual(criteria.apply(to: data, sortedBy: []).map(\.id), [0])

        criteria = FilterCriteria()
        criteria.hidden = .hiddenOnly
        XCTAssertEqual(criteria.apply(to: data, sortedBy: []).map(\.id), [2])

        criteria = FilterCriteria()
        criteria.reviewOnly = true
        XCTAssertTrue(criteria.apply(to: data, sortedBy: []).map(\.id).contains(4))
        XCTAssertFalse(criteria.apply(to: data, sortedBy: []).map(\.id).contains(1))

        criteria = FilterCriteria()
        criteria.minBytes = 1_000
        XCTAssertEqual(criteria.apply(to: data, sortedBy: []).map(\.id), [1])

        criteria = FilterCriteria()
        criteria.modifiedFrom = now.addingTimeInterval(-7 * 86_400)
        XCTAssertEqual(Set(criteria.apply(to: data, sortedBy: []).map(\.id)), [1, 2, 4])

        criteria = FilterCriteria()
        criteria.excludedRelativePaths = ["Taxes", "mystery.xyz"]
        XCTAssertEqual(criteria.apply(to: data, sortedBy: []).map(\.id), [3])

        criteria.excludedRelativePaths = ["Tax"]
        XCTAssertEqual(criteria.apply(to: data, sortedBy: []).count, 5)
    }
}
