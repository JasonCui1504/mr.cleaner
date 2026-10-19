import Foundation

public enum GroupKind: String, Sendable, Hashable, CaseIterable, Identifiable {
    case potentialDuplicates = "Potential duplicates"
    case versionCluster = "Version clusters"
    case sameStem = "Same name, different formats"
    case project = "Software projects"
    case sharedPrefix = "Shared filename prefix"
    case keywordRelated = "Related by keywords"
    case sameDay = "Same-day clusters"
    case folderTheme = "Folder themes"

    public var id: String { rawValue }
}

/// A recommendation that some files belong together. Nothing is moved.
public struct FileGroup: Identifiable, Sendable, Hashable {
    public let id: String
    public let kind: GroupKind
    public let title: String
    public let explanation: String
    public let memberIDs: [Int]
}

/// Detected software project: a folder containing project manifests.
public struct ProjectInfo: Sendable, Hashable {
    /// Relative path of the project folder ("" when the selected root itself is the project).
    public let relativePath: String
    public let name: String
    public let evidence: [String]
}

/// Rule-based grouping. Conservative by design: every group needs at least
/// two members and a stated reason, and most rules are limited to one folder.
public struct GroupingEngine: Sendable {

    public init() {}

    public struct Output: Sendable {
        public let groups: [FileGroup]
        public let projects: [ProjectInfo]
        /// Record id → relative path of the outermost project folder containing it.
        public let projectByRecord: [Int: String]
    }

    static let strongManifests: Set<String> = [
        "package.json", "pyproject.toml", "cargo.toml", "package.swift", "go.mod", "setup.py", "pom.xml",
        "build.gradle", "build.gradle.kts", "gemfile", "composer.json", "cmakelists.txt", "requirements.txt", ".git",
    ]
    static let weakManifests: Set<String> = ["makefile", "dockerfile", "readme", "readme.md", "readme.txt", "readme.rst", "license"]

    /// - Parameters:
    ///   - categories: rule category per record id (`nil` for folders).
    ///   - rootName: display name for a project at the selected root.
    public func run(records: [FileRecord], categories: [FileCategory?], rootName: String) -> Output {
        let projectsOutput = detectProjects(records: records, rootName: rootName)
        var groups: [FileGroup] = []
        groups += projectsOutput.groups
        let files = records.filter { $0.kind.isFileLike }
        groups += duplicateGroups(files)
        groups += sameStemGroups(files)
        let versions = versionGroups(files)
        groups += versions
        groups += prefixGroups(files, excluding: Set(versions.map { Set($0.memberIDs) }))
        groups += keywordGroups(files)
        groups += sameDayGroups(files, categories: categories)
        groups += folderThemeGroups(files, categories: categories)
        return Output(groups: groups, projects: projectsOutput.projects, projectByRecord: projectsOutput.byRecord)
    }

    // MARK: Projects

    private func detectProjects(records: [FileRecord], rootName: String)
        -> (groups: [FileGroup], projects: [ProjectInfo], byRecord: [Int: String]) {
        var childrenByFolder: [String: [FileRecord]] = [:]
        for record in records { childrenByFolder[record.parentRelativePath, default: []].append(record) }

        var candidates: [String: [String]] = [:]
        for (folder, children) in childrenByFolder {
            let names = children.map { NameAnalysis.fold($0.name) }
            var evidence = names.filter { Self.strongManifests.contains($0) }
            evidence += children.filter { ["xcodeproj", "xcworkspace", "sln"].contains($0.fileExtension) }.map(\.name)
            if evidence.isEmpty {
                let weak = names.filter { Self.weakManifests.contains($0) }
                let codeFiles = children.filter { $0.kind == .file && CategoryRules.softwareExtensions.contains($0.fileExtension) }
                if !weak.isEmpty && codeFiles.count >= 2 {
                    evidence = weak + ["\(codeFiles.count) source files"]
                }
            }
            if !evidence.isEmpty { candidates[folder] = evidence }
        }

        // Keep outermost projects only; nested ones are reported in the explanation.
        func ancestors(of path: String) -> [String] {
            guard !path.isEmpty else { return [] }
            var result = [""]
            var current = ""
            for component in path.split(separator: "/").dropLast() {
                current = current.isEmpty ? String(component) : current + "/" + component
                result.append(current)
            }
            return result
        }
        let roots = candidates.keys.filter { folder in !ancestors(of: folder).contains { candidates[$0] != nil } }
        let rootSet = Set(roots)

        var byRecord: [Int: String] = [:]
        var members: [String: [Int]] = [:]
        for record in records {
            // The project folder itself is the record whose relativePath is the root.
            let chain = ancestors(of: record.relativePath) + [record.relativePath]
            if let projectRoot = chain.first(where: { rootSet.contains($0) }), projectRoot != record.relativePath {
                byRecord[record.id] = projectRoot
                members[projectRoot, default: []].append(record.id)
            }
        }

        var groups: [FileGroup] = []
        var projects: [ProjectInfo] = []
        for root in roots.sorted() {
            let name = root.isEmpty ? rootName : String(root.split(separator: "/").last ?? "")
            let evidence = candidates[root] ?? []
            let nested = candidates.keys.filter { $0 != root && (root.isEmpty || $0.hasPrefix(root + "/")) }.count
            projects.append(ProjectInfo(relativePath: root, name: name, evidence: evidence))
            var explanation = "Folder “\(root.isEmpty ? "(selected folder)" : root)” contains project files: \(evidence.joined(separator: ", ")). Files inside a project usually belong together and should stay in their current structure."
            if nested > 0 { explanation += " It also contains \(nested) nested project folder(s)." }
            groups.append(FileGroup(id: "project:\(root)", kind: .project, title: "Project: \(name)",
                                    explanation: explanation, memberIDs: members[root] ?? []))
        }
        return (groups, projects, byRecord)
    }

