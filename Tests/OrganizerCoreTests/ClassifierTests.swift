import XCTest
@testable import OrganizerCore

final class ClassifierTests: XCTestCase {
    private let classifier = RuleClassifier()

    private func classify(_ name: String, kind: FileKind = .file) -> Classification {
        classifier.classify(name: name, kind: kind)
    }

    private func assertCategory(
        _ name: String, _ category: FileCategory, _ confidence: Confidence? = nil,
        secondary: FileCategory? = nil, file: StaticString = #filePath, line: UInt = #line
    ) {
        let result = classify(name)
        XCTAssertEqual(result.category, category, "\(name): \(result.explanation)", file: file, line: line)
        if let confidence {
            XCTAssertEqual(result.confidence, confidence, "\(name): \(result.explanation)", file: file, line: line)
        }
        if let secondary {
            XCTAssertTrue(result.secondary.contains(secondary), "\(name) secondary \(result.secondary)", file: file, line: line)
        }
        XCTAssertFalse(result.explanation.isEmpty, file: file, line: line)
        XCTAssertFalse(result.ruleIDs.isEmpty, file: file, line: line)
    }

    func testFinancial() {
        assertCategory("invoice.pdf", .financial, .high)
        assertCategory("2023 W-2.pdf", .financial, .high)
        assertCategory("w2_2022.PDF", .financial, .high)
        assertCategory("Chase Bank Statement March.pdf", .financial, .high)
        assertCategory("receipt.jpg", .financial, .high, secondary: .images)
        assertCategory("budget 2024.xlsx", .financial, .high, secondary: .spreadsheets)
    }

    func testAmbiguousFinancialWordIsMediumConfidence() {
        assertCategory("statement.pdf", .financial, .medium)
        assertCategory("payment.pdf", .financial, .medium)
    }

    func testTravelAcademicResearchWork() {
        assertCategory("boarding pass SFO-JFK.pdf", .travel, .high)
        assertCategory("Hotel Reservation.eml", .travel, .high)
        assertCategory("Lecture 3 slides.pdf", .academic, .high, secondary: .presentations)
        assertCategory("pset3_solutions.pdf", .academic, .high)
        assertCategory("hw2.py", .academic, .high, secondary: .software)
        assertCategory("thesis_final_v3.docx", .research, .high, secondary: .notes)
        assertCategory("western-blot-quant.xlsx", .research, .high)
        assertCategory("Résumé Jane Doe.pdf", .work, .high)
        assertCategory("Cover Letter - Acme.docx", .work, .high)
    }

    func testCVIsConservative() {
        assertCategory("cv.pdf", .work, .medium)
        // In code "cv" usually means computer vision; the type wins.
        assertCategory("cv_utils.py", .software, .high)
        XCTAssertFalse(classify("cv_utils.py").secondary.contains(.work))
    }

    func testFinalAloneIsNotAcademic() {
        let result = classify("final report.docx")
        XCTAssertNotEqual(result.category, .academic)
        assertCategory("Final Exam Review.pdf", .academic, .high)
    }

    func testTypeCategories() {
        assertCategory("deck.pptx", .presentations, .high)
        assertCategory("quarterly.pptx", .presentations, .medium)
        assertCategory("talk.pdf", .presentations, .medium)
        assertCategory("results.csv", .spreadsheets, .high)
        assertCategory("export.json", .spreadsheets, .high)
        assertCategory("table1.parquet", .spreadsheets, .high)
        assertCategory("main.swift", .software, .high)
        assertCategory("package.json", .software, .high)
        assertCategory("Dockerfile", .software, .high)
        assertCategory("README.md", .software, .medium)
        assertCategory("LICENSE", .software, .medium)
        assertCategory("config.yaml", .software, .high)
        assertCategory("archive.tar.gz", .archives, .high)
        assertCategory("Installer.dmg", .archives, .high)
        assertCategory("song.flac", .media, .high)
        assertCategory("clip.MOV", .media, .high)
        assertCategory("poster.psd", .design, .high)
        assertCategory("logo.ai", .design, .medium)
        assertCategory("novel.epub", .ebooks, .high)
        assertCategory("User Manual.pdf", .ebooks, .medium)
        assertCategory("reads.fastq", .research, .high)
        assertCategory("embeddings.npy", .research, .high)
        assertCategory("meeting notes.txt", .notes, .high)
        assertCategory("random.txt", .notes, .medium)
    }

