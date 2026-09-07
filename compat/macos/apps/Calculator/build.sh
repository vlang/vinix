#!/bin/sh
# Build a dependency-free AArch64 Mach-O. All imported Objective-C and AppKit
# symbols are supplied by Vinix's V compatibility runtime.
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$here/../../.." && pwd)
output=${1:-"$root/build/macos/Calculator.app"}
object="$output/Contents/MacOS/Calculator.o"
executable="$output/Contents/MacOS/Calculator"
cc=${CLANG:-clang}

mkdir -p "$output/Contents/MacOS"
cp "$here/Info.plist" "$output/Contents/Info.plist"

"$cc" -target arm64-apple-macos11 -fobjc-runtime=macosx-11.0 \
    -fno-objc-arc -fno-stack-protector -O1 -fno-pic \
    -I "$root/compat/macos/include" -c "$here/main.m" -o "$object"

# Apple's linker records the real framework ordinals when an SDK is present.
# On non-macOS builders ld64.lld can emit the same classic fixup format with
# flat imports; Vinix resolves those imports by symbol name in either case.
if [ "${VINIX_MACHO_LINKER:-auto}" != lld ] && [ "$(uname -s)" = Darwin ]; then
    "$cc" -target arm64-apple-macos11 -Wl,-e,_main -Wl,-no_fixup_chains \
        -Wl,-bind_at_load "$object" -framework Cocoa -o "$executable"
else
    ld64=${LD64_LLD:-$(command -v ld64.lld || true)}
    [ -n "$ld64" ] || {
        echo 'ERROR: building Calculator.app off macOS requires ld64.lld' >&2
        exit 1
    }
    "$ld64" -arch arm64 -platform_version macos 11.0 14.0 -e _main \
        -undefined dynamic_lookup -no_fixup_chains "$object" -o "$executable"
fi
rm -f "$object"
chmod +x "$executable"
echo "$executable"
