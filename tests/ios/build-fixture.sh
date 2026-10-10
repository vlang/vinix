#!/bin/sh
set -eu
repo=$(cd "$(dirname "$0")/../.." && pwd)
output=${1:-"$repo/build/ios/fixtures"}
mkdir -p "$output"
sh "$repo/tests/ios/build-modules-fixture.sh" "$output"
for name in calculator unsupported lifecycle exit-handlers pointer-tags common-crypto atomic-queue assertions libsystem-safety runes sockets numeric nan poll permissions fcntl netdb interfaces system-queries process proc-memory atfork ioctl calendar; do
    "${IOS_CLANG:-clang}" -target arm64-apple-ios15.0 -nostdinc -isysroot "$output" -ffreestanding \
        -fno-stack-protector -O1 -Wall -Wextra -Werror \
        -c "$repo/tests/ios/$name.c" -o "$output/$name.o"
    "${IOS_LD:-ld64.lld}" -arch arm64 -platform_version ios 15.0 15.0 \
        -fixup_chains -e _main "$output/$name.o" "$repo/tests/ios/libSystem.tbd" \
        -o "$output/$name"
done
"${IOS_CLANG:-clang}" -target arm64-apple-ios15.0 -nostdinc -isysroot "$output" -ffreestanding \
    -fblocks -fno-stack-protector -O1 -Wall -Wextra -Werror \
    -c "$repo/tests/ios/dispatch.c" -o "$output/dispatch.o"
"${IOS_LD:-ld64.lld}" -arch arm64 -platform_version ios 15.0 15.0 \
    -fixup_chains -e _main "$output/dispatch.o" "$repo/tests/ios/libSystem.tbd" -o "$output/dispatch"
# -ffreestanding disables Darwin's compiler-generated stack checks. Compile
# this fixture with hosted code generation so it actually imports the helper.
"${IOS_CLANG:-clang}" -target arm64-apple-ios15.0 -nostdinc -isysroot "$output" \
    -fno-stack-protector -O1 -Wall -Wextra -Werror \
    -c "$repo/tests/ios/stack-probe.c" -o "$output/stack-probe.o"
"${IOS_LD:-ld64.lld}" -arch arm64 -platform_version ios 15.0 15.0 \
    -fixup_chains -e _main "$output/stack-probe.o" "$repo/tests/ios/libSystem.tbd" \
    -o "$output/stack-probe"
"${IOS_CLANG:-clang}" -target arm64-apple-ios15.0 -nostdinc -isysroot "$output" \
    -fno-objc-arc -fno-objc-exceptions -fno-stack-protector -O1 -Wall -Wextra -Werror \
    -c "$repo/tests/ios/cfnetwork.m" -o "$output/cfnetwork.o"
"${IOS_LD:-ld64.lld}" -arch arm64 -platform_version ios 15.0 15.0 \
    -fixup_chains -e _main "$output/cfnetwork.o" "$repo/tests/ios/libSystem.tbd" \
    "$repo/tests/ios/startup.tbd" "$repo/tests/ios/core-foundation.tbd" "$repo/tests/ios/cfnetwork.tbd" -o "$output/cfnetwork"
for name in audio-converter audio-graph; do
    "${IOS_CLANG:-clang}" -target arm64-apple-ios15.0 -nostdinc -isysroot "$output" -ffreestanding \
        -fno-stack-protector -O1 -Wall -Wextra -Werror \
        -c "$repo/tests/ios/$name.c" -o "$output/$name.o"
    "${IOS_LD:-ld64.lld}" -arch arm64 -platform_version ios 15.0 15.0 \
        -fixup_chains -e _main "$output/$name.o" "$repo/tests/ios/libSystem.tbd" \
        "$repo/tests/ios/audio.tbd" -o "$output/$name"
done
# Exercise the same arithmetic image through the older dyld opcode format.
"${IOS_LD:-ld64.lld}" -arch arm64 -platform_version ios 15.0 15.0 \
    -no_fixup_chains -e _main "$output/calculator.o" "$repo/tests/ios/libSystem.tbd" \
    -o "$output/calculator-legacy"
