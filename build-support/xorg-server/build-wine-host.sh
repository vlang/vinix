#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Refresh only the embedded input bridge using an already-built X11 sysroot.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
arch=${1:-aarch64}
x11=${2:-$root/build-$arch-x11/staging}
sysroot=${VINIX_X11_SYSROOT:-$(dirname "$x11")/sysroot}
userland=${3:-$root/build-$arch-userland/staging}
binary=$x11/usr/bin/vinix-wine-host
source=$root/build-support/xorg-server/wine-host-v-abi.c
header=$root/build-support/xorg-server/wine-host-v-abi.h
core=$root/build-support/xorg-server/winehost/core.v
generator=$root/build-support/xorg-server/compile-v-host.py
if [ -x "$binary" ] && [ "$binary" -nt "$source" ] && [ "$binary" -nt "$header" ] &&
   [ "$binary" -nt "$core" ] && [ "$binary" -nt "$generator" ]; then
    exit 0
fi
triple=$arch-linux-musl
gcc=$(find "$userland/usr/lib/gcc/$arch-alpine-linux-musl" -mindepth 1 -maxdepth 1 -type d | sort | tail -n 1)
clang=${LLVM_BIN:-/opt/homebrew/opt/llvm/bin}/clang
[ -x "$clang" ] || clang=clang
temp=$(mktemp "$x11/usr/bin/.vinix-wine-host.XXXXXX")
generated=$temp.core.c
trap 'rm -f "$temp" "$generated"' EXIT HUP INT TERM
v_arch=arm64
[ "$arch" != x86_64 ] && [ "$arch" != amd64 ] || v_arch=amd64
python3 "$generator" winehost "$generated" --arch "$v_arch"
echo "==> Updating the $arch embedded X11 clipboard bridge..."
"$clang" --target="$triple" --sysroot="$sysroot" --gcc-install-dir="$gcc" \
    -static-libgcc -O2 -Wall -Wextra -Werror -D__vinix__ -I"$sysroot/usr/include" \
    "$source" "$generated" -I"$root/build-support/xorg-server" -fuse-ld=lld -L"$sysroot/usr/lib" -L"$sysroot/lib" \
    -Wl,-rpath-link,"$sysroot/usr/lib" -Wl,-rpath-link,"$sysroot/lib" \
    -lXtst -lXdamage -lX11 -lXext -lxcb -o "$temp"
chmod 755 "$temp"
mv -f "$temp" "$binary"
