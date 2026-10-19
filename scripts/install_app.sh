#!/bin/bash
# Builds the app, installs it to ~/Applications, and pins it to your Dock.
#
#   scripts/install_app.sh              # install + add to Dock
#   scripts/install_app.sh --no-dock    # install only
#   scripts/install_app.sh --sandbox    # install the App Sandbox build (see docs/SAFETY_REVIEW.md)
#   scripts/install_app.sh --uninstall  # remove from ~/Applications (Dock tile: drag it out)
#
# What it changes on your Mac (nothing else):
#   - ~/Applications/Read-Only File Organizer.app   (created or replaced)
#   - your Dock's app list (one tile added, via `defaults write com.apple.dock`,
#     then the Dock is restarted so the tile appears)
# No sudo, no /Applications, no network, no login items.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_ID="local.readonly.fileorganizer"
DEST_DIR="$HOME/Applications"
DEST="$DEST_DIR/Read-Only File Organizer.app"

ADD_TO_DOCK=1
SANDBOX=""
for arg in "$@"; do
  case "$arg" in
    --no-dock) ADD_TO_DOCK=0 ;;
    --sandbox) SANDBOX="--sandbox" ;;
    --uninstall)
      if [ -d "$DEST" ] && [ "$(defaults read "$DEST/Contents/Info" CFBundleIdentifier 2>/dev/null)" = "$BUNDLE_ID" ]; then
        rm -rf "$DEST"
        echo "Removed $DEST. If a Dock tile remains, drag it out of the Dock."
      else
        echo "Nothing to remove at $DEST."
      fi
      exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 64 ;;
  esac
done

"$REPO/scripts/bundle_app.sh" $SANDBOX
BUILT="$REPO/.build/ReadOnlyOrganizer.app"

# Only ever replace a previous copy of this same app.
if [ -e "$DEST" ]; then
  if [ "$(defaults read "$DEST/Contents/Info" CFBundleIdentifier 2>/dev/null)" != "$BUNDLE_ID" ]; then
    echo "Refusing to overwrite $DEST: it is not this app." >&2
    exit 1
  fi
  rm -rf "$DEST"
fi
mkdir -p "$DEST_DIR"
cp -R "$BUILT" "$DEST"

# Local ad-hoc signature so macOS treats the bundle as one consistent app.
# (The --sandbox build is already signed with its entitlements.)
if [ -z "$SANDBOX" ]; then
  codesign --force --sign - "$DEST"
fi
echo "Installed: $DEST"

if [ "$ADD_TO_DOCK" = 1 ]; then
  URL="file://$(printf '%s' "$DEST" | sed 's/ /%20/g')/"
  if defaults read com.apple.dock persistent-apps 2>/dev/null | grep -q "Read-Only%20File%20Organizer.app"; then
    echo "Already in the Dock."
  else
    defaults write com.apple.dock persistent-apps -array-add \
      "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>$URL</string><key>_CFURLStringType</key><integer>15</integer></dict></dict></dict>"
    killall Dock
    echo "Added to the Dock."
  fi
fi
echo "Open it from the Dock, Launchpad, or: open \"$DEST\""