"${IOS_LD:-ld64.lld}" -arch arm64 -platform_version ios 15.0 15.0 \
    -no_fixup_chains -e _main "$output/pointer-tags.o" "$repo/tests/ios/libSystem.tbd" \
    -o "$output/pointer-tags-legacy"
"${IOS_CLANG:-clang}" -target arm64-apple-ios15.0 -nostdinc -isysroot "$output" -ffreestanding \
    -fno-stack-protector -O1 -Wall -Wextra -Werror -c "$repo/tests/ios/lazy.c" -o "$output/lazy.o"
"${IOS_LD:-ld64.lld}" -arch arm64 -platform_version ios 15.0 15.0 \
    -no_fixup_chains -e _main "$output/lazy.o" "$repo/tests/ios/libSystem.tbd" \
    "$repo/tests/ios/lazy.tbd" -o "$output/lazy"
SDK="${IOS_SDK:-$(xcrun --show-sdk-path)}"
for name in security keychain security-trust; do
    "${IOS_CLANG:-clang}" -target arm64-apple-ios15.0 -nostdinc -isysroot "$output" \
        -fno-objc-arc -fno-objc-exceptions -fno-stack-protector -O1 -Wall -Wextra -Werror \
        -c "$repo/tests/ios/$name.m" -o "$output/$name.o"
    "${IOS_LD:-ld64.lld}" -arch arm64 -platform_version ios 15.0 15.0 \
        -fixup_chains -e _main "$output/$name.o" "$repo/tests/ios/libSystem.tbd" \
        "$repo/tests/ios/startup.tbd" "$repo/tests/ios/core-foundation.tbd" "$repo/tests/ios/security.tbd" -o "$output/$name"
done
"${IOS_CLANG:-clang}" -target arm64-apple-ios15.0 -nostdinc -isysroot "$output" \
    -fobjc-arc -fno-objc-exceptions -fno-stack-protector -O1 -Wall -Wextra -Werror \
    -c "$repo/tests/ios/game-constants.m" -o "$output/game-constants.o"
"${IOS_LD:-ld64.lld}" -arch arm64 -platform_version ios 15.0 15.0 \
    -fixup_chains -e _main "$output/game-constants.o" "$repo/tests/ios/libSystem.tbd" \
    "$repo/tests/ios/startup.tbd" "$repo/tests/ios/game-constants.tbd" -o "$output/game-constants"
"${IOS_CLANG:-clang}" -target arm64-apple-ios15.0 -nostdinc -isysroot "$output" -ffreestanding \
    -fno-stack-protector -O1 -Wall -Wextra -Werror \
    -c "$repo/tests/ios/geometry.c" -o "$output/geometry.o"
"${IOS_LD:-ld64.lld}" -arch arm64 -platform_version ios 15.0 15.0 \
    -fixup_chains -e _main "$output/geometry.o" "$repo/tests/ios/libSystem.tbd" \
    "$repo/tests/ios/geometry.tbd" -o "$output/geometry"
"${IOS_CLANG:-clang}" -target arm64-apple-ios15.0 -nostdinc -isysroot "$output" -ffreestanding \
    -fno-stack-protector -O1 -Wall -Wextra -Werror \
    -c "$repo/tests/ios/provider-images.c" -o "$output/provider-images.o"
"${IOS_LD:-ld64.lld}" -arch arm64 -platform_version ios 15.0 15.0 \
    -fixup_chains -e _main "$output/provider-images.o" "$repo/tests/ios/libSystem.tbd" \
    "$repo/tests/ios/core-foundation.tbd" "$repo/tests/ios/graphics-core.tbd" \
    "$repo/tests/ios/provider-images.tbd" -o "$output/provider-images"
"${IOS_CLANG:-clang}" -target arm64-apple-ios15.0 -nostdinc -isysroot "$output" \
    -fobjc-arc -fno-objc-exceptions -fno-stack-protector -O1 -Wall -Wextra -Werror \
    -c "$repo/tests/ios/colors.m" -o "$output/colors.o"
