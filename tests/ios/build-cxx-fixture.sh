#!/bin/bash
# Compile standard C++ headers into an iOS ARM64 Mach-O. Only linker stubs are
# used; no Apple libraries or framework binaries are copied into Vinix.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUTPUT="${1:-$ROOT/build/ios/fixtures}"
SDK="${IOS_SDK:-$(xcrun --show-sdk-path)}"
mkdir -p "$OUTPUT"
"${IOS_CLANGXX:-clang++}" -target arm64-apple-ios15.0 -isysroot "$SDK" \
    -std=c++17 -fno-stack-protector -O1 -Wall -Wextra -Werror \
    -Wno-error=incompatible-sysroot -c "$ROOT/tests/ios/cxx.cpp" -o "$OUTPUT/cxx.o"
"${IOS_LD:-ld64.lld}" -arch arm64 -platform_version ios 15.0 15.0 \
    -no_fixup_chains -e _main "$OUTPUT/cxx.o" "$ROOT/tests/ios/libcxx.tbd" \
    "$ROOT/tests/ios/libSystem.tbd" -o "$OUTPUT/cxx"

"${IOS_CLANGXX:-clang++}" -target arm64-apple-ios15.0 -isysroot "$SDK" \
    -std=c++17 -fno-stack-protector -O1 -Wall -Wextra -Werror \
    -Wno-error=incompatible-sysroot -c "$ROOT/tests/ios/cxx-extended.cpp" -o "$OUTPUT/cxx-extended.o"
"${IOS_LD:-ld64.lld}" -arch arm64 -platform_version ios 15.0 15.0 \
    -no_fixup_chains -e _main "$OUTPUT/cxx-extended.o" "$ROOT/tests/ios/libcxx.tbd" \
    "$ROOT/tests/ios/libSystem.tbd" -o "$OUTPUT/cxx-extended"

"${IOS_CLANGXX:-clang++}" -target arm64-apple-ios15.0 -isysroot "$SDK" \
    -std=c++17 -fobjc-arc -fno-objc-exceptions -fno-exceptions -fno-stack-protector \
    -O1 -Wall -Wextra -Werror -Wno-error=incompatible-sysroot \
    -c "$ROOT/tests/ios/startup.mm" -o "$OUTPUT/startup.o"
"${IOS_LD:-ld64.lld}" -arch arm64 -platform_version ios 15.0 15.0 \
    -no_fixup_chains -e _main "$OUTPUT/startup.o" "$ROOT/tests/ios/libcxx.tbd" \
    "$ROOT/tests/ios/libSystem.tbd" "$ROOT/tests/ios/startup.tbd" \
    "$ROOT/examples/ios-calculator/api/Foundation.tbd" "$ROOT/tests/ios/GameController.tbd" \
    "$ROOT/tests/ios/CoreLocation.tbd" -o "$OUTPUT/startup"
