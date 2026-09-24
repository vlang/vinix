#!/bin/sh
# Boot Vinix with the Docker engine and run tests/docker/smoke.sh inside it.
set -eu

repo=$(cd "$(dirname "$0")/../.." && pwd)
userland=${VINIX_AARCH64_USERLAND_BUILD_DIR:-"$repo/build-aarch64-userland"}
minirootfs=${VINIX_ALPINE_MINIROOTFS:-"$userland/downloads/alpine-minirootfs-3.21.7-aarch64.tar.gz"}
docker_staging=${VINIX_DOCKER_STAGING:-"$repo/build-aarch64-docker/staging"}
work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-docker-test.XXXXXX")

cleanup() {
	rm -rf "$work"
}
trap cleanup EXIT INT TERM

if [ ! -f "$minirootfs" ]; then
	echo "ERROR: Alpine minirootfs is missing: $minirootfs" >&2
	echo "       Run ./build-userland-aarch64.sh first." >&2
	exit 1
fi
if [ ! -x "$docker_staging/usr/bin/dockerd" ]; then
	echo "ERROR: Docker staging is missing: $docker_staging" >&2
	echo "       Run ./build-docker-aarch64.sh first." >&2
	exit 1
fi

echo "==> Assembling the Docker test initramfs..."
mkdir -p "$work/rootfs"
tar -xzf "$minirootfs" -C "$work/rootfs"
# rsync replaces BusyBox's command symlinks instead of writing through them.
rsync -a "$docker_staging/" "$work/rootfs/"
rm -f "$work/rootfs/sbin/init"
install -m755 "$repo/build-support/init-aarch64/alpine-init" "$work/rootfs/sbin/init"
install -m755 "$repo/tests/docker/smoke.sh" "$work/rootfs/root/docker-smoke.sh"
mkdir -p "$work/rootfs/dev" "$work/rootfs/proc" "$work/rootfs/sys" \
	"$work/rootfs/tmp" "$work/rootfs/run" "$work/rootfs/var/log"
chmod 1777 "$work/rootfs/tmp"
COPYFILE_DISABLE=1 tar --format=ustar -cf "$work/initramfs.tar" -C "$work/rootfs" .

set -- --init "${VINIX_DOCKER_GUEST_INIT:-$repo/tests/docker/guest-init.sh}" \
	--initramfs "$work/initramfs.tar" \
	--state-dir "$work/vm" \
	--timeout "${VINIX_QEMU_TIMEOUT:-900}" \
	--mem "${VINIX_QEMU_MEM:-4096}" \
	--pass-marker "VINIX DOCKER TEST: PASS" \
	--fail-marker "VINIX DOCKER TEST: FAIL"
if [ -n "${VINIX_DOCKER_TEST_LOG:-}" ]; then
	set -- "$@" --log "$VINIX_DOCKER_TEST_LOG"
fi
if [ "${VINIX_DOCKER_TEST_NO_BUILD:-0}" = 1 ]; then
	set -- "$@" --no-build
fi
python3 "$repo/tests/docker/run_vm.py" "$@"
