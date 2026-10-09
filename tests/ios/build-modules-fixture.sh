#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu
repo=$(cd "$(dirname "$0")/../.." && pwd)
output=${1:-"$repo/build/ios/fixtures"}
bundle="$output/Modules.app"
mkdir -p "$bundle/Frameworks/Middle.framework" "$bundle/Frameworks/Leaf.framework"
for source in modules-leaf.c modules-middle.m modules.m; do
    "${IOS_CLANG:-clang}" -target arm64-apple-ios15.0 -x objective-c -nostdinc -isysroot "$output" \
        -fno-stack-protector -fobjc-arc -fno-objc-exceptions -O1 -Wall -Wextra -Werror \
        -c "$repo/tests/ios/$source" -o "$output/$source.o"
done
"${IOS_LD:-ld64.lld}" -arch arm64 -platform_version ios 15.0 15.0 -dylib \
    -no_fixup_chains -install_name '@rpath/Leaf.framework/Leaf' \
    "$output/modules-leaf.c.o" "$repo/tests/ios/libSystem.tbd" -o "$bundle/Frameworks/Leaf.framework/Leaf"
"${IOS_LD:-ld64.lld}" -arch arm64 -platform_version ios 15.0 15.0 -dylib \
    -fixup_chains -install_name '@rpath/Middle.framework/Middle' -rpath '@loader_path/..' \
    "$output/modules-middle.m.o" "$bundle/Frameworks/Leaf.framework/Leaf" \
    "$repo/tests/ios/libSystem.tbd" "$repo/examples/ios-calculator/api/Foundation.tbd" \
    "$repo/tests/ios/startup.tbd" -o "$bundle/Frameworks/Middle.framework/Middle"
# Present at link time, absent in the guest: genuine weak-library binding.
printf 'int module_optional(void) { return 1; }\n' > "$output/modules-optional.c"
"${IOS_CLANG:-clang}" -target arm64-apple-ios15.0 -c "$output/modules-optional.c" -o "$output/modules-optional.o"
"${IOS_LD:-ld64.lld}" -arch arm64 -platform_version ios 15.0 15.0 -dylib \
    -install_name '@executable_path/Absent.dylib' "$output/modules-optional.o" -o "$output/modules-optional.dylib"
"${IOS_LD:-ld64.lld}" -arch arm64 -platform_version ios 15.0 15.0 -fixup_chains -e _main \
    -rpath '@executable_path/Frameworks' "$output/modules.m.o" \
    "$bundle/Frameworks/Middle.framework/Middle" "$bundle/Frameworks/Leaf.framework/Leaf" \
    -weak_library "$output/modules-optional.dylib" \
    "$repo/tests/ios/libSystem.tbd" "$repo/tests/ios/modules-dyld.tbd" \
    "$repo/examples/ios-calculator/api/Foundation.tbd" "$repo/tests/ios/startup.tbd" -o "$bundle/Modules"
