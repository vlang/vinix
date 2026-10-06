#!/bin/bash
# Build the V Mach-O compatibility runner as a static ARM64 Vinix executable.
set -euo pipefail
WITH_2048=0
WITH_CXX=0
WITH_GLES=0
WITH_PPSSPP=0
for option in "$@"; do
    case "$option" in
        --with-2048) WITH_2048=1 ;;
        --with-cxx) WITH_CXX=1 ;;
        --with-gles) WITH_GLES=1 ;;
        --with-ppsspp) WITH_PPSSPP=1; WITH_CXX=1; WITH_GLES=1 ;;
        --help|-h) echo 'Usage: scripts/build-ios-aarch64.sh [--with-2048] [--with-cxx] [--with-gles] [--with-ppsspp]'; exit 0 ;;
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

if [ "$WITH_GLES" = 1 ]; then
    MESA_SYSROOT="${VINIX_IOS_MESA_SYSROOT:-$SCRIPT_DIR/build-aarch64-x11/sysroot}"
    python3 "$SCRIPT_DIR/build-support/ios/stage-gles.py" --output "$OUTPUT/staging" \
        --sysroot "$SYSROOT" --mesa-sysroot "$MESA_SYSROOT" --readelf "$LLVM_BIN/llvm-readelf"
    "$V" -os linux -arch arm64 -enable-globals -gc none -prod -d glibc -d no_backtrace \
        -d ios_gles -d ios_text "${VFLAGS[@]}" -path "@vlib|$SCRIPT_DIR/compat/ios|@vmodules" \
        -o "$OUTPUT/run-ios-gles.c" "$SCRIPT_DIR/compat/ios/runner"
    # Mesa uses dynamically loaded DRI drivers. Keep the ordinary runner static,
    # and link this optional executable against musl and the private Mesa closure.
    "$LLVM_BIN/clang" --target=aarch64-linux-musl -nostdinc -nostdlib \
        -isystem "$SCRIPT_DIR/build-support/aarch64-cc-shim" -isystem "$GCCLIB/include" \
        -isystem "$SYSROOT/usr/include" -isystem "$MESA_SYSROOT/usr/include" \
        -isystem "$MESA_SYSROOT/usr/include/freetype2" \
        -O2 -fno-stack-protector -w -no-pie \
        "$SYSROOT/usr/lib/crt1.o" "$SYSROOT/usr/lib/crti.o" "$GCCLIB/crtbegin.o" \
        "$OUTPUT/run-ios-gles.c" "$SCRIPT_DIR/compat/ios/runner/abi/dispatch.S" -ffixed-x18 \
        -L"$OUTPUT/staging/usr/lib/vinix/ios-gles" -L"$SYSROOT/usr/lib" -L"$GCCLIB" \
        "${CXXLIBS[@]}" -lEGL -lGLESv2 -lfreetype -lgcc_eh -lc -lgcc -lm \
        -Wl,--dynamic-linker=/usr/lib/vinix/ios-gles/ld-musl-aarch64.so.1 \
        -Wl,-rpath,/usr/lib/vinix/ios-gles -Wl,-rpath-link,"$OUTPUT/staging/usr/lib/vinix/ios-gles" \
        "$GCCLIB/crtend.o" "$SYSROOT/usr/lib/crtn.o" \
        -fuse-ld=lld -B"$LLVM_BIN" -o "$OUTPUT/staging/usr/bin/run-ios-gles"
    echo "Built $OUTPUT/staging/usr/bin/run-ios-gles"
fi

VINIX_IOS_CALCULATOR_BUILD_DIR="$OUTPUT/objc" bash "$SCRIPT_DIR/examples/ios-calculator/build.sh"
mkdir -p "$OUTPUT/staging/usr/share/vinix/ios"
cp -R "$OUTPUT/objc/Calculator.app" "$OUTPUT/staging/usr/share/vinix/ios/"
ln -sf run-ios "$OUTPUT/staging/usr/bin/vinix-ios-calculator"
if [ "$WITH_2048" = 1 ]; then
    VINIX_IOS_2048_BUILD_DIR="$OUTPUT/2048" bash "$SCRIPT_DIR/examples/ios-2048/build.sh"
    cp -R "$OUTPUT/2048/NumberTileGame.app" "$OUTPUT/staging/usr/share/vinix/ios/"
    ln -sf run-ios "$OUTPUT/staging/usr/bin/vinix-ios-2048"
fi

if [ "$WITH_PPSSPP" = 1 ]; then
    python3 "$SCRIPT_DIR/examples/ios-ppsspp/download.py" --output "$OUTPUT/ppsspp"
    cp -R "$OUTPUT/ppsspp/unpacked/Payload/PPSSPP.app" "$OUTPUT/staging/usr/share/vinix/ios/"
    ln -sf run-ios-gles "$OUTPUT/staging/usr/bin/vinix-ios-ppsspp"
fi
