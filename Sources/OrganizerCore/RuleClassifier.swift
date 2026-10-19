import Foundation

/// Deterministic, explainable classifier. Uses only the filename, extension
/// and entry kind — never file contents. See docs/CATEGORY_RULES.md.
///
/// Decision order:
/// 1. Special entries: symbolic links, system metadata files, incomplete downloads.
/// 2. Topic rules (Financial, Travel, Academic, Research, Work) are scored from
///    filename keywords: strong keyword = 2, weak keyword = 1, +1 if the
///    extension is typical for the topic. Highest score wins; ties go to the
///    earlier topic.
/// 3. A type category is derived from the extension (or exact project filename).
/// 4. The topic becomes primary when the extension is typical for it, or when
///    the type category is a generic one (notes/PDF-keyword based) or absent.
///    Otherwise the type category is primary and the topic is a secondary tag
///    (e.g. "lecture.mp4" is Video & Audio, tagged Academic).
/// 5. Nothing matched → Uncategorized / Review with the reason.
public struct RuleClassifier: Sendable {

    public init() {}

    /// Classification for a scanned record; `nil` for folders.
    public func classify(_ record: FileRecord) -> Classification? {
        if record.kind == .directory { return nil }
        var result = classify(name: record.name, kind: record.kind)
        switch record.access {
        case .readable:
            break
        case .notReadable:
            result.reviewReasons.append("File is not readable with your permissions (metadata only).")
        case .cloudPlaceholder:
            result.tags.append("Cloud placeholder")
            result.reviewReasons.append("Stored in the cloud only; not downloaded and not inspected.")
        case .error(let message):
            result.reviewReasons.append("Metadata could not be fully read: \(message)")
        }
        if record.isHidden { result.tags.append("Hidden") }
        return result
    }

