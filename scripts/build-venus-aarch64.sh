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
python3 - "$archive" "$build" "$assets/packages.sha256" <<'PY'
import concurrent.futures, hashlib, pathlib, sys, tarfile, urllib.request
archive, build, manifest = map(pathlib.Path, sys.argv[1:])
expected = 'f17f8c2a733fd3c37f346b9304241dc1d13e01df9c8c723b73b10279dd3c2ebed062ec1f15cdbc8b9936bae840a087b23ac38cae7d8982228d582d468ab8c9c9'
if hashlib.blake2b(archive.read_bytes()).hexdigest() != expected:
    raise SystemExit('Mesa source checksum mismatch')
source = build / 'mesa-25.0.5'
if not source.exists():
    with tarfile.open(archive) as tar: tar.extractall(build)
packages = [line.split() for line in manifest.read_text().splitlines() if line and not line.startswith('#')]
def download(item):
    name, expected = item
    dest = build / 'downloads' / name
    if not dest.exists():
        url = 'https://dl-cdn.alpinelinux.org/alpine/v3.21/main/aarch64/' + name
        dest.write_bytes(urllib.request.urlopen(url).read())
    if hashlib.sha256(dest.read_bytes()).hexdigest() != expected:
        raise RuntimeError('Alpine checksum mismatch: ' + name)
    return dest
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
    archives = list(pool.map(download, packages))
for archive in archives:
    with tarfile.open(archive) as tar: tar.extractall(build / 'sysroot')
PY
source=$build/mesa-$version
if patch --batch --forward --dry-run -p1 -d "$source" < "$assets/vinix.patch" >/dev/null 2>&1; then
    patch --batch --forward -p1 -d "$source" < "$assets/vinix.patch"
elif ! patch --batch --forward --dry-run -R -p1 -d "$source" < "$assets/vinix.patch" >/dev/null 2>&1; then
    echo 'Mesa source does not match the Vinix Venus patch' >&2
    exit 1
fi
# Use a private Python environment so code generators see the same modules.
[ -x "$build/tools/bin/meson" ] || python3 -m venv "$build/tools"
"$build/tools/bin/pip" -q install meson==1.11.2 mako==1.3.12 MarkupSafe==3.0.3 pyyaml==6.0.3 packaging==26.3
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
meson setup "${reconfigure[@]}" "$build/mesa-build" "$source" \
    --cross-file "$build/cross.ini" --prefix=/opt/venus --libdir=lib --buildtype=release \
    -Dplatforms=x11 -Dgallium-drivers= -Dvulkan-drivers=virtio -Dglx=disabled \
    -Degl=disabled -Dgbm=disabled -Dopengl=false -Dgles1=disabled -Dgles2=disabled \
    -Dllvm=disabled -Dshader-cache=disabled -Dxmlconfig=disabled -Dbuild-tests=false \
    -Dtools= -Dvulkan-layers=overlay -Dvalgrind=disabled -Dlibunwind=disabled
ninja -C "$build/mesa-build" -j"${VINIX_VENUS_JOBS:-8}"
DESTDIR="$build/staging" meson install -C "$build/mesa-build"
# Dependencies stay private to Venus. Xvfb keeps its matching X11 runtime.
python3 - "$sysroot/usr/lib" "$build/staging/opt/venus/lib" <<'PYLIB'
import os, pathlib, shutil, sys
source, dest = map(pathlib.Path, sys.argv[1:])
for library in source.glob('*.so*'):
    target = dest / library.name
    if target.exists() or target.is_symlink(): target.unlink()
    if library.is_symlink(): target.symlink_to(os.readlink(library))
    else: shutil.copy2(library, target)
PYLIB
mkdir -p "$build/staging/opt/venus/bin"
python3 "$repo/build-support/compile-v-module.py" "$assets/availablecore" \
    "$build/available.c" --arch arm64
"$cc" -O2 -static -Wall -Wextra -Werror -Wno-unused-function \
    -Wno-unused-label -Wno-unused-parameter -I"$source/include/drm-uapi" "$build/available.c" \
    -o "$build/staging/opt/venus/bin/venus-available"
"$cc" -O2 -static -I"$source/include/drm-uapi" "$repo/tests/virtio-gpu-venus/abi.c" \
    -o "$build/staging/opt/venus/bin/venus-abi"
"$cc" -O2 -I"$opengothic/vulkan-headers/include" "$repo/tests/virtio-gpu-venus/smoke.c" \
    -L"$opengothic/staging/opt/opengothic/lib" -Wl,--allow-shlib-undefined \
    -l:libvulkan.so.1 -o "$build/staging/opt/venus/bin/venus-smoke"
echo "Venus runtime ready: $build/staging"
