#!/bin/sh
set -eu

repo=$(cd "$(dirname "$0")/../.." && pwd)
sysroot=${VINIX_AARCH64_SYSROOT:-"$repo/build-aarch64-userland/sysroot"}
cc=${CC:-clang}
work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-qemu-core.XXXXXX")

cleanup() {
	rm -rf "$work"
}
trap cleanup EXIT INT TERM

# `run.sh amd64` runs the same test on the amd64 kernel build-amd64.sh made:
# built for x86-64, installed as /sbin/init in a throwaway ISO, and booted once
# under TCG, there being no persistent volume for a second boot to check.
if [ "${1:-}" = amd64 ]; then
	mkdir -p "$work/rootfs/root" "$work/rootfs/sbin" "$work/rootfs/tmp" "$work/rootfs/dev"
	"${CC_AMD64:-x86_64-linux-musl-gcc}" -static -O2 -Wall -Wextra -Werror \
		"$repo/tests/qemu-core/test.c" -o "$work/rootfs/sbin/init" -lpthread
	COPYFILE_DISABLE=1 tar --format=ustar -cf "$work/initramfs.tar" -C "$work/rootfs" .
	VINIX_AMD64_KERNEL="${VINIX_AMD64_KERNEL:-$repo/build-amd64-kernel/bin/vinix}" \
	VINIX_AMD64_INITRAMFS="$work/initramfs.tar" \
	VINIX_AMD64_ISO="$work/test.iso" \
	VINIX_AMD64_ISO_BUILD_DIR="$work/iso" \
		"$repo/build-support/build-amd64-iso.sh" >/dev/null
	qemu=$(command -v "${VINIX_QEMU_X86_64:-qemu-system-x86_64}")
	firmware=${VINIX_OVMF_CODE:-"$(cd "$(dirname "$qemu")/.." && pwd)/share/qemu/edk2-x86_64-code.fd"}
	python3 "$repo/tests/qemu-core/run_vm.py" --arch amd64 --iso "$work/test.iso" \
		--qemu "$qemu" --firmware "$firmware" --timeout "${VINIX_QEMU_TIMEOUT:-900}" \
		--cpus "${VINIX_QEMU_CORE_CPUS:-4}"
	exit
fi

for input in \
	"$sysroot/include" \
	"$sysroot/lib/crt1.o" \
	"$sysroot/lib/libc.a" \
	"$sysroot/lib/libgcc.a"; do
	if [ ! -e "$input" ]; then
		echo "ERROR: AArch64 test sysroot input is missing: $input" >&2
		echo "       Run ./build-userland-aarch64.sh first or set VINIX_AARCH64_SYSROOT." >&2
		exit 1
	fi
done
for command_name in "$cc" python3 tar; do
	command -v "$command_name" >/dev/null 2>&1 || {
		echo "ERROR: required command not found: $command_name" >&2
		exit 1
	}
done

echo "==> Building static AArch64 core-test init..."
"$cc" --target=aarch64-linux-musl --sysroot="$sysroot" \
	-static -O2 -fno-stack-protector -Wall -Wextra -Werror \
	"$repo/tests/qemu-core/test.c" -L"$sysroot/lib" -fuse-ld=lld \
	-o "$work/init"

# The actual PID 1 is supplied as the runner's final initramfs overlay. This
# tiny base only needs to provide the persistent EXT2 mount point.
mkdir -p "$work/rootfs/root" "$work/rootfs/sbin"
COPYFILE_DISABLE=1 tar --format=ustar -cf "$work/initramfs.tar" \
	-C "$work/rootfs" .

python3 "$repo/tests/qemu-core/run_vm.py" \
	--init "$work/init" \
	--initramfs "$work/initramfs.tar" \
	--state-dir "$work/vm" \
	--timeout "${VINIX_QEMU_TIMEOUT:-300}"
