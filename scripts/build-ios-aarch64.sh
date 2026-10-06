#!/bin/bash
# Build the V Mach-O compatibility runner as a static ARM64 Vinix executable.
set -euo pipefail
WITH_2048=0
WITH_CXX=0
for option in "$@"; do
    case "$option" in
        --with-2048) WITH_2048=1 ;;
        --with-cxx) WITH_CXX=1 ;;
        --help|-h) echo 'Usage: scripts/build-ios-aarch64.sh [--with-2048] [--with-cxx]'; exit 0 ;;
        *) echo "ERROR: unknown option: $option" >&2; exit 2 ;;
    esac
done
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$SCRIPT_DIR/build-support/find-v.sh"
OUTPUT="${VINIX_IOS_BUILD_DIR:-$SCRIPT_DIR/build/ios}"
SYSROOT="${VINIX_AARCH64_SYSROOT:-$SCRIPT_DIR/build-aarch64-userland/staging}"
LLVM_BIN="${LLVM_BIN:-/opt/homebrew/opt/llvm/bin}"
if [ ! -x "$LLVM_BIN/clang" ]; then
    LLVM_BIN="$(dirname "$(command -v clang)")"
fi
GCCLIB=$(find "$SYSROOT/usr/lib/gcc/aarch64-alpine-linux-musl" \
    -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort | tail -n1)
for input in "$SYSROOT/usr/lib/libc.a" "$SYSROOT/usr/lib/crt1.o" "$GCCLIB/libgcc.a"; do
    if [ ! -f "$input" ]; then
        echo "ERROR: missing ARM64 musl build input: $input; run ./scripts/build-userland-aarch64.sh" >&2
        exit 1
    fi
done
mkdir -p "$OUTPUT/staging/usr/bin"
VFLAGS=()
CXXLIBS=()
if [ "$WITH_CXX" = 1 ]; then
    python3 "$SCRIPT_DIR/build-support/ios/build-cxx.py" --output "$OUTPUT/cxx" --sysroot "$SYSROOT"
    VFLAGS+=(-d ios_cxx)
    CXXLIBS+=("$OUTPUT/cxx/libcxx-ios.a" "$OUTPUT/cxx/sysroot/usr/lib/libc++abi.a" "$OUTPUT/cxx/sysroot/usr/lib/libunwind.a")
fi
"$V" -os linux -arch arm64 -enable-globals -gc none -prod -d glibc -d no_backtrace \
    "${VFLAGS[@]}" \
    -path "@vlib|$SCRIPT_DIR/compat/ios|@vmodules" \
    -o "$OUTPUT/run-ios.c" "$SCRIPT_DIR/compat/ios/runner"
"$LLVM_BIN/clang" --target=aarch64-linux-musl -static -nostdinc -nostdlib \
    -isystem "$SCRIPT_DIR/build-support/aarch64-cc-shim" \
    -isystem "$GCCLIB/include" -isystem "$SYSROOT/usr/include" \
    -O2 -fno-stack-protector -w \
    "$SYSROOT/usr/lib/crt1.o" "$SYSROOT/usr/lib/crti.o" "$GCCLIB/crtbeginT.o" \
    "$OUTPUT/run-ios.c" "$SCRIPT_DIR/compat/ios/runner/abi/dispatch.S" -ffixed-x18 -L"$SYSROOT/usr/lib" -L"$GCCLIB" \
    "${CXXLIBS[@]}" -lgcc_eh -lc -lgcc -lm "$GCCLIB/crtend.o" "$SYSROOT/usr/lib/crtn.o" \
    -fuse-ld=lld -B"$LLVM_BIN" -o "$OUTPUT/staging/usr/bin/run-ios"
echo "Built $OUTPUT/staging/usr/bin/run-ios"

VINIX_IOS_CALCULATOR_BUILD_DIR="$OUTPUT/objc" bash "$SCRIPT_DIR/examples/ios-calculator/build.sh"
mkdir -p "$OUTPUT/staging/usr/share/vinix/ios"
cp -R "$OUTPUT/objc/Calculator.app" "$OUTPUT/staging/usr/share/vinix/ios/"
ln -sf run-ios "$OUTPUT/staging/usr/bin/vinix-ios-calculator"
if [ "$WITH_2048" = 1 ]; then
    VINIX_IOS_2048_BUILD_DIR="$OUTPUT/2048" bash "$SCRIPT_DIR/examples/ios-2048/build.sh"
    cp -R "$OUTPUT/2048/NumberTileGame.app" "$OUTPUT/staging/usr/share/vinix/ios/"
    ln -sf run-ios "$OUTPUT/staging/usr/bin/vinix-ios-2048"
fi
