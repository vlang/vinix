#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Same loader/lifetime behavior checked against the installed Mac libraries.
set -eu
repo=$(cd "$(dirname "$0")/../.." && pwd)
output=${1:-"$repo/build/ios/reference"}
bundle="$output/Modules.app"
mkdir -p "$bundle/Frameworks/Leaf.framework" "$bundle/Frameworks/Middle.framework"
"${IOS_CLANG:-clang}" -x objective-c -fobjc-arc -O1 -Wall -Wextra -Werror -dynamiclib \
    -Wl,-install_name,@rpath/Leaf.framework/Leaf "$repo/tests/ios/modules-leaf.c" \
    -o "$bundle/Frameworks/Leaf.framework/Leaf"
"${IOS_CLANG:-clang}" -fobjc-arc -O1 -Wall -Wextra -Werror -dynamiclib -framework Foundation \
    -Wl,-install_name,@rpath/Middle.framework/Middle -Wl,-rpath,@loader_path/.. \
    "$repo/tests/ios/modules-middle.m" "$bundle/Frameworks/Leaf.framework/Leaf" -o "$bundle/Frameworks/Middle.framework/Middle"
printf 'int module_optional(void) { return 1; }\n' > "$output/modules-optional.c"
"${IOS_CLANG:-clang}" -dynamiclib -Wl,-install_name,@executable_path/Absent.dylib \
    "$output/modules-optional.c" -o "$output/modules-optional.dylib"
"${IOS_CLANG:-clang}" -fobjc-arc -O1 -Wall -Wextra -Werror -framework Foundation \
    -Wl,-rpath,@executable_path/Frameworks "$repo/tests/ios/modules.m" \
    "$bundle/Frameworks/Middle.framework/Middle" "$bundle/Frameworks/Leaf.framework/Leaf" \
    -Wl,-weak_library,"$output/modules-optional.dylib" -o "$bundle/Modules"
"$bundle/Modules"
