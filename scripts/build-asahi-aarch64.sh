#!/bin/bash
# Build the Mesa Asahi and VirGL userspace used by Vinix/aarch64.
#
# By default this is the Mesa Omarchy packages, omacom/mesa at the pinned
# commit below, with the Asahi Gallium and Honeykrisp Vulkan drivers, built
# unmodified for Linux. Vinix provides the Linux interfaces it uses, including
# the DRM sysfs entries libdrm looks devices up in. VINIX_MESA_RELEASE=25.0.5
# builds the earlier release with Vinix's patches instead: its legacy Asahi
# interface is what the fake G17 renderer patch targets.
#
# Run this in the Debian aarch64 build VM. Native Mesa helper programs are
# built for the VM; the installed driver is linked against an Alpine musl
# sysroot so it can run in the Vinix initramfs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${VINIX_ASAHI_BUILD_DIR:-$SCRIPT_DIR/build-aarch64-asahi}"
MESA_RELEASE="${VINIX_MESA_RELEASE:-omarchy}"
case "$MESA_RELEASE" in
    omarchy)
        MESA_COMMIT=b7b03c5b3b8abe1e040d6056dc62c01b02d3639c
        MESA_VERSION=26.3.0-devel
        MESA_ARCHIVE="$BUILD_DIR/downloads/mesa-$MESA_COMMIT.tar.gz"
        MESA_URL="https://codeload.github.com/omacom/mesa/tar.gz/$MESA_COMMIT"
        MESA_CHECKSUM=(sha256 924e5a7b57f61c6ccee4b538959a3d66d21a299f8346a9b576626c682a77ca5b)
        MESA_SRC="$BUILD_DIR/mesa-$MESA_COMMIT"
        MESA_PATCHES=()
        VTN_BINDGEN=vtn_bindgen2
        BUILD_SUFFIX=-omarchy
        VULKAN_DRIVERS=asahi
        ;;
    25.0.5)
        MESA_COMMIT=
        MESA_VERSION=25.0.5
        MESA_ARCHIVE="$BUILD_DIR/downloads/mesa-$MESA_VERSION.tar.xz"
        MESA_URL="https://archive.mesa3d.org/mesa-$MESA_VERSION.tar.xz"
        MESA_CHECKSUM=(blake2b f17f8c2a733fd3c37f346b9304241dc1d13e01df9c8c723b73b10279dd3c2ebed062ec1f15cdbc8b9936bae840a087b23ac38cae7d8982228d582d468ab8c9c9)
        MESA_SRC="$BUILD_DIR/mesa-$MESA_VERSION"
        MESA_PATCHES=(
            "$SCRIPT_DIR/patches/mesa/jinx-working-patch.patch"
            "$SCRIPT_DIR/patches/mesa/vinix-virgl-render-node.patch"
            "$SCRIPT_DIR/patches/mesa/vinix-fake-g17-renderer.patch"
            "$SCRIPT_DIR/patches/mesa/vinix-libagx-link-names.patch"
        )
        VTN_BINDGEN=vtn_bindgen
        BUILD_SUFFIX=
        VULKAN_DRIVERS=
        ;;
    *)
        echo "VINIX_MESA_RELEASE must be omarchy or 25.0.5" >&2
        exit 1
        ;;
esac
# Builds of each release are kept apart; the staging tree is the output.
HOST_TOOLS="$BUILD_DIR/host-tools$BUILD_SUFFIX"
SYSROOT="$BUILD_DIR/sysroot"
TARGET_BUILD="$BUILD_DIR/target-build$BUILD_SUFFIX"
STAGING="$BUILD_DIR/staging"
ALPINE_MIRROR="${ALPINE_MIRROR:-https://dl-cdn.alpinelinux.org/alpine/v3.21}"
ALPINE_ARCH=aarch64
NPROC="${NPROC:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}"

if [ "$(uname -s)" != Linux ] || [ "$(uname -m)" != aarch64 ]; then
    echo "scripts/build-asahi-aarch64.sh must run in the Debian aarch64 build VM" >&2
    exit 1
fi

# glslangValidator compiles the Honeykrisp driver's own shaders.
for tool in curl meson ninja python3 pkg-config clang clang++ ld.lld patch tar \
    file install glslangValidator; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "missing build tool: $tool" >&2
        exit 1
    fi
done

