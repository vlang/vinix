#!/bin/bash
# Boot one Vinix VM, then boot a second Vinix VM using QEMU within the first.
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
userland=${VINIX_AARCH64_USERLAND_BUILD_DIR:-"$repo/build-aarch64-userland"}
minirootfs=${VINIX_ALPINE_MINIROOTFS:-"$userland/downloads/alpine-minirootfs-3.21.7-aarch64.tar.gz"}
qemu_staging=${VINIX_QEMU_SYSTEM_STAGING:-"$repo/build-aarch64-qemu-system/staging"}
work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-qemu-nested.XXXXXX")

cleanup() { rm -rf "$work"; }
trap cleanup EXIT INT TERM

if [ "${VINIX_QEMU_NESTED_NO_BUILD:-0}" != 1 ]; then
    . "$repo/build-support/find-v.sh"
    echo '==> Building the Vinix kernel for both VM levels'
    make -C "$repo/kernel" CC=clang ARCH=aarch64 V="$V" LIMINE_MP=1 \
        -j"$(sysctl -n hw.ncpu 2>/dev/null || nproc)"
fi

for input in "$minirootfs" "$qemu_staging/usr/bin/qemu-system-aarch64" \
    "$qemu_staging/usr/bin/vinix-qemu" \
    "$qemu_staging/usr/share/qemu/edk2-aarch64-code.fd" \
    "$qemu_staging/usr/share/qemu/edk2-arm-vars.fd" \
    "$repo/kernel/bin/vinix" "$repo/boot-image/limine-bin/BOOTAA64.EFI"; do
    if [ ! -f "$input" ]; then
        echo "missing nested QEMU test input: $input" >&2
        echo 'Run ./scripts/build-qemu-system-aarch64.sh and build the AArch64 kernel and Limine.' >&2
        exit 1
    fi
done
for tool in clang ld.lld rsync tar; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "missing test tool: $tool" >&2
        exit 1
    }
done

echo '==> Building the inner Vinix initramfs and boot disk'
clang --target=aarch64-linux-none -nostdlib -ffreestanding -O2 -c \
    "$repo/tests/qemu-nested/inner-init.c" -o "$work/inner-init.o"
ld.lld -m aarch64elf --nostdlib -static \
    -o "$work/inner-init" "$work/inner-init.o"
mkdir -p "$work/inner-root/sbin"
install -m755 "$work/inner-init" "$work/inner-root/sbin/init"
COPYFILE_DISABLE=1 tar --format=ustar -cf "$work/inner-initramfs.tar" \
    -C "$work/inner-root" .
"$repo/scripts/build-vinix-guest-disk.sh" "$work/vinix-inner.img" \
    "$work/inner-initramfs.tar"

echo '==> Assembling the outer Vinix initramfs'
mkdir -p "$work/outer-root/root"
tar -xzf "$minirootfs" -C "$work/outer-root"
rsync -a "$qemu_staging/" "$work/outer-root/"
install -m644 "$work/vinix-inner.img" "$work/outer-root/root/vinix-inner.img"
rm -f "$work/outer-root/sbin/init"
install -m755 "$repo/build-support/init-aarch64/alpine-init" "$work/outer-root/sbin/init"
mkdir -p "$work/outer-root/dev" "$work/outer-root/proc" \
    "$work/outer-root/sys" "$work/outer-root/tmp" "$work/outer-root/run"
chmod 1777 "$work/outer-root/tmp"
COPYFILE_DISABLE=1 tar --format=ustar -cf "$work/outer-initramfs.tar" \
    -C "$work/outer-root" .

set -- --init "$repo/tests/qemu-nested/outer-init.sh" \
    --initramfs "$work/outer-initramfs.tar" \
    --state-dir "$work/vm" \
    --timeout "${VINIX_QEMU_NESTED_TIMEOUT:-900}" \
    --mem "${VINIX_QEMU_MEM:-4096}" \
    --pass-marker 'VINIX NESTED QEMU: PASS' \
    --fail-marker 'VINIX NESTED QEMU: FAIL'
if [ -n "${VINIX_QEMU_NESTED_LOG:-}" ]; then
    set -- "$@" --log "$VINIX_QEMU_NESTED_LOG"
fi
set -- "$@" --no-build
python3 "$repo/tests/docker/run_vm.py" "$@"
