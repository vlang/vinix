#!/bin/sh
# Boot Vinix once per step, make one change to the persistent volume -- mkdir,
# create, rename, link, unlink, chmod, and an inode freed by exit and by
# execve -- stop the machine the moment the call returns, and check with
# debugfs that the change is on the volume. Nothing calls sync.
#
#   ./build-userland-aarch64.sh        # once, for the musl test sysroot
#   tests/disk-no-sync/run.sh
#
# VINIX_DISK_NO_SYNC_NO_BUILD=1 reuses kernel/bin/vinix. Needs e2fsprogs.
set -eu

repo=$(cd "$(dirname "$0")/../.." && pwd)
sysroot=${VINIX_AARCH64_SYSROOT:-"$repo/build-aarch64-userland/sysroot"}
cc=${CC:-clang}
work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-disk-no-sync.XXXXXX")

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

echo "==> Building the static AArch64 no-sync init..."
"$cc" --target=aarch64-linux-musl --sysroot="$sysroot" \
	-static -O2 -fno-stack-protector -Wall -Wextra -Werror \
	"$repo/tests/disk-no-sync/test.c" -L"$sysroot/lib" -fuse-ld=lld \
	-o "$work/init"

python3 "$repo/tests/disk-no-sync/run_vm.py" \
	--init "$work/init" \
	--state-dir "$work/vm" \
	--timeout "${VINIX_QEMU_TIMEOUT:-240}"