if ! command -v llvm-config-19 >/dev/null 2>&1 \
    && ! command -v llvm-config >/dev/null 2>&1; then
    echo "missing native Mesa compiler dependencies" >&2
    echo "install libclang-19-dev libclang-rt-19-dev libclc-19-dev libllvmspirvlib-19-dev spirv-tools" >&2
    exit 1
fi

mkdir -p "$BUILD_DIR/downloads" "$HOST_TOOLS/bin" "$SYSROOT" "$STAGING"

if [ ! -f "$MESA_ARCHIVE" ] && [ ! -d "$MESA_SRC" ]; then
    echo "==> Downloading Mesa $MESA_VERSION"
    curl -fL --retry 3 -o "$MESA_ARCHIVE" "$MESA_URL"
fi

if [ -f "$MESA_ARCHIVE" ]; then
    "$SCRIPT_DIR/build-support/graphics-tools/run" checksum "${MESA_CHECKSUM[0]}" \
        "$MESA_ARCHIVE" "${MESA_CHECKSUM[1]}" 'Mesa archive'
fi

if [ ! -d "$MESA_SRC" ]; then
    tar -xf "$MESA_ARCHIVE" -C "$BUILD_DIR"
fi

for MESA_PATCH in ${MESA_PATCHES[@]+"${MESA_PATCHES[@]}"}; do
    if patch --dry-run -p1 -d "$MESA_SRC" < "$MESA_PATCH" >/dev/null 2>&1; then
        echo "==> Applying $(basename "$MESA_PATCH")"
        patch -p1 -d "$MESA_SRC" < "$MESA_PATCH"
    elif ! patch --dry-run -R -p1 -d "$MESA_SRC" < "$MESA_PATCH" >/dev/null 2>&1; then
        echo "Mesa source is neither clean nor patched for $(basename "$MESA_PATCH")" >&2
        exit 1
    fi
done

echo "==> Building native Asahi shader tools"
NATIVE_BUILD="$BUILD_DIR/native-tools-build$BUILD_SUFFIX"
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
# The same compiler for C and C++: Mesa probes flags with one and passes them
# to both, and the VM's cc may be GCC while its c++ is Clang.
if [ -f "$NATIVE_BUILD/build.ninja" ]; then
    CC=clang CXX=clang++ meson setup --reconfigure "$NATIVE_BUILD" "$MESA_SRC" \
        "${NATIVE_MESON_OPTIONS[@]}"
else
    CC=clang CXX=clang++ meson setup "$NATIVE_BUILD" "$MESA_SRC" \
        "${NATIVE_MESON_OPTIONS[@]}"
fi
ninja -C "$NATIVE_BUILD" -j"$NPROC" \
    src/compiler/clc/mesa_clc \
    "src/compiler/spirv/$VTN_BINDGEN" \
    src/asahi/clc/asahi_clc
install -m755 "$NATIVE_BUILD/src/compiler/clc/mesa_clc" "$HOST_TOOLS/bin/"
install -m755 "$NATIVE_BUILD/src/compiler/spirv/$VTN_BINDGEN" "$HOST_TOOLS/bin/"
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
    libxrandr libxrandr-dev libxxf86vm libxxf86vm-dev \
    libxshmfence libxshmfence-dev vulkan-loader; do
    extract_apk main "$package"
done
# Honeykrisp's display support reads monitor data with libdisplay-info.
download_index community
for package in libdisplay-info libdisplay-info-dev; do
    extract_apk community "$package"
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

# Target programs link with compiler-rt. Clang finds Debian's aarch64 builtins
# for the musl triple too, once they are installed.
if [ ! -f "$(clang --target=aarch64-linux-musl --rtlib=compiler-rt -print-libgcc-file-name)" ]; then
    echo "missing compiler-rt for aarch64; install libclang-rt-19-dev" >&2
    exit 1
fi

LLVM_AR="$(command -v llvm-ar-19 || command -v llvm-ar)"
LLVM_NM="$(command -v llvm-nm-19 || command -v llvm-nm)"
LLVM_STRIP="$(command -v llvm-strip-19 || command -v llvm-strip)"
# The patched 25.0.5 knows Vinix as its own system; the Omarchy Mesa is built
# for Linux, whose interfaces Vinix provides.
if [ "$MESA_RELEASE" = 25.0.5 ]; then
    CROSS_SYSTEM=vinix
    CROSS_DEFINES=", '-D__vinix__'"
else
    CROSS_SYSTEM=linux
    CROSS_DEFINES=""
fi
CROSS_FILE="$BUILD_DIR/aarch64-vinix$BUILD_SUFFIX.ini"
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
system = '$CROSS_SYSTEM'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'

