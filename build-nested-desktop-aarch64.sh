#!/bin/sh
# Build a small Vinix desktop disk for QEMU running inside Vinix.
set -eu

repo=$(cd "$(dirname "$0")" && pwd)
output=${1:-"$repo/build-aarch64-qemu-system/vinix-inner-desktop.img"}
minirootfs=${VINIX_ALPINE_MINIROOTFS:-"$repo/build-aarch64-userland/downloads/alpine-minirootfs-3.21.7-aarch64.tar.gz"}

for input in "$minirootfs" "$repo/build/vinix-desktop" \
    "$repo/build/desktop-init" "$repo/kernel/bin/vinix"; do
    if [ ! -f "$input" ]; then
        echo "missing nested desktop input: $input" >&2
        echo 'Build the AArch64 desktop and kernel first.' >&2
        exit 1
    fi
done

work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-inner-desktop.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/root"
tar -xzf "$minirootfs" -C "$work/root"
install -m755 "$repo/build/vinix-desktop" "$work/root/usr/bin/vinix-desktop"
install -m755 "$repo/build/desktop-init" "$work/root/sbin/init"
# The compositor loads QOI app artwork from this directory at startup.
mkdir -p "$work/root/usr/share/vinix/icons"
install -m644 "$repo"/desktop/assets/*.qoi \
    "$work/root/usr/share/vinix/icons/"
for app in vinix-files vinix-calculator vinix-terminal vinix-settings \
    vinix-activity vinix-editor vinix-calendar vinix-clock; do
    ln -sf vinix-desktop "$work/root/usr/bin/$app"
done
mkdir -p "$work/root/dev" "$work/root/proc" "$work/root/sys" \
    "$work/root/tmp" "$work/root/run" "$work/root/root"
chmod 1777 "$work/root/tmp"
COPYFILE_DISABLE=1 tar --format=ustar -cf "$work/initramfs.tar" -C "$work/root" .
"$repo/build-vinix-guest-disk.sh" "$output" "$work/initramfs.tar"

# Match the native viewer's fixed framebuffer on the first boot.
cat > "$work/limine.conf" <<'EOF'
timeout: 0
verbose: yes

/Vinix
    protocol: limine
    kernel_path: boot():/boot/vinix
    module_path: boot():/boot/initramfs.tar
    cmdline: vinix.qemu_platform=1
    kaslr: no
    resolution: 1024x768x32
EOF
mcopy -o -i "$output" "$work/limine.conf" ::/boot/limine.conf
