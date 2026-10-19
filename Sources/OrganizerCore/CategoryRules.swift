import Foundation

/// The complete, fixed rule table used by `RuleClassifier`.
/// Documented in docs/CATEGORY_RULES.md — keep the two in sync.

struct Keyword: Sendable {
    let text: String
    let phrase: [String]
    let isStrong: Bool
    /// When set, the keyword only counts for these extensions (e.g. "cv").
    let onlyForExtensions: Set<String>?

    init(_ text: String, strong: Bool, onlyFor: Set<String>? = nil) {
        self.text = text
        self.phrase = NameAnalysis.tokens(text)
        self.isStrong = strong
        self.onlyForExtensions = onlyFor
    }
}

/// A topic category is driven by filename keywords, reinforced by type.
struct TopicRule: Sendable {
    let id: String
    let category: FileCategory
    /// Lower number wins ties.
    let priority: Int
    let keywords: [Keyword]
    /// Extensions for which a keyword match is "typical", which lets the
    /// topic take precedence over the type category.
    let relevantExtensions: Set<String>
}

enum CategoryRules {

    private static func strong(_ words: [String]) -> [Keyword] { words.map { Keyword($0, strong: true) } }
    private static func weak(_ words: [String]) -> [Keyword] { words.map { Keyword($0, strong: false) } }

    static let documentExtensions: Set<String> = ["pdf", "doc", "docx", "pages", "rtf", "txt", "odt", "md"]
    static let imageDocumentExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif"]
    static let emailExtensions: Set<String> = ["eml", "emlx", "msg", "mbox"]

    // MARK: Topic rules, in priority order

    static let topics: [TopicRule] = [
        TopicRule(
            id: "FIN", category: .financial, priority: 1,
            keywords: strong([
                "tax", "taxes", "1099", "w2", "w-2", "1040", "1098", "invoice", "invoices", "receipt", "receipts",
                "bank", "bank statement", "credit card", "reimbursement", "paystub", "pay stub", "payslip",
                "payroll", "budget", "expense", "expenses", "billing",
            ]) + weak(["statement", "payment", "payments", "bill", "refund"]),
            relevantExtensions: documentExtensions.union(imageDocumentExtensions)
                .union(["csv", "xls", "xlsx", "xlsm", "ods", "numbers", "ofx", "qfx", "qif", "tif", "tiff"])
                .union(emailExtensions)
        ),
        TopicRule(
            id: "TRAVEL", category: .travel, priority: 2,
            keywords: strong([
                "itinerary", "boarding pass", "boardingpass", "reservation", "booking", "hotel", "flight",
                "airline", "rental car", "passport", "airbnb", "train ticket", "e-ticket", "eticket",
            ]) + weak(["confirmation", "travel", "trip", "visa", "ticket", "vacation"]),
            relevantExtensions: documentExtensions.union(imageDocumentExtensions)
                .union(emailExtensions).union(["pkpass", "ics"])
        ),
        TopicRule(
            id: "ACAD", category: .academic, priority: 3,
            keywords: strong([
                "assignment", "problem set", "pset", "lecture", "course", "coursework", "syllabus", "exam",
                "midterm", "final exam", "homework", "hw", "class notes", "diploma", "quiz",
            ]) + weak(["transcript", "degree", "class", "semester", "tutorial"]),
            relevantExtensions: documentExtensions
                .union(["ppt", "pptx", "key", "xls", "xlsx", "csv", "ipynb", "py", "r", "m", "tex"])
        ),
        TopicRule(
            id: "RES", category: .research, priority: 4,
            keywords: strong([
                "manuscript", "supplementary", "supplemental", "protocol", "experiment", "experiments", "research",
                "thesis", "dissertation", "western blot", "sequencing", "genomics", "microscopy", "preprint",
                "rnaseq", "rna seq", "assay",
            ]) + weak(["paper", "lab", "figure", "fig", "analysis"]),
            relevantExtensions: documentExtensions
                .union(["ppt", "pptx", "key", "csv", "tsv", "xls", "xlsx", "tif", "tiff", "ipynb", "tex", "bib", "ris"])
                .union(scienceDataExtensions)
        ),
        TopicRule(
            id: "WORK", category: .work, priority: 5,
            keywords: strong([
                "resume", "cover letter", "coverletter", "offer letter", "employment", "interview",
                "job description", "performance review",
            ]) + weak(["application", "payroll", "job", "career", "salary"])
                + [Keyword("cv", strong: false, onlyFor: ["pdf", "doc", "docx", "pages", "txt", "rtf", "odt"])],
            relevantExtensions: documentExtensions
        ),
    ]

    // MARK: Type tables