    // MARK: Potential duplicates (name + size)

    private func duplicateGroups(_ files: [FileRecord]) -> [FileGroup] {
        var buckets: [String: [FileRecord]] = [:]
        for file in files {
            guard let size = file.size, size > 0 else { continue }
            let base = NameAnalysis.duplicateBase(of: file.stem)
            guard !base.isEmpty else { continue }
            buckets["\(base).\(file.fileExtension)|\(size)", default: []].append(file)
        }
        return buckets.filter { $0.value.count >= 2 }.sorted { $0.key < $1.key }.map { entry -> FileGroup in
            let (key, members) = (entry.key, entry.value)
            let size = members[0].size ?? 0
            let sameExactName = Set(members.map { NameAnalysis.fold($0.name) }).count == 1
            let reason = sameExactName
                ? "Same filename and identical size (\(Formatting.size(size)), \(size) bytes) in different folders."
                : "Same filename after ignoring copy markers such as “(1)” or “copy”, and identical size (\(Formatting.size(size)), \(size) bytes)."
            return FileGroup(
                id: "dup:\(key)", kind: .potentialDuplicates, title: members[0].name,
                explanation: reason + " Contents were not compared, so these are possible duplicates only.",
                memberIDs: members.map(\.id))
        }
    }

    // MARK: Same stem, different extensions (same folder)

    private func sameStemGroups(_ files: [FileRecord]) -> [FileGroup] {
        var buckets: [String: [FileRecord]] = [:]
        for file in files where !file.fileExtension.isEmpty {
            buckets[file.parentRelativePath + "\u{0}" + NameAnalysis.fold(file.stem), default: []].append(file)
        }
        return buckets.compactMap { entry -> FileGroup? in
            let (key, members) = (entry.key, entry.value)
            let extensions = Set(members.map(\.fileExtension))
            guard members.count >= 2, extensions.count >= 2 else { return nil }
            return FileGroup(
                id: "stem:\(key)", kind: .sameStem, title: members[0].stem,
                explanation: "Same name “\(members[0].stem)” in the same folder with different formats (\(extensions.sorted().map { "." + $0 }.joined(separator: ", "))), e.g. a document and its exported PDF.",
                memberIDs: members.map(\.id))
        }.sorted { $0.id < $1.id }
    }

    // MARK: Version clusters (same folder)

    private func versionGroups(_ files: [FileRecord]) -> [FileGroup] {
        var buckets: [String: [(FileRecord, [String])]] = [:]
        for file in files {
            let (base, markers) = NameAnalysis.versionBase(of: file.stem)
            guard !base.isEmpty else { continue }
            buckets[file.parentRelativePath + "\u{0}" + base, default: []].append((file, markers))
        }
        return buckets.compactMap { entry -> FileGroup? in
            let (key, entries) = (entry.key, entry.value)
            guard entries.count >= 2, entries.contains(where: { !$0.1.isEmpty }) else { return nil }
            // Skip sets that differ only by extension; those are same-stem groups.
            guard Set(entries.map { NameAnalysis.fold($0.0.stem) }).count >= 2 else { return nil }
            let markers = Array(Set(entries.flatMap(\.1))).sorted()
            let base = String(key.split(separator: "\u{0}", omittingEmptySubsequences: false).last ?? "")
            return FileGroup(
                id: "ver:\(key)", kind: .versionCluster, title: base,
                explanation: "Names share the base “\(base)” and differ by version markers (\(markers.map { "“\($0)”" }.joined(separator: ", "))). These look like drafts or versions of one document.",
                memberIDs: entries.map(\.0.id))
        }.sorted { $0.id < $1.id }
    }

    // MARK: Shared prefix (same folder, ≥3 files)

