#!/bin/bash
# Records (or compares) a snapshot of a fixture folder: every entry's path,
# type, size, birth time, modification time, permissions, flags and SHA-256.
#
# The snapshot is written to Tests/Fixtures/Snapshots/ — outside the scanned
# folder — and only for folders inside Tests/Fixtures/. This script reads file
# contents to hash them; the app itself never does.
#
#   scripts/snapshot_fixture.sh record  [folder]   # before scanning
#   scripts/snapshot_fixture.sh compare [folder]   # after scanning
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-}"
TARGET="${2:-$REPO/Tests/Fixtures/Manual}"
TARGET="$(cd "$TARGET" && pwd)"
SNAPDIR="$REPO/Tests/Fixtures/Snapshots"
SNAPFILE="$SNAPDIR/$(basename "$TARGET").snapshot.txt"

case "$TARGET" in
  "$REPO"/Tests/Fixtures/*) ;;
  *) echo "Only folders inside $REPO/Tests/Fixtures may be snapshotted." >&2; exit 1 ;;
esac

take_snapshot() {
  cd "$TARGET"
  find . -print0 | LC_ALL=C sort -z | while IFS= read -r -d '' entry; do
    meta="$(stat -f '%HT|%z|%Sp|%Sf|%SB|%Sm' -t '%Y-%m-%dT%H:%M:%S' "$entry")"
    if [ -f "$entry" ] && [ ! -L "$entry" ]; then
      hash="$(shasum -a 256 "$entry" | cut -d' ' -f1)"
    elif [ -L "$entry" ]; then
      hash="link->$(readlink "$entry")"
    else
      hash="-"
    fi
    printf '%s|%s|%s\n' "$entry" "$meta" "$hash"
  done
}

case "$MODE" in
  record)
    mkdir -p "$SNAPDIR"
    take_snapshot > "$SNAPFILE"
    echo "Recorded $(wc -l < "$SNAPFILE" | tr -d ' ') entries to $SNAPFILE"
    ;;
  compare)
    [ -f "$SNAPFILE" ] || { echo "No snapshot at $SNAPFILE; run 'record' first." >&2; exit 1; }
    if diff -u "$SNAPFILE" <(take_snapshot); then
      echo "OK: no entries were created, removed, or changed."
    else
      echo "DIFFERENCE DETECTED (see diff above)." >&2
      exit 2
    fi
    ;;
  *)
    echo "usage: $0 record|compare [folder-inside-Tests/Fixtures]" >&2
    exit 64
    ;;
esac
