#!/bin/sh
# Boot the desktop image and hold LibreOffice Writer to a window and a page.
#
# The image has to have been built with the office layer in it:
#
#   ./build-libreoffice-aarch64.sh
#   ./build-desktop-aarch64.sh --compact-initramfs --with-libreoffice
#
# The suite adds about 1.5 GiB to the image, and this boot is a RAM root, so
# the guest needs enough memory to hold the whole of it plus the machine.
set -eu

repo=$(cd "$(dirname "$0")/../.." && pwd)
initramfs=${VINIX_DESKTOP_INITRAMFS:-"$repo/build-support/init-aarch64/initramfs-desktop.tar"}

if [ ! -f "$initramfs" ]; then
	echo "ERROR: desktop image not found: $initramfs" >&2
	echo "       Run ./build-desktop-aarch64.sh --compact-initramfs --with-libreoffice" >&2
	exit 1
fi

# Limine loads the image into RAM before the kernel starts, so the guest needs
# room for the image and for the machine that unpacks it.
image_mb=$(( $(wc -c < "$initramfs") / 1024 / 1024 ))
mem=${VINIX_QEMU_MEM:-$(( image_mb * 2 + 4096 ))}

exec python3 "$repo/tests/browsers/run_vm.py" \
	--libreoffice \
	--initramfs "$initramfs" \
	--state-dir "${VINIX_OFFICE_STATE_DIR:-$repo/build/office-vm}" \
	--mem "$mem" \
	--timeout "${VINIX_QEMU_TIMEOUT:-2400}" \
	"$@"
