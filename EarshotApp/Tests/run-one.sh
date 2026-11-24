#!/usr/bin/env bash
# Runs one spec test: run-one.sh <test file> <scenario>. The test file's first lines name its sources:
#   // sources: CallAudio.swift
# The test binary runs only the named scenario and exits non-zero if it fails or no such scenario exists.
set -euo pipefail
file="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"; name="$2"
cd "$(dirname "$0")/.."
src=$(sed -n 's|^// sources: *||p' "$file" | head -1)
[[ -n "$src" ]] || { echo "no '// sources:' line in $file" >&2; exit 2; }
out=$(mktemp -d); trap 'rm -rf "$out"' EXIT
# shellcheck disable=SC2086
swiftc -O -swift-version 5 -target arm64-apple-macosx26.4 -parse-as-library $src "$file" -o "$out/t"
"$out/t" "$name"