"${IOS_LD:-ld64.lld}" -arch arm64 -platform_version ios 15.0 15.0 \
    -fixup_chains -e _main "$output/colors.o" "$repo/tests/ios/libSystem.tbd" \
    "$repo/tests/ios/startup.tbd" "$repo/tests/ios/graphics-core.tbd" "$repo/tests/ios/colors.tbd" \
    "$repo/examples/ios-calculator/api/UIKit.tbd" -o "$output/colors"
"${IOS_CLANG:-clang}" -target arm64-apple-ios15.0 -nostdinc -isysroot "$output" \
    -fobjc-arc -fno-objc-exceptions -fno-stack-protector -O1 -Wall -Wextra -Werror \
    -c "$repo/tests/ios/graphics.m" -o "$output/graphics.o"
"${IOS_LD:-ld64.lld}" -arch arm64 -platform_version ios 15.0 15.0 \
    -fixup_chains -e _main "$output/graphics.o" "$repo/tests/ios/libSystem.tbd" \
    "$repo/tests/ios/startup.tbd" "$repo/tests/ios/graphics.tbd" "$repo/tests/ios/graphics-core.tbd" \
    "$repo/tests/ios/core-foundation.tbd" "$repo/examples/ios-calculator/api/Foundation.tbd" -o "$output/graphics"
"${IOS_CLANG:-clang}" -target arm64-apple-ios15.0 -nostdinc -isysroot "$output" \
    -fno-objc-arc -fno-objc-exceptions -fno-stack-protector -O1 -Wall -Wextra -Werror \
    -c "$repo/tests/ios/arc-registers.m" -o "$output/arc-registers.o"
"${IOS_CLANG:-clang}" -target arm64-apple-ios15.0 \
    -c "$repo/tests/ios/arc-registers.S" -o "$output/arc-registers-abi.o"
"${IOS_LD:-ld64.lld}" -arch arm64 -platform_version ios 15.0 15.0 \
    -fixup_chains -e _main "$output/arc-registers.o" "$output/arc-registers-abi.o" \
    "$repo/tests/ios/libSystem.tbd" "$repo/tests/ios/startup.tbd" "$repo/tests/ios/arc-registers.tbd" \
    "$repo/examples/ios-calculator/api/Foundation.tbd" -o "$output/arc-registers"
"${IOS_CLANG:-clang}" -target arm64-apple-ios15.0 -nostdinc -isysroot "$output" \
    -fobjc-arc -fno-objc-exceptions -fno-stack-protector -O1 -Wall -Wextra -Werror \
    -c "$repo/tests/ios/objc-runtime.m" -o "$output/objc-runtime.o"
"${IOS_LD:-ld64.lld}" -arch arm64 -platform_version ios 15.0 15.0 \
    -fixup_chains -e _main "$output/objc-runtime.o" "$repo/tests/ios/libSystem.tbd" \
    "$repo/tests/ios/startup.tbd" "$repo/tests/ios/objc-runtime.tbd" \
    "$repo/examples/ios-calculator/api/Foundation.tbd" -o "$output/objc-runtime"
"${IOS_CLANG:-clang}" -target arm64-apple-ios15.0 -nostdinc -isysroot "$output" \
    -fobjc-arc -fno-objc-exceptions -fno-stack-protector -O1 -Wall -Wextra -Werror \
    -c "$repo/tests/ios/accessibility.m" -o "$output/accessibility.o"
"${IOS_LD:-ld64.lld}" -arch arm64 -platform_version ios 15.0 15.0 \
    -fixup_chains -e _main "$output/accessibility.o" "$repo/tests/ios/libSystem.tbd" \
    "$repo/tests/ios/startup.tbd" "$repo/examples/ios-calculator/api/Foundation.tbd" \
    "$repo/tests/ios/accessibility.tbd" -o "$output/accessibility"
"${IOS_CLANG:-clang}" -target arm64-apple-ios15.0 -nostdinc -isysroot "$output" -ffreestanding \
    -fno-stack-protector -O1 -Wall -Wextra -Werror \
    -c "$repo/tests/ios/core-foundation.c" -o "$output/core-foundation.o"
