import Foundation

/// Pure string helpers for filenames: extension splitting, normalization,
/// tokenization and version/copy-marker detection. No filesystem access.
public enum NameAnalysis {

    private static let compoundExtensions = ["tar.gz", "tar.bz2", "tar.xz", "tar.zst"]

    /// Splits "Report Final.PDF" into ("Report Final", "pdf").
    ///
    /// - Dotfiles such as ".gitignore" have no extension.
    /// - An "extension" must be 1–10 ASCII letters/digits with at least one
    ///   letter, so "notes v2.5" or "budget 2023.2024" keep their full stem.
    public static func splitExtension(_ name: String) -> (stem: String, ext: String) {
        let lower = name.lowercased()
        for compound in compoundExtensions where lower.hasSuffix("." + compound) && lower.count > compound.count + 1 {
            return (String(name.dropLast(compound.count + 1)), compound)
        }
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else {
            return (name, "")
        }
        let ext = name[name.index(after: dot)...]
        let isValid = (1...10).contains(ext.count)
            && ext.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
            && ext.contains { $0.isLetter }
        guard isValid else { return (name, "") }
        return (String(name[..<dot]), ext.lowercased())
    }

    /// Case-, diacritic- and width-insensitive form ("Résumé" → "resume").
    public static func fold(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil).lowercased()
    }

    /// Splits on anything that is not a letter or digit, and on lower→upper
    /// camel-case boundaries. Letter/digit runs stay together ("w2", "hw3").
    public static func tokens(_ string: String) -> [String] {
        var result: [String] = []
        var current = ""
        var previous: Character?
        for character in string {
            if character.isLetter || character.isNumber {
                if let previous, previous.isLowercase, character.isUppercase, !current.isEmpty {
                    result.append(current)
                    current = ""
                }
                current.append(character)
            } else if !current.isEmpty {
                result.append(current)
                current = ""
            }
            previous = character
        }
        if !current.isEmpty { result.append(current) }
        return result.map(fold).filter { !$0.isEmpty }
    }

    /// Forms a token may match a keyword under: itself, and the token with a
    /// trailing number removed when at least two letters remain
    /// ("pset3" → "pset", "final2" → "final"; "w2" stays "w2").
    public static func matchForms(_ token: String) -> [String] {
        guard let first = token.first, first.isLetter, let last = token.last, last.isNumber else { return [token] }
        let stripped = String(token.reversed().drop(while: { $0.isNumber }).reversed())
        guard stripped.count >= 2, stripped.allSatisfy({ $0.isLetter }) else { return [token] }
        return [token, stripped]
    }

    public static func isNumeric(_ token: String) -> Bool {
        !token.isEmpty && token.allSatisfy { $0.isNumber }
    }

    // MARK: Version and copy markers

    private static let versionWords: Set<String> = [
        "final", "draft", "revised", "rev", "copy", "edited", "updated", "latest", "old", "new", "version",
    ]

    /// Words that, when followed by a number, take that number with them
    /// ("copy 2", "version 3").
    private static let numberedVersionWords: Set<String> = ["copy", "version", "draft", "rev", "final"]

    public static func isVersionMarker(_ token: String) -> Bool {
        if versionWords.contains(token) { return true }
        if matchForms(token).dropFirst().contains(where: { versionWords.contains($0) }) { return true }
        // v2, v10, V3 (already folded)
        if token.count >= 2, token.first == "v", token.dropFirst().allSatisfy({ $0.isNumber }) { return true }
        return false
    }

    /// True for names ending in "(1)", "(2)"… as created by browsers/Finder.
    public static func hasParenthesizedCounter(_ stem: String) -> Bool {
        stem.range(of: #"\(\d{1,3}\)\s*$"#, options: .regularExpression) != nil
    }

    /// Stem with version markers removed, plus the markers that were found.
    /// "Thesis_final_v3" → ("thesis", ["final", "v3"]).
    public static func versionBase(of stem: String) -> (base: String, markers: [String]) {
        var tokens = tokens(stem)
        var markers: [String] = []
        if hasParenthesizedCounter(stem), let last = tokens.last, isNumeric(last) {
            markers.append("(\(last))")
            tokens.removeLast()
        }
        var kept: [String] = []
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if isVersionMarker(token) {
                var marker = token
                if numberedVersionWords.contains(token), index + 1 < tokens.count, isNumeric(tokens[index + 1]) {
                    marker += " " + tokens[index + 1]
                    index += 1
                }
                markers.append(marker)
            } else {
                kept.append(token)
            }
            index += 1
        }
        return (kept.joined(separator: " "), markers)
    }

    /// Stem with trailing copy markers removed: "(1)", "copy", "copy 2".
    /// Used for the potential-duplicate key. Other version words are kept,
    /// because "report final" and "report" are not the same name.
    public static func duplicateBase(of stem: String) -> String {
        var tokens = tokens(stem)
        var changed = true
        var parenthesized = hasParenthesizedCounter(stem)
        while changed, !tokens.isEmpty {
            changed = false
            if parenthesized, let last = tokens.last, isNumeric(last) {
                tokens.removeLast()
                parenthesized = false
                changed = true
            } else if tokens.count >= 2, tokens[tokens.count - 2] == "copy", isNumeric(tokens[tokens.count - 1]) {
                tokens.removeLast(2)
                changed = true
            } else if tokens.last == "copy", tokens.count >= 2 {
                tokens.removeLast()
                changed = true
            }
        }
        return tokens.joined(separator: " ")
    }

    // MARK: Meaningful tokens (for grouping)

    public static let stopWords: Set<String> = [
        "the", "and", "for", "with", "from", "into", "of", "a", "an", "to", "in", "on", "at", "by",
        "file", "files", "document", "doc", "docs", "scan", "scanned", "untitled", "image", "img",
        "screenshot", "screen", "shot", "photo", "export", "download", "downloads", "page", "new",
    ]

    /// Lowercased tokens that carry meaning: no numbers, version markers,
    /// stop words, or very short tokens.
    public static func meaningfulTokens(_ stem: String) -> [String] {
        tokens(stem).filter { token in
            token.count >= 3 && !isNumeric(token) && !isVersionMarker(token) && !stopWords.contains(token)
                && !(token.first?.isNumber ?? false)
        }
    }

    // MARK: Camera / screenshot patterns

    /// IMG_1234, DSC01234, PXL_20230101_…, DJI_0001, GOPR0001, 20230101_123456.
    public static func looksLikeCameraName(_ stem: String) -> Bool {
        let folded = fold(stem)
        if folded.range(of: #"^(img|dsc|dscn|dscf|pxl|dji|gopr|mvimg|vid|_dsc)[_\- ]?\d{3,}"#, options: .regularExpression) != nil {
            return true
        }
        return folded.range(of: #"^\d{8}[_\- ]\d{6}"#, options: .regularExpression) != nil
    }

    public static func looksLikeScreenshot(_ stem: String) -> Bool {
        let tokens = tokens(stem)
        if tokens.contains("screenshot") || tokens.contains("cleanshot") { return true }
        return zip(tokens, tokens.dropFirst()).contains { $0 == "screen" && $1 == "shot" }
    }
}
