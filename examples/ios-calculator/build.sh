#!/bin/bash
# Compile a UIKit Objective-C calculator for an ARM64 iOS device.
set -euo pipefail
SOURCE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SOURCE/../.." && pwd)"
OUTPUT="${VINIX_IOS_CALCULATOR_BUILD_DIR:-$REPO/build/ios/objc}"
SDK="${IOS_SDK:-}"
if [ -z "$SDK" ] && command -v xcrun >/dev/null 2>&1; then
    SDK="$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)"
fi
mkdir -p "$OUTPUT/Calculator.app" "$OUTPUT/objects"
CLANG="${IOS_CLANG:-clang}"
COMMON=(-target arm64-apple-ios15.0 -fobjc-arc -fno-objc-exceptions -fno-exceptions
    -fno-stack-protector -O2 -Wall -Wextra -Werror)
if [ -n "$SDK" ]; then
    if [ ! -d "$SDK/System/Library/Frameworks/UIKit.framework" ]; then
        echo "ERROR: IOS_SDK is not an iPhoneOS SDK: $SDK" >&2
        exit 1
    fi
    "$CLANG" "${COMMON[@]}" -isysroot "$SDK" "$SOURCE/Calculator.m" "$SOURCE/App.m" \
        -framework Foundation -framework UIKit -o "$OUTPUT/Calculator.app/Calculator"
    printf 'iPhoneOS SDK: %s\n' "$SDK" > "$OUTPUT/build-mode.txt"
else
    # Linker stubs contain API names, never placeholder implementations. The
    # Mach-O imports the genuine iOS Foundation/UIKit/Objective-C libraries.
    for name in Calculator App; do
        "$CLANG" "${COMMON[@]}" -nostdinc -isysroot "$OUTPUT" -ffreestanding \
            -c "$SOURCE/$name.m" -o "$OUTPUT/objects/$name.o"
    done
    "${IOS_LD:-ld64.lld}" -arch arm64 -platform_version ios 15.0 15.0 \
        -fixup_chains -e _main "$OUTPUT/objects/Calculator.o" "$OUTPUT/objects/App.o" \
        "$SOURCE/api/Foundation.tbd" "$SOURCE/api/UIKit.tbd" \
        "$SOURCE/api/libobjc.tbd" "$SOURCE/api/libSystem.tbd" \
        -o "$OUTPUT/Calculator.app/Calculator"
    printf 'Minimal ABI declarations and import stubs (no iOS SDK)\n' > "$OUTPUT/build-mode.txt"
fi
cp "$SOURCE/Info.plist" "$OUTPUT/Calculator.app/Info.plist"
# An ad-hoc signature records bundle integrity. Device distribution signing
# remains a separate step using the developer's own identity/profile.
if command -v codesign >/dev/null 2>&1; then
    codesign --force --sign - --timestamp=none "$OUTPUT/Calculator.app"
    codesign --verify --strict "$OUTPUT/Calculator.app"
fi
# Package only owned bundle files, with the standard IPA Payload layout.
python3 - "$OUTPUT" <<'PY'
from pathlib import Path
import sys, zipfile
root = Path(sys.argv[1])
with zipfile.ZipFile(root / "Calculator.ipa", "w", zipfile.ZIP_DEFLATED) as archive:
    for path in sorted((root / "Calculator.app").rglob("*")):
        if path.is_file():
            archive.write(path, "Payload/" + str(path.relative_to(root)))
PY
echo "Built $OUTPUT/Calculator.app/Calculator"
echo "Packaged $OUTPUT/Calculator.ipa"