    public func classify(name: String, kind: FileKind) -> Classification {
        let (stem, ext) = NameAnalysis.splitExtension(name)
        let foldedName = NameAnalysis.fold(name)
        let tokens = NameAnalysis.tokens(stem)
        let forms = tokens.map(NameAnalysis.matchForms)

        // 1. Special entries
        if kind == .symbolicLink {
            return Classification(
                category: .uncategorized, tags: ["Symbolic link"], confidence: .low,
                explanation: "Symbolic link. Its target is not followed or scanned, so what it points to is unknown.",
                reviewReasons: ["Symbolic link — target not inspected."], ruleIDs: ["SPECIAL.SYMLINK"])
        }
        if kind == .other {
            return Classification(
                category: .uncategorized, tags: ["Special file"], confidence: .low,
                explanation: "Not a regular file, folder, package or link (for example a socket or device).",
                reviewReasons: ["Special filesystem entry."], ruleIDs: ["SPECIAL.OTHER"])
        }
        if CategoryRules.systemMetadataNames.contains(foldedName) {
            return Classification(
                category: .uncategorized, tags: ["System file"], confidence: .high,
                explanation: "“\(name)” is a metadata file created automatically by the operating system.",
                ruleIDs: ["SPECIAL.SYSTEM"])
        }
        if CategoryRules.incompleteDownloadExtensions.contains(ext) {
            return Classification(
                category: .uncategorized, tags: ["Incomplete download"], confidence: .medium,
                explanation: "Extension .\(ext) is used by browsers for downloads that have not finished.",
                reviewReasons: ["Possibly an incomplete download."], ruleIDs: ["SPECIAL.PARTIAL"])
        }

        // 2. Topic scoring
        let hits = CategoryRules.topics
            .compactMap { evaluate($0, forms: forms, ext: ext) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.rule.priority < $1.rule.priority }

        // 3. Type category
        let typeMatch = typeCategory(foldedName: foldedName, stem: stem, ext: ext, forms: forms)

        var tags = typeMatch?.tags ?? []
        var ruleIDs: [String] = []
        var reasons: [String] = []
        var reviewReasons: [String] = []
        var secondary: [FileCategory] = []
        let category: FileCategory
        var confidence: Confidence

        if let best = hits.first,
           typeMatch == nil || best.isRelevant || typeMatch!.yieldsToTopics || typeMatch!.category == best.rule.category {
            // 4a. Topic is primary.
            category = best.rule.category
            confidence = best.baseConfidence
            ruleIDs.append("TOPIC.\(best.rule.id)")
            reasons.append(best.description(ext: ext))
            if let typeMatch {
                if typeMatch.category == category {
                    confidence = max(confidence, typeMatch.confidence)
                    reasons.append(typeMatch.reason)
                } else {
                    secondary.append(typeMatch.category)
                    reasons.append("Also matches \(typeMatch.category.displayName) by type (kept as a secondary tag).")
                }
                ruleIDs.append(typeMatch.ruleID)
            }
            if best.strong.isEmpty && !best.isRelevant {
                reviewReasons.append("Only an ambiguous keyword matched (\(best.weak.joined(separator: ", "))).")
            }
            for other in hits.dropFirst() where other.rule.category != category && !secondary.contains(other.rule.category) {
                secondary.append(other.rule.category)
            }
            if let runnerUp = hits.dropFirst().first {
                let conflict = (!runnerUp.strong.isEmpty && !best.strong.isEmpty) || runnerUp.score == best.score
                if conflict {
                    confidence = confidence.lowered
                    ruleIDs.append("TOPIC.CONFLICT")
                    reasons.append("Keywords for \(runnerUp.rule.category.displayName) also matched (\(runnerUp.matchedText)); \(category.displayName) was chosen by score/priority.")
                    reviewReasons.append("Matches more than one topic: \(category.displayName) and \(runnerUp.rule.category.displayName).")
                }
            }
        } else if let typeMatch {
            // 4b. Type is primary; topics become secondary tags.
            category = typeMatch.category
            confidence = typeMatch.confidence
            ruleIDs.append(typeMatch.ruleID)
            reasons.append(typeMatch.reason)
            for hit in hits where hit.rule.category != category && !secondary.contains(hit.rule.category) {
                secondary.append(hit.rule.category)
                ruleIDs.append("TOPIC.\(hit.rule.id).SECONDARY")
            }
            if !hits.isEmpty {
                let names = hits.map { "\($0.rule.category.displayName) (\($0.matchedText))" }.joined(separator: "; ")
                reasons.append("Filename also suggests \(names), but .\(ext) is not a typical type for that topic, so the type takes precedence.")
            }
        } else {
            // 5. Nothing matched.
            category = .uncategorized
            confidence = .low
            ruleIDs.append("NONE")
            if ext.isEmpty {
                reasons.append("No extension and no recognizable keywords in the name.")
            } else if ext == "pdf" {
                reasons.append("PDF with no recognizable topic keywords in its name. Contents were not inspected.")
            } else if CategoryRules.emailExtensions.contains(ext) {
                tags.append("Email export")
                reasons.append("Email export (.\(ext)) with no recognizable topic keywords in its name.")
            } else {
                reasons.append("Extension .\(ext) is not in the rule tables and the name has no recognizable keywords.")
            }
            reviewReasons.append("Could not be categorized confidently.")
        }

        if confidence == .low && reviewReasons.isEmpty {
            reviewReasons.append("Low-confidence match.")
        }

        return Classification(
            category: category, secondary: secondary, tags: tags, confidence: confidence,
            explanation: reasons.joined(separator: " "), reviewReasons: reviewReasons, ruleIDs: ruleIDs)
    }

    // MARK: Topic evaluation

    private struct TopicHit {
        let rule: TopicRule
        let strong: [String]
        let weak: [String]
        let isRelevant: Bool

        var score: Int { strong.count * 2 + weak.count + (isRelevant ? 1 : 0) }

        var baseConfidence: Confidence {
            if !strong.isEmpty { return isRelevant ? .high : .medium }
            return isRelevant ? .medium : .low
        }

        var matchedText: String { (strong + weak).map { "“\($0)”" }.joined(separator: ", ") }

        func description(ext: String) -> String {
            var parts: [String] = []
            if !strong.isEmpty {
                parts.append("Filename contains \(strong.map { "“\($0)”" }.joined(separator: ", ")) (strong \(rule.category.displayName) signal)")
            }
            if !weak.isEmpty {
                parts.append("\(strong.isEmpty ? "Filename contains" : "and") \(weak.map { "“\($0)”" }.joined(separator: ", ")) (ambiguous on its own)")
            }
            var sentence = parts.joined(separator: " ")
            if isRelevant {
                sentence += ", and .\(ext) is a typical type for this category."
            } else {
                sentence += ext.isEmpty ? "; the file has no extension." : "; .\(ext) is not a typical type for this category."
            }
            return sentence
        }
    }

