# Manual Verification Checklist

Use synthetic files only. Do not point the app at real personal folders while verifying.

## 0. Build and run the automated tests

```sh
swift build
swift test            # all tests, including SafetyTests (static source checks)
```

- [ ] All tests pass.
- [ ] `git status` shows nothing new outside `.build/` (fixtures under `Tests/Fixtures/Generated/` are removed after the tests and are git-ignored).

## 1. Create the synthetic fixture (inside the repo only)

```sh
scripts/make_manual_fixture.sh        # creates Tests/Fixtures/Manual/
```

It contains financial, travel, academic, research, career, photo, media, archive, and project files; same-stem and versioned names; name+size duplicates; a hidden file; a Unicode/emoji name; an `.app` package; and two symbolic links (one pointing outside the fixture, one loop).

## 2. Record the "before" state (stored outside the scanned folder)

```sh
scripts/snapshot_fixture.sh record    # writes Tests/Fixtures/Snapshots/Manual.snapshot.txt
```

This records every entry's path, type, size, permissions, flags, birth time, modification time, and SHA-256 (or link target). The script reads contents for hashing. The app never does.

## 3. Scan the fixture

```sh
swift run ReadOnlyOrganizer
```

- [ ] The app does not scan anything at launch.
- [ ] **Choose Folder…** → select `Tests/Fixtures/Manual`. The picker has no "New Folder" button. The exact path is shown.
- [ ] The "Read-only · Offline · No AI" badge and the "never changes…" banner are visible.
- [ ] **Scan Folder** → the scan completes. Try **Stop Scan** on a larger synthetic folder (e.g. run the tests' performance fixture generator, or duplicate the fixture several times *inside* `Tests/Fixtures/`) and confirm partial results are shown with a warning.
- [ ] Dashboard: counts and total size look right; top file types, largest files and recently modified lists are populated. "Creation date unavailable" is 0 on APFS. Potential duplicates show `photo.jpg` / `photo (1).jpg`.
- [ ] Files: sort by Size and Modified (numeric/chronological order). Search "invoice". Filter by category, type, hidden, and needs-review. Select rows and read the rationale and rule IDs.
- [ ] `link-outside` is shown as a symbolic link "pointing outside", and nothing from `Sources/` appears in the results. `link-loop` causes no repetition.
- [ ] `Tool.app` is one item (Package) with no children listed.
- [ ] Change a file's category and mark "Review later". The Dashboard and Suggested Organization update. Quit and relaunch: the edits are gone.
- [ ] Groups tab: version cluster (thesis…), same-stem (report.docx/pdf), project (`project`), same-day cluster (IMG_000x), each with an explanation.
- [ ] Suggested Organization: banner says PREVIEW ONLY, paths are italic "Suggested" next to "Currently". There are no Apply/Move/Rename/Delete/Organize buttons.

## 3b. Organize mode (optional; do this on a fresh copy of the fixture)

- [ ] The switch is off at launch, and turning it on asks for confirmation.
- [ ] Files tab: select two rows → Move 2 items to… → `Trash` folder. `Tests/Fixtures/Manual/Trash/` now holds both, with unchanged names, sizes and SHA-256.
- [ ] Moving a file to a folder that already has the same name is skipped and listed under Changes.
- [ ] Changes → Undo All Moves puts everything back.
- [ ] Suggested Organization → Create Folders and Move Files… creates only the checked folders, leaves `project/` untouched, and reports skips.
- [ ] Re-run `scripts/snapshot_fixture.sh compare` after Undo All. Content hashes, names and sizes match the snapshot (folder modification times and `Trash/` itself may differ).

## 4. Verify that nothing changed (read-only mode)

```sh
scripts/snapshot_fixture.sh compare
```

- [ ] Prints `OK: no entries were created, removed, or changed.`
- [ ] `ls -la@ Tests/Fixtures/Manual` shows no new files and no new extended attributes.
- [ ] Optional: `xattr -lr Tests/Fixtures/Manual` lists no new attributes.

## 5. Verify no network activity

Any of:

- [ ] Turn off Wi-Fi/Ethernet, then launch and scan. Everything works.
- [ ] While the app runs: `lsof -i -a -c ReadOnlyOrganizer` prints nothing.
- [ ] `nettop -p $(pgrep ReadOnlyOrganizer)` shows no connections.
- [ ] With a firewall such as Little Snitch or LuLu installed, no connection attempts are reported for the app.
- [ ] `nm -u .build/debug/ReadOnlyOrganizer | grep -iE "socket|connect|URLSession|nw_"` prints nothing referenced by app code. System frameworks may link networking symbols internally; the source check in `SafetyTests` is the authoritative test for app code.

## 6. Verify no persistent app data

- [ ] `defaults read ReadOnlyOrganizer 2>/dev/null` and `defaults read local.readonly.fileorganizer 2>/dev/null` show nothing, **except** keys the system open panel may store (e.g. `NSNavLastRootDirectory`, `NSNavPanelExpandedSizeForOpenMode`). Those are written by macOS's `NSOpenPanel`, not by app code (see SAFETY_REVIEW.md).
- [ ] No new files for the app in `~/Library/Application Support`, `~/Library/Caches`, `~/Library/Logs`, or `$TMPDIR` (compare `ls -lt` before and after).
- [ ] `~/Library/Saved Application State` has no entry for the app.

## 7. Verify permissions

- [ ] The app never asks for Full Disk Access. It does not appear in System Settings → Privacy & Security → Full Disk Access unless you add it yourself.
- [ ] Choosing a protected folder (e.g. a synthetic folder on a removable volume) shows only the standard macOS consent prompt for that location.
- [ ] Optional: build with `scripts/bundle_app.sh --sandbox`, launch the `.app`, and repeat steps 3–5. macOS now enforces read-only access and no network.

## 8. Clean up

```sh
rm -rf Tests/Fixtures/Manual Tests/Fixtures/Snapshots
```
