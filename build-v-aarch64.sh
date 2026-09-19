#!/bin/bash
# Cross-build the current pinned V compiler for Vinix/AArch64 and stage the
# matching vlib tree. The resulting layer is merged into every desktop image,
# so V programs and vinix-desktop itself can be built natively inside Vinix.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/build-support/find-v.sh"

BUILD_DIR="${VINIX_V_BUILD_DIR:-$SCRIPT_DIR/build-aarch64-v}"
STAGING="$BUILD_DIR/staging"
DOWNLOADS="$BUILD_DIR/downloads"
USERLAND_DIR="${VINIX_AARCH64_USERLAND_BUILD_DIR:-$SCRIPT_DIR/build-aarch64-userland}"
SYSROOT="${VINIX_AARCH64_SYSROOT:-$USERLAND_DIR/staging}"
LLVM_BIN="${LLVM_BIN:-/opt/homebrew/opt/llvm/bin}"
V_COMMIT="${VINIX_V_COMMIT:-${V_COMMIT:-9bfa1dc3f3455d5733d5c226662b6aaba8544f2c}}"
V_SOURCE="${VINIX_V_SOURCE:-}"
CC_SHIM="$SCRIPT_DIR/build-support/aarch64-cc-shim"

if [ ! -x "$LLVM_BIN/clang" ]; then
    host_clang="$(command -v clang || true)"
    if [ -n "$host_clang" ]; then
        LLVM_BIN="$(dirname "$host_clang")"
    fi
fi
if [ ! -x "$LLVM_BIN/clang" ] || [ ! -x "$LLVM_BIN/llvm-strip" ]; then
    echo "ERROR: LLVM clang and llvm-strip not found in $LLVM_BIN" >&2
    exit 1
fi
if [ ! -f "$SYSROOT/usr/lib/libc.a" ] || [ ! -d "$SYSROOT/usr/include" ]; then
    echo "ERROR: Alpine development sysroot is incomplete: $SYSROOT" >&2
    echo "Run ./build-userland-aarch64.sh first." >&2
    exit 1
fi
GCCLIB="$(find "$SYSROOT/usr/lib/gcc/aarch64-alpine-linux-musl" \
    -mindepth 1 -maxdepth 1 -type d 2>/dev/null | LC_ALL=C sort | tail -n1)"
if [ -z "$GCCLIB" ] || [ ! -f "$GCCLIB/libgcc.a" ]; then
    echo "ERROR: Alpine GCC runtime not found below $SYSROOT/usr/lib/gcc" >&2
    exit 1
fi

mkdir -p "$BUILD_DIR" "$DOWNLOADS"
if [ -n "$V_SOURCE" ]; then
    SOURCE_DIR="$(cd "$V_SOURCE" && pwd)"
    if [ ! -f "$SOURCE_DIR/cmd/v/v.v" ] || [ ! -d "$SOURCE_DIR/vlib/builtin" ]; then
        echo "ERROR: VINIX_V_SOURCE is not a V checkout: $SOURCE_DIR" >&2
        exit 1
    fi
else
    archive="$DOWNLOADS/v-$V_COMMIT.tar.gz"
    SOURCE_DIR="$BUILD_DIR/source-$V_COMMIT"
    if [ ! -f "$archive" ]; then
        echo "==> Fetching V $V_COMMIT..."
        archive_tmp="$archive.tmp.$$"
        trap 'rm -f "$archive_tmp"' EXIT
        curl -fL --retry 3 \
            "https://github.com/vlang/v/archive/$V_COMMIT.tar.gz" \
            -o "$archive_tmp"
        mv -f "$archive_tmp" "$archive"
        trap - EXIT
    fi
    if [ ! -f "$SOURCE_DIR/cmd/v/v.v" ]; then
        source_tmp="$BUILD_DIR/.source-$V_COMMIT.tmp.$$"
        rm -rf "$source_tmp"
        mkdir -p "$source_tmp"
        tar xzf "$archive" --strip-components=1 -C "$source_tmp"
        rm -rf "$SOURCE_DIR"
        mv "$source_tmp" "$SOURCE_DIR"
    fi
fi

