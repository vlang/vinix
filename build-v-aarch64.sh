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
TCC_ALPINE_REPOSITORY="${VINIX_TCC_ALPINE_REPOSITORY:-https://dl-cdn.alpinelinux.org/alpine/v3.24/community/aarch64}"
TCC_ALPINE_VERSION=0.9.27_git20250619-r1
TCC_PACKAGE="tcc-$TCC_ALPINE_VERSION.apk"
TCC_DEV_PACKAGE="tcc-dev-$TCC_ALPINE_VERSION.apk"
TCC_LIBS_PACKAGE="tcc-libs-$TCC_ALPINE_VERSION.apk"
TCC_STATIC_PACKAGE="tcc-libs-static-$TCC_ALPINE_VERSION.apk"
TCC_PACKAGE_SHA256=5329d1702d2a7ff39efdab46b915308d1479a37595619a9002ec4b3e35eba209
TCC_DEV_PACKAGE_SHA256=c68f967def600a0e877ca8941354b987a67ad17695e6b962f64847dd8069fe37
TCC_LIBS_PACKAGE_SHA256=b46e95d8dc6e643b836ea3809d964f9c0628adc621602c29d94207d99a9e1e7c
TCC_STATIC_PACKAGE_SHA256=50e4866cb072e898643e178d78b974fc6e04e88f45f18ebfdc3bb2f11ca86c2a

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

fetch_alpine_tcc_package() {
    local package="$1"
    local expected_sha256="$2"
    local archive="$DOWNLOADS/$package"
    local archive_tmp actual_sha256
    if [ ! -f "$archive" ]; then
        echo "==> Fetching Alpine TCC package $package..."
        archive_tmp="$archive.tmp.$$"
        trap 'rm -f "$archive_tmp"' EXIT
        curl -fL --retry 3 "$TCC_ALPINE_REPOSITORY/$package" -o "$archive_tmp"
        mv -f "$archive_tmp" "$archive"
        trap - EXIT
    fi
    actual_sha256="$(sha256_file "$archive")"
    if [ "$actual_sha256" != "$expected_sha256" ]; then
        echo "ERROR: Alpine TCC package checksum mismatch: $archive" >&2
        echo "Expected: $expected_sha256" >&2
        echo "Actual:   $actual_sha256" >&2
        exit 1
    fi
}

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

fetch_alpine_tcc_package "$TCC_PACKAGE" "$TCC_PACKAGE_SHA256"
fetch_alpine_tcc_package "$TCC_DEV_PACKAGE" "$TCC_DEV_PACKAGE_SHA256"
fetch_alpine_tcc_package "$TCC_LIBS_PACKAGE" "$TCC_LIBS_PACKAGE_SHA256"
fetch_alpine_tcc_package "$TCC_STATIC_PACKAGE" "$TCC_STATIC_PACKAGE_SHA256"

# Apply the small Vinix compatibility patches to a private source copy. This
# keeps VINIX_V_SOURCE untouched and ensures both the bootstrap compiler and
# the sources later consumed by `v self` contain the same fixes.
PREPARED_SOURCE="$BUILD_DIR/source-vinix-$V_COMMIT"
rm -rf "$PREPARED_SOURCE"
mkdir -p "$PREPARED_SOURCE"
cp -a "$SOURCE_DIR/cmd" "$SOURCE_DIR/vlib" "$SOURCE_DIR/thirdparty" "$PREPARED_SOURCE/"
install -m644 "$SOURCE_DIR/GNUmakefile" "$PREPARED_SOURCE/GNUmakefile"
install -m644 "$SOURCE_DIR/v.mod" "$PREPARED_SOURCE/v.mod"
patch -d "$PREPARED_SOURCE" -p0 < "$SCRIPT_DIR/build-support/v-no-parallel-native-inputs.patch"
patch -d "$PREPARED_SOURCE" -p0 < "$SCRIPT_DIR/build-support/v-serial-driver.patch"
SOURCE_DIR="$PREPARED_SOURCE"

echo "==> Translating V $V_COMMIT for aarch64-linux-musl..."
# The compiler itself uses the mature hosted Linux/musl runtime. The installed
# `v` command supplies Vinix as the default output target, so programs use the
# Vinix-specific runtime paths while this large self-hosted compiler retains the
# process and allocator behavior already exercised by the desktop build.
"$V" -new-compiler -no-memory-limit -cross -os linux -arch arm64 -musl \
    -gc none -no-parallel -o "$BUILD_DIR/v.c" "$SOURCE_DIR/cmd/v"

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