    private func evaluate(_ rule: TopicRule, forms: [[String]], ext: String) -> TopicHit? {
        var strong: [String] = []
        var weak: [String] = []
        for keyword in rule.keywords {
            if let allowed = keyword.onlyForExtensions, !allowed.contains(ext) { continue }
            guard Self.contains(keyword.phrase, in: forms) else { continue }
            if keyword.isStrong {
                if !strong.contains(keyword.text) { strong.append(keyword.text) }
            } else if !weak.contains(keyword.text) {
                weak.append(keyword.text)
            }
        }
        // A phrase match ("bank statement") makes the single words redundant.
        weak.removeAll { word in strong.contains { $0.split(separator: " ").contains(Substring(word)) } }
        guard !strong.isEmpty || !weak.isEmpty else { return nil }
        return TopicHit(rule: rule, strong: strong, weak: weak, isRelevant: rule.relevantExtensions.contains(ext))
    }

    /// True if `phrase` occurs as consecutive tokens (whole-word match).
    static func contains(_ phrase: [String], in forms: [[String]]) -> Bool {
        guard !phrase.isEmpty, phrase.count <= forms.count else { return false }
        for start in 0...(forms.count - phrase.count) {
            var matched = true
            for (offset, word) in phrase.enumerated() where !forms[start + offset].contains(word) {
                matched = false
                break
            }
            if matched { return true }
        }
        return false
    }

    static func containsAny(_ keywords: [Keyword], in forms: [[String]]) -> [String] {
        keywords.filter { contains($0.phrase, in: forms) }.map(\.text)
    }

    // MARK: Type evaluation

    private struct TypeMatch {
        let category: FileCategory
        let confidence: Confidence
        let ruleID: String
        let reason: String
        var tags: [String] = []
        /// Generic type matches (notes formats, keyword-only PDFs) yield to a topic.
        var yieldsToTopics = false
    }

