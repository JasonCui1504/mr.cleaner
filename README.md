# Read-Only File Organizer (mr.cleaner)

A small native macOS app that **inspects** a folder you choose and **suggests** how its files could be organized. It is a read-only inventory and recommendation tool:

- **Read-only.** It never creates, renames, moves, copies, deletes, or edits files, and never changes permissions, tags, timestamps, or extended attributes. There is no "apply" step. The suggested organization is a preview only.
- **Offline.** No network code, no remote assets, no update checks, no telemetry.
- **No AI.** Categories come from a fixed, documented rule table (filename keywords, extension, entry kind). Every result shows the rule that produced it and its confidence.
- **Nothing saved.** Scan results, category edits, and thresholds stay in memory and are discarded when you quit. No database, cache, log, settings file, or export.

## Requirements

- macOS 13 Ventura or later
- Xcode 15+ or the Swift 5.9+ command-line tools (`xcode-select --install`)
- No third-party packages; nothing is downloaded during the build.

## Build and run

```sh
swift build                 # debug build into .build/ (inside the repo)
swift run ReadOnlyOrganizer # launches the app window
```

Or open `Package.swift` in Xcode and run the `ReadOnlyOrganizer` scheme.

Optional: `scripts/bundle_app.sh` wraps the release build into `.build/ReadOnlyOrganizer.app`, which you can double-click. Add `--sandbox` to ad-hoc sign it with an App Sandbox profile that makes macOS itself enforce read-only folder access and block networking (see [docs/SAFETY_REVIEW.md](docs/SAFETY_REVIEW.md#optional-os-enforced-sandbox)). Nothing is installed, signed with a real identity, or notarized.

## Install it in your Dock

On your Mac, from the repository folder:

```sh
scripts/install_app.sh
```

This builds a release copy, installs it as `~/Applications/Read-Only File Organizer.app` (with its icon and a local ad-hoc signature), and adds a tile to your Dock. It needs no `sudo`, doesn't touch `/Applications`, and uses no network. Options: `--no-dock` (install only), `--sandbox` (install the App Sandbox build, so macOS itself enforces read-only access and no network), `--uninstall`. To update after pulling new code, run the script again; it replaces only its own previous copy.

The app opens on the **Dashboard** tab: file/folder/size totals, review candidates, potential duplicates, large/old/recent counts, category breakdown, top file types, the largest files, and the most recently modified files. Everything is computed locally, in memory, from the folder you scan.

## Run the tests

```sh
swift test
```

Tests create synthetic files only under `Tests/Fixtures/Generated/` (git-ignored) and delete them afterwards. They never read your real folders. `SafetyTests` scans every file in `Sources/` for file-mutation, content-reading, process, networking, persistence, and AI/ML APIs and fails if any appear.

## Using the app

1. **Choose Folder…** opens the standard macOS folder picker. The picker's "New Folder" button is disabled.
2. **Scan Folder** lists that folder and its subfolders. A scan never starts on its own. **Stop Scan** cancels and keeps partial results.
3. Tabs:
   - **Dashboard**: totals, size, counts per category, review candidates, potential duplicates, large/old/recent files (thresholds adjustable for the session), category breakdown, top file types, largest and most recently modified files, and skipped/inaccessible paths.
   - **Files**: a sortable, virtualized table (Name, Category, Type, Size, Created, Modified, Relative Path, Confidence) with search and filters (category, type, kind, date range, size range, hidden, needs-review). Select a row to see its metadata, the category rationale, matched rule IDs, and session-only edits (change category, mark "Review later").
   - **Groups**: potential duplicates (name + size), version clusters, same-name-different-format, software projects, shared prefixes, keyword-related files, same-day clusters, and folder themes, each with its reason.
   - **Suggested Organization (Preview)**: virtual destination paths next to each file's current path. These folders do not exist and the app has no way to create them.

**Scan Options** (in memory): include hidden files (on), skip `.git`/`.svn`/`.hg` internals (on), and measure package sizes (off).

## What is read

For each entry, only filesystem metadata: name, extension, kind (file/folder/link/package/other), size, birth ("Created"), content modification ("Modified"), status change ("Metadata changed"), last access, hidden flag, readability, cloud placeholder status, and the system type for the extension. **File contents are never opened** (no hashing, no previews, no thumbnails).

- Symbolic links are listed but never followed. Their target text is shown, along with a note if it points outside the selected folder.
- Packages (`.app`, `.key`, `.photoslibrary`, …) are treated as single items.
- iCloud/File Provider placeholders are flagged, and placeholder folders are not listed, so no downloads are triggered.
- Permission-denied folders are reported and skipped; the rest of the scan continues.

## Project layout

```
Package.swift
Sources/OrganizerCore/      scanning, rules, grouping, filtering (Foundation only)
  FolderScanner.swift       the only file that touches the filesystem
  CategoryRules.swift       the rule table (see docs/CATEGORY_RULES.md)
  RuleClassifier.swift      deterministic classifier with explanations
  GroupingEngine.swift      group suggestions
  OrganizationPlan.swift    virtual destination paths
  Summary.swift, SortAndFilter.swift, Analyzer.swift, ScanController.swift
  SafetyPolicy.swift        read-only/offline statement shown in the UI
Sources/ReadOnlyOrganizer/  AppKit lifecycle + SwiftUI views
Tests/OrganizerCoreTests/   unit, integration, performance and safety tests
scripts/                    Dock installer, .app bundler, icon generator, manual fixture + snapshot tools
Support/                    Info.plist, app icon, optional sandbox entitlements
docs/                       safety review, rules, manual checklist, limitations
```

## Documentation

- [docs/SAFETY_REVIEW.md](docs/SAFETY_REVIEW.md): every filesystem and system API used, and what the OS may do on its own
- [docs/CATEGORY_RULES.md](docs/CATEGORY_RULES.md): the full rule table and precedence
- [docs/MANUAL_VERIFICATION.md](docs/MANUAL_VERIFICATION.md): step-by-step checklist (no writes, no network, no Full Disk Access)
- [docs/LIMITATIONS.md](docs/LIMITATIONS.md): known limitations and edge cases
