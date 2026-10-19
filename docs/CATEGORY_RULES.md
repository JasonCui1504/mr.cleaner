# Category Rules

All categorization is deterministic and is implemented in `Sources/OrganizerCore/CategoryRules.swift` (the data) and `RuleClassifier.swift` (the procedure). Only the **filename, extension, and entry kind** are used. File contents are never read. A category is a suggestion, not a statement about what the file contains.

## Normalization

- Names are folded case-, diacritic- and width-insensitively ("Résumé" → `resume`).
- The stem is split into tokens on any non-letter/digit character and on lower→UPPER camel-case boundaries (`BankStatement` → `bank`, `statement`). Letter/digit runs stay together (`w2`, `hw3`).
- A token also matches with a trailing number removed when at least two letters remain (`pset3` → `pset`, `final2` → `final`).
- Keywords must match **whole tokens** (or consecutive tokens for phrases), so `wallpaper` does not match `paper` and `taxonomy` does not match `tax`.
- Extensions are lowercased. `tar.gz`/`tar.bz2`/`tar.xz`/`tar.zst` are kept whole. Dotfiles (`.gitignore`) have no extension. An extension must be 1–10 ASCII letters/digits containing a letter (so `notes v2.5` has none).

## Decision procedure

1. **Special entries**
   - Symbolic link → Uncategorized, Low, review ("target not inspected").
   - Socket/device/other → Uncategorized, Low, review.
   - `.DS_Store`, `Thumbs.db`, `desktop.ini`, `.localized`, `Icon\r` → Uncategorized, High, tag "System file" (not flagged).
   - `.crdownload`, `.part`, `.partial`, `.download`, `.opdownload` → Uncategorized, Medium, tag "Incomplete download", review.
2. **Topic scoring.** Each topic rule below is scored: strong keyword = 2, weak keyword = 1, +1 if the extension is in the topic's *typical types*. The highest score wins; ties go to the higher-priority topic (listed order).
3. **Type category** from the extension or exact filename (table below).
4. **Precedence**
   - The topic is primary when the extension is typical for it, when the type category is generic (notes formats or keyword-only PDF matches), when there is no type category, or when the type category is the same as the topic.
   - Otherwise the type category is primary and the topic is a secondary tag. For example, `lecture.mp4` → Video & Audio (secondary: Academic) and `invoice.zip` → Archives (secondary: Financial).
5. Nothing matched → **Uncategorized / Review**, Low, with the specific reason (unknown extension, PDF with no keywords, email export with no keywords, no extension).

### Topic confidence

| Evidence | Confidence |
|---|---|
| Strong keyword + typical type | High |
| Strong keyword, atypical/unknown type | Medium |
| Only weak keyword(s) + typical type | Medium |
| Only weak keyword(s), atypical type | Low (review) |
| Another topic also has a strong keyword, or ties on score | One level lower, plus review flag and `TOPIC.CONFLICT` |

Any Low result is flagged for review.

## Topic rules (priority order)

