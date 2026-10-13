#!/bin/bash
# Cross-build a private Mesa Venus runtime for Vinix on KekVM.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
build=${VINIX_VENUS_BUILD_DIR:-$repo/build-aarch64-venus}
opengothic=${VINIX_OPENGOTHIC_BUILD_DIR:-$repo/build/opengothic}
assets=$repo/build-support/venus
version=25.0.5
mkdir -p "$build/downloads" "$build/sysroot"
archive=$build/downloads/mesa-$version.tar.xz
if [ ! -f "$archive" ]; then
    curl -fL --retry 3 "https://archive.mesa3d.org/mesa-$version.tar.xz" -o "$archive"
fi
"$repo/build-support/graphics-tools/run" venus-prepare "$archive" "$build" "$assets/packages.sha256"
source=$build/mesa-$version
if patch --batch --forward --dry-run -p1 -d "$source" < "$assets/vinix.patch" >/dev/null 2>&1; then
    patch --batch --forward -p1 -d "$source" < "$assets/vinix.patch"
elif ! patch --batch --forward --dry-run -R -p1 -d "$source" < "$assets/vinix.patch" >/dev/null 2>&1; then
    echo 'Mesa source does not match the Vinix Venus patch' >&2
    exit 1
fi
# Mesa's external generator SDK is provisioned separately from repository tools.
meson=${VINIX_VENUS_MESON:-$build/tools/bin/meson}
if [ ! -x "$meson" ]; then
    echo "Mesa generator SDK is missing: $meson; see build-support/venus/README.md" >&2
    exit 1
fi
export PATH="$build/tools/bin:$opengothic/host-tools/glslang/16.6.0/bin:$PATH"
cc=${VINIX_VENUS_CC:-$(command -v aarch64-linux-musl-gcc)}
cxx=${VINIX_VENUS_CXX:-$(command -v aarch64-linux-musl-g++)}
ar=$(command -v aarch64-linux-musl-ar)
strip=$(command -v aarch64-linux-musl-strip)
pkgconfig=$(command -v pkg-config)
sysroot=$build/sysroot
cat > "$build/cross.ini" <<CROSS
[binaries]
c = '$cc'
cpp = '$cxx'
ar = '$ar'
strip = '$strip'
pkg-config = '$pkgconfig'
[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
[properties]
needs_exe_wrapper = true
pkg_config_libdir = ['$sysroot/usr/lib/pkgconfig']
sys_root = '$sysroot'
[built-in options]
c_args = ['-O2', '-D__vinix__', '-I$sysroot/usr/include']
cpp_args = ['-O2', '-D__vinix__', '-I$sysroot/usr/include']
c_link_args = ['-L$sysroot/usr/lib', '-Wl,-rpath-link,$sysroot/usr/lib']
cpp_link_args = ['-L$sysroot/usr/lib', '-Wl,-rpath-link,$sysroot/usr/lib']
CROSS
reconfigure=()
[ ! -f "$build/mesa-build/build.ninja" ] || reconfigure=(--reconfigure)
"$meson" setup "${reconfigure[@]}" "$build/mesa-build" "$source" \
    --cross-file "$build/cross.ini" --prefix=/opt/venus --libdir=lib --buildtype=release \
    -Dplatforms=x11 -Dgallium-drivers= -Dvulkan-drivers=virtio -Dglx=disabled \
    -Degl=disabled -Dgbm=disabled -Dopengl=false -Dgles1=disabled -Dgles2=disabled \
    -Dllvm=disabled -Dshader-cache=disabled -Dxmlconfig=disabled -Dbuild-tests=false \
    -Dtools= -Dvulkan-layers=overlay -Dvalgrind=disabled -Dlibunwind=disabled
ninja -C "$build/mesa-build" -j"${VINIX_VENUS_JOBS:-8}"
DESTDIR="$build/staging" "$meson" install -C "$build/mesa-build"
# Dependencies stay private to Venus. Xvfb keeps its matching X11 runtime.
"$repo/build-support/graphics-tools/run" libraries "$sysroot/usr/lib" "$build/staging/opt/venus/lib"
mkdir -p "$build/staging/opt/venus/bin"
"$repo/build-support/compile-v-module" "$assets/availablecore" \
    "$build/available.c" --arch arm64
"$cc" -O2 -static -Wall -Wextra -Werror -Wno-unused-function \
    -Wno-unused-label -Wno-unused-parameter -I"$source/include/drm-uapi" \
    -isystem "$sysroot/usr/include" "$build/available.c" \
    -o "$build/staging/opt/venus/bin/venus-available"
"$cc" -O2 -static -I"$source/include/drm-uapi" "$repo/tests/virtio-gpu-venus/abi.c" \
    -o "$build/staging/opt/venus/bin/venus-abi"
"$cc" -O2 -I"$opengothic/vulkan-headers/include" "$repo/tests/virtio-gpu-venus/smoke.c" \
    -L"$opengothic/staging/opt/opengothic/lib" -Wl,--allow-shlib-undefined \
    -l:libvulkan.so.1 -o "$build/staging/opt/venus/bin/venus-smoke"
echo "Venus runtime ready: $build/staging"
