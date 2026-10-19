#!/bin/bash
# OPTIONAL. Wraps the release build into a double-clickable .app bundle at
# .build/ReadOnlyOrganizer.app (inside this repository). It does not install
# anything, does not touch /Applications, and does not notarize.
#
#   scripts/bundle_app.sh             # unsigned bundle (normal use)
#   scripts/bundle_app.sh --sandbox   # also ad-hoc sign with the App Sandbox
#                                     # profile in Support/ (OS-enforced
#                                     # read-only + no network)
#
# Note on --sandbox: on first launch macOS itself creates a sandbox container
# folder at ~/Library/Containers/local.readonly.fileorganizer. That is an OS
# action, not the app's; the app writes nothing there. See docs/SAFETY_REVIEW.md.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/ReadOnlyOrganizer"
APP="$REPO/.build/ReadOnlyOrganizer.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/ReadOnlyOrganizer"
cp "$REPO/Support/Info.plist" "$APP/Contents/Info.plist"

if [ "${1:-}" = "--sandbox" ]; then
  codesign --force --sign - --entitlements "$REPO/Support/ReadOnlyOrganizer.entitlements" "$APP"
  echo "Built sandboxed (ad-hoc signed) app: $APP"
else
  echo "Built app: $APP"
fi
echo "Run with: open \"$APP\""
