#!/usr/bin/env bash
# Fetches and builds the native pieces Earshot bundles, so a user needs no Homebrew (ADR-2611141800):
#   whisper-cli   whisper.cpp, built from a pinned commit, statically linked, with Metal embedded
#   sherpa-onnx   the official macOS arm64 C library + ONNX Runtime, pinned by SHA-256
# Output goes to EarshotApp/.vendor (git-ignored). Re-running is cheap: each piece is skipped when
# the stamp file for its pinned version is already there.
#
#   bash EarshotApp/vendor.sh
#
# Needs: Xcode, cmake (brew install cmake; GitHub's macOS runners have it), and the network.
set -euo pipefail
cd "$(dirname "$0")"

WHISPER_TAG=v1.9.5
WHISPER_COMMIT=d1be6fde11ac6e0407606b4e42fe72d34add8037
SHERPA_VERSION=2.0.1
SHERPA_NAME=sherpa-onnx-v$SHERPA_VERSION-osx-arm64-shared-no-tts
SHERPA_SHA256=4fcc6c77c8d8d2e2f04cfdc17c6fd224c01469b78529370eb9d8e0e5ec97ac79

V="$(pwd)/.vendor"
mkdir -p "$V"
die() { echo "vendor: $*" >&2; exit 1; }

# MARK: whisper.cpp
if [[ "$(cat "$V/whisper.stamp" 2>/dev/null)" != "$WHISPER_COMMIT" || ! -x "$V/whisper-cli" ]]; then
  command -v cmake >/dev/null || die "cmake is needed to build whisper.cpp: brew install cmake"
  src="$V/whisper.cpp"
  rm -rf "$src" "$V/whisper-build"
  git clone --quiet --depth 1 --branch "$WHISPER_TAG" https://github.com/ggml-org/whisper.cpp.git "$src"
  got=$(git -C "$src" rev-parse HEAD)
  [[ $got == "$WHISPER_COMMIT" ]] || die "whisper.cpp $WHISPER_TAG is $got, expected $WHISPER_COMMIT"
  # Static, so the app carries one file. GGML_NATIVE=OFF: built for every Apple silicon Mac, not
  # just the build machine's chip. The Metal shaders are embedded in the binary.
  cmake -S "$src" -B "$V/whisper-build" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=26.4 \
    -DBUILD_SHARED_LIBS=OFF -DGGML_NATIVE=OFF -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON \
    -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_SERVER=OFF -DWHISPER_SDL2=OFF -DWHISPER_CURL=OFF >/dev/null
  cmake --build "$V/whisper-build" --config Release --target whisper-cli -j "$(sysctl -n hw.ncpu)" >/dev/null
  install -m 755 "$V/whisper-build/bin/whisper-cli" "$V/whisper-cli"
  # Nothing outside the OS may be linked: a Homebrew path here would work on this Mac and nowhere else.
  if otool -L "$V/whisper-cli" | tail -n +2 | grep -v -E '^\s+(/usr/lib/|/System/Library/)'; then
    die "whisper-cli links a library outside macOS (above)"
  fi
  rm -rf "$src" "$V/whisper-build"  # only the binary is needed; keeps the CI cache small
  echo "$WHISPER_COMMIT" > "$V/whisper.stamp"
  echo "vendor: whisper-cli $WHISPER_TAG built"
fi

# MARK: sherpa-onnx
if [[ "$(cat "$V/sherpa.stamp" 2>/dev/null)" != "$SHERPA_SHA256" || ! -f "$V/sherpa/lib/libonnxruntime.dylib" ]]; then
  tarball="$V/$SHERPA_NAME.tar.bz2"
  curl -fsSL -o "$tarball" \
    "https://github.com/k2-fsa/sherpa-onnx/releases/download/v$SHERPA_VERSION/$SHERPA_NAME.tar.bz2"
  got=$(shasum -a 256 "$tarball" | cut -d' ' -f1)
  [[ $got == "$SHERPA_SHA256" ]] || die "sherpa-onnx download has SHA-256 $got, expected $SHERPA_SHA256"
  rm -rf "$V/sherpa"
  mkdir -p "$V/sherpa/lib" "$V/sherpa/include"
  tar -xjf "$tarball" -C "$V" "$SHERPA_NAME/lib/libsherpa-onnx-c-api.dylib" "$SHERPA_NAME/lib/libonnxruntime.dylib" \
    "$SHERPA_NAME/include/sherpa-onnx/c-api/c-api.h"
  mv "$V/$SHERPA_NAME/lib/"*.dylib "$V/sherpa/lib/"
  mv "$V/$SHERPA_NAME/include/sherpa-onnx/c-api/c-api.h" "$V/sherpa/include/"
  rm -rf "$V/$SHERPA_NAME" "$tarball"
  echo "$SHERPA_SHA256" > "$V/sherpa.stamp"
  echo "vendor: sherpa-onnx $SHERPA_VERSION unpacked"
fi
