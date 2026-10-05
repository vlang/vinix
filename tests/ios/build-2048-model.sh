#!/bin/bash
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
OUTPUT="${VINIX_IOS_2048_BUILD_DIR:-$REPO/build/ios/2048}"
UPSTREAM="$OUTPUT/source/NumberTileGame"
if [ ! -f "$UPSTREAM/NumberTileGame/Models/F3HGameModel.m" ]; then
    echo 'Build examples/ios-2048/build.sh first' >&2; exit 1
fi
objects=()
for file in "$UPSTREAM/NumberTileGameTests/F3HModelTests.m" "$REPO/tests/ios/2048-model.m"; do
    obj="$OUTPUT/objects/$(basename "${file%.m}").o"
    "${IOS_CLANG:-clang}" -target arm64-apple-ios15.0 -fobjc-arc -fblocks \
        -fno-objc-exceptions -fno-exceptions -fno-stack-protector -O2 \
        -nostdinc -ffreestanding -isysroot "$OUTPUT" -I"$REPO/tests/ios/sdk" \
        -I"$REPO/examples/ios-2048/sdk" -I"$UPSTREAM/NumberTileGame/Models" \
        -c "$file" -o "$obj"
    objects+=("$obj")
done
for name in F3HGameModel F3HTileModel F3HMergeTile F3HMoveOrder F3HQueueCommand; do
    objects+=("$OUTPUT/objects/$name.o")
done
"${IOS_LD:-ld64.lld}" -arch arm64 -platform_version ios 15.0 15.0 -fixup_chains \
    -e _main "${objects[@]}" "$REPO/examples/ios-2048/sdk/"*.tbd -o "$OUTPUT/model-tests"
