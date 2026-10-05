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
source=$root/build-support/xorg-server/vinix-wine-host.c
header=$root/build-support/xorg-server/vinix-clipboard.h
if [ -x "$binary" ] && [ "$binary" -nt "$source" ] && [ "$binary" -nt "$header" ]; then
    exit 0
fi
triple=$arch-linux-musl
gcc=$(find "$userland/usr/lib/gcc/$arch-alpine-linux-musl" -mindepth 1 -maxdepth 1 -type d | sort | tail -n 1)
clang=${LLVM_BIN:-/opt/homebrew/opt/llvm/bin}/clang
[ -x "$clang" ] || clang=clang
temp=$(mktemp "$x11/usr/bin/.vinix-wine-host.XXXXXX")
trap 'rm -f "$temp"' EXIT HUP INT TERM
echo "==> Updating the $arch embedded X11 clipboard bridge..."
"$clang" --target="$triple" --sysroot="$sysroot" --gcc-install-dir="$gcc" \
    -static-libgcc -O2 -Wall -Wextra -Werror -D__vinix__ -I"$sysroot/usr/include" \
    "$source" -fuse-ld=lld -L"$sysroot/usr/lib" -L"$sysroot/lib" \
    -Wl,-rpath-link,"$sysroot/usr/lib" -Wl,-rpath-link,"$sysroot/lib" \
    -lXtst -lXdamage -lX11 -lXext -lxcb -o "$temp"
chmod 755 "$temp"
mv -f "$temp" "$binary"
