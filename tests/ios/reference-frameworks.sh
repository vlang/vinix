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
