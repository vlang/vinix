#!/bin/sh
# Boot Vinix once, let it restart itself with reboot(2), and check that a file
# written just before the restart is still there afterwards.
#
#   ./scripts/build-userland-aarch64.sh        # once, for the musl test sysroot
#   tests/reboot-persistence/run.sh
#
# VINIX_REBOOT_PERSISTENCE_ARCH=x86_64 selects the native x86 guest.
# VINIX_REBOOT_PERSISTENCE_NO_BUILD=1 reuses an already built ARM kernel.
set -eu

repo=$(cd "$(dirname "$0")/../.." && pwd)
arch=${VINIX_REBOOT_PERSISTENCE_ARCH:-aarch64}
if [ -n "${VINIX_REBOOT_PERSISTENCE_STATE_DIR:-}" ]; then
	work=$VINIX_REBOOT_PERSISTENCE_STATE_DIR
	mkdir -p "$(dirname "$work")"
	mkdir "$work"
	keep_state=1
else
	work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-reboot-persistence.XXXXXX")
	keep_state=0
fi

cleanup() {
	if [ "$keep_state" = 0 ]; then rm -rf "$work"; fi
}
trap cleanup EXIT INT TERM

module="$repo/tests/reboot-persistence/persistfixture"
python3 "$repo/tests/kernel-gaps/compile-v-fixture.py" "$work/fixture.c" \
	--arch "$arch" --module "$module"

echo "==> Building the static $arch reboot-persistence init..."
case "$arch" in
	aarch64)
		sysroot=${VINIX_AARCH64_SYSROOT:-"$repo/build-aarch64-userland/sysroot"}
		cc=${CC:-clang}
		for input in "$sysroot/include" "$sysroot/lib/crt1.o" "$sysroot/lib/libc.a"; do
			if [ ! -e "$input" ]; then
				echo "ERROR: AArch64 test sysroot input is missing: $input" >&2
				echo "       Run ./scripts/build-userland-aarch64.sh first or set VINIX_AARCH64_SYSROOT." >&2
				exit 1
			fi
		done
		"$cc" --target=aarch64-linux-musl --sysroot="$sysroot" \
			-static -std=gnu11 -O2 -fno-builtin -fno-stack-protector -Wall -Wextra -Werror \
			-Wno-unused-function -Wno-unused-parameter -fPIC -I"$module" \
			"$work/fixture.c" -L"$sysroot/lib" -fuse-ld=lld -o "$work/init"
		;;
	x86_64)
		cc=${CC_AMD64:-x86_64-linux-musl-gcc}
		"$cc" -static -std=gnu11 -O2 -fno-builtin -fno-stack-protector -Wall -Wextra -Werror \
			-Wno-unused-function -Wno-unused-parameter -fPIC -I"$module" \
			"$work/fixture.c" -o "$work/init"
		;;
	*) echo "ERROR: unsupported reboot-persistence architecture: $arch" >&2; exit 1 ;;
esac

# The runner supplies the real PID 1 as its last initramfs overlay; this base
# only has to provide the mount point the persistent volume lands on.
mkdir -p "$work/rootfs/root" "$work/rootfs/sbin"
COPYFILE_DISABLE=1 tar --format=ustar -cf "$work/initramfs.tar" -C "$work/rootfs" .

python3 "$repo/tests/reboot-persistence/run_vm.py" \
	--arch "$arch" \
	--init "$work/init" \
	--initramfs "$work/initramfs.tar" \
	--state-dir "$work/vm" \
	--timeout "${VINIX_QEMU_TIMEOUT:-240}"
