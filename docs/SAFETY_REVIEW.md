# Safety Review

This document lists every filesystem, system, and network-relevant API used by the app sources (`Sources/`), what each does, and what the operating system may do on its own. It is enforced by `Tests/OrganizerCoreTests/SafetyTests.swift`.

## Summary of guarantees

| Guarantee | How it is ensured |
|---|---|
| No delete / rename / copy / edit | None of these APIs appear anywhere in `Sources/` (`testNoFileMutationAPIs`). |
| Changes limited to "create folder" + "move" | `createDirectory` and `moveItem` appear only in `FileOrganizer.swift` (`testFolderCreationAndMovingOnlyInFileOrganizer`, `testFileManagerUsageIsAllowListed`), are reachable only when Organize mode is on (off at every launch, confirmation required), and never create intermediate folders (`testFileOrganizerNeverOverwritesOrCreatesIntermediates`). All other filesystem access is in `FolderScanner.swift`. |
| No file contents read by the app | No content-reading API (`Data(contentsOf:)`, `FileHandle`, `read(`, `mmap`, PDFKit, AVFoundation, hashing) appears in `Sources/` (`testNoFileContentReads`). The only content access is the Quick Look preview of the one file you select, confined to `FilePreview.swift` (`testQuickLookPreviewOnlyInFilePreview`). |
| No code execution | No `Process`, `NSTask`, `system`, `posix_spawn`, AppleScript, or `NSWorkspace` (`testNoProcessExecutionOrOpening`). |
| Offline | No networking API, framework, or URL literal (`testNoNetworking`). `Package.swift` declares no dependencies (`testPackageHasNoDependencies`). Only Apple system frameworks are imported. |
| No persistence (one exception) | No `UserDefaults` writes, `@AppStorage`, `@SceneStorage`, Core Data, SQLite, bookmarks, window frame autosave, temp/cache/support directories, or logging (`testNoPersistence`), except `FolderListStore.swift`, which saves only the **Your folders** names per selected folder path in the preferences domain `local.readonly.fileorganizer.folders` (`testOnlyTheFolderListIsSaved`). |
| No AI/ML | No Core ML, Create ML, Natural Language, Vision, Speech, or model/LLM references (`testNoAIOrMLFrameworks`). |
| No mutation-implying UI | No buttons or labels named Apply/Move/Rename/Delete/Organize now/Trash/Clean, and no "safe to delete" text (`testNoForbiddenActionLabelsInUI`). |

## Imported frameworks

| Framework | Where | Purpose |
|---|---|---|
| Foundation | core + app | strings, dates, `FileManager` (listing only), formatting |
| Darwin | `FolderScanner.swift` | `lstat(2)`, `strerror` |
| UniformTypeIdentifiers | `FolderScanner.swift` | map extension → type identifier / MIME type (no file access) |
| Combine | `ScanController.swift` | `ObservableObject` / `@Published` |
| AppKit | app | `NSApplication`, `NSWindow`, `NSOpenPanel`, menus |
| SwiftUI | app | views |
| Quartz (QuickLookUI) | `FilePreview.swift` | read-only preview of the selected file |

There are no third-party dependencies.

## Filesystem API inventory (complete)

All in `Sources/OrganizerCore/FolderScanner.swift`:

| API | Effect | Notes |
|---|---|---|
| `FileManager.contentsOfDirectory(at:includingPropertiesForKeys:options:)` | Lists one folder's entries | Read-only. Never called on symlinks, packages (unless "measure package sizes" is on), cloud placeholder folders, or version-control internals (by default). |
| `lstat(2)` via `URL.withUnsafeFileSystemRepresentation` | Kind, size, timestamps, flags | Does **not** follow symbolic links. |
| `URL.resourceValues(forKeys:)` | Hidden, readable, package, content type, iCloud status | Metadata lookups only. `isReadable` uses `access(2)`; nothing is opened. |
| `FileManager.destinationOfSymbolicLink(atPath:)` | Reads a link's target text (`readlink`) | The target is **not** resolved or visited. "Points outside" is a lexical check. |
| `UTType(filenameExtension:)` | Extension → type | Pure lookup in the system type database. No file access. |

App target (`Sources/ReadOnlyOrganizer/`):

| API | Effect | Notes |
|---|---|---|
| `NSOpenPanel` | Standard folder picker | `canChooseFiles = false`, `canCreateDirectories = false`, `allowsMultipleSelection = false`, `resolvesAliases = false`. |
| `UserDefaults.standard.register(defaults:)` | Fills the in-memory registration domain | **Never writes to disk.** Used to disable window-state restoration (`NSQuitAlwaysKeepsWindows = false`, `ApplePersistenceIgnoreState = true`). |
| `NSWindow.isRestorable = false` | No saved window state | No `frameAutosaveName` is set. |

The app uses an AppKit lifecycle instead of a SwiftUI `App`/`WindowGroup` scene. SwiftUI scenes autosave window frames and restoration state to disk by default; the AppKit lifecycle avoids that.

## Organize mode API inventory (complete)

All in `Sources/OrganizerCore/FileOrganizer.swift`, called only when Organize mode is on:

