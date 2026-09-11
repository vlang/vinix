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
	--timeout "${VINIX_QEMU_TIMEOUT:-300}"
