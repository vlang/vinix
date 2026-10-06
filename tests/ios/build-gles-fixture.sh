#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUTPUT="${1:-$ROOT/build/ios/fixtures}"
SDK="${IOS_SDK:-$(xcrun --show-sdk-path)}"
MESA_SYSROOT="${VINIX_IOS_MESA_SYSROOT:-$ROOT/build-aarch64-x11/sysroot}"
mkdir -p "$OUTPUT"
"${IOS_CLANG:-clang}" -target arm64-apple-ios15.0 -isysroot "$SDK" \
    -I"$MESA_SYSROOT/usr/include" -fobjc-arc -fno-objc-exceptions -fno-stack-protector \
    -O1 -Wall -Wextra -Werror -Wno-error=incompatible-sysroot \
    -c "$ROOT/tests/ios/gles.m" -o "$OUTPUT/gles.o"
"${IOS_LD:-ld64.lld}" -arch arm64 -platform_version ios 15.0 15.0 \
    -no_fixup_chains -e _main "$OUTPUT/gles.o" "$ROOT/tests/ios/libSystem.tbd" \
    "$ROOT/tests/ios/startup.tbd" "$ROOT/examples/ios-calculator/api/Foundation.tbd" \
    "$ROOT/examples/ios-calculator/api/UIKit.tbd" "$ROOT/tests/ios/OpenGLES.tbd" \
    "$ROOT/tests/ios/GLKit.tbd" -o "$OUTPUT/gles"

"${IOS_CLANG:-clang}" -target arm64-apple-ios15.0 -isysroot "$SDK" \
    -I"$MESA_SYSROOT/usr/include" -fobjc-arc -fno-objc-exceptions -fno-stack-protector \
    -O1 -Wall -Wextra -Werror -Wno-error=incompatible-sysroot \
    -c "$ROOT/tests/ios/gles-app.m" -o "$OUTPUT/gles-app.o"
"${IOS_LD:-ld64.lld}" -arch arm64 -platform_version ios 15.0 15.0 \
    -no_fixup_chains -e _main "$OUTPUT/gles-app.o" "$ROOT/tests/ios/libSystem.tbd" \
    "$ROOT/tests/ios/startup.tbd" "$ROOT/examples/ios-calculator/api/Foundation.tbd" \
    "$ROOT/examples/ios-calculator/api/UIKit.tbd" "$ROOT/tests/ios/OpenGLES.tbd" \
    "$ROOT/tests/ios/GLKit.tbd" "$ROOT/tests/ios/QuartzCore.tbd" -o "$OUTPUT/gles-app"

mkdir -p "$OUTPUT/TextFixture.app"
"${IOS_CLANG:-clang}" -target arm64-apple-ios15.0 -isysroot "$SDK" \
    -fobjc-arc -fno-objc-exceptions -fno-stack-protector -O1 -Wall -Wextra -Werror \
    -Wno-error=incompatible-sysroot -c "$ROOT/tests/ios/text.m" -o "$OUTPUT/text.o"
"${IOS_LD:-ld64.lld}" -arch arm64 -platform_version ios 15.0 15.0 \
    -no_fixup_chains -e _main "$OUTPUT/text.o" "$ROOT/tests/ios/libSystem.tbd" \
    "$ROOT/tests/ios/startup.tbd" "$ROOT/examples/ios-calculator/api/Foundation.tbd" \
    "$ROOT/examples/ios-calculator/api/UIKit.tbd" "$ROOT/tests/ios/CoreText.tbd" \
    "$ROOT/tests/ios/CoreFoundation.tbd" "$ROOT/tests/ios/CoreGraphics.tbd" \
    -o "$OUTPUT/TextFixture.app/TextFixture"

"${IOS_CLANG:-clang}" -target arm64-apple-ios15.0 -isysroot "$SDK" \
    -fno-stack-protector -O1 -Wall -Wextra -Werror -Wno-error=incompatible-sysroot \
    -c "$ROOT/tests/ios/compression.c" -o "$OUTPUT/compression.o"
"${IOS_LD:-ld64.lld}" -arch arm64 -platform_version ios 15.0 15.0 \
    -no_fixup_chains -e _main "$OUTPUT/compression.o" "$ROOT/tests/ios/libSystem.tbd" \
    "$ROOT/tests/ios/zlib.tbd" -o "$OUTPUT/compression"