| # | Category | Strong keywords | Weak keywords (ambiguous alone) | Typical types |
|---|---|---|---|---|
| 1 | Financial & Tax | tax, taxes, 1099, w2, w-2, 1040, 1098, invoice(s), receipt(s), bank, bank statement, credit card, reimbursement, paystub, pay stub, payslip, payroll, budget, expense(s), billing | statement, payment(s), bill, refund | pdf doc docx pages rtf txt odt md, jpg jpeg png heic heif tif tiff, csv xls xlsx xlsm ods numbers, ofx qfx qif, eml emlx msg mbox |
| 2 | Travel & Reservations | itinerary, boarding pass, boardingpass, reservation, booking, hotel, flight, airline, rental car, passport, airbnb, train ticket, e-ticket, eticket | confirmation, travel, trip, visa, ticket, vacation | documents, images (jpg/png/heic), email exports, pkpass, ics |
| 3 | Academic & Coursework | assignment, problem set, pset, lecture, course, coursework, syllabus, exam, midterm, final exam, homework, hw, class notes, diploma, quiz | transcript, degree, class, semester, tutorial | documents, ppt pptx key, xls xlsx csv, ipynb py r m tex |
| 4 | Research & Scientific | manuscript, supplementary, supplemental, protocol, experiment(s), research, thesis, dissertation, western blot, sequencing, genomics, microscopy, preprint, rnaseq, rna seq, assay | paper, lab, figure, fig, analysis | documents, ppt pptx key, csv tsv xls xlsx, tif tiff, ipynb tex bib ris, scientific data formats |
| 5 | Work & Career | resume/résumé, cover letter, coverletter, offer letter, employment, interview, job description, performance review | application, payroll, job, career, salary, cv (*only* for pdf/doc/docx/pages/txt/rtf/odt) | pdf doc docx pages rtf txt odt md |

Deliberate choices:

- **"final" alone is not academic.** It is treated as a version marker (`report_final.docx`). Only the phrase "final exam" counts.
- **"cv" is conservative.** It is weak and only counts for document types, so `cv_utils.py` (computer vision) is Software.
- **"statement" / "payment"** are weak: Medium for typical types, Low otherwise.
- **Travel** wording never claims a booking is confirmed; it only says the name suggests travel.

## Type rules (checked in this order)

| Category | Matches | Confidence |
|---|---|---|
| Software & Development | exact names: package.json, package-lock.json, yarn.lock, pnpm-lock.yaml, requirements.txt, pyproject.toml, setup.py, setup.cfg, Pipfile, Cargo.toml, Cargo.lock, go.mod, go.sum, Package.swift, Gemfile(.lock), pom.xml, build.gradle(.kts), CMakeLists.txt, Makefile, Dockerfile, docker-compose.y(a)ml, .gitignore, .gitattributes, .gitmodules, .editorconfig, .dockerignore, .npmrc, .nvmrc, composer.json, tsconfig.json | High |
| Software & Development | README / LICENSE / LICENCE / CHANGELOG / CONTRIBUTING / COPYING with no extension or .md/.txt/.rst | Medium |
| Archives & Installers | zip tar gz tgz 7z rar xz bz2 tar.gz tar.bz2 tar.xz tar.zst zst lz lzma cab | High (tag Archive; never extracted) |
| Archives & Installers | dmg pkg mpkg app iso msi exe deb rpm apk ipa xip | High (tag Installer; never opened) |
| Video & Audio | mp4 mov m4v mkv avi webm wmv mpg mpeg 3gp / mp3 m4a wav flac aac aiff aif ogg opus wma caf | High (never played) |
| Images & Photography | jpg jpeg png heic heif tif tiff gif webp bmp svg ico avif; RAW cr2 cr3 nef arw dng raf orf rw2; photoslibrary | High. Tags: Camera RAW; Screenshot ("screenshot", "screen shot", "cleanshot"); Photography (camera names like IMG_1234, DSC_0001, PXL_…, DJI_…, GOPR…, 20240101_123456) |
| Research & Scientific | fastq fq bam sam cram vcf bcf bed gtf gff gff3 fasta fa fna npy npz h5 hdf5 mat czi nd2 lif fcs pdb mzml nc | High (tag Scientific data) |
| Software & Development | swift py js mjs cjs ts jsx tsx html htm css scss sql sh zsh bash rs go java kt c h cpp cc hpp m mm cs rb php pl r ipynb toml yaml yml lock gradle xcodeproj xcworkspace playground vue lua | High (never executed) |
| Design & Creative | psd aep prproj sketch blend fcpbundle xd indd afdesign afphoto c4d procreate kra xcf aup3 logicx band motn | High |
| Design & Creative | ai, fig (also used by other apps, e.g. MATLAB .fig) | Medium |
| E-books & Reference | epub mobi azw azw3 djvu ibooks fb2 | High |
| Presentations | ppt pptx key odp | Medium; High with deck/slides/slide/presentation/pitch/talk/keynote in name |
| Spreadsheets & Data | xls xlsx xlsm csv tsv ods numbers json xml parquet sqlite sqlite3 db feather arrow | Medium; High with dataset/data/export/results/table/metrics |
| Notes & Writing | txt md rtf doc docx pages odt markdown org | Medium; High with notes/note/draft/outline/journal/meeting notes/brainstorm/memo/todo. **Yields to any topic match.** |
| (PDF/other, keyword-only) | presentation keywords → Presentations; textbook/manual/handbook/reference/guide/documentation/ebook → E-books & Reference; notes keywords → Notes & Writing | Medium. **Yields to any topic match.** |

