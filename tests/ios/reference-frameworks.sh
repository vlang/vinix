#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Apple's installed libraries are behavioral references only. No Apple library
# is copied into the runner, guest, or repository.
set -eu
repo=$(cd "$(dirname "$0")/../.." && pwd)
output=${1:-"$repo/build/ios/reference"}
mkdir -p "$output"
"${IOS_CLANG:-clang}" -O1 -Wall -Wextra -Werror -framework CoreFoundation \
    "$repo/tests/ios/core-foundation.c" -o "$output/core-foundation"
"$output/core-foundation"
"${IOS_CLANG:-clang}" -target arm64-apple-ios17.0-macabi -O1 -Wall -Wextra -Werror \
    -F"$(xcrun --show-sdk-path)/System/iOSSupport/System/Library/Frameworks" \
    -framework Foundation -framework UIKit \
    "$repo/tests/ios/framework-constants.m" -o "$output/framework-constants"
"$output/framework-constants"
"${IOS_CLANG:-clang}" -target arm64-apple-ios17.0-macabi -fobjc-arc -O1 -Wall -Wextra -Werror \
    -F"$(xcrun --show-sdk-path)/System/iOSSupport/System/Library/Frameworks" \
    -framework Foundation -framework UIKit \
    "$repo/tests/ios/accessibility.m" -o "$output/accessibility"
"$output/accessibility"
"${IOS_CLANG:-clang}" -fobjc-arc -O1 -Wall -Wextra -Werror -framework Foundation \
    "$repo/tests/ios/objc-runtime.m" -o "$output/objc-runtime"
"$output/objc-runtime"
"${IOS_CLANG:-clang}" -DIOS_ARC_REFERENCE -fno-objc-arc -O1 -Wall -Wextra -Werror \
    -framework Foundation "$repo/tests/ios/arc-registers.m" "$repo/tests/ios/arc-registers.S" \
    -o "$output/arc-registers"
"$output/arc-registers"
"${IOS_CLANG:-clang}" -target arm64-apple-ios17.0-macabi -fobjc-arc -O1 -Wall -Wextra -Werror \
    -F"$(xcrun --show-sdk-path)/System/iOSSupport/System/Library/Frameworks" \
    -framework Foundation -framework UIKit -framework CoreGraphics \
    "$repo/tests/ios/graphics.m" -o "$output/graphics-fixture"
"$output/graphics-fixture"
sh "$repo/tests/ios/reference-modules.sh" "$output"