    static let archiveExtensions: Set<String> = [
        "zip", "tar", "gz", "tgz", "7z", "rar", "xz", "bz2", "tar.gz", "tar.bz2", "tar.xz", "tar.zst", "zst", "lz", "lzma", "cab",
    ]
    static let installerExtensions: Set<String> = [
        "dmg", "pkg", "mpkg", "app", "iso", "msi", "exe", "deb", "rpm", "apk", "ipa", "xip",
    ]
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "mkv", "avi", "webm", "wmv", "mpg", "mpeg", "3gp"]
    static let audioExtensions: Set<String> = ["mp3", "m4a", "wav", "flac", "aac", "aiff", "aif", "ogg", "opus", "wma", "caf"]
    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "webp", "bmp", "svg", "ico", "avif",
    ]
    static let rawImageExtensions: Set<String> = ["cr2", "cr3", "nef", "arw", "dng", "raf", "orf", "rw2"]
    static let photoLibraryExtensions: Set<String> = ["photoslibrary"]
    static let scienceDataExtensions: Set<String> = [
        "fastq", "fq", "bam", "sam", "cram", "vcf", "bcf", "bed", "gtf", "gff", "gff3", "fasta", "fa", "fna",
        "npy", "npz", "h5", "hdf5", "mat", "czi", "nd2", "lif", "fcs", "pdb", "mzml", "nc",
    ]
    static let softwareExtensions: Set<String> = [
        "swift", "py", "js", "mjs", "cjs", "ts", "jsx", "tsx", "html", "htm", "css", "scss", "sql", "sh", "zsh",
        "bash", "rs", "go", "java", "kt", "c", "h", "cpp", "cc", "hpp", "m", "mm", "cs", "rb", "php", "pl", "r",
        "ipynb", "toml", "yaml", "yml", "lock", "gradle", "xcodeproj", "xcworkspace", "playground", "vue", "lua",
    ]
    /// Exact filenames (lowercased) that identify project files. High confidence.
    static let softwareManifestNames: Set<String> = [
        "package.json", "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "requirements.txt", "pyproject.toml",
        "setup.py", "setup.cfg", "pipfile", "cargo.toml", "cargo.lock", "go.mod", "go.sum", "package.swift",
        "gemfile", "gemfile.lock", "pom.xml", "build.gradle", "build.gradle.kts", "cmakelists.txt", "makefile",
        "dockerfile", "docker-compose.yml", "docker-compose.yaml", ".gitignore", ".gitattributes", ".gitmodules",
        ".editorconfig", ".dockerignore", ".npmrc", ".nvmrc", "composer.json", "tsconfig.json",
    ]
    /// Stems that usually (not always) belong to a project. Medium confidence.
    static let softwareDocStems: Set<String> = ["readme", "license", "licence", "changelog", "contributing", "copying"]

    static let designExtensions: Set<String> = [
        "psd", "aep", "prproj", "sketch", "blend", "fcpbundle", "xd", "indd", "afdesign", "afphoto",
        "c4d", "procreate", "kra", "xcf", "aup3", "logicx", "band", "motn",
    ]
    /// Extensions that are design files in most cases but have other meanings
    /// (.ai: Illustrator / other; .fig: Figma / MATLAB figure).
    static let cautiousDesignExtensions: Set<String> = ["ai", "fig"]
    static let ebookExtensions: Set<String> = ["epub", "mobi", "azw", "azw3", "djvu", "ibooks", "fb2"]
    static let presentationExtensions: Set<String> = ["ppt", "pptx", "key", "odp"]
    static let spreadsheetExtensions: Set<String> = [
        "xls", "xlsx", "xlsm", "csv", "tsv", "ods", "numbers", "json", "xml", "parquet", "sqlite", "sqlite3", "db", "feather", "arrow",
    ]
    static let notesExtensions: Set<String> = ["txt", "md", "rtf", "doc", "docx", "pages", "odt", "markdown", "org"]

    // MARK: Type keyword signals

    static let presentationKeywords = strong(["deck", "slides", "slide", "presentation", "pitch", "talk", "keynote"])
    static let dataKeywords = strong(["dataset", "data", "export", "results", "table", "metrics"])
    static let notesKeywords = strong(["notes", "note", "draft", "outline", "journal", "meeting notes", "brainstorm", "memo", "todo"])
    static let referenceKeywords = strong(["textbook", "manual", "handbook", "reference", "guide", "documentation", "ebook"])

    // MARK: Special files

    static let systemMetadataNames: Set<String> = [".ds_store", "thumbs.db", "desktop.ini", ".localized", "icon\r", ".directory"]
    static let incompleteDownloadExtensions: Set<String> = ["crdownload", "part", "partial", "download", "opdownload"]
}