    private func prefixGroups(_ files: [FileRecord], excluding: Set<Set<Int>>) -> [FileGroup] {
        var buckets: [String: [FileRecord]] = [:]
        for file in files {
            let tokens = NameAnalysis.tokens(file.stem)
            guard tokens.count >= 3 else { continue }
            let prefix = Array(tokens.prefix(2))
            guard prefix.allSatisfy({ !NameAnalysis.isNumeric($0) && !NameAnalysis.isVersionMarker($0) && !NameAnalysis.stopWords.contains($0) }),
                  prefix.joined().count >= 6 else { continue }
            buckets[file.parentRelativePath + "\u{0}" + prefix.joined(separator: " "), default: []].append(file)
        }
        return buckets.compactMap { entry -> FileGroup? in
            let (key, members) = (entry.key, entry.value)
            guard members.count >= 3, !excluding.contains(Set(members.map(\.id))) else { return nil }
            let prefix = String(key.split(separator: "\u{0}", omittingEmptySubsequences: false).last ?? "")
            return FileGroup(
                id: "prefix:\(key)", kind: .sharedPrefix, title: "“\(prefix) …”",
                explanation: "\(members.count) files in the same folder start with “\(prefix)”.",
                memberIDs: members.map(\.id))
        }.sorted { $0.id < $1.id }
    }

    // MARK: Related by keywords (across folders)

    private func keywordGroups(_ files: [FileRecord]) -> [FileGroup] {
        var buckets: [String: [FileRecord]] = [:]
        for file in files {
            let keywords = Array(Set(NameAnalysis.meaningfulTokens(file.stem))).sorted()
            guard keywords.count >= 2 else { continue }
            buckets[keywords.joined(separator: " "), default: []].append(file)
        }
        return buckets.compactMap { entry -> FileGroup? in
            let (key, members) = (entry.key, entry.value)
            guard members.count >= 2, Set(members.map(\.parentRelativePath)).count >= 2 else { return nil }
            return FileGroup(
                id: "kw:\(key)", kind: .keywordRelated, title: key,
                explanation: "Files in different folders whose names contain the same keywords: \(key.split(separator: " ").map { "“\($0)”" }.joined(separator: ", ")).",
                memberIDs: members.map(\.id))
        }.sorted { $0.id < $1.id }
    }

    // MARK: Same-day clusters (same folder, same category, supporting name signal)

    private func sameDayGroups(_ files: [FileRecord], categories: [FileCategory?]) -> [FileGroup] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var buckets: [String: [FileRecord]] = [:]
        for file in files {
            guard let modified = file.modified, file.id < categories.count, let category = categories[file.id],
                  category != .uncategorized else { continue }
            let day = calendar.dateComponents([.year, .month, .day], from: modified)
            let dayKey = String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
            buckets[file.parentRelativePath + "\u{0}" + dayKey + "\u{0}" + category.rawValue, default: []].append(file)
        }
        return buckets.compactMap { entry -> FileGroup? in
            let (key, members) = (entry.key, entry.value)
            guard members.count >= 3 else { return nil }
            let parts = key.split(separator: "\u{0}", omittingEmptySubsequences: false)
            let day = parts.count > 1 ? String(parts[1]) : ""
            let category = parts.count > 2 ? String(parts[2]) : ""
            let allCamera = members.allSatisfy { NameAnalysis.looksLikeCameraName($0.stem) || NameAnalysis.looksLikeScreenshot($0.stem) }
            var shared = Set(NameAnalysis.meaningfulTokens(members[0].stem))
            for member in members.dropFirst() {
                shared.formIntersection(NameAnalysis.meaningfulTokens(member.stem))
            }
            let signal: String
            if allCamera {
                signal = "all names follow camera or screenshot naming patterns"
            } else if !shared.isEmpty {
                signal = "all names contain \(shared.sorted().map { "“\($0)”" }.joined(separator: ", "))"
            } else {
                return nil
            }
            return FileGroup(
                id: "day:\(key)", kind: .sameDay, title: "\(day) · \(category)",
                explanation: "\(members.count) \(category) files in the same folder were modified on \(day), and \(signal).",
                memberIDs: members.map(\.id))
        }.sorted { $0.id < $1.id }
    }

    // MARK: Folder themes (≥5 files, ≥80% one category)

    private func folderThemeGroups(_ files: [FileRecord], categories: [FileCategory?]) -> [FileGroup] {
        var byFolder: [String: [FileRecord]] = [:]
        for file in files { byFolder[file.parentRelativePath, default: []].append(file) }
        return byFolder.compactMap { entry -> FileGroup? in
            let (folder, members) = (entry.key, entry.value)
            guard members.count >= 5 else { return nil }
            var counts: [FileCategory: Int] = [:]
            for member in members where member.id < categories.count {
                if let category = categories[member.id] { counts[category, default: 0] += 1 }
            }
            guard let best = counts.max(by: { $0.value < $1.value }), best.key != .uncategorized,
                  Double(best.value) / Double(members.count) >= 0.8 else { return nil }
            let (top, count) = (best.key, best.value)
            let percent = Int((Double(count) / Double(members.count) * 100).rounded())
            return FileGroup(
                id: "folder:\(folder)", kind: .folderTheme, title: folder.isEmpty ? "(selected folder)" : folder,
                explanation: "\(percent)% of the \(members.count) files directly in this folder are \(top.displayName). The folder already looks like a coherent collection.",
                memberIDs: members.map(\.id))
        }.sorted { $0.id < $1.id }
    }
}