"${IOS_LD:-ld64.lld}" -arch arm64 -platform_version ios 15.0 15.0 \
    -fixup_chains -e _main "$output/core-foundation.o" "$repo/tests/ios/libSystem.tbd" \
    "$repo/tests/ios/core-foundation.tbd" -o "$output/core-foundation"
"${IOS_CLANG:-clang}" -target arm64-apple-ios15.0 -nostdinc -isysroot "$output" \
    -fno-objc-exceptions -fno-stack-protector -O1 -Wall -Wextra -Werror \
    -c "$repo/tests/ios/framework-constants.m" -o "$output/framework-constants.o"
"${IOS_LD:-ld64.lld}" -arch arm64 -platform_version ios 15.0 15.0 \
    -fixup_chains -e _main "$output/framework-constants.o" "$repo/tests/ios/libSystem.tbd" \
    "$repo/tests/ios/startup.tbd" "$repo/tests/ios/objc-runtime.tbd" \
    "$repo/tests/ios/framework-constants.tbd" -o "$output/framework-constants"
"${IOS_CLANG:-clang}" -target arm64-apple-ios15.0 -isysroot "$SDK" -D_FORTIFY_SOURCE=0 \
    -fno-stack-protector -O1 -Wall -Wextra -Werror -Wno-error=incompatible-sysroot \
    -c "$repo/tests/ios/stdio.c" -o "$output/stdio.o"
"${IOS_LD:-ld64.lld}" -arch arm64 -platform_version ios 15.0 15.0 \
    -no_fixup_chains -e _main "$output/stdio.o" "$repo/tests/ios/libSystem.tbd" -o "$output/stdio"

mkdir -p "$output/SceneFixture.app"
"${IOS_CLANG:-clang}" -target arm64-apple-ios15.0 -nostdinc -isysroot "$output" \
    -fobjc-arc -fno-objc-exceptions -fno-stack-protector -O1 -Wall -Wextra -Werror \
    -c "$repo/tests/ios/scene.m" -o "$output/scene.o"
"${IOS_LD:-ld64.lld}" -arch arm64 -platform_version ios 15.0 15.0 \
    -no_fixup_chains -e _main "$output/scene.o" "$repo/tests/ios/libSystem.tbd" \
    "$repo/tests/ios/startup.tbd" "$repo/examples/ios-calculator/api/Foundation.tbd" \
    "$repo/examples/ios-calculator/api/UIKit.tbd" -o "$output/SceneFixture.app/SceneFixture"
cp "$repo/tests/ios/scene.plist" "$output/SceneFixture.app/Info.plist"

"${IOS_CLANG:-clang}" -target arm64-apple-ios15.0 -isysroot "$SDK" \
    -fobjc-arc -fno-objc-exceptions -fno-stack-protector -O1 -Wall -Wextra -Werror \
    -Wno-error=incompatible-sysroot -c "$repo/tests/ios/arc-threads.m" -o "$output/arc-threads.o"
"${IOS_LD:-ld64.lld}" -arch arm64 -platform_version ios 15.0 15.0 \
    -no_fixup_chains -e _main "$output/arc-threads.o" "$repo/tests/ios/libSystem.tbd" \
    "$repo/tests/ios/startup.tbd" "$repo/examples/ios-calculator/api/Foundation.tbd" -o "$output/arc-threads"

"${IOS_CLANG:-clang}" -target arm64-apple-ios15.0 -isysroot "$SDK" \
    -fno-stack-protector -O1 -Wall -Wextra -Werror -Wno-error=incompatible-sysroot \
    -c "$repo/tests/ios/mach-memory.c" -o "$output/mach-memory.o"
"${IOS_LD:-ld64.lld}" -arch arm64 -platform_version ios 15.0 15.0 \
    -no_fixup_chains -e _main "$output/mach-memory.o" "$repo/tests/ios/libSystem.tbd" \
    -o "$output/mach-memory"
