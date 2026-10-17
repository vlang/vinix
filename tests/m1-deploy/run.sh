#!/bin/bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/vinix-m1-deploy-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
fixture="$work/fixture"
esp="$work/esp"

mkdir -p "$fixture/kernel/bin" "$fixture/build-support/init-aarch64" \
    "$fixture/boot-image/limine-bin" "$esp/boot"
mkdir -p "$fixture/scripts"
cp "$repo/scripts/deploy-m1-efi.sh" "$fixture/scripts/"

# A minimal ELF64/AArch64 header is enough for the deployment architecture
# guard and keeps this test independent of generated kernel artifacts.
"$repo/build-support/source-tools/run" m1-kernel "$fixture/kernel/bin/vinix"

printf '%s\n' 'Limine 12.9.3 (aarch64, UEFI)' \
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

# A direct/default kernel build omits the MP request. It must be rejected
# before the old single-core image can be copied to a real M1.
cp "$fixture/kernel/bin/vinix" "$work/vinix-with-mp"
dd if="$work/vinix-with-mp" of="$fixture/kernel/bin/vinix" bs=64 count=1 \
    2>/dev/null
if "$fixture/scripts/deploy-m1-efi.sh" --desktop-initramfs "$esp" \
    >"$work/single-core.log" 2>&1; then
    echo "deployment accepted an M1 kernel without the MP request" >&2
    exit 1
fi
grep -Fq 'M1 kernel has no Limine MP request' "$work/single-core.log"
cp "$work/vinix-with-mp" "$fixture/kernel/bin/vinix"

"$fixture/scripts/deploy-m1-efi.sh" --desktop-initramfs "$esp" >"$work/deploy.log"
grep -Fq 'native boot limit: 4 CPUs' "$work/deploy.log"
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
