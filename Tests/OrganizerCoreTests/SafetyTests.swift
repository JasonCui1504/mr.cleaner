import Foundation
import XCTest

/// Static checks over every Swift file in `Sources/`. These prove, by source
/// inspection, that the app contains no file-mutation, process-execution,
/// networking, persistence, or AI/ML code paths. Comment lines are ignored so
/// that documentation can name the APIs it forbids.
final class SafetyTests: XCTestCase {

    private struct SourceLine {
        let file: String
        let number: Int
        let text: String
    }

    private static let sourcesDirectory = Fixture.repositoryRoot.appendingPathComponent("Sources", isDirectory: true)

    private func sourceFiles() throws -> [URL] {
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: Self.sourcesDirectory, includingPropertiesForKeys: nil))
        let files = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        XCTAssertGreaterThan(files.count, 10, "Expected to find the app sources")
        return files
    }

    /// Code lines only: `//` comment lines and `/* … */` blocks removed.
    private func codeLines() throws -> [SourceLine] {
        var result: [SourceLine] = []
        for url in try sourceFiles() {
            let text = try String(contentsOf: url, encoding: .utf8)
            var inBlockComment = false
            for (index, rawLine) in text.components(separatedBy: "\n").enumerated() {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if inBlockComment {
                    if line.contains("*/") { inBlockComment = false }
                    continue
                }
                if line.hasPrefix("/*") {
                    inBlockComment = !line.contains("*/")
                    continue
                }
                if line.hasPrefix("//") { continue }
                result.append(SourceLine(file: url.lastPathComponent, number: index + 1, text: rawLine))
            }
        }
        return result
    }

    private func assertNoMatches(_ patterns: [String], _ reason: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let lines = try codeLines()
        for pattern in patterns {
            let regex = try NSRegularExpression(pattern: pattern)
            for sourceLine in lines {
                let range = NSRange(sourceLine.text.startIndex..., in: sourceLine.text)
                if regex.firstMatch(in: sourceLine.text, range: range) != nil {
                    XCTFail("\(reason): pattern `\(pattern)` found in \(sourceLine.file):\(sourceLine.number): \(sourceLine.text.trimmingCharacters(in: .whitespaces))",
                            file: file, line: line)
                }
            }
        }
    }

    // C-function patterns use (?<![.\w]) so that methods such as SwiftUI's
    // `.system(...)` font or `.read(...)` on other types do not match.
    func testNoFileMutationAPIs() throws {
        try assertNoMatches([
            #"createFile"#, #"moveItem"#, #"copyItem"#, #"removeItem"#, #"replaceItem"#, #"trashItem"#,
            #"createDirectory"#, #"createSymbolicLink"#, #"linkItem"#, #"setAttributes"#,
            #"setResourceValue"#, #"setResourceValues"#, #"setTagNames"#, #"setxattr"#, #"removexattr"#,
            #"\.write\("#, #"\.write\(to"#, #"write\(toFile"#, #"writeToFile"#, #"writeToURL"#,
            #"FileHandle\(forWriting"#, #"FileHandle\(forUpdating"#, #"forWritingTo"#, #"forWritingAtPath"#,
            #"FileWrapper"#, #"OutputStream"#, #"NSFileCoordinator"#,
            #"(?<![.\w])fopen\("#, #"(?<![.\w])open\("#, #"(?<![.\w])openat\("#, #"(?<![.\w])creat\("#, #"(?<![.\w])unlink\("#, #"(?<![.\w])rmdir\("#, #"(?<![.\w])mkdir\("#,
            #"(?<![.\w])rename\("#, #"(?<![.\w])renameat\("#, #"(?<![.\w])symlink\("#, #"(?<![.\w])link\("#, #"(?<![.\w])truncate\("#, #"(?<![.\w])ftruncate\("#,
            #"(?<![.\w])chmod\("#, #"(?<![.\w])fchmod\("#, #"(?<![.\w])chown\("#, #"(?<![.\w])lchown\("#, #"(?<![.\w])chflags\("#, #"(?<![.\w])utimes\("#,
            #"(?<![.\w])futimes\("#, #"(?<![.\w])utimensat\("#, #"(?<![.\w])setattrlist\("#, #"(?<![.\w])copyfile\("#, #"(?<![.\w])clonefile\("#,
        ], "File-mutation API in app sources")
    }

    func testNoFileContentReads() throws {
        // Version 1 never opens file contents (no hashing, no previews).
        try assertNoMatches([
            #"Data\(contentsOf"#, #"String\(contentsOf"#, #"contentsOfFile"#, #"FileHandle"#, #"InputStream"#,
            #"(?<![.\w])fread\("#, #"(?<![.\w])read\("#, #"(?<![.\w])mmap\("#, #"QLThumbnail"#, #"QuickLook"#, #"CGImageSource"#,
            #"NSImage\(contentsOf"#, #"PDFDocument"#, #"AVAsset"#, #"CryptoKit"#, #"CommonCrypto"#, #"\bSHA256\b"#, #"\bMD5\b"#,
        ], "File content read in app sources")
    }

    func testNoProcessExecutionOrOpening() throws {
        try assertNoMatches([
            #"\bProcess\("#, #"\bProcess\b\s*\.\s*run"#, #"NSTask"#, #"(?<![.\w])system\("#, #"(?<![.\w])popen\("#, #"posix_spawn"#,
            #"\bexecv"#, #"\bexecl"#, #"NSAppleScript"#, #"OSAScript"#, #"NSWorkspace"#, #"LSOpen"#,
            #"NSUserUnixTask"#, #"STPrivilegedTask"#, #"AuthorizationExecute"#,
        ], "Process execution or file opening in app sources")
    }

    func testNoNetworking() throws {
        try assertNoMatches([
            #"URLSession"#, #"NSURLConnection"#, #"URLRequest"#, #"NWConnection"#, #"NWListener"#, #"NWBrowser"#,
            #"import\s+Network\b"#, #"import\s+WebKit\b"#, #"WKWebView"#, #"CFStream"#, #"(?<![.\w])socket\("#, #"(?<![.\w])connect\("#,
            #"(?<![.\w])bind\("#, #"(?<![.\w])listen\("#, #"getaddrinfo"#, #"http://"#, #"https://"#, #"ftp://"#, #"\bAsyncImage\b"#,
            #"CloudKit"#, #"CKContainer"#, #"NSUbiquitousKeyValueStore"#, #"startDownloadingUbiquitousItem"#,
        ], "Networking in app sources")
    }

    func testNoPersistence() throws {
        try assertNoMatches([
            #"UserDefaults\.standard\.set"#, #"\.set\(.*forKey"#, #"@AppStorage"#, #"@SceneStorage"#,
            #"CoreData"#, #"NSPersistentContainer"#, #"SwiftData"#, #"sqlite3_"#, #"NSKeyedArchiver"#,
            #"bookmarkData"#, #"setFrameAutosaveName"#, #"frameAutosaveName"#, #"FileManager\.default\.temporaryDirectory"#,
            #"applicationSupportDirectory"#, #"cachesDirectory"#, #"documentDirectory"#, #"\bos_log\b"#, #"Logger\("#,
            #"NSLog\("#, #"\bprint\("#, #"FileLogger"#, #"noteNewRecentDocument"#,
        ], "Persistence or logging in app sources")
    }

    func testNoAIOrMLFrameworks() throws {
        try assertNoMatches([
            #"import\s+CoreML"#, #"import\s+CreateML"#, #"import\s+NaturalLanguage"#, #"import\s+Vision\b"#,
            #"import\s+Speech"#, #"import\s+SoundAnalysis"#, #"MLModel"#, #"NLEmbedding"#, #"NLModel"#, #"VNRecognizeText"#,
            #"(?i)ollama"#, #"(?i)openai"#, #"(?i)anthropic"#, #"(?i)\bllm\b"#, #"(?i)embedding"#, #"FoundationModels"#,
        ], "AI/ML dependency in app sources")
    }

    func testFileManagerUsageIsAllowListed() throws {
        let allowed: Set<String> = ["contentsOfDirectory", "destinationOfSymbolicLink", "default"]
        let regex = try NSRegularExpression(pattern: #"(?:FileManager\.default|fileManager)\.(\w+)"#)
        for sourceLine in try codeLines() {
            let text = sourceLine.text
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range(at: 1), in: text) else { continue }
                let method = String(text[range])
                XCTAssertTrue(allowed.contains(method), "Unexpected FileManager call `\(method)` in \(sourceLine.file):\(sourceLine.number)")
            }
        }
    }

    func testFilesystemAccessIsConfinedToScanner() throws {
        let filesystemPatterns = try NSRegularExpression(pattern: #"FileManager|lstat\(|resourceValues\(|\bstat\("#)
        for sourceLine in try codeLines() {
            let text = sourceLine.text
            if filesystemPatterns.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                XCTAssertEqual(sourceLine.file, "FolderScanner.swift", "Filesystem access outside FolderScanner.swift at \(sourceLine.file):\(sourceLine.number)")
            }
        }
    }

    func testPackageHasNoDependencies() throws {
        let manifest = try String(contentsOf: Fixture.repositoryRoot.appendingPathComponent("Package.swift"), encoding: .utf8)
        XCTAssertFalse(manifest.contains(".package("), "Package.swift must not declare external dependencies")
        XCTAssertFalse(manifest.contains("dependencies: [."), "No remote package dependencies")
    }

    func testOnlySwiftSourcesAreBundled() throws {
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: Self.sourcesDirectory, includingPropertiesForKeys: [.isDirectoryKey]))
        for case let url as URL in enumerator {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if !isDirectory {
                XCTAssertEqual(url.pathExtension, "swift", "Unexpected non-Swift file in Sources: \(url.lastPathComponent)")
            }
        }
    }

    func testNoForbiddenActionLabelsInUI() throws {
        // The UI must not offer actions that imply changing files.
        try assertNoMatches([
            #"Button\("(Apply|Move|Rename|Delete|Organize now|Trash|Clean)"#,
            #"Label\("(Apply|Move|Rename|Delete|Organize now|Trash|Clean)"#,
            #"(?i)safe to delete"#,
        ], "Mutation-implying UI label")
    }
}