# V's native-input preprocessing must obey -no-parallel in the generated
# bootstrap too. The check makes patch/source drift fail during the build.
if ! grep -Fq 'bool native_inputs_overlap = !current_no_parallel && driver__should_overlap_v3_native_inputs(' "$BUILD_DIR/v.c"; then
    echo "ERROR: V native-input serialisation patch is missing from generated C" >&2
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
cp -a "$SOURCE_DIR/cmd" "$STAGING/usr/lib/vlang/cmd"
install -m644 "$SOURCE_DIR/GNUmakefile" "$STAGING/usr/lib/vlang/GNUmakefile"
install -m644 "$SOURCE_DIR/v.mod" "$STAGING/usr/lib/vlang/v.mod"
# `make` populates a V checkout with a bundled TCC for the build host. When a
# macOS checkout is supplied through VINIX_V_SOURCE that executable is Mach-O,
# not an AArch64 Linux/musl program. V probes an executable bundled TCC before
# falling back to a system compiler; on Vinix the incompatible probe can enter
# the Mach-O compatibility path and never return. Replace those host-generated
# artifacts with Alpine's native AArch64 TCC packages below.
rm -rf "$STAGING/usr/lib/vlang/thirdparty/tcc"
for package in "$TCC_PACKAGE" "$TCC_DEV_PACKAGE" "$TCC_LIBS_PACKAGE" "$TCC_STATIC_PACKAGE"; do
    tar xzf "$DOWNLOADS/$package" -C "$STAGING"
done
rm -f "$STAGING/.PKGINFO" "$STAGING/.SIGN"*
# Alpine's TCC stddef.h declares wchar_t before including musl headers but
# does not set the guard musl uses to avoid declaring it again. This is an
# incompatible signed/unsigned redeclaration on AArch64. Keep the official
# header and apply only the missing integration guard; patch will fail if the
# packaged header changes, forcing the pin to be qualified again.
patch -d "$STAGING" -p0 < "$SCRIPT_DIR/build-support/alpine-tcc-musl.patch"
printf '%s\n' "$V_COMMIT" > "$STAGING/usr/lib/vlang/VERSION"
install -m755 "$SCRIPT_DIR/build-support/v-command" "$STAGING/usr/bin/v"
install -m644 "$SCRIPT_DIR/tests/vlang/hello.v" "$STAGING/root/v-smoke.v"
install -m755 "$SCRIPT_DIR/tests/vlang/smoke.sh" "$STAGING/root/v-smoke.sh"

if ! file "$STAGING/usr/lib/vlang/v" | grep -q 'ARM aarch64'; then
    echo "ERROR: staged V compiler is not an AArch64 executable" >&2
    file "$STAGING/usr/lib/vlang/v" >&2
    exit 1
fi
if [ -e "$STAGING/usr/lib/vlang/thirdparty/tcc/tcc.exe" ]; then
    echo "ERROR: host TCC leaked into the Vinix V layer" >&2
    exit 1
fi
if ! file "$STAGING/usr/bin/tcc" | grep -q 'ARM aarch64'; then
    echo "ERROR: staged Alpine TCC is not an AArch64 executable" >&2
    file "$STAGING/usr/bin/tcc" >&2
    exit 1
fi
if [ ! -f "$STAGING/usr/lib/libtcc.so" ] || \
   [ ! -f "$STAGING/usr/lib/tcc/include/stdatomic.h" ] || \
   [ ! -f "$STAGING/usr/lib/tcc/libtcc1.a" ] || \
   [ ! -f "$STAGING/usr/lib/vlang/cmd/v/v.v" ] || \
   [ ! -f "$STAGING/usr/lib/vlang/GNUmakefile" ] || \
   [ ! -f "$STAGING/usr/lib/vlang/v.mod" ]; then
    echo "ERROR: native TCC or V self-host sources are incomplete" >&2
    exit 1
fi

echo "    compiler: $(du -h "$STAGING/usr/lib/vlang/v" | cut -f1)"
echo "    layer:    $(du -sh "$STAGING" | cut -f1)"
