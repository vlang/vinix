#!/bin/sh
# Stream a file far larger than the block cache onto a disk root while other
# threads read, create files and sleep, and fail if any of them waits too long
# on average, or ten seconds at once. Each prints its worst and mean wait, with
# nothing being written and while the stream runs.
#
#   ./build-userland-aarch64.sh        # once, for the musl test sysroot
#   tests/disk-writeback/run.sh
#
# VINIX_DISK_ROOT_NO_BUILD=1 reuses kernel/bin/vinix.
set -eu

repo=$(cd "$(dirname "$0")/../.." && pwd)
sysroot=${VINIX_AARCH64_SYSROOT:-"$repo/build-aarch64-userland/sysroot"}
cc=${CC:-clang}
work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-disk-writeback.XXXXXX")

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

echo "==> Building the static AArch64 writeback init..."
"$cc" --target=aarch64-linux-musl --sysroot="$sysroot" \
	-static -O2 -fno-stack-protector -Wall -Wextra -Werror \
	"$repo/tests/disk-writeback/test.c" -L"$sysroot/lib" -fuse-ld=lld \
	-o "$work/init"

mkdir -p "$work/system/sbin" "$work/vm"
cp "$work/init" "$work/system/sbin/init"
chmod +x "$work/system/sbin/init"
COPYFILE_DISABLE=1 tar --format=ustar -cf "$work/system.tar" -C "$work/system" .

# The cache is sized from the device and reaches its 256 MiB ceiling at 8 GiB,
# the size of the desktop's own system volume. The file is sparse on the host.
VINIX_QEMU_PERSIST_SIZE_MB=${VINIX_QEMU_PERSIST_SIZE_MB:-8192} \
python3 "$repo/tests/disk-writeback/run_vm.py" \
	--image "$work/system.tar" \
	--state-dir "$work/vm" \
	--timeout "${VINIX_QEMU_TIMEOUT:-900}"