## Context rules (after classification)

- Files inside a detected software project get the tag `In project “name”`, Software as a secondary category, and rule ID `CONTEXT.PROJECT`. The suggested organization keeps the project intact under `Software & Development/<project>/…`.
- Access status adds review reasons: not readable, cloud placeholder, or metadata error. Hidden entries get the tag "Hidden".

## Rule IDs shown in the UI

`TOPIC.FIN|TRAVEL|ACAD|RES|WORK`, `TOPIC.<id>.SECONDARY`, `TOPIC.CONFLICT`, `TYPE.SOFTWARE.MANIFEST`, `TYPE.SOFTWARE.DOC`, `TYPE.ARCHIVE`, `TYPE.INSTALLER`, `TYPE.VIDEO`, `TYPE.AUDIO`, `TYPE.IMAGE`, `TYPE.SCIENCE_DATA`, `TYPE.SOFTWARE`, `TYPE.DESIGN`, `TYPE.DESIGN.CAUTIOUS`, `TYPE.EBOOK`, `TYPE.PRESENTATION`, `TYPE.DATA`, `TYPE.NOTES`, `KW.PRESENTATION`, `KW.REFERENCE`, `KW.NOTES`, `SPECIAL.SYMLINK|OTHER|SYSTEM|PARTIAL`, `CONTEXT.PROJECT`, `NONE`.

## Grouping rules (`GroupingEngine.swift`)

Every group has at least two members and a written reason. Groups are recommendations only.

| Group | Rule |
|---|---|
| Potential duplicates | Same name after removing trailing "(n)", "copy", "copy n"; same extension; same size in bytes (> 0). Anywhere in the tree. Contents are **not** compared. |
| Version clusters | Same folder; same name after removing version markers (final, finalN, vN, version N, draft, revised, rev, copy, edited, updated, latest, old, new, "(n)"); at least one member has a marker; names actually differ. |
| Same name, different formats | Same folder; identical stem; at least two different extensions. |
| Software projects | A folder containing a strong manifest (package.json, pyproject.toml, Cargo.toml, Package.swift, go.mod, setup.py, pom.xml, build.gradle(.kts), Gemfile, composer.json, CMakeLists.txt, requirements.txt, `.git`, `*.xcodeproj`, `*.xcworkspace`, `*.sln`), or a weak one (README, Makefile, Dockerfile, LICENSE) plus ≥ 2 source files. Only the outermost project is grouped; nested ones are mentioned. |
| Shared filename prefix | Same folder; ≥ 3 files; names with ≥ 3 tokens whose first two tokens match (non-numeric, not markers or stop words, ≥ 6 letters combined). |
| Related by keywords | Identical set of ≥ 2 meaningful keywords (≥ 3 letters, no numbers, markers, or stop words), in ≥ 2 different folders. |
| Same-day clusters | Same folder, same category (not Uncategorized), same local modification day, ≥ 3 files, **and** either all names follow camera/screenshot patterns or all share a keyword. |
| Folder themes | A folder with ≥ 5 files directly inside, ≥ 80% of them in one category (not Uncategorized). |