    func testImageTags() {
        let photo = classify("IMG_1234.HEIC")
        XCTAssertEqual(photo.category, .images)
        XCTAssertTrue(photo.tags.contains("Photography"))
        let screenshot = classify("Screenshot 2024-05-01 at 10.15.00.png")
        XCTAssertEqual(screenshot.category, .images)
        XCTAssertTrue(screenshot.tags.contains("Screenshot"))
        let raw = classify("DSC_0042.NEF")
        XCTAssertTrue(raw.tags.contains("Camera RAW"))
        XCTAssertTrue(raw.tags.contains("Photography"))
    }

    func testTypeTakesPrecedenceWhenTopicTypeIsAtypical() {
        assertCategory("lecture.mp4", .media, .high, secondary: .academic)
        assertCategory("invoice.zip", .archives, .high, secondary: .financial)
        let result = classify("lecture.mp4")
        XCTAssertTrue(result.explanation.contains("type takes precedence"))
    }

    func testWholeWordMatchingAvoidsAccidentalMatches() {
        // "wallpaper" must not match "paper"; "taxonomy" must not match "tax".
        assertCategory("wallpaper.png", .images, .high)
        XCTAssertTrue(classify("wallpaper.png").secondary.isEmpty)
        assertCategory("taxonomy.txt", .notes, .medium)
        // camelCase is split: "BankStatement" → bank + statement
        assertCategory("BankStatement.pdf", .financial, .high)
    }

    func testConflictingTopicsLowerConfidenceAndFlagReview() {
        let result = classify("hotel invoice.pdf")
        XCTAssertEqual(result.category, .financial)   // tie → earlier priority
        XCTAssertEqual(result.confidence, .medium)
        XCTAssertTrue(result.secondary.contains(.travel))
        XCTAssertTrue(result.needsReview)
        XCTAssertTrue(result.ruleIDs.contains("TOPIC.CONFLICT"))
    }

    func testUncategorizedHasReason() {
        let unknown = classify("mystery.xyz")
        XCTAssertEqual(unknown.category, .uncategorized)
        XCTAssertEqual(unknown.confidence, .low)
        XCTAssertTrue(unknown.needsReview)
        XCTAssertTrue(unknown.explanation.contains(".xyz"))

        let pdf = classify("scan0001.pdf")
        XCTAssertEqual(pdf.category, .uncategorized)
        XCTAssertTrue(pdf.explanation.contains("Contents were not inspected"))

        let noExtension = classify("something")
        XCTAssertEqual(noExtension.category, .uncategorized)
    }

    func testSpecialEntries() {
        let dsStore = classify(".DS_Store")
        XCTAssertEqual(dsStore.category, .uncategorized)
        XCTAssertTrue(dsStore.tags.contains("System file"))
        XCTAssertFalse(dsStore.needsReview)

        let partial = classify("movie.mp4.crdownload")
        XCTAssertTrue(partial.tags.contains("Incomplete download"))
        XCTAssertTrue(partial.needsReview)

        let link = classify("shortcut", kind: .symbolicLink)
        XCTAssertEqual(link.category, .uncategorized)
        XCTAssertTrue(link.needsReview)
        XCTAssertTrue(link.explanation.contains("not followed"))
    }

    func testFoldersAreNotClassified() {
        let folder = makeRecord(0, "Taxes", kind: .directory)
        XCTAssertNil(classifier.classify(folder))
    }

