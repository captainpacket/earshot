#!/usr/bin/env bash
# Packs a built Earshot.app into a drag-to-Applications disk image.
#   bash EarshotApp/make-dmg.sh [APP] [OUT]
# APP defaults to the one build.sh installs; OUT defaults to Earshot-<version>.dmg in the current directory.
set -euo pipefail

APP="${1:-$HOME/Applications/Earshot.app}"
[ -d "$APP" ] || { echo "No app at $APP. Run EarshotApp/build.sh first." >&2; exit 1; }
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
OUT="${2:-Earshot-$version.dmg}"

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

# The window shows the app next to an Applications shortcut: drag one onto the other to install.
ditto "$APP" "$stage/Earshot.app"
ln -s /Applications "$stage/Applications"

rm -f "$OUT"
hdiutil create -volname "Earshot $version" -srcfolder "$stage" -fs APFS -format UDZO -ov "$OUT" >/dev/null
hdiutil verify "$OUT" >/dev/null

# A Developer ID build signs the disk image too, so notarize.sh can notarize and staple it
# (ADR-2611141600). The app inside must already be signed with the same identity by build.sh.
if [[ -n ${EARSHOT_SIGN_IDENTITY:-} ]]; then
  codesign --force --timestamp --sign "$EARSHOT_SIGN_IDENTITY" "$OUT"
  codesign --verify --strict "$OUT"
  echo "Signed: $OUT. Next: bash EarshotApp/notarize.sh $OUT"
fi

echo "Created: $OUT"
