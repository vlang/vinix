#!/bin/bash
# Build the Mesa 25.0.5 Asahi and VirGL userspace used by Vinix/aarch64.
#
# Run this in the Debian aarch64 build VM. Native Mesa helper programs are
# built for the VM; the installed driver is linked against an Alpine musl
# sysroot so it can run in the Vinix initramfs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${VINIX_ASAHI_BUILD_DIR:-$SCRIPT_DIR/build-aarch64-asahi}"
MESA_VERSION=25.0.5
MESA_ARCHIVE="$BUILD_DIR/downloads/mesa-$MESA_VERSION.tar.xz"
MESA_URL="https://archive.mesa3d.org/mesa-$MESA_VERSION.tar.xz"
MESA_BLAKE2B="f17f8c2a733fd3c37f346b9304241dc1d13e01df9c8c723b73b10279dd3c2ebed062ec1f15cdbc8b9936bae840a087b23ac38cae7d8982228d582d468ab8c9c9"
MESA_SRC="$BUILD_DIR/mesa-$MESA_VERSION"
HOST_TOOLS="$BUILD_DIR/host-tools"
SYSROOT="$BUILD_DIR/sysroot"
TARGET_BUILD="$BUILD_DIR/target-build"
STAGING="$BUILD_DIR/staging"
ALPINE_MIRROR="${ALPINE_MIRROR:-https://dl-cdn.alpinelinux.org/alpine/v3.21}"
ALPINE_ARCH=aarch64
NPROC="${NPROC:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}"

if [ "$(uname -s)" != Linux ] || [ "$(uname -m)" != aarch64 ]; then
    echo "build-asahi-aarch64.sh must run in the Debian aarch64 build VM" >&2
    exit 1
fi

for tool in curl meson ninja python3 pkg-config clang clang++ ld.lld patch tar \
    file install; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "missing build tool: $tool" >&2
        exit 1
    fi
done

if ! command -v llvm-config-19 >/dev/null 2>&1 \
    && ! command -v llvm-config >/dev/null 2>&1; then
    echo "missing native Mesa compiler dependencies" >&2
    echo "install libclang-19-dev libclc-19-dev libllvmspirvlib-19-dev spirv-tools" >&2
    exit 1
fi

mkdir -p "$BUILD_DIR/downloads" "$HOST_TOOLS/bin" "$SYSROOT" "$STAGING"

if [ ! -f "$MESA_ARCHIVE" ] && [ ! -d "$MESA_SRC" ]; then
    echo "==> Downloading Mesa $MESA_VERSION"
    curl -fL --retry 3 -o "$MESA_ARCHIVE" "$MESA_URL"
fi

if [ -f "$MESA_ARCHIVE" ]; then
    python3 - "$MESA_ARCHIVE" "$MESA_BLAKE2B" <<'PY'
import hashlib
import pathlib
import sys

archive = pathlib.Path(sys.argv[1])
expected = sys.argv[2]
actual = hashlib.blake2b(archive.read_bytes()).hexdigest()
if actual != expected:
    raise SystemExit(f"Mesa archive checksum mismatch: {actual}")
PY
fi

if [ ! -d "$MESA_SRC" ]; then
    tar -xJf "$MESA_ARCHIVE" -C "$BUILD_DIR"
fi

for MESA_PATCH in \
    "$SCRIPT_DIR/patches/mesa/jinx-working-patch.patch" \
    "$SCRIPT_DIR/patches/mesa/vinix-fake-g17-renderer.patch" \
    "$SCRIPT_DIR/patches/mesa/vinix-libagx-link-names.patch"; do
    if patch --dry-run -p1 -d "$MESA_SRC" < "$MESA_PATCH" >/dev/null 2>&1; then
        echo "==> Applying $(basename "$MESA_PATCH")"
        patch -p1 -d "$MESA_SRC" < "$MESA_PATCH"
    elif ! patch --dry-run -R -p1 -d "$MESA_SRC" < "$MESA_PATCH" >/dev/null 2>&1; then
        echo "Mesa source is neither clean nor patched for $(basename "$MESA_PATCH")" >&2
        exit 1
    fi