| API | Effect | Guards |
|---|---|---|
| `FileManager.createDirectory(at:withIntermediateDirectories: false, attributes: nil)` | Creates one empty folder **directly inside** the selected folder | Name must be valid (no `/`, `:`, leading `.`, or surrounding spaces). If something with that name exists it must be a real folder (not a file, link, or package); nothing is replaced. |
| `FileManager.moveItem(at:to:)` | Moves one item into such a folder (or back, for Undo) | Source and destination are inside the selected folder; every parent is a real folder on the same disk (no symlinks, no other volumes); the name is unchanged; the destination must not exist (checked first, and `moveItem` itself fails rather than replacing); a folder can't move into itself. On the same disk this is a single `rename(2)` of the directory entry: contents and the item's own dates are untouched. |

Not present anywhere: delete, trash, rename, copy, replace, write, set attributes or permissions, or create files. Moving to another disk is refused, because `moveItem` would implement it as copy + delete.

The move log (for Undo) lives in memory only and is lost when you quit.

## Preview (Quick Look)

`Sources/ReadOnlyOrganizer/FilePreview.swift` embeds `QLPreviewView` (Quartz / QuickLookUI) for the file selected in the Files tab. It is the same read-only previewer Finder uses for Space-bar previews: macOS reads the file to render it and does not modify it. The app never previews iCloud-only placeholders or unreadable files. Quick Look's renderers run in macOS's own sandboxed helper processes, and macOS may keep preview thumbnails in its system Quick Look cache. That is macOS's own cache, not app data. Hide the preview with the **Hide** link in the detail pane.

## Network API inventory

None. The app makes no network requests, starts no server, and loads no remote content. It uses system fonts and SF Symbols only.

## Reads and their possible side effects

Not writing is not the same as having zero filesystem effects. In particular:

- **Folder access time.** Listing a folder can update its access time (`atime`) on some filesystems, depending on mount options. APFS defaults to a relaxed policy. The app never modifies timestamps itself, and `atime` is shown only as an informational field.
- **No file contents are read.** No file's data is opened, so file access times are not touched by content reads, and cloud-only files are never downloaded.
- **Cloud placeholders.** Entries marked dataless (`SF_DATALESS`) or reported by iCloud as not downloaded are shown as "Cloud placeholder" and never descended into. Fetching their metadata does not materialize them.
- **Type lookup** uses the extension only (Launch Services). It does not read file contents.

## What macOS may write on its own (outside the app's control)

The app's code writes nothing. The operating system may still record some state as a consequence of normal use:

1. **Open panel state.** `NSOpenPanel` may save its last-used directory and panel size in the app's preferences domain via `cfprefsd`, and may update the system's recent-places list. This is system framework behavior the app cannot disable. The app itself never calls a preference-writing API.
2. **Privacy (TCC) records.** If the chosen folder is in a protected location (Desktop, Documents, Downloads, removable or network volumes), macOS may ask for permission and record your answer in its privacy database. The app never requests Full Disk Access and never asks for broader access.
3. **Sandbox container (only with the optional `--sandbox` bundle).** On first launch macOS creates `~/Library/Containers/local.readonly.fileorganizer`. The app does not write into it.
4. **Crash reports.** If the app crashes, macOS's own crash reporter may write a local diagnostic report. The app contains no crash-reporting code.

## Optional OS-enforced sandbox

`scripts/bundle_app.sh --sandbox` produces an ad-hoc-signed `.app` with `Support/ReadOnlyOrganizer.entitlements`:

- `com.apple.security.app-sandbox`
- `com.apple.security.files.user-selected.read-write`

With this profile, macOS denies any outbound network connection and any access outside the folder you pick, independent of the app's code. It allows read-write access to the picked folder so that Organize mode works. It is optional because it involves ad-hoc code signing and the container folder described above.

## Installing (`scripts/install_app.sh`)

The installer runs only when you invoke it. It is not part of the app. It writes exactly:

- `.build/ReadOnlyOrganizer.app` (inside the repository)
- `~/Applications/Read-Only File Organizer.app`, replacing a previous copy only if that copy has this app's bundle identifier
- one Dock tile, added to `com.apple.dock persistent-apps` with `defaults write`, after which the Dock is restarted (`killall Dock`). Skip this with `--no-dock`.

The installed bundle gets a local ad-hoc code signature (`codesign --sign -`). This is not a Developer ID signature, and nothing is notarized or uploaded. The app itself still writes nothing at runtime.

## Build-time writes

`swift build` / `swift test` write only to `.build/` inside the repository. Tests write synthetic fixtures only to `Tests/Fixtures/Generated/` (the helper refuses any other path). The manual-verification scripts write only to `Tests/Fixtures/Manual/` and `Tests/Fixtures/Snapshots/`.

## Reviewing the source yourself

```sh
# Every filesystem call in the app:
grep -rn "FileManager\|lstat\|resourceValues\|destinationOfSymbolicLink" Sources/
# Anything that could write, execute, or connect (should print nothing):
grep -rnE "createFile|moveItem|copyItem|removeItem|createDirectory|setAttributes|\.write\(|Process\(|URLSession|NSWorkspace" Sources/
swift test --filter SafetyTests
```