    private func typeCategory(foldedName: String, stem: String, ext: String, forms: [[String]]) -> TypeMatch? {
        let foldedStem = NameAnalysis.fold(stem)

        if CategoryRules.softwareManifestNames.contains(foldedName) {
            return TypeMatch(category: .software, confidence: .high, ruleID: "TYPE.SOFTWARE.MANIFEST",
                             reason: "“\(foldedName)” is a standard software project file.")
        }
        if CategoryRules.softwareDocStems.contains(foldedStem), ["", "md", "txt", "rst", "markdown"].contains(ext) {
            return TypeMatch(category: .software, confidence: .medium, ruleID: "TYPE.SOFTWARE.DOC",
                             reason: "“\(stem)” is a name commonly used in software projects (but not only there).")
        }
        if CategoryRules.archiveExtensions.contains(ext) {
            return TypeMatch(category: .archives, confidence: .high, ruleID: "TYPE.ARCHIVE",
                             reason: "Extension .\(ext) is an archive format. It is never extracted.", tags: ["Archive"])
        }
        if CategoryRules.installerExtensions.contains(ext) {
            return TypeMatch(category: .archives, confidence: .high, ruleID: "TYPE.INSTALLER",
                             reason: "Extension .\(ext) is an installer, app or disk image. It is never opened or run.", tags: ["Installer / disk image"])
        }
        if CategoryRules.videoExtensions.contains(ext) {
            return TypeMatch(category: .media, confidence: .high, ruleID: "TYPE.VIDEO",
                             reason: "Extension .\(ext) is a video format.", tags: ["Video"])
        }
        if CategoryRules.audioExtensions.contains(ext) {
            return TypeMatch(category: .media, confidence: .high, ruleID: "TYPE.AUDIO",
                             reason: "Extension .\(ext) is an audio format.", tags: ["Audio"])
        }
        if CategoryRules.imageExtensions.contains(ext) || CategoryRules.rawImageExtensions.contains(ext)
            || CategoryRules.photoLibraryExtensions.contains(ext) {
            var tags: [String] = []
            var reason = "Extension .\(ext) is an image format."
            if CategoryRules.rawImageExtensions.contains(ext) {
                tags.append("Camera RAW")
                reason = "Extension .\(ext) is a camera RAW format."
            }
            if CategoryRules.photoLibraryExtensions.contains(ext) {
                tags.append("Photo library")
                reason = "A photo library package. Its contents are not scanned."
            }
            if NameAnalysis.looksLikeScreenshot(stem) {
                tags.append("Screenshot")
                reason += " The name looks like a screenshot."
            } else if NameAnalysis.looksLikeCameraName(stem) {
                tags.append("Photography")
                reason += " The name follows a camera naming pattern."
            }
            return TypeMatch(category: .images, confidence: .high, ruleID: "TYPE.IMAGE", reason: reason, tags: tags)
        }
        if CategoryRules.scienceDataExtensions.contains(ext) {
            return TypeMatch(category: .research, confidence: .high, ruleID: "TYPE.SCIENCE_DATA",
                             reason: "Extension .\(ext) is a common scientific data format.", tags: ["Scientific data"])
        }
        if CategoryRules.softwareExtensions.contains(ext) {
            return TypeMatch(category: .software, confidence: .high, ruleID: "TYPE.SOFTWARE",
                             reason: "Extension .\(ext) is a source code or project configuration format. It is never executed.")
        }
        if CategoryRules.designExtensions.contains(ext) {
            return TypeMatch(category: .design, confidence: .high, ruleID: "TYPE.DESIGN",
                             reason: "Extension .\(ext) is a design or creative-application format.")
        }
        if CategoryRules.cautiousDesignExtensions.contains(ext) {
            return TypeMatch(category: .design, confidence: .medium, ruleID: "TYPE.DESIGN.CAUTIOUS",
                             reason: "Extension .\(ext) is usually a design file, but the same extension is used by other applications.")
        }
        if CategoryRules.ebookExtensions.contains(ext) {
            return TypeMatch(category: .ebooks, confidence: .high, ruleID: "TYPE.EBOOK",
                             reason: "Extension .\(ext) is an e-book format.")
        }
        if CategoryRules.presentationExtensions.contains(ext) {
            let signals = Self.containsAny(CategoryRules.presentationKeywords, in: forms)
            return TypeMatch(
                category: .presentations, confidence: signals.isEmpty ? .medium : .high, ruleID: "TYPE.PRESENTATION",
                reason: "Extension .\(ext) is a presentation format" + Self.signalSuffix(signals))
        }
        if CategoryRules.spreadsheetExtensions.contains(ext) {
            let signals = Self.containsAny(CategoryRules.dataKeywords, in: forms)
            return TypeMatch(
                category: .spreadsheets, confidence: signals.isEmpty ? .medium : .high, ruleID: "TYPE.DATA",
                reason: "Extension .\(ext) is a spreadsheet or data format" + Self.signalSuffix(signals))
        }
        if CategoryRules.notesExtensions.contains(ext) {
            let signals = Self.containsAny(CategoryRules.notesKeywords, in: forms)
            return TypeMatch(
                category: .notes, confidence: signals.isEmpty ? .medium : .high, ruleID: "TYPE.NOTES",
                reason: "Extension .\(ext) is a text/document format with no stronger topic match" + Self.signalSuffix(signals),
                yieldsToTopics: true)
        }

        // PDFs, email exports and unknown types: keyword-only type categories.
        let presentation = Self.containsAny(CategoryRules.presentationKeywords, in: forms)
        if !presentation.isEmpty {
            return TypeMatch(category: .presentations, confidence: .medium, ruleID: "KW.PRESENTATION",
                             reason: "Filename contains \(Self.quoted(presentation)), which suggests slides exported as .\(ext.isEmpty ? "(no extension)" : ext).",
                             yieldsToTopics: true)
        }
        let reference = Self.containsAny(CategoryRules.referenceKeywords, in: forms)
        if !reference.isEmpty {
            return TypeMatch(category: .ebooks, confidence: .medium, ruleID: "KW.REFERENCE",
                             reason: "Filename contains \(Self.quoted(reference)), which suggests reference material.",
                             yieldsToTopics: true)
        }
        let notes = Self.containsAny(CategoryRules.notesKeywords, in: forms)
        if !notes.isEmpty {
            return TypeMatch(category: .notes, confidence: .medium, ruleID: "KW.NOTES",
                             reason: "Filename contains \(Self.quoted(notes)), which suggests notes or writing.",
                             yieldsToTopics: true)
        }
        return nil
    }

    private static func quoted(_ words: [String]) -> String { words.map { "“\($0)”" }.joined(separator: ", ") }

    private static func signalSuffix(_ signals: [String]) -> String {
        signals.isEmpty ? " (type alone)." : ", and the filename contains \(quoted(signals))."
    }
}