done

echo "==> Building native Asahi shader tools"
NATIVE_BUILD="$BUILD_DIR/native-tools-build"
NATIVE_MESON_OPTIONS=(
    --buildtype=release
    -Dplatforms=
    -Dglx=disabled
    -Degl=disabled
    -Dgbm=disabled
    -Dopengl=false
    -Dgles1=disabled
    -Dgles2=disabled
    -Dgallium-drivers=asahi
    -Dvulkan-drivers=
    -Dllvm=enabled
    -Dshared-llvm=enabled
    -Dmesa-clc=enabled
    -Dprecomp-compiler=enabled
    -Dbuild-tests=false
    -Dtools=
    -Dvideo-codecs=
)
if [ -f "$NATIVE_BUILD/build.ninja" ]; then
    meson setup --reconfigure "$NATIVE_BUILD" "$MESA_SRC" \
        "${NATIVE_MESON_OPTIONS[@]}"
else
    meson setup "$NATIVE_BUILD" "$MESA_SRC" \
        "${NATIVE_MESON_OPTIONS[@]}"
fi
ninja -C "$NATIVE_BUILD" -j"$NPROC" \
    src/compiler/clc/mesa_clc \
    src/compiler/spirv/vtn_bindgen \
    src/asahi/clc/asahi_clc
install -m755 "$NATIVE_BUILD/src/compiler/clc/mesa_clc" "$HOST_TOOLS/bin/"
install -m755 "$NATIVE_BUILD/src/compiler/spirv/vtn_bindgen" "$HOST_TOOLS/bin/"
install -m755 "$NATIVE_BUILD/src/asahi/clc/asahi_clc" "$HOST_TOOLS/bin/"

APK_DIR="$BUILD_DIR/downloads/apk"
mkdir -p "$APK_DIR"

download_index() {
    local repo="$1"
    local index="$APK_DIR/${repo}_APKINDEX"
    if [ ! -f "$index" ]; then
        curl -fsSL "$ALPINE_MIRROR/$repo/$ALPINE_ARCH/APKINDEX.tar.gz" \
            | tar xzOf - APKINDEX > "$index"
    fi
}

extract_apk() {
    local repo="$1"
    local package="$2"
    local index="$APK_DIR/${repo}_APKINDEX"
    local filename
    filename="$(awk -v wanted="$package" '
        /^P:/ { name = substr($0, 3) }
        /^V:/ { version = substr($0, 3) }
        /^$/ {
            if (name == wanted) print name "-" version ".apk"
            name = version = ""
        }
    ' "$index")"
    if [ -z "$filename" ]; then
        echo "Alpine package not found: $package" >&2
        exit 1
    fi
    if [ ! -f "$APK_DIR/$filename" ]; then
        echo "    $package"
        curl -fsSL --retry 3 -o "$APK_DIR/$filename" \
            "$ALPINE_MIRROR/$repo/$ALPINE_ARCH/$filename"
    fi
    tar xzf "$APK_DIR/$filename" -C "$SYSROOT" 2>/dev/null || true
    rm -f "$SYSROOT/.PKGINFO" "$SYSROOT"/.SIGN*
}

echo "==> Preparing pinned Alpine 3.21 musl sysroot"
download_index main
for package in \
    musl musl-dev linux-headers libgcc libstdc++ libstdc++-dev libatomic \
    libmd libmd-dev libbsd libbsd-dev \
    zlib zlib-dev zstd-libs zstd-dev \
    libdrm libdrm-dev libpciaccess libpciaccess-dev \
    expat libexpat expat-dev hwdata-pci \
    xorgproto xcb-proto libxau libxau-dev libxdmcp libxdmcp-dev \
    libxcb libxcb-dev libx11 libx11-dev libxext libxext-dev \
    libxfixes libxfixes-dev libxrender libxrender-dev \
    libxrandr libxrandr-dev \
    libxshmfence libxshmfence-dev; do
    extract_apk main "$package"