    func testOverrideKeepsRuleExplanation() {
        let base = classify("invoice.pdf")
        let edited = base.overridden(with: .work)
        XCTAssertEqual(edited.category, .work)
        XCTAssertTrue(edited.isOverridden)
        XCTAssertTrue(edited.explanation.contains("Financial & Tax"))
        XCTAssertEqual(base.overridden(with: .financial), base)
    }

    func testDeterminism() {
        let names = ["invoice.pdf", "hotel invoice.pdf", "IMG_0001.jpg", "mystery.bin", "thesis draft.docx"]
        for name in names {
            XCTAssertEqual(classify(name), classify(name))
        }
    }
}

final class NameAnalysisTests: XCTestCase {
    func testSplitExtension() {
        XCTAssertEqual(NameAnalysis.splitExtension("Report.PDF").ext, "pdf")
        XCTAssertEqual(NameAnalysis.splitExtension("Report.PDF").stem, "Report")
        XCTAssertEqual(NameAnalysis.splitExtension(".gitignore").ext, "")
        XCTAssertEqual(NameAnalysis.splitExtension("backup.tar.gz").ext, "tar.gz")
        XCTAssertEqual(NameAnalysis.splitExtension("backup.tar.gz").stem, "backup")
        XCTAssertEqual(NameAnalysis.splitExtension("notes v2.5").ext, "")
        XCTAssertEqual(NameAnalysis.splitExtension("README").ext, "")
        XCTAssertEqual(NameAnalysis.splitExtension("trailing.").ext, "")
        XCTAssertEqual(NameAnalysis.splitExtension("Résumé.docx").stem, "Résumé")
    }

    func testTokens() {
        XCTAssertEqual(NameAnalysis.tokens("BankStatement_2024-03"), ["bank", "statement", "2024", "03"])
        XCTAssertEqual(NameAnalysis.tokens("Résumé (final) 🎉"), ["resume", "final"])
        XCTAssertEqual(NameAnalysis.tokens("w-2"), ["w", "2"])
        XCTAssertEqual(NameAnalysis.matchForms("pset3"), ["pset3", "pset"])
        XCTAssertEqual(NameAnalysis.matchForms("w2"), ["w2"])
    }

    func testVersionBase() {
        XCTAssertEqual(NameAnalysis.versionBase(of: "Thesis_final_v3").base, "thesis")
        XCTAssertEqual(NameAnalysis.versionBase(of: "Thesis_final_v3").markers, ["final", "v3"])
        XCTAssertEqual(NameAnalysis.versionBase(of: "report (2)").base, "report")
        XCTAssertEqual(NameAnalysis.versionBase(of: "report copy 2").base, "report")
        XCTAssertEqual(NameAnalysis.versionBase(of: "chapter 2").base, "chapter 2")
        XCTAssertTrue(NameAnalysis.versionBase(of: "chapter 2").markers.isEmpty)
    }

    func testDuplicateBase() {
        XCTAssertEqual(NameAnalysis.duplicateBase(of: "photo (1)"), "photo")
        XCTAssertEqual(NameAnalysis.duplicateBase(of: "photo copy"), "photo")
        XCTAssertEqual(NameAnalysis.duplicateBase(of: "photo copy 3"), "photo")
        XCTAssertEqual(NameAnalysis.duplicateBase(of: "photo final"), "photo final")
    }

    func testCameraAndScreenshotPatterns() {
        XCTAssertTrue(NameAnalysis.looksLikeCameraName("IMG_1234"))
        XCTAssertTrue(NameAnalysis.looksLikeCameraName("PXL_20240101_123456789"))
        XCTAssertTrue(NameAnalysis.looksLikeCameraName("20240101_123456"))
        XCTAssertFalse(NameAnalysis.looksLikeCameraName("image of cat"))
        XCTAssertTrue(NameAnalysis.looksLikeScreenshot("Screen Shot 2020-01-01 at 1.00.00 PM"))
    }
}
