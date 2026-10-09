#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Apple's installed libraries are behavioral references only. No Apple library
# is copied into the runner, guest, or repository.
set -eu
repo=$(cd "$(dirname "$0")/../.." && pwd)
output=${1:-"$repo/build/ios/reference"}
mkdir -p "$output"
"${IOS_CLANG:-clang}" -DIOS_KEYCHAIN_REFERENCE -fno-objc-arc -O1 -Wall -Wextra -Werror \
    -framework Security -framework Foundation "$repo/tests/ios/keychain.m" -o "$output/keychain"
"$output/keychain"
"${IOS_CLANG:-clang}" -O1 -Wall -Wextra -Werror \
    "$repo/tests/ios/common-crypto.c" -o "$output/common-crypto"
"$output/common-crypto"
"${IOS_CLANG:-clang}" -fno-objc-arc -O1 -Wall -Wextra -Werror -framework Security -framework Foundation \
    "$repo/tests/ios/security.m" -o "$output/security"
"$output/security"
"${IOS_CLANG:-clang}" -DIOS_TRUST_REFERENCE -fno-objc-arc -O1 -Wall -Wextra -Werror \
    -framework Security -framework Foundation "$repo/tests/ios/security-trust.m" -o "$output/security-trust"
"$output/security-trust"
"${IOS_CLANG:-clang}" -DIOS_PROXY_REFERENCE -fno-objc-arc -O1 -Wall -Wextra -Werror \
    -framework CFNetwork -framework Foundation "$repo/tests/ios/cfnetwork.m" -o "$output/cfnetwork"
"$output/cfnetwork"
"${IOS_CLANG:-clang}" -fobjc-arc -O1 -Wall -Wextra -Werror -framework Foundation -framework GameController \
    "$repo/tests/ios/game-constants.m" -o "$output/game-constants"
"$output/game-constants"
"${IOS_CLANG:-clang}" -O1 -Wall -Wextra -Werror -framework CoreGraphics \
    "$repo/tests/ios/geometry.c" -o "$output/geometry"
"$output/geometry"
"${IOS_CLANG:-clang}" -O1 -Wall -Wextra -Werror -framework CoreGraphics -framework CoreFoundation \
    "$repo/tests/ios/provider-images.c" -o "$output/provider-images"
"$output/provider-images"
"${IOS_CLANG:-clang}" -O1 -Wall -Wextra -Werror -framework AudioToolbox \
    "$repo/tests/ios/audio-converter.c" -o "$output/audio-converter"
"$output/audio-converter"
"${IOS_CLANG:-clang}" -O1 -Wall -Wextra -Werror -framework AudioToolbox \
    "$repo/tests/ios/audio-graph.c" -o "$output/audio-graph"
"$output/audio-graph"
"${IOS_CLANG:-clang}" -target arm64-apple-ios17.0-macabi -fobjc-arc -O1 -Wall -Wextra -Werror \
    -F"$(xcrun --show-sdk-path)/System/iOSSupport/System/Library/Frameworks" \
    -framework Foundation -framework UIKit -framework CoreGraphics \
    "$repo/tests/ios/colors.m" -o "$output/colors"
"$output/colors"
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
