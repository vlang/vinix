#!/bin/bash
# Build the Vinix Aquamarine backend and stage Hyprland for Vinix/aarch64.
#
# Hyprland itself comes from Alpine edge's musl package; Aquamarine is rebuilt
# with Vinix's framebuffer and console-input backend, against the exact ABI
# required by that package. The build runs on ARM64 Linux or macOS.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${VINIX_HYPRLAND_BUILD_DIR:-$SCRIPT_DIR/build-aarch64-hyprland}"
DOWNLOADS="$BUILD_DIR/downloads"
SYSROOT="$BUILD_DIR/sysroot"
SOURCE="$BUILD_DIR/aquamarine-0.12.0"
TARGET_BUILD="$BUILD_DIR/aquamarine-build"
CUSTOM_INSTALL="$BUILD_DIR/aquamarine-install"
STAGING="$BUILD_DIR/staging"
ALPINE_MIRROR="${ALPINE_MIRROR:-https://dl-cdn.alpinelinux.org/alpine/edge}"
ALPINE_ARCH=aarch64
AQUAMARINE_VERSION=0.12.0
AQUAMARINE_ARCHIVE="$DOWNLOADS/aquamarine-v$AQUAMARINE_VERSION.tar.gz"
AQUAMARINE_URL="https://github.com/hyprwm/aquamarine/archive/v$AQUAMARINE_VERSION/aquamarine-v$AQUAMARINE_VERSION.tar.gz"
AQUAMARINE_SHA512=14eea03cba498ed398f90933bebd987e6d3f319f5223efdeb808e194b4237486d2b05334799415930821b0e17d9478709bea8ab4f9d6c8aaf297e95f251b0b84
NPROC="${NPROC:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}"

if [ "$(uname -m)" != aarch64 ] && [ "$(uname -m)" != arm64 ]; then
    echo "build-hyprland-aarch64.sh requires an ARM64 host" >&2
    exit 1
fi

for tool in curl tar patch python3 cmake ninja pkg-config clang clang++ ld.lld \
    file install; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "missing build tool: $tool" >&2
        exit 1
    fi
done

mkdir -p "$DOWNLOADS" "$BUILD_DIR"

if [ "$(uname -s)" = Darwin ]; then
    TARGET_CLANG="${TARGET_CLANG:-/opt/homebrew/opt/llvm/bin/clang}"
    TARGET_CLANGXX="${TARGET_CLANGXX:-/opt/homebrew/opt/llvm/bin/clang++}"
    TARGET_READELF="${TARGET_READELF:-/opt/homebrew/opt/llvm/bin/llvm-readelf}"
else
    TARGET_CLANG="${TARGET_CLANG:-$(command -v clang)}"
    TARGET_CLANGXX="${TARGET_CLANGXX:-$(command -v clang++)}"
    TARGET_READELF="${TARGET_READELF:-$(command -v readelf)}"
fi
for tool in "$TARGET_CLANG" "$TARGET_CLANGXX" "$TARGET_READELF"; do
    if [ ! -x "$tool" ]; then
        echo "missing target tool: $tool" >&2
        exit 1
    fi
done

download_index() {
    local repository="$1"
    local index="$DOWNLOADS/${repository}_APKINDEX"
    echo "==> Fetching Alpine edge $repository index"
    curl -fsSL --retry 3 "$ALPINE_MIRROR/$repository/$ALPINE_ARCH/APKINDEX.tar.gz" \
        | tar xzOf - APKINDEX > "$index"
}

resolve_closure() {
    local output="$1"
    shift
    python3 "$SCRIPT_DIR/build-support/alpine-resolve.py" \
        --index main "$DOWNLOADS/main_APKINDEX" \
        --index community "$DOWNLOADS/community_APKINDEX" \
        "$@" > "$output"
}

download_and_extract() {
    local list="$1" destination="$2"
    local repository filename archive
    mkdir -p "$destination"
    while IFS=$'\t' read -r repository filename; do
        [ -n "$filename" ] || continue
        archive="$DOWNLOADS/$filename"
        if [ ! -f "$archive" ]; then
            echo "    $filename"
            curl -fsSL --retry 3 -o "$archive" \
                "$ALPINE_MIRROR/$repository/$ALPINE_ARCH/$filename"
        fi
        # APFS cannot contain Alpine's separate Hyprland and hyprland names.
        # Vinix starts the canonical executable, so the lowercase alias is
        # unnecessary on every host.
        tar xzf "$archive" -C "$destination" \
            --exclude='./usr/bin/hyprland' --exclude='usr/bin/hyprland' \
            2>/dev/null || true
        rm -f "$destination/.PKGINFO" "$destination"/.SIGN* "$destination"/.trigger*
    done < "$list"
}

download_index main
download_index community

