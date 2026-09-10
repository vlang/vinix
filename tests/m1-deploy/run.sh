#!/bin/bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/vinix-m1-deploy-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
fixture="$work/fixture"
esp="$work/esp"

mkdir -p "$fixture/kernel/bin" "$fixture/build-support/init-aarch64" \
    "$fixture/boot-image/limine-bin" "$esp/boot"
cp "$repo/deploy-m1-efi.sh" "$fixture/"

# A minimal ELF64/AArch64 header is enough for the deployment architecture
# guard and keeps this test independent of generated kernel artifacts.
python3 - "$fixture/kernel/bin/vinix" <<'PY'
import struct
import sys

header = bytearray(64)
header[:7] = b"\x7fELF\x02\x01\x01"
struct.pack_into("<HHI", header, 16, 2, 183, 1)
with open(sys.argv[1], "wb") as output:
    output.write(header)
    output.write(bytes.fromhex("888b4cdf30ddb1c77bf094a183e8820a"))
PY

printf '%s\n' 'Limine 12.8.0 (aarch64, UEFI)' \
    > "$fixture/boot-image/limine-bin/BOOTAA64.EFI"
cat > "$fixture/build-support/limine.conf" <<'EOF'
timeout: 0
/Vinix
    protocol: limine
    kernel_path: boot():/boot/vinix
    module_path: boot():/boot/initramfs.tar
EOF
mkdir -p "$work/root/sbin"
printf '#!/bin/sh\n' > "$work/root/sbin/init"
tar --format=ustar -cf "$work/initramfs-desktop.tar" -C "$work/root" .
gzip -n -6 -c "$work/initramfs-desktop.tar" \
    > "$fixture/build-support/init-aarch64/initramfs-desktop.tar.gz"
printf '%s\n' old > "$esp/boot/initramfs.tar"

"$fixture/deploy-m1-efi.sh" --desktop-initramfs "$esp" >/dev/null
cmp -s "$fixture/build-support/init-aarch64/initramfs-desktop.tar.gz" \
    "$esp/boot/initramfs.tar"
grep -Fq 'module_path: $boot():/boot/initramfs.tar' \
    "$esp/EFI/BOOT/limine.conf"
gzip -cd "$esp/boot/initramfs.tar" | cmp -s - "$work/initramfs-desktop.tar"
if find "$esp" -name '*.vinix-new' -print | grep -q .; then
    echo "deployment left a staging file on the ESP" >&2
    exit 1
fi

echo "PASS compressed M1 ESP deployment"
