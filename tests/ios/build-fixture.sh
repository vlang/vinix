#!/bin/sh
set -eu
repo=$(cd "$(dirname "$0")/../.." && pwd)
output=${1:-"$repo/build/ios/fixtures"}
mkdir -p "$output"
for name in calculator unsupported; do
    "${IOS_CLANG:-clang}" -target arm64-apple-ios15.0 -nostdinc -isysroot "$output" -ffreestanding \
        -fno-stack-protector -O1 -Wall -Wextra -Werror \
        -c "$repo/tests/ios/$name.c" -o "$output/$name.o"
    "${IOS_LD:-ld64.lld}" -arch arm64 -platform_version ios 15.0 15.0 \
        -fixup_chains -e _main "$output/$name.o" "$repo/tests/ios/libSystem.tbd" \
        -o "$output/$name"
done