RUNTIME_LIST="$BUILD_DIR/runtime-packages.txt"
resolve_closure "$RUNTIME_LIST" \
    hyprland foot font-dejavu capitaine-cursors xkeyboard-config mesa-dri-gallium

if ! grep -q $'community\thyprland-0.54.3-r0.apk' "$RUNTIME_LIST" || \
   ! grep -q $'community\taquamarine-0.12.0-r0.apk' "$RUNTIME_LIST"; then
    echo "Alpine edge no longer carries the tested Hyprland 0.54.3/Aquamarine 0.12 ABI pair" >&2
    echo "Update this script, the Aquamarine patch, and their version pins together." >&2
    exit 1
fi

echo "==> Staging the Hyprland runtime closure"
rm -rf "$STAGING"
download_and_extract "$RUNTIME_LIST" "$STAGING"

BUILD_LIST="$BUILD_DIR/build-packages.txt"
resolve_closure "$BUILD_LIST" \
    musl-dev linux-headers libstdc++-dev libgcc libgcc-static \
    eudev-dev hwdata-dev hyprutils-dev hyprwayland-scanner \
    libdisplay-info-dev libinput-dev libseat-dev mesa-dev pixman-dev \
    wayland-dev wayland-protocols

echo "==> Preparing the Alpine musl build sysroot"
rm -rf "$SYSROOT"
download_and_extract "$BUILD_LIST" "$SYSROOT"
ln -sf libgcc_s.so.1 "$SYSROOT/usr/lib/libgcc_s.so"

CXX_VERSION="$(basename "$(find "$SYSROOT/usr/include/c++" -mindepth 1 -maxdepth 1 -type d | head -n1)")"
CXX_ARCH_INCLUDE="$SYSROOT/usr/include/c++/$CXX_VERSION/aarch64-alpine-linux-musl"
GCC_INSTALL_DIR="$SYSROOT/usr/lib/gcc/aarch64-alpine-linux-musl/$CXX_VERSION"
if [ -z "$CXX_VERSION" ] || [ ! -d "$CXX_ARCH_INCLUDE" ] || \
   [ ! -f "$GCC_INSTALL_DIR/crtbeginS.o" ]; then
    echo "Alpine libstdc++ headers are incomplete" >&2
    exit 1
fi

if [ ! -f "$AQUAMARINE_ARCHIVE" ]; then
    echo "==> Downloading Aquamarine $AQUAMARINE_VERSION"
    curl -fL --retry 3 -o "$AQUAMARINE_ARCHIVE" "$AQUAMARINE_URL"
fi
python3 - "$AQUAMARINE_ARCHIVE" "$AQUAMARINE_SHA512" <<'PY'
import hashlib
import pathlib
import sys

archive = pathlib.Path(sys.argv[1])
actual = hashlib.sha512(archive.read_bytes()).hexdigest()
if actual != sys.argv[2]:
    raise SystemExit(f"Aquamarine archive checksum mismatch: {actual}")
PY

rm -rf "$SOURCE"
tar xzf "$AQUAMARINE_ARCHIVE" -C "$BUILD_DIR"
patch -p1 -d "$SOURCE" < "$SCRIPT_DIR/patches/aquamarine/vinix-backend.patch"

TOOLCHAIN="$BUILD_DIR/aarch64-vinix.cmake"
cat > "$TOOLCHAIN" <<EOF
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_SYSROOT "$SYSROOT")
set(CMAKE_C_COMPILER "$TARGET_CLANG")
set(CMAKE_C_COMPILER_TARGET aarch64-linux-musl)
set(CMAKE_CXX_COMPILER "$TARGET_CLANGXX")
set(CMAKE_CXX_COMPILER_TARGET aarch64-linux-musl)
set(CMAKE_C_FLAGS_INIT "-O2 -fPIC -D__vinix__ --gcc-install-dir=$GCC_INSTALL_DIR")
set(CMAKE_CXX_FLAGS_INIT "-O2 -fPIC -D__vinix__ --gcc-install-dir=$GCC_INSTALL_DIR -nostdinc++ -isystem $SYSROOT/usr/include/c++/$CXX_VERSION -isystem $CXX_ARCH_INCLUDE")
set(CMAKE_EXE_LINKER_FLAGS_INIT "-fuse-ld=lld --rtlib=libgcc --unwindlib=libgcc")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "-fuse-ld=lld --rtlib=libgcc --unwindlib=libgcc")
set(CMAKE_FIND_ROOT_PATH "$SYSROOT")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
EOF

echo "==> Building Aquamarine $AQUAMARINE_VERSION for Vinix"
rm -rf "$TARGET_BUILD" "$CUSTOM_INSTALL"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"
export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig"
cmake -S "$SOURCE" -B "$TARGET_BUILD" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DAQUAMARINE_VINIX_BACKEND=ON \
    -DBUILD_TESTING=OFF