echo "==> Translating V $V_COMMIT for aarch64-linux-musl..."
# Vinix runs the Alpine/musl hosted user ABI, so both the compiler and the
# desktop it produces use V's Linux target. V's separate `-os vinix` selector
# remains available for freestanding kernel builds.
"$V" -new-compiler -no-memory-limit -cross -os linux -arch arm64 -musl \
    -gc none -o "$BUILD_DIR/v.c" "$SOURCE_DIR/cmd/v"

# V3 records @VMODROOT and @VEXEROOT as C string constants. A compiler copied
# away from its checkout would otherwise keep looking for vlib in the host's
# build directory. Rewrite only complete V string constants so the installed
# compiler resolves its matching runtime tree beside itself.
relocate_v_root() {
    old_root="$1"
    [ "$old_root" = "/usr/lib/vlang" ] && return
    if ! V_RELOCATE_FROM="$old_root" V_RELOCATE_TO=/usr/lib/vlang perl -0pi -e '
        BEGIN {
            $from = quotemeta($ENV{"V_RELOCATE_FROM"});
            $to = $ENV{"V_RELOCATE_TO"};
            $to_len = length($to);
        }
        $count += s/\{"$from", \d+, 1\}/\{"$to", $to_len, 1\}/g;
        END { exit($count > 0 ? 0 : 1); }
    ' "$BUILD_DIR/v.c"; then
        echo "ERROR: V did not embed its source root as expected: $old_root" >&2
        exit 1
    fi
}
relocate_v_root "$SOURCE_DIR"
physical_source_dir="$(cd "$SOURCE_DIR" && pwd -P)"
if [ "$physical_source_dir" != "$SOURCE_DIR" ]; then
    relocate_v_root "$physical_source_dir"
fi
if ! grep -Fq '{"/usr/lib/vlang", 14, 1}' "$BUILD_DIR/v.c"; then
    echo "ERROR: failed to relocate V's embedded installation root" >&2
    exit 1
fi

echo "==> Linking the native V compiler..."
"$LLVM_BIN/clang" --target=aarch64-linux-musl -static -nostdinc -nostdlib \
    -isystem "$CC_SHIM" \
    -isystem "$GCCLIB/include" -isystem "$SYSROOT/usr/include" \
    -I "$SOURCE_DIR/thirdparty/stdatomic/nix" \
    -O2 -fno-stack-protector -w \
    "$SYSROOT/usr/lib/crt1.o" "$SYSROOT/usr/lib/crti.o" "$GCCLIB/crtbeginT.o" \
    "$BUILD_DIR/v.c" \
    -L"$SYSROOT/usr/lib" -L"$GCCLIB" -lc -lpthread -ldl -latomic -lgcc -lm \
    "$GCCLIB/crtend.o" "$SYSROOT/usr/lib/crtn.o" \
    -fuse-ld=lld -B"$LLVM_BIN" -o "$BUILD_DIR/v"
"$LLVM_BIN/llvm-strip" "$BUILD_DIR/v"

echo "==> Staging V and its standard library..."
rm -rf "$STAGING"
mkdir -p "$STAGING/usr/bin" "$STAGING/usr/lib/vlang" "$STAGING/root"
install -m755 "$BUILD_DIR/v" "$STAGING/usr/lib/vlang/v"
cp -a "$SOURCE_DIR/vlib" "$STAGING/usr/lib/vlang/vlib"
cp -a "$SOURCE_DIR/thirdparty" "$STAGING/usr/lib/vlang/thirdparty"
printf '%s\n' "$V_COMMIT" > "$STAGING/usr/lib/vlang/VERSION"
install -m755 "$SCRIPT_DIR/build-support/v-command" "$STAGING/usr/bin/v"
install -m644 "$SCRIPT_DIR/tests/vlang/hello.v" "$STAGING/root/v-smoke.v"
install -m755 "$SCRIPT_DIR/tests/vlang/smoke.sh" "$STAGING/root/v-smoke.sh"

if ! file "$STAGING/usr/lib/vlang/v" | grep -q 'ARM aarch64'; then
    echo "ERROR: staged V compiler is not an AArch64 executable" >&2
    file "$STAGING/usr/lib/vlang/v" >&2
    exit 1
fi

echo "    compiler: $(du -h "$STAGING/usr/lib/vlang/v" | cut -f1)"
echo "    layer:    $(du -sh "$STAGING" | cut -f1)"
