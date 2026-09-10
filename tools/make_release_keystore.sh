#!/usr/bin/env bash
# Generates the project release keystore (LOCAL ONLY — never committed).
# Usage: ROAR_KEY_PASS=your-strong-password tools/make_release_keystore.sh
# The keystore signs release builds; losing it means a new store identity,
# so back it up somewhere safe outside this repository.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${ROAR_KEY_PASS:?set ROAR_KEY_PASS to a strong password}"
mkdir -p keystore
keytool -genkeypair -v \
  -keystore keystore/roarball-release.keystore \
  -alias roarball \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass "$ROAR_KEY_PASS" -keypass "$ROAR_KEY_PASS" \
  -dname "CN=Roarball, OU=Games, O=ther12k, C=ID"
echo "keystore/roarball-release.keystore created (gitignored)"
