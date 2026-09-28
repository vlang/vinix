#!/bin/sh
# Boot the kernel already built for ARCH (aarch64, the default, or amd64) with
# the OpenBSD security test as PID 1. Build the kernel first:
#   make -C kernel CC=clang ARCH=aarch64 LIMINE_MP=1 V=...
#   V=... ./build-amd64.sh --no-userland --no-iso
set -eu

repo=$(cd "$(dirname "$0")/../.." && pwd)
arch=${1:-aarch64}
work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-openbsd-security.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM

mkdir -p "$work/rootfs/root" "$work/rootfs/sbin" "$work/rootfs/tmp"
case "$arch" in
aarch64)
	sysroot=${VINIX_AARCH64_SYSROOT:-"$repo/build-aarch64-userland/sysroot"}
	"${CC:-clang}" --target=aarch64-linux-musl --sysroot="$sysroot" \
		-static -O2 -Wall -Wextra -Werror \
		"$repo/tests/openbsd-security/test.c" -L"$sysroot/lib" -fuse-ld=lld \
		-o "$work/init"
	# run-aarch64.sh overlays the test as /sbin/init itself.
	COPYFILE_DISABLE=1 tar --format=ustar -cf "$work/initramfs.tar" -C "$work/rootfs" .
	python3 "$repo/tests/openbsd-security/run_vm.py" --arch aarch64 \
		--init "$work/init" --initramfs "$work/initramfs.tar" \
		--state-dir "$work/vm" --timeout "${VINIX_QEMU_TIMEOUT:-600}"
	;;
amd64)
	"${CC_AMD64:-x86_64-linux-musl-gcc}" -static -O2 -Wall -Wextra -Werror \
		"$repo/tests/openbsd-security/test.c" -o "$work/rootfs/sbin/init" -lpthread
	mkdir -p "$work/rootfs/dev"
	COPYFILE_DISABLE=1 tar --format=ustar -cf "$work/initramfs.tar" -C "$work/rootfs" .
	VINIX_AMD64_KERNEL="${VINIX_AMD64_KERNEL:-$repo/build-amd64-kernel/bin/vinix}" \
	VINIX_AMD64_INITRAMFS="$work/initramfs.tar" \
	VINIX_AMD64_ISO="$work/test.iso" \
	VINIX_AMD64_ISO_BUILD_DIR="$work/iso" \
		"$repo/build-support/build-amd64-iso.sh" >/dev/null
	qemu=$(command -v "${VINIX_QEMU_X86_64:-qemu-system-x86_64}")
	firmware=${VINIX_OVMF_CODE:-"$(cd "$(dirname "$qemu")/.." && pwd)/share/qemu/edk2-x86_64-code.fd"}
	python3 "$repo/tests/openbsd-security/run_vm.py" --arch amd64 \
		--iso "$work/test.iso" --qemu "$qemu" --firmware "$firmware" \
		--timeout "${VINIX_QEMU_TIMEOUT:-600}"
	;;
*)
	echo "usage: $0 [aarch64|amd64]" >&2
	exit 2
	;;
esac
