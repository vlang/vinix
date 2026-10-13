#!/bin/bash
# Build the pinned upstream iOS app without modifying its Objective-C sources.
set -euo pipefail
SOURCE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SOURCE/../.." && pwd)"
OUTPUT="${VINIX_IOS_2048_BUILD_DIR:-$REPO/build/ios/2048}"
REVISION=7c0840a0f7bd77b01d6a36778a253f8f4b2e6529
UPSTREAM="$OUTPUT/source"
mkdir -p "$OUTPUT/objects" "$OUTPUT/NumberTileGame.app"
if [ ! -d "$UPSTREAM/.git" ]; then
    git clone https://github.com/austinzheng/iOS-2048.git "$UPSTREAM"
fi
git -C "$UPSTREAM" checkout --detach "$REVISION"
if [ -n "$(git -C "$UPSTREAM" status --porcelain)" ]; then
    echo 'ERROR: upstream sources have local modifications' >&2
    exit 1
fi
APP="$UPSTREAM/NumberTileGame/NumberTileGame"
CLANG="${IOS_CLANG:-clang}"
objects=()
while IFS= read -r file; do
    obj="$OUTPUT/objects/$(basename "${file%.m}").o"
    "$CLANG" -target arm64-apple-ios15.0 -fobjc-arc -fblocks -fno-objc-exceptions \
        -fno-exceptions -fno-stack-protector -O2 -Wall -Wextra -Wno-unused-parameter \
        -nostdinc -ffreestanding -isysroot "$OUTPUT" -I"$SOURCE/sdk" \
        -I"$APP" -I"$APP/Models" -I"$APP/Views" -include UIKit/UIKit.h \
        -c "$file" -o "$obj"
    objects+=("$obj")
done < <(find "$APP" -name '*.m' -type f | LC_ALL=C sort)
"${IOS_LD:-ld64.lld}" -arch arm64 -platform_version ios 15.0 15.0 \
    -fixup_chains -e _main "${objects[@]}" "$SOURCE"/sdk/*.tbd \
    -o "$OUTPUT/NumberTileGame.app/NumberTileGame"
# Preserve upstream resources; substitute Xcode build variables in the plist.
"$REPO/build-support/source-tools/run" game-bundle "$APP" "$OUTPUT/NumberTileGame.app"
cp "$UPSTREAM/LICENSE" "$OUTPUT/NumberTileGame.app/LICENSE"
printf '%s\n' "$REVISION" > "$OUTPUT/NumberTileGame.app/UPSTREAM_REVISION"
if command -v codesign >/dev/null 2>&1; then
    codesign --force --sign - --timestamp=none "$OUTPUT/NumberTileGame.app"
    codesign --verify --strict "$OUTPUT/NumberTileGame.app"
fi
"$REPO/build-support/source-tools/run" ipa "$OUTPUT" NumberTileGame
echo "Built $OUTPUT/NumberTileGame.app/NumberTileGame"
