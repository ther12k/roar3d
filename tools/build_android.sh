#!/usr/bin/env bash
# Reproducible Android builds (RB-055).
#   tools/build_android.sh debug          -> build/roarball-debug.apk (debug keystore)
#   ROAR_KEY_PASS=pw tools/build_android.sh release -> build/roarball-release.apk
# Release signing reads keystore/roarball-release.keystore (create it with
# tools/make_release_keystore.sh); credentials arrive via env, never files
# committed to the repository.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT_BIN="${GODOT_BIN:-/home/ther12k/Tools/godot/Godot_v4.7.2-stable_linux.x86_64}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
MODE="${1:-debug}"
mkdir -p build
if [ "$MODE" = "release" ]; then
  : "${ROAR_KEY_PASS:?set ROAR_KEY_PASS (same password as make_release_keystore.sh)}"
  export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$PWD/keystore/roarball-release.keystore"
  export GODOT_ANDROID_KEYSTORE_RELEASE_USER="roarball"
  export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$ROAR_KEY_PASS"
  OUT="build/roarball-release.apk"
  FLAG="--export-release"
else
  OUT="build/roarball-debug.apk"
  FLAG="--export-debug"
fi
"$GODOT_BIN" --headless --path . $FLAG "Android" "$OUT"
echo "built: $OUT"
