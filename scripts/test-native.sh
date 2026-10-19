#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="${BUILD_ROOT:-$HOME/Library/Caches/GoldenPassport-build}"
OUTPUT="$BUILD_ROOT/native-tests"
source "$ROOT/scripts/native-build.sh"
build_native_core "$(uname -m)" "$OUTPUT" "$ROOT"
xcrun swiftc -parse-as-library -I "$OUTPUT" "$ROOT/scripts/native-smoke.swift" \
  "$ROOT/Tests/GoldenPassportCoreTests/MigrationFixtures.swift" \
  "$OUTPUT/GoldenPassportCore.o" -o "$OUTPUT/smoke"
"$OUTPUT/smoke"
