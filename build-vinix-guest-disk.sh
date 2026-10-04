#!/bin/sh
# Create a raw AArch64 UEFI boot image for QEMU running inside Vinix.
set -eu

repo=$(cd "$(dirname "$0")" && pwd)
output=${1:-"$repo/build-aarch64-qemu-system/vinix-guest.img"}
initramfs=${2:-"$repo/build-support/init-aarch64/initramfs.tar"}
kernel="$repo/kernel/bin/vinix"
limine="$repo/boot-image/limine-bin/BOOTAA64.EFI"

if [ -e "$output" ]; then
    echo "image already exists: $output" >&2
    exit 1
fi
for input in "$initramfs" "$kernel" "$limine"; do
    if [ ! -f "$input" ]; then
        echo "missing guest image input: $input" >&2
        exit 1
    fi
done
for tool in mformat mmd mcopy python3 truncate; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "missing image build tool: $tool" >&2
        exit 1
    }
done

mkdir -p "$(dirname "$output")"
work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-guest-disk.XXXXXX")
image="$output.partial.$$"
cleanup() { rm -rf "$work"; rm -f "$image"; }
trap cleanup EXIT INT TERM

cat > "$work/limine.conf" <<'EOF'
timeout: 0
verbose: yes

/Vinix
    protocol: limine
    kernel_path: boot():/boot/vinix
    module_path: boot():/boot/initramfs.tar
    cmdline: vinix.qemu_platform=1
    kaslr: no
EOF

# Leave space for FAT metadata, the kernel, and updates to the initramfs.
size_mb=$(python3 - "$initramfs" "$kernel" <<'PY'
import os
import sys

payload = sum(os.path.getsize(path) for path in sys.argv[1:])
print(max(128, (payload + 128 * 1024 * 1024 + 1024 * 1024 - 1) // (1024 * 1024)))
PY
)
truncate -s "${size_mb}M" "$image"
mformat -F -i "$image" ::
mmd -i "$image" ::/EFI ::/EFI/BOOT ::/boot
mcopy -i "$image" "$limine" ::/EFI/BOOT/BOOTAA64.EFI
mcopy -i "$image" "$work/limine.conf" ::/boot/limine.conf
mcopy -i "$image" "$kernel" ::/boot/vinix
mcopy -i "$image" "$initramfs" ::/boot/initramfs.tar
mv "$image" "$output"
echo "wrote $output (${size_mb} MiB)"
