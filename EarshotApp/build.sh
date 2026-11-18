#!/usr/bin/env bash
# Builds Earshot.app and installs it in ~/Applications, plus terminal commands for the helpers it
# runs (transcribe, speakers, earshot-speak) in ~/.local/bin. This repo is the master copy: edit
# here, then run this script.
#
# The app carries everything it runs (ADR-2611141800): whisper-cli, earshot-convert (audio/video
# decoding) and speakers (with the sherpa-onnx libraries). vendor.sh fetches and builds the native
# parts once; after that a build is just swiftc.
set -euo pipefail
cd "$(dirname "$0")"

bash vendor.sh
V="$(pwd)/.vendor"

APP="${EARSHOT_APP:-$HOME/Applications/Earshot.app}"
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT

# Every .swift file in this directory is part of the app (Tests/ is a subdirectory, so it is not
# matched). A glob, not a list: a hand-kept list silently fell behind when DictationCleanup.swift
# was added, and the app then failed to build while the typecheck gate, which globs, was green.
swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macosx26.4 \
  *.swift -o "$build/Earshot"

# The bundled command-line helpers. They sit in Contents/MacOS, where macOS expects nested code, and
# find the sherpa-onnx libraries in Contents/Frameworks.
swiftc -O -swift-version 5 -target arm64-apple-macosx26.4 \
  Tools/AudioDecode.swift Tools/convert/main.swift -o "$build/earshot-convert"
swiftc -O -swift-version 5 -target arm64-apple-macosx26.4 \
  -I "$V/sherpa/include" -import-objc-header Tools/speakers/Bridging.h \
  Tools/AudioDecode.swift Tools/SpeakerMerge.swift Tools/speakers/main.swift \
  -L "$V/sherpa/lib" -lsherpa-onnx-c-api -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -o "$build/speakers"

# The app icon is a layered Icon Composer file. actool turns it into Assets.car (Liquid Glass
# icon for macOS 26) plus Earshot.icns (fallback), as Apple's guidelines ask.
xcrun actool "$(cd ../assets && pwd)/Earshot.icon" --compile "$build" --platform macosx \
  --minimum-deployment-target 26.4 --app-icon Earshot \
  --output-partial-info-plist "$build/icon.plist" >/dev/null

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp Info.plist "$APP/Contents/Info.plist"

# Version: the release number from ../VERSION, a build number that rises with every commit, and the
# commit itself ("-dirty" when built from uncommitted changes). The app shows all three.
version=$(tr -d '[:space:]' < ../VERSION)
build_number=$(git rev-list --count HEAD 2>/dev/null || echo 0)
commit=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
git diff --quiet HEAD 2>/dev/null || commit="$commit-dirty"
plist="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" \
  -c "Set :CFBundleVersion $build_number" -c "Add :EarshotCommit string $commit" "$plist"
cp "$build/Earshot" "$APP/Contents/MacOS/Earshot"
cp "$build/Assets.car" "$build/Earshot.icns" "$APP/Contents/Resources/"
# Menu bar artwork (a template image: macOS tints it for light and dark menu bars).
cp ../assets/menubar.svg "$APP/Contents/Resources/"
# The app runs its own copy of the helpers, so an install from the DMG needs nothing else.
install -m 755 ../scripts/transcribe ../scripts/earshot-speak "$APP/Contents/Resources/"
install -m 755 "$V/whisper-cli" "$build/earshot-convert" "$build/speakers" "$APP/Contents/MacOS/"
install -m 644 "$V/sherpa/lib/libsherpa-onnx-c-api.dylib" "$V/sherpa/lib/libonnxruntime.dylib" "$APP/Contents/Frameworks/"

# Signing (ADR-2611141600). Every build uses the hardened runtime and Earshot.entitlements, so a local
# build behaves like the notarized release (a missing entitlement shows up here, not in users' hands).
#  - EARSHOT_SIGN_IDENTITY set ("Developer ID Application: Name (TEAMID)"): signed for distribution,
#    with a secure timestamp, ready for EarshotApp/notarize.sh. The Developer ID designated requirement
#    (bundle id + team) stays the same across builds by itself.
#  - Not set: signed ad hoc. Ad hoc alone makes macOS identify the app by the hash of the exact binary,
#    so every build looked like a new app and lost its Accessibility and Microphone permission. The
#    explicit designated requirement keeps the identity the same across builds.
# Nested code is signed first, inside out, each with the hardened runtime: notarization rejects an
# unsigned or runtime-less binary anywhere in the bundle. The helpers need no entitlements.
entitlements="$(pwd)/Earshot.entitlements"
nested=("$APP/Contents/Frameworks/libonnxruntime.dylib" "$APP/Contents/Frameworks/libsherpa-onnx-c-api.dylib"
        "$APP/Contents/MacOS/whisper-cli" "$APP/Contents/MacOS/earshot-convert" "$APP/Contents/MacOS/speakers")
if [[ -n ${EARSHOT_SIGN_IDENTITY:-} ]]; then
  for f in "${nested[@]}"; do
    codesign --force --options runtime --timestamp --sign "$EARSHOT_SIGN_IDENTITY" "$f"
  done
  codesign --force --options runtime --timestamp --entitlements "$entitlements" \
    --sign "$EARSHOT_SIGN_IDENTITY" "$APP"
else
  for f in "${nested[@]}"; do
    if [[ $f == */MacOS/speakers ]]; then
      # Ad hoc has no team, so library validation would refuse the bundled dylibs (see the file).
      codesign --force --options runtime --entitlements Tools/speakers/adhoc.entitlements --sign - "$f"
    else
      codesign --force --options runtime --sign - "$f"
    fi
  done
  codesign --force --options runtime --entitlements "$entitlements" \
    --sign - -r='designated => identifier "org.sticksandstrings.earshot"' "$APP"
fi
codesign --verify --strict --verbose=1 "$APP"
# Tell Finder/Launchpad about the app (and its "Open With" file types), and give the terminal the same
# commands. The commands are two-line wrappers around the app's own copies, so the terminal and the
# app always run the same version, and the helpers find their bundled tools. Not for a scratch build.
if [[ -z ${EARSHOT_APP:-} ]]; then
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
  BIN="$HOME/.local/bin"
  mkdir -p "$BIN"
  for cmd in transcribe:Resources/transcribe speakers:MacOS/speakers earshot-speak:Resources/earshot-speak; do
    name=${cmd%%:*}
    rm -f "$BIN/$name"  # replace, never write through: an old install may have left a symlink here
    printf '#!/bin/sh\nexec "%s/Contents/%s" "$@"\n' "$APP" "${cmd#*:}" > "$BIN/$name"
    chmod 755 "$BIN/$name"
  done
fi

echo "Installed: $APP (Earshot $version, build $build_number, $commit)"