[properties]
sys_root = '$SYSROOT'
pkg_config_libdir = ['$SYSROOT/usr/lib/pkgconfig', '$SYSROOT/usr/share/pkgconfig']

[built-in options]
c_args = ['-O2', '-fPIC'$CROSS_DEFINES]
cpp_args = ['-O2', '-fPIC'$CROSS_DEFINES]
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
    # Minecraft/GLFW creates GLX contexts. Build libGL against the same
    # Gallium drivers as EGL so DRI3 can reach Asahi or VirGL directly.
    -Dglx=dri
    -Dglvnd=disabled
    -Degl=enabled
    -Dgbm=enabled
    -Dopengl=true
    -Dgles1=disabled
    -Dgles2=enabled
    -Dshared-glapi=enabled
    -Dgallium-drivers=asahi,virgl,softpipe
    "-Dvulkan-drivers=$VULKAN_DRIVERS"
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
if [ ! -f "$STAGING/usr/lib/libGL.so.1" ]; then
    echo "Mesa's DRI GLX library was not installed" >&2
    exit 1
fi

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
    'libXrender.so*' 'libXrandr.so*' 'libXxf86vm.so*' \
    'libxshmfence.so*' ${VULKAN_DRIVERS:+'libvulkan.so*' 'libdisplay-info.so*'}; do
    for library in "$SYSROOT/usr/lib"/$pattern; do
        [ -e "$library" ] || continue
        cp -a "$library" "$STAGING/usr/lib/"
    done
done

TARGET_CC=(clang --target=aarch64-linux-musl --sysroot="$SYSROOT" -fuse-ld=lld --rtlib=compiler-rt --unwindlib=none)
"${TARGET_CC[@]}" -O2 -Wall -Wextra -Werror -fPIC -shared \
    "$SCRIPT_DIR/tests/agx-fake-g17/ioctl_fault.c" \
    -o "$STAGING/usr/lib/libvinix-agx-fault.so" -ldl
"$SCRIPT_DIR/gl-triangle/stage" "$STAGING/usr/share/examples/gl-triangle" --arch arm64
"${TARGET_CC[@]}" -O2 -D__vinix__ -fwrapv -fno-strict-aliasing \
    -I"$STAGING/usr/include" \
    "$STAGING/usr/share/examples/gl-triangle/egl_triangle.c" \
    -L"$STAGING/usr/lib" -Wl,-rpath-link,"$STAGING/usr/lib" \
    -o "$STAGING/usr/bin/gl-triangle-agx" -lEGL -lGLESv2 \
    -Wl,--no-as-needed -lvinix-agx-fault -Wl,--as-needed \
    -ldl -lpthread -lm
install -m755 "$SCRIPT_DIR/gl-triangle/run-gl-triangle-agx" "$STAGING/usr/bin/"
install -m755 "$SCRIPT_DIR/gl-triangle/run-gl-triangle" "$STAGING/usr/bin/"
install -m755 "$SCRIPT_DIR/gl-triangle/run-m1-agx-smoke" "$STAGING/usr/bin/"
install -m755 "$SCRIPT_DIR/gl-triangle/run-virgl-smoke" "$STAGING/usr/bin/"
printf '%s\n' "mesa=$MESA_VERSION${MESA_COMMIT:+ source=omacom/mesa@$MESA_COMMIT} drivers=asahi,virgl,softpipe${VULKAN_DRIVERS:+ vulkan=$VULKAN_DRIVERS} platforms=x11,surfaceless gbm=enabled glx=dri" \
    > "$STAGING/usr/share/vinix/mesa-x11-egl"
# Keep the old marker for deployment scripts and images built before the
# virtual GPU path was added.
cp "$STAGING/usr/share/vinix/mesa-x11-egl" \
    "$STAGING/usr/share/vinix/asahi-x11-egl"

# VINIX_ASAHI_X11_STAGING names another X11 layer; empty leaves the layer alone.
X11_STAGING="${VINIX_ASAHI_X11_STAGING-$SCRIPT_DIR/build-aarch64-x11/staging}"
if [ -n "$X11_STAGING" ] && [ -d "$X11_STAGING/usr/lib" ]; then
    echo "==> Overlaying exact Mesa GPU runtime onto ARM64 X11 staging"
    cp -a "$STAGING/." "$X11_STAGING/"
fi

echo "==> Mesa GPU userspace ready: $STAGING"
file "$STAGING/usr/bin/gl-triangle-agx"
