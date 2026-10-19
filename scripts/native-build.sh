#!/bin/bash
# Shared compiler path for macOS Command Line Tools without an Xcode platform.
# Source this file from the build or smoke-test scripts.
build_native_core() {
  local arch="$1" output="$2" root="$3"
  mkdir -p "$output"
  xcrun swiftc -O -whole-module-optimization -parse-as-library \
    -emit-object -emit-module -module-name GoldenPassportCore \
    -target "$arch-apple-macosx13.0" \
    "$root"/Sources/GoldenPassportCore/*.swift \
    -o "$output/GoldenPassportCore.o" \
    -emit-module-path "$output/GoldenPassportCore.swiftmodule"
}

build_native_app() {
  local arch="$1" output="$2" root="$3"
  build_native_core "$arch" "$output" "$root"
  xcrun swiftc -O -parse-as-library -module-name GoldenPassport \
    -target "$arch-apple-macosx13.0" -I "$output" \
    "$root"/Sources/GoldenPassport/*.swift "$output/GoldenPassportCore.o" \
    -o "$output/GoldenPassport"
}