done
# Alpine's runtime package carries the SONAME file but not the linker name.
# Clang's libgcc unwind mode needs this while linking Mesa's C++ objects.
ln -sf libgcc_s.so.1 "$SYSROOT/usr/lib/libgcc_s.so"

# Clang's compiler-rt supplies target builtins. libstdc++ headers come from
# Alpine because Debian's headers target glibc.
CXX_VERSION="$(basename "$(find "$SYSROOT/usr/include/c++" -mindepth 1 -maxdepth 1 -type d | head -n1)")"
CXX_ARCH_INCLUDE="$SYSROOT/usr/include/c++/$CXX_VERSION/aarch64-alpine-linux-musl"
if [ -z "$CXX_VERSION" ] || [ ! -d "$CXX_ARCH_INCLUDE" ]; then
    echo "Alpine libstdc++ headers are incomplete" >&2
    exit 1
fi

LLVM_AR="$(command -v llvm-ar-19 || command -v llvm-ar)"
LLVM_NM="$(command -v llvm-nm-19 || command -v llvm-nm)"
LLVM_STRIP="$(command -v llvm-strip-19 || command -v llvm-strip)"
CROSS_FILE="$BUILD_DIR/aarch64-vinix.ini"
cat > "$CROSS_FILE" <<EOF
[binaries]
c = ['clang', '--target=aarch64-linux-musl', '--sysroot=$SYSROOT']
cpp = ['clang++', '--target=aarch64-linux-musl', '--sysroot=$SYSROOT', '-nostdinc++', '-isystem', '$SYSROOT/usr/include/c++/$CXX_VERSION', '-isystem', '$CXX_ARCH_INCLUDE']
ar = '$LLVM_AR'
nm = '$LLVM_NM'
strip = '$LLVM_STRIP'
pkg-config = 'pkg-config'
exe_wrapper = ['$SYSROOT/lib/ld-musl-aarch64.so.1', '--library-path', '$SYSROOT/lib:$SYSROOT/usr/lib']

[host_machine]
system = 'vinix'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'

[properties]
sys_root = '$SYSROOT'
pkg_config_libdir = ['$SYSROOT/usr/lib/pkgconfig', '$SYSROOT/usr/share/pkgconfig']

[built-in options]
c_args = ['-O2', '-fPIC', '-D__vinix__']
cpp_args = ['-O2', '-fPIC', '-D__vinix__']
c_link_args = ['-fuse-ld=lld', '--rtlib=compiler-rt', '--unwindlib=none']
cpp_link_args = ['-fuse-ld=lld', '--rtlib=compiler-rt', '--unwindlib=libgcc']
EOF

echo "==> Building Mesa $MESA_VERSION Asahi/VirGL for Vinix"
export PATH="$HOST_TOOLS/bin:$PATH"
TARGET_MESON_OPTIONS=(
    --prefix=/usr
    --libdir=lib
    --buildtype=release
    -Dstrip=true
    -Dplatforms=x11
    -Dglx=disabled
    -Degl=enabled
    -Dgbm=enabled
    -Dopengl=true
    -Dgles1=disabled
    -Dgles2=enabled
    -Dshared-glapi=enabled
    -Dgallium-drivers=asahi,virgl,softpipe
    -Dvulkan-drivers=
    -Dllvm=disabled
    -Ddraw-use-llvm=false
    -Dmesa-clc=system
    -Dprecomp-compiler=system
    -Dshader-cache=disabled
    -Dxmlconfig=disabled
    -Dvalgrind=disabled
    -Dlibunwind=disabled
    -Dbuild-tests=false
    -Dtools=
    -Dvideo-codecs=
)
if [ -f "$TARGET_BUILD/build.ninja" ]; then
    meson setup --reconfigure "$TARGET_BUILD" "$MESA_SRC" \
        --cross-file "$CROSS_FILE" "${TARGET_MESON_OPTIONS[@]}"
else
    meson setup "$TARGET_BUILD" "$MESA_SRC" --cross-file "$CROSS_FILE" \
        "${TARGET_MESON_OPTIONS[@]}"