cmake --build "$TARGET_BUILD" -j "$NPROC"
DESTDIR="$CUSTOM_INSTALL" cmake --install "$TARGET_BUILD"

install -m755 "$CUSTOM_INSTALL/usr/lib/libaquamarine.so.$AQUAMARINE_VERSION" \
    "$STAGING/usr/lib/libaquamarine.so.$AQUAMARINE_VERSION"
ln -sf "libaquamarine.so.$AQUAMARINE_VERSION" "$STAGING/usr/lib/libaquamarine.so.11"

echo "==> Installing the Vinix session"
mkdir -p "$STAGING/usr/bin" "$STAGING/usr/share/vinix" \
    "$STAGING/root/.config/hypr" "$STAGING/root/.config/foot" \
    "$STAGING/sys/dev/char/226:0/device/drm/card0" \
    "$STAGING/sys/dev/char/226:128/device/drm/card0" \
    "$STAGING/sys/dev/char/226:128/device/drm/renderD128"
install -m755 "$SCRIPT_DIR/build-support/hyprland/start-hyprland-vinix" \
    "$STAGING/usr/bin/start-hyprland-vinix"
install -m644 "$SCRIPT_DIR/build-support/hyprland/hyprland.conf" \
    "$STAGING/root/.config/hypr/hyprland.conf"
install -m644 "$SCRIPT_DIR/build-support/hyprland/foot.ini" \
    "$STAGING/root/.config/foot/foot.ini"
install -m644 "$SCRIPT_DIR/tests/hyprland/smoke.sh" \
    "$STAGING/root/hyprland-smoke.sh"
chmod +x "$STAGING/root/hyprland-smoke.sh"

# Vinix's musl loader opens shared objects with O_NOFOLLOW. Materialize package
# library aliases now so dlopen and ordinary DT_NEEDED resolution both work.
find "$STAGING/lib" "$STAGING/usr/lib" -type l -name '*.so*' 2>/dev/null | while IFS= read -r link; do
    target="$(readlink "$link")"
    case "$target" in
        /*) real="$STAGING$target" ;;
        *) real="$(dirname "$link")/$target" ;;
    esac
    if [ -f "$real" ]; then
        rm "$link"
        cp "$real" "$link"
    fi
done

# The complete desktop overlays its patched Asahi Mesa after this layer.  Keep
# the Alpine software renderer internally consistent for machines without an
# Asahi render node; the launcher selects this private set only for card0.
SOFTWARE_MESA="$STAGING/usr/lib/vinix-hyprland-software"
mkdir -p "$SOFTWARE_MESA/dri" "$SOFTWARE_MESA/gbm"
for soname in libEGL.so.1 libGL.so.1 libGLESv2.so.2 libgbm.so.1; do
    install -m755 "$STAGING/usr/lib/$soname" "$SOFTWARE_MESA/$soname"
done
for gallium in "$STAGING/usr/lib"/libgallium-*.so; do
    [ -f "$gallium" ] || continue
    install -m755 "$gallium" "$SOFTWARE_MESA/$(basename "$gallium")"
done
install -m755 "$STAGING/usr/lib/dri/kms_swrast_dri.so" \
    "$SOFTWARE_MESA/dri/kms_swrast_dri.so"
install -m755 "$STAGING/usr/lib/gbm/dri_gbm.so" \
    "$SOFTWARE_MESA/gbm/dri_gbm.so"

# Alpine exposes LLVM through both its versioned directory and top-level
# aliases. The only runtime consumer in this pinned closure asks for
# libLLVM.so.22.1; after materializing that SONAME the other two 168 MiB copies
# are redundant in an initramfs.
rm -rf "$STAGING/usr/lib/llvm22"
rm -f "$STAGING/usr/lib/libLLVM-22.so"

if ! "$TARGET_READELF" -d "$STAGING/usr/bin/Hyprland" | grep -q 'libaquamarine.so.11'; then
    echo "staged Hyprland does not use the Aquamarine ABI this backend provides" >&2
    exit 1
fi
if ! "$TARGET_READELF" -d "$STAGING/usr/lib/libaquamarine.so.11" | grep -q 'SONAME.*libaquamarine.so.11'; then
    echo "custom Aquamarine has the wrong SONAME" >&2
    exit 1
fi

printf '%s\n' \
    "hyprland=0.54.3-r0" \
    "aquamarine=$AQUAMARINE_VERSION vinix-framebuffer-backend" \
    "alpine=edge aarch64" \
    > "$STAGING/usr/share/vinix/hyprland"

echo "==> Hyprland staging ready: $STAGING"
du -sh "$STAGING"
file "$STAGING/usr/bin/Hyprland" "$STAGING/usr/lib/libaquamarine.so.11"
