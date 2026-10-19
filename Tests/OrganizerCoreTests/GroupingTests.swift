import XCTest
@testable import OrganizerCore

final class GroupingTests: XCTestCase {

    private func run(_ records: [FileRecord]) -> GroupingEngine.Output {
        let classifier = RuleClassifier()
        return GroupingEngine().run(
            records: records, categories: records.map { classifier.classify($0)?.category }, rootName: "Root")
    }

    private func groups(_ output: GroupingEngine.Output, _ kind: GroupKind) -> [FileGroup] {
        output.groups.filter { $0.kind == kind }
    }

    func testSameStemDifferentExtensionsInSameFolder() {
        let output = run([
            makeRecord(0, "docs/report.docx"),
            makeRecord(1, "docs/report.pdf"),
            makeRecord(2, "other/report.pdf"),
        ])
        let stems = groups(output, .sameStem)
        XCTAssertEqual(stems.count, 1)
        XCTAssertEqual(Set(stems[0].memberIDs), [0, 1])
        XCTAssertTrue(stems[0].explanation.contains(".docx"))
    }

    func testPotentialDuplicatesByNameAndSize() {
        let output = run([
            makeRecord(0, "a/photo.jpg", size: 100),
            makeRecord(1, "b/photo.jpg", size: 100),
            makeRecord(2, "c/photo (1).jpg", size: 100),
            makeRecord(3, "d/photo.jpg", size: 200),
            makeRecord(4, "e/empty.txt", size: 0),
            makeRecord(5, "f/empty.txt", size: 0),
        ])
        let duplicates = groups(output, .potentialDuplicates)
        XCTAssertEqual(duplicates.count, 1, "zero-byte files are not reported as duplicates")
        XCTAssertEqual(Set(duplicates[0].memberIDs), [0, 1, 2])
        XCTAssertTrue(duplicates[0].explanation.contains("possible duplicates only"))
        XCTAssertFalse(duplicates[0].explanation.lowercased().contains("safe to delete"))
    }

    func testVersionCluster() {
        let output = run([
            makeRecord(0, "thesis.docx"),
            makeRecord(1, "thesis_final.docx"),
            makeRecord(2, "thesis_final_v2.docx"),
            makeRecord(3, "thesis_revised.pdf"),
            makeRecord(4, "chapter 1.docx"),
            makeRecord(5, "chapter 2.docx"),
        ])
        let versions = groups(output, .versionCluster)
        XCTAssertEqual(versions.count, 1)
        XCTAssertEqual(Set(versions[0].memberIDs), [0, 1, 2, 3])
        XCTAssertTrue(versions[0].explanation.contains("final"))
    }

    func testProjectDetectionKeepsOutermostProject() {
        let records = [
            makeRecord(0, "app", kind: .directory),
            makeRecord(1, "app/package.json"),
            makeRecord(2, "app/src", kind: .directory),
            makeRecord(3, "app/src/index.js"),
            makeRecord(4, "app/tools", kind: .directory),
            makeRecord(5, "app/tools/Cargo.toml"),
            makeRecord(6, "invoice.pdf"),
        ]
        let output = run(records)
        let projects = groups(output, .project)
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(output.projects.first?.relativePath, "app")
        XCTAssertEqual(Set(projects[0].memberIDs), [1, 2, 3, 4, 5])
        XCTAssertTrue(projects[0].explanation.contains("package.json"))
        XCTAssertTrue(projects[0].explanation.contains("nested"))
        XCTAssertEqual(output.projectByRecord[3], "app")
        XCTAssertNil(output.projectByRecord[6])
    }

    func testReadmePlusSourceFilesIsAProject() {
        let output = run([
            makeRecord(0, "tool", kind: .directory),
            makeRecord(1, "tool/README.md"),
            makeRecord(2, "tool/a.py"),
            makeRecord(3, "tool/b.py"),
            makeRecord(4, "notes", kind: .directory),
            makeRecord(5, "notes/README.md"),
        ])
        XCTAssertEqual(output.projects.map(\.relativePath), ["tool"])
    }

    func testGitFolderMarksProject() {
        let output = run([
            makeRecord(0, "repo", kind: .directory),
            makeRecord(1, "repo/.git", kind: .directory, hidden: true),
            makeRecord(2, "repo/notes.md"),
        ])
        XCTAssertEqual(output.projects.map(\.relativePath), ["repo"])
    }