fi
ninja -C "$TARGET_BUILD" -j"$NPROC"
rm -rf "$STAGING"
DESTDIR="$STAGING" ninja -C "$TARGET_BUILD" install

echo "==> Installing Mesa hardware runtime and triangle test"
mkdir -p "$STAGING/lib" "$STAGING/etc" "$STAGING/usr/lib" \
    "$STAGING/usr/bin" "$STAGING/usr/share/examples/gl-triangle" \
    "$STAGING/usr/share/vinix"
# The base ARM64 userland uses a static musl build. The Asahi libraries need
# Alpine's dynamic loader from the same pinned sysroot as Mesa.
install -m755 "$SYSROOT/lib/ld-musl-aarch64.so.1" \
    "$STAGING/lib/ld-musl-aarch64.so.1"
printf '%s\n' /lib /usr/lib > "$STAGING/etc/ld-musl-aarch64.path"
for pattern in \
    'libdrm.so*' 'libpciaccess.so*' 'libstdc++.so*' 'libgcc_s.so*' \
    'libmd.so*' 'libbsd.so*' \
    'libatomic.so*' 'libz.so*' 'libzstd.so*' 'libexpat.so*' \
    'libX11.so*' 'libX11-xcb.so*' 'libXau.so*' 'libXdmcp.so*' \
    'libxcb.so*' 'libxcb-*.so*' 'libXext.so*' 'libXfixes.so*' \
    'libXrender.so*' 'libXrandr.so*' 'libxshmfence.so*'; do
    for library in "$SYSROOT/usr/lib"/$pattern; do
        [ -e "$library" ] || continue
        cp -a "$library" "$STAGING/usr/lib/"
    done
done

TARGET_CC=(clang --target=aarch64-linux-musl --sysroot="$SYSROOT" -fuse-ld=lld --rtlib=compiler-rt --unwindlib=none)
"${TARGET_CC[@]}" -O2 -Wall -Wextra -Werror -fPIC -shared \
    "$SCRIPT_DIR/tests/agx-fake-g17/ioctl_fault.c" \
    -o "$STAGING/usr/lib/libvinix-agx-fault.so" -ldl
"${TARGET_CC[@]}" -O2 -D__vinix__ \
    -I"$STAGING/usr/include" \
    "$SCRIPT_DIR/gl-triangle/egl_triangle.c" \
    -L"$STAGING/usr/lib" -Wl,-rpath-link,"$STAGING/usr/lib" \
    -o "$STAGING/usr/bin/gl-triangle-agx" -lEGL -lGLESv2 \
    -Wl,--no-as-needed -lvinix-agx-fault -Wl,--as-needed \
    -ldl -lpthread -lm
install -m644 "$SCRIPT_DIR/gl-triangle/egl_triangle.c" \
    "$STAGING/usr/share/examples/gl-triangle/"
install -m755 "$SCRIPT_DIR/gl-triangle/run-gl-triangle-agx" "$STAGING/usr/bin/"
install -m755 "$SCRIPT_DIR/gl-triangle/run-gl-triangle" "$STAGING/usr/bin/"
install -m755 "$SCRIPT_DIR/gl-triangle/run-virgl-smoke" "$STAGING/usr/bin/"
printf '%s\n' "mesa=$MESA_VERSION drivers=asahi,virgl,softpipe platforms=x11,surfaceless gbm=enabled" \
    > "$STAGING/usr/share/vinix/mesa-x11-egl"
# Keep the old marker for deployment scripts and images built before the
# virtual GPU path was added.
cp "$STAGING/usr/share/vinix/mesa-x11-egl" \
    "$STAGING/usr/share/vinix/asahi-x11-egl"

X11_STAGING="$SCRIPT_DIR/build-aarch64-x11/staging"
if [ -d "$X11_STAGING/usr/lib" ]; then
    echo "==> Overlaying exact Mesa GPU runtime onto ARM64 X11 staging"
    cp -a "$STAGING/." "$X11_STAGING/"
fi

echo "==> Mesa GPU userspace ready: $STAGING"
file "$STAGING/usr/bin/gl-triangle-agx"
