#!/bin/bash
# Creates a synthetic folder for manual verification at Tests/Fixtures/Manual.
# Writes ONLY inside this repository. Never point it anywhere else.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$REPO/Tests/Fixtures/Manual"

case "$DEST" in
  "$REPO"/Tests/Fixtures/*) ;;
  *) echo "Refusing to write outside the repository fixture folder: $DEST" >&2; exit 1 ;;
esac

if [ -e "$DEST" ]; then
  echo "$DEST already exists. Remove it first if you want a fresh fixture." >&2
  exit 1
fi

mkfile_bytes() { # path bytes
  mkdir -p "$(dirname "$DEST/$1")"
  head -c "$2" /dev/zero | tr '\0' 'a' > "$DEST/$1"
}

mkfile_bytes "Financial/invoice 2024-03.pdf" 2048
mkfile_bytes "Financial/2023 W-2.pdf" 1024
mkfile_bytes "Financial/budget.xlsx" 4096
mkfile_bytes "Financial/statement.pdf" 512
mkfile_bytes "Travel/boarding pass SFO-JFK.pdf" 900
mkfile_bytes "Travel/Hotel Reservation.eml" 300
mkfile_bytes "School/Lecture 3 slides.pdf" 5000
mkfile_bytes "School/pset3_solutions.pdf" 1200
mkfile_bytes "Research/thesis.docx" 7000
mkfile_bytes "Research/thesis_final.docx" 7100
mkfile_bytes "Research/thesis_final_v2.docx" 7200
mkfile_bytes "Research/reads.fastq" 10000
mkfile_bytes "Research/experiment_results.csv" 800
mkfile_bytes "Career/Résumé Jane Doe.pdf" 1500
mkfile_bytes "Career/Cover Letter - Acme.docx" 1300
mkfile_bytes "Photos/IMG_0001.HEIC" 3000
mkfile_bytes "Photos/IMG_0002.HEIC" 3000
mkfile_bytes "Photos/IMG_0003.HEIC" 3000
mkfile_bytes "Photos/Screenshot 2024-05-01 at 10.15.00.png" 700
mkfile_bytes "Media/lecture.mp4" 20000
mkfile_bytes "Downloads/report.docx" 2500
mkfile_bytes "Downloads/report.pdf" 2600
mkfile_bytes "Downloads/photo.jpg" 4444
mkfile_bytes "Old/photo.jpg" 4444
mkfile_bytes "Old/photo (1).jpg" 4444
mkfile_bytes "Downloads/archive.tar.gz" 6000
mkfile_bytes "Downloads/mystery.xyz" 10
mkfile_bytes "Downloads/movie.mp4.crdownload" 10
mkfile_bytes "Notes/meeting notes.txt" 100
mkfile_bytes "Notes/emoji 🗂️ name.md" 100
mkfile_bytes "project/package.json" 50
mkfile_bytes "project/src/index.js" 80
mkfile_bytes "project/README.md" 40
mkfile_bytes ".hidden-config" 5
mkdir -p "$DEST/Tool.app/Contents"
mkfile_bytes "Tool.app/Contents/Info.plist" 60
# A link that points outside the fixture; the app must not follow it.
ln -s "$REPO/Sources" "$DEST/link-outside"
ln -s "." "$DEST/link-loop"

echo "Created synthetic fixture at: $DEST"
