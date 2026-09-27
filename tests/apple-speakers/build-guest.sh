#!/bin/sh
# Build a small native-M1 sound test initramfs, independent of the desktop.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
sysroot=${VINIX_AARCH64_SYSROOT:-"$root/build-aarch64-userland/sysroot"}
output="$root/build-support/init-aarch64/initramfs-sound.tar"
cc=${CC:-clang}
for input in "$sysroot/include" "$sysroot/lib/crt1.o" "$sysroot/lib/libc.a"; do
    if [ ! -e "$input" ]; then
        echo "ERROR: AArch64 sysroot input is missing: $input" >&2
        exit 1
    fi
done
work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-m1-sound.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/rootfs/sbin"
"$cc" --target=aarch64-linux-musl --sysroot="$sysroot" \
    -static -O2 -fno-stack-protector -Wall -Wextra -Werror \
    "$root/tests/apple-speakers/guest_sound.c" -L"$sysroot/lib" -fuse-ld=lld \
    -o "$work/rootfs/sbin/init"
COPYFILE_DISABLE=1 tar --format=ustar -cf "$work/initramfs-sound.tar" \
    -C "$work/rootfs" .
mv -f "$work/initramfs-sound.tar" "$output"
echo "M1 sound test image: $output ($(wc -c < "$output" | tr -d ' ') bytes)"
