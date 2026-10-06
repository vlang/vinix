#!/bin/bash
# Build the native Vinix PlayStation frontend and pinned PCSX-ReARMed core.
set -euo pipefail
WITH_HOMEBREW=1
CORE_ONLY=0
for option in "$@"; do
    case "$option" in
        --with-homebrew) WITH_HOMEBREW=1 ;;
        --without-homebrew) WITH_HOMEBREW=0 ;;
        --core-only) CORE_ONLY=1 ;;
        --help|-h)
            echo 'Usage: scripts/build-ps1-aarch64.sh [--without-homebrew] [--core-only]'
            exit 0 ;;
        *) echo "ERROR: unknown option: $option" >&2; exit 2 ;;
    esac
done
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="${VINIX_PS1_BUILD_DIR:-$SCRIPT_DIR/build/ps1}"
SYSROOT="${VINIX_AARCH64_SYSROOT:-$SCRIPT_DIR/build-aarch64-userland/staging}"
LINUX_HEADERS="${VINIX_AARCH64_LINUX_HEADERS:-$SCRIPT_DIR/build-aarch64-userland/sysroot/include}"
LLVM_BIN="${LLVM_BIN:-/opt/homebrew/opt/llvm/bin}"
if [ ! -x "$LLVM_BIN/clang" ]; then
    LLVM_BIN="$(dirname "$(command -v clang)")"
fi
GCCLIB=$(find "$SYSROOT/usr/lib/gcc/aarch64-alpine-linux-musl" \
    -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort | tail -n1)
for input in "$SYSROOT/usr/lib/libc.a" "$SYSROOT/usr/lib/crt1.o" "$GCCLIB/libgcc.a"; do
    if [ ! -f "$input" ]; then
        echo "ERROR: missing ARM64 musl input: $input; run scripts/build-userland-aarch64.sh" >&2
        exit 1
    fi
done
python3 "$SCRIPT_DIR/build-support/ps1/build.py" --output "$OUTPUT" --sysroot "$SYSROOT" --llvm-bin "$LLVM_BIN"
mkdir -p "$OUTPUT/staging/usr/bin" "$OUTPUT/staging/usr/share/games/ps1" \
    "$OUTPUT/staging/usr/share/licenses/vinix-ps1"
cp "$OUTPUT/source/COPYING" "$OUTPUT/staging/usr/share/licenses/vinix-ps1/PCSX-ReARMed-COPYING"
cp "$SCRIPT_DIR/build-support/ps1/README.md" "$OUTPUT/staging/usr/share/licenses/vinix-ps1/SOURCES.md"
if [ "$WITH_HOMEBREW" = 1 ]; then
    python3 "$SCRIPT_DIR/build-support/ps1/download-homebrew.py" --output "$OUTPUT/homebrew"
    for name in tetrade.exe TETRADE_PSX.bin TETRADE_PSX.cue TETRADE-LICENSE; do
        cp "$OUTPUT/homebrew/$name" "$OUTPUT/staging/usr/share/games/ps1/$name"
    done
else
    for name in tetrade.exe TETRADE_PSX.bin TETRADE_PSX.cue TETRADE-LICENSE; do
        rm -f "$OUTPUT/staging/usr/share/games/ps1/$name"
    done
fi
if [ "$CORE_ONLY" = 1 ]; then
    exit 0
fi
. "$SCRIPT_DIR/build-support/find-v.sh"
"$V" -os linux -arch arm64 -enable-globals -gc none -prod -d glibc -d no_backtrace \
    -o "$OUTPUT/frontend.c" "$SCRIPT_DIR/games/ps1"
"$LLVM_BIN/clang" --target=aarch64-linux-musl -static -nostdinc -nostdlib \
    -isystem "$SCRIPT_DIR/build-support/aarch64-cc-shim" \
    -isystem "$GCCLIB/include" -isystem "$SYSROOT/usr/include" \
    -idirafter "$LINUX_HEADERS" \
    -I"$SCRIPT_DIR/games/ps1" -I"$OUTPUT/source/deps/libretro-common/include" \
    -O2 -D_GNU_SOURCE -fno-stack-protector -w \
    "$SYSROOT/usr/lib/crt1.o" "$SYSROOT/usr/lib/crti.o" "$GCCLIB/crtbeginT.o" \
    "$OUTPUT/frontend.c" "$OUTPUT/source/pcsx_rearmed_libretro.a" \
    -L"$SYSROOT/usr/lib" -L"$GCCLIB" -lgcc_eh -lc -lgcc -lm -lpthread -ldl \
    "$GCCLIB/crtend.o" "$SYSROOT/usr/lib/crtn.o" \
    -fuse-ld=lld -B"$LLVM_BIN" -o "$OUTPUT/staging/usr/bin/vinix-ps1"
echo "Built $OUTPUT/staging/usr/bin/vinix-ps1"
