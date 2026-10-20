# Limitations and Known Edge Cases

## By design (version 1)

- **Only two actions, only in Organize mode.** Create a folder directly inside the selected folder, and move an item (name unchanged) into it. There is no delete, rename, copy, or export. Emptying the `Trash` folder is up to you.
- **Name conflicts are skipped.** If the destination already has an item with that name, the move is skipped and reported in the Changes tab; the app never renames to make room.
- **Undo is per session.** The move log is in memory. After quitting, move things back in Finder.
- **Empty source folders stay.** After moving files out, their old folders remain (possibly empty); remove them yourself if you like.
- **Software projects are never split.** "Create Folders and Move Files…" skips files inside detected projects; move a whole project folder from the Files tab if you want.
- **After a move, the list is updated in place** (no full rescan), so dates such as "Metadata changed" show the values from the last scan. Click **Scan Folder** for fresh metadata.
- **Folder buttons are per session.** The **Your folders** list is in memory. The folders themselves stay on disk.
- **Previews** use macOS Quick Look and show whatever Quick Look supports. Some formats only show an icon. iCloud-only files are not previewed.
- **Same disk only.** Items on another volume mounted inside the selected folder are not moved.
- **No saving.** Results, edits, and thresholds disappear on quit. There is no report export. (A future export would need its own explicit, separately approved design.)
- **Filenames only.** Categories come from names, extensions, and kinds. A file named `IMG_2041.pdf` that is really a tax form will not be recognized. Confidence describes rule strength, not truth.
- **No content inspection.** No hashing, so duplicates are *potential* (same name + size). Two different files can share both, and true duplicates with different names are not found.
- **English keywords.** The keyword table is English. Diacritics are folded (`résumé` = `resume`), but other languages are not covered.

## Metadata accuracy

- **Creation date.** Shown from the filesystem birth time (`st_birthtime`). Zero/negative values are shown as "Unavailable" instead of 1970. Some filesystems (certain network shares, FAT/exFAT variants, some FUSE mounts) may report a substitute value that the app cannot distinguish from a real birth time.
- **Copied/downloaded files.** Copying or downloading usually gives a *new* creation date, so "Created" may be later than "Modified". That is accurate filesystem data, not an error.
- **Last accessed** is informational. Many systems update it lazily, or not at all.
- **Sizes** are logical sizes (`st_size`). Sparse files, compressed APFS files, and clones may use less disk space than shown.
- **Packages** (`.app`, `.key`, `.pages`, `.photoslibrary`, `.fcpbundle`, …) are single items with no size unless "Measure package sizes" is on. Package detection relies on macOS's registry of package extensions.

## Scanning

- **Symbolic links** are never followed. A link to a folder elsewhere contributes nothing beyond the link itself. Finder **aliases** are regular files on disk and are listed as such (not resolved).
- **Version-control internals** (`.git`, `.svn`, `.hg`) are not listed by default. Turn this off in Scan Options to include them.
- **Cloud folders.** iCloud/File Provider placeholder folders are not listed, to avoid triggering downloads. Their contents are missing from totals.
- **Permission-denied folders** are reported under "Skipped or inaccessible" and their contents are excluded.
- **Files that change during a scan** may be missed or reported as "Metadata unavailable".
- **Very large trees.** Records are kept in memory (roughly a few hundred bytes to ~1 KB each, so ~1M entries ≈ 1 GB). The table is virtualized, but group and suggestion views cap expanded lists (300 members / 2,000 items) and point to the Files tab for the rest.
- **Hard links** appear once per path and are counted toward the total size each time.
- **Folders on network volumes** can be slow to list. Stop Scan is always available.

## Classification edge cases

- Ties between topics go to the earlier topic (Financial → Travel → Academic → Research → Work), with confidence lowered and a review flag (e.g. `hotel invoice.pdf`).
- An extension that belongs to a strong type (archive, media, code, design, e-book, scientific data) wins over a topic keyword unless that type is typical for the topic. Topic keywords are then kept as secondary tags.
- `.m` is counted as Objective-C/MATLAB source, and `.fig`/`.ai` are only Medium confidence because those extensions are shared by unrelated apps.
- Uncategorized PDFs are common, because many PDFs have uninformative names (e.g. `scan0001.pdf`).

## Platform

- Requires macOS 13+. The core library uses Darwin APIs (`lstat`, `st_birthtimespec`, `st_flags`) and is not intended for Linux.
- The default build is not sandboxed (it runs as a normal user process). The optional `--sandbox` bundle adds OS-enforced read-only access but makes macOS create a container folder.
- `NSOpenPanel` may remember its last location in the app's preferences domain. This is system behavior (see SAFETY_REVIEW.md).
