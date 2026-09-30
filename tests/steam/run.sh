#!/bin/sh
# Boot the desktop image and hold Valve's Steam client to its first window.
#
# The image has to have been built with the x86 translators and the Steam
# layer in it:
#
#   ./scripts/build-x86-translation-aarch64.sh --translator-only
#   ./scripts/build-steam-aarch64.sh
#   ./scripts/build-desktop-aarch64.sh --compact-initramfs --with-steam
#
# The boot is a RAM root, so the guest needs enough memory to hold the whole
# image plus the machine, plus the client the bootstrapper downloads.
set -eu

repo=$(cd "$(dirname "$0")/../.." && pwd)
initramfs=${VINIX_DESKTOP_INITRAMFS:-"$repo/build-support/init-aarch64/initramfs-desktop.tar"}
if [ -s "$initramfs.gz" ] && [ "$initramfs.gz" -nt "$initramfs" ]; then
	initramfs="$initramfs.gz"
fi

if [ ! -f "$initramfs" ]; then
	echo "ERROR: desktop image not found: $initramfs" >&2
	echo "       Run ./scripts/build-desktop-aarch64.sh --compact-initramfs --with-steam" >&2
	exit 1
fi

# Limine loads the image into RAM before the kernel starts. The translated
# Steam client and several Chromium helpers also map large private libraries;
# a 16 GiB guest ran out of physical pages while starting the web helper.
image_mb=$(( $(wc -c < "$initramfs") / 1024 / 1024 ))
minimum_mem=$(( image_mb * 2 + 4096 ))
if [ "$minimum_mem" -lt 32768 ]; then
	minimum_mem=32768
fi
mem=${VINIX_QEMU_MEM:-$minimum_mem}

exec python3 "$repo/tests/browsers/run_vm.py" \
	--steam \
	--initramfs "$initramfs" \
	--state-dir "${VINIX_STEAM_STATE_DIR:-$repo/build/steam-vm}" \
	--mem "$mem" \
	--timeout "${VINIX_QEMU_TIMEOUT:-3600}" \
	"$@"
