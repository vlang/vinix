#!/bin/sh
# Boot Vinix once, let it restart itself with reboot(2), and check that a file
# written just before the restart is still there afterwards.
#
#   ./build-userland-aarch64.sh        # once, for the musl test sysroot
#   tests/reboot-persistence/run.sh
#
# VINIX_REBOOT_PERSISTENCE_NO_BUILD=1 reuses kernel/bin/vinix.
set -eu

repo=$(cd "$(dirname "$0")/../.." && pwd)
sysroot=${VINIX_AARCH64_SYSROOT:-"$repo/build-aarch64-userland/sysroot"}
cc=${CC:-clang}
work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-reboot-persistence.XXXXXX")

cleanup() {
	rm -rf "$work"
}
trap cleanup EXIT INT TERM

for input in "$sysroot/include" "$sysroot/lib/crt1.o" "$sysroot/lib/libc.a"; do
	if [ ! -e "$input" ]; then
		echo "ERROR: AArch64 test sysroot input is missing: $input" >&2
		echo "       Run ./build-userland-aarch64.sh first or set VINIX_AARCH64_SYSROOT." >&2
		exit 1
	fi
done

echo "==> Building the static AArch64 reboot-persistence init..."
"$cc" --target=aarch64-linux-musl --sysroot="$sysroot" \
	-static -O2 -fno-stack-protector -Wall -Wextra -Werror \
	"$repo/tests/reboot-persistence/test.c" -L"$sysroot/lib" -fuse-ld=lld \
	-o "$work/init"

# The runner supplies the real PID 1 as its last initramfs overlay; this base
# only has to provide the mount point the persistent volume lands on.
mkdir -p "$work/rootfs/root" "$work/rootfs/sbin"
COPYFILE_DISABLE=1 tar --format=ustar -cf "$work/initramfs.tar" -C "$work/rootfs" .

python3 "$repo/tests/reboot-persistence/run_vm.py" \
	--init "$work/init" \
	--initramfs "$work/initramfs.tar" \
	--state-dir "$work/vm" \
	--timeout "${VINIX_QEMU_TIMEOUT:-240}"