    func testKeywordRelatedAcrossFolders() {
        let output = run([
            makeRecord(0, "2023/Acme Proposal.docx"),
            makeRecord(1, "Sent/acme-proposal.pdf"),
            makeRecord(2, "Sent/acme-invoice.pdf"),
        ])
        let related = groups(output, .keywordRelated)
        XCTAssertEqual(related.count, 1)
        XCTAssertEqual(Set(related[0].memberIDs), [0, 1])
    }

    func testSameDayClusterNeedsNameSignal() {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let output = run([
            makeRecord(0, "Trip/IMG_0001.jpg", modified: day),
            makeRecord(1, "Trip/IMG_0002.jpg", modified: day.addingTimeInterval(60)),
            makeRecord(2, "Trip/IMG_0003.jpg", modified: day.addingTimeInterval(120)),
            makeRecord(3, "Misc/apple.png", modified: day),
            makeRecord(4, "Misc/banana.png", modified: day),
            makeRecord(5, "Misc/cherry.png", modified: day),
        ])
        let clusters = groups(output, .sameDay)
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(Set(clusters[0].memberIDs), [0, 1, 2])
    }

    func testSharedPrefixRequiresThreeFiles() {
        let output = run([
            makeRecord(0, "Project Apollo budget.xlsx"),
            makeRecord(1, "Project Apollo timeline.pdf"),
            makeRecord(2, "Project Apollo team.docx"),
            makeRecord(3, "Project Gemini plan.pdf"),
        ])
        let prefixes = groups(output, .sharedPrefix)
        XCTAssertEqual(prefixes.count, 1)
        XCTAssertEqual(Set(prefixes[0].memberIDs), [0, 1, 2])
    }

    func testFolderTheme() {
        var records = (0..<5).map { makeRecord($0, "Pics/photo\($0).jpg") }
        records.append(makeRecord(5, "Mixed/a.jpg"))
        records.append(makeRecord(6, "Mixed/b.pdf"))
        let themes = groups(run(records), .folderTheme)
        XCTAssertEqual(themes.map(\.title), ["Pics"])
    }

    func testEveryGroupHasExplanationAndMembers() {
        let output = run([
            makeRecord(0, "a/report.docx"), makeRecord(1, "a/report.pdf"),
            makeRecord(2, "b/report.pdf", size: 100), makeRecord(3, "c/report.pdf", size: 100),
        ])
        XCTAssertFalse(output.groups.isEmpty)
        for group in output.groups {
            XCTAssertFalse(group.explanation.isEmpty)
            XCTAssertGreaterThanOrEqual(group.memberIDs.count, 2)
        }
    }
}

final class OrganizationPlanTests: XCTestCase {
    func testVirtualPathsProjectsAndCollisions() {
        let records = [
            makeRecord(0, "app", kind: .directory),
            makeRecord(1, "app/package.json"),
            makeRecord(2, "app/docs/invoice.pdf"),
            makeRecord(3, "Downloads/invoice.pdf"),
            makeRecord(4, "Old/invoice.pdf"),
            makeRecord(5, "experiment_results.csv"),
        ]
        let analysis = Analyzer.analyze(ScanResult(
            rootPath: "/fixture/Root", records: records, issues: [], wasCancelled: false,
            startedAt: Date(), finishedAt: Date()))
        let plan = OrganizationPlan.build(
            records: records, classifications: analysis.classifications,
            projects: analysis.projects, projectByRecord: analysis.projectByRecord)
        let items = Dictionary(uniqueKeysWithValues: plan.flatMap(\.items).map { ($0.id, $0) })

        XCTAssertNil(items[0], "folders are not planned")
        XCTAssertEqual(items[1]?.suggestedPath, "Software & Development/app/package.json")
        XCTAssertEqual(items[2]?.suggestedPath, "Software & Development/app/docs/invoice.pdf")
        XCTAssertEqual(items[3]?.suggestedPath, "Financial & Tax/invoice.pdf")
        XCTAssertEqual(items[3]?.currentRelativePath, "Downloads/invoice.pdf")
        XCTAssertEqual(items[3]?.hasNameCollision, true)
        XCTAssertEqual(items[4]?.hasNameCollision, true)
        XCTAssertEqual(items[5]?.suggestedPath, "Research & Scientific/experiment_results.csv")
        XCTAssertTrue(plan.allSatisfy { !$0.items.isEmpty })
    }

    func testOverridesChangeSuggestedFolder() {
        let records = [makeRecord(0, "invoice.pdf")]
        var classification = RuleClassifier().classify(records[0])
        classification = classification?.overridden(with: .work)
        let plan = OrganizationPlan.build(records: records, classifications: [classification], projects: [], projectByRecord: [:])
        XCTAssertEqual(plan.first?.items.first?.suggestedPath, "Work & Career/invoice.pdf")
    }
}
