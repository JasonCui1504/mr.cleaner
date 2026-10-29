# Read-Only File Organizer (mr.cleaner)

A small native macOS app that **inspects** a folder you choose and **suggests** how its files could be organized. If you turn on **Organize mode**, it can also carry out the two safest possible actions for you:

- **Read-only by default.** On launch it only reads metadata. It never deletes, renames, copies, or edits files, and never changes permissions, tags, timestamps, or extended attributes, in any mode.
- **Organize mode (off at every launch, confirmation required)** allows exactly two things, only inside the selected folder: **create a new folder** directly inside it, and **move an item into such a folder, keeping its name**. If the name is taken, the item is skipped, never overwritten or renamed. A folder named `Trash` is just a folder; you delete it yourself in Finder when you're ready. Every move can be undone during the session (Changes tab).
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

Optional: `scripts/bundle_app.sh` wraps the release build into `.build/ReadOnlyOrganizer.app`, which you can double-click. Add `--sandbox` to ad-hoc sign it with an App Sandbox profile that makes macOS itself block networking and any access outside the folder you pick (see [docs/SAFETY_REVIEW.md](docs/SAFETY_REVIEW.md#optional-os-enforced-sandbox)). Nothing is installed, signed with a real identity, or notarized.

## Install it in your Dock

On your Mac, from the repository folder:

```sh
scripts/install_app.sh
```

This builds a release copy, installs it as `~/Applications/Read-Only File Organizer.app` (with its icon and a local ad-hoc signature), and adds a tile to your Dock. It needs no `sudo`, doesn't touch `/Applications`, and uses no network. Options: `--no-dock` (install only), `--sandbox` (install the App Sandbox build, so macOS itself blocks networking and access outside the chosen folder), `--uninstall`. To update after pulling new code, run the script again; it replaces only its own previous copy.

The app opens on the **Dashboard** tab: file/folder/size totals, review candidates, potential duplicates, large/old/recent counts, category breakdown, top file types, the largest files, and the most recently modified files. Everything is computed locally, in memory, from the folder you scan.

## Run the tests

```sh
swift test
```

Tests create synthetic files only under `Tests/Fixtures/Generated/` (git-ignored) and delete them afterwards. They never read your real folders. `SafetyTests` scans every file in `Sources/` and fails on any delete/rename/copy/write, content-reading, process, networking, persistence, or AI/ML API, and on folder creation or moving anywhere except `FileOrganizer.swift`.

## Using the app

1. **Choose Folder…** opens the standard macOS folder picker. The picker's "New Folder" button is disabled.
2. **Scan Folder** lists that folder and its subfolders. A scan never starts on its own. **Stop Scan** cancels and keeps partial results.
3. Tabs:
   - **Dashboard**: totals, size, counts per category, review candidates, potential duplicates, large/old/recent files (thresholds adjustable for the session), category breakdown, top file types, largest and most recently modified files, and skipped/inaccessible paths.
   - **Files**: click a file to see a **Quick Look preview** (the same read-only viewer as Space in Finder), plus a sortable, virtualized table (Name, Category, Type, Size, Created, Modified, Relative Path, Confidence) with search and filters (category, type, kind, date range, size range, hidden, needs-review). Select a row to see its metadata, the category rationale, matched rule IDs, and session-only edits (change category, mark "Review later").
   - **Groups**: potential duplicates (name + size), version clusters, same-name-different-format, software projects, shared prefixes, keyword-related files, same-day clusters, and folder themes, each with its reason.
   - **Suggested Organization**: suggested destination paths next to each file's current path. In Organize mode, **Create Folders and Move Files…** lets you pick which suggested folders to create and fill. Software projects and files already in place are left alone.
   - **Changes**: every move made this session, with **Undo** and **Undo All Moves**, plus what was skipped and why.

### Organize mode

1. Flip the **Organize mode** switch in the toolbar and confirm.
2. Move things in any of these ways:
   - **Files tab, one click per file**: type a name in **Your folders** and click **Create Folder** (make as many as you like; `Trash` is always there). To reuse folders that already exist in the selected folder (for example ones you made in an earlier session), open **Existing Folders** and check the ones you want, or **Add All**. Each row's **Move to** column then has one button per folder.
   - **Files tab, several at once**: select rows (⌘-click / ⇧-click), then click a folder button on any selected row, use **Move N items to…**, or right-click the selection. Destinations are your folders, any folder already in the selected folder, a suggested category folder, or **New Folder…** (menu only). Items inside a selected folder move with it.
   - **Groups tab**: on potential duplicates, **Move to "Trash" folder** next to each copy.
   - **Suggested Organization tab**: **Create Folders and Move Files…**, choose folders, confirm.
3. The folder is rescanned automatically after each action.
4. When you're happy, delete the `Trash` folder yourself in Finder. The app has no delete function.

What a move changes: the item's location, the modification time of the two folders involved, and the item's "metadata changed" time. Its contents, name, created and modified dates are untouched. Moves to another disk are refused, because the system would perform them as copy + delete.

**Scan Options** (in memory): include hidden files (on), skip `.git`/`.svn`/`.hg` internals (on), and measure package sizes (off).

## What is read

Scanning reads only filesystem metadata. The one exception is the **preview** of the single file you select, which macOS Quick Look renders read-only. iCloud-only files are never previewed, so nothing is downloaded. For each entry, the scan reads only: name, extension, kind (file/folder/link/package/other), size, birth ("Created"), content modification ("Modified"), status change ("Metadata changed"), last access, hidden flag, readability, cloud placeholder status, and the system type for the extension. Scanning never opens file contents: no hashing, and no thumbnails written by the app.

- Symbolic links are listed but never followed. Their target text is shown, along with a note if it points outside the selected folder.
- Packages (`.app`, `.key`, `.photoslibrary`, …) are treated as single items.
- iCloud/File Provider placeholders are flagged, and placeholder folders are not listed, so no downloads are triggered.
- Permission-denied folders are reported and skipped; the rest of the scan continues.

## Project layout

```
Package.swift
Sources/OrganizerCore/      scanning, rules, grouping, filtering (Foundation only)
  FolderScanner.swift       all reading (metadata only)
  FileOrganizer.swift       the only code that changes anything: create folder, move (Organize mode)
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
