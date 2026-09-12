#!/bin/sh
# Boot a machine whose entire filesystem is the persistent volume, let it
# restart itself, and check that a file written outside /root survived.
#
#   ./build-userland-aarch64.sh        # once, for the musl test sysroot
#   tests/disk-root/run.sh
#
# VINIX_DISK_ROOT_NO_BUILD=1 reuses kernel/bin/vinix.
set -eu

repo=$(cd "$(dirname "$0")/../.." && pwd)
sysroot=${VINIX_AARCH64_SYSROOT:-"$repo/build-aarch64-userland/sysroot"}
cc=${CC:-clang}
work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-disk-root.XXXXXX")

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

echo "==> Building the static AArch64 disk-root init..."
"$cc" --target=aarch64-linux-musl --sysroot="$sysroot" \
	-static -O2 -fno-stack-protector -Wall -Wextra -Werror \
	"$repo/tests/disk-root/test.c" -L"$sysroot/lib" -fuse-ld=lld \
	-o "$work/init"

# The whole system this machine runs, as the image the runner installs onto the
# volume. It is deliberately tiny: what is under test is the root itself, not
# how much of a userland fits on it. The runner adds the kernel's mount points.
mkdir -p "$work/system/sbin" "$work/system/etc" "$work/system/usr/share"
cp "$work/init" "$work/system/sbin/init"
chmod +x "$work/system/sbin/init"
# A file reaching past the twelve direct blocks of an ext2 inode, written by
# the host rather than by the kernel, so what is under test is reading back
# somebody else's block layout. The guest recomputes every byte from its offset.
python3 "$repo/tests/disk-root/make-large-file.py" "$work/system/usr/share/vinix-large"
COPYFILE_DISABLE=1 tar --format=ustar -cf "$work/system.tar" -C "$work/system" .

python3 "$repo/tests/disk-root/run_vm.py" \
	--image "$work/system.tar" \
	--state-dir "$work/vm" \
	--timeout "${VINIX_QEMU_TIMEOUT:-300}"
