#!/bin/bash
# Assemble an aarch64 UEFI ISO around an already-built kernel and initramfs.
# Limine's EFI boot image comes from its pinned release; the loader inside it
# is that release built with Vinix's base revision patch
# (scripts/build-limine-aarch64.sh), since upstream Limine refuses the
# kernel's base revision 2 on arm64.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${VINIX_AARCH64_ISO_BUILD_DIR:-$SCRIPT_DIR/build-aarch64-iso}"
KERNEL="${VINIX_AARCH64_KERNEL:-$SCRIPT_DIR/build-aarch64-kernel/bin/vinix}"
INITRAMFS="${VINIX_AARCH64_INITRAMFS:-$SCRIPT_DIR/build-support/init-aarch64/initramfs.tar}"
OUTPUT_ISO="${VINIX_AARCH64_ISO:-$SCRIPT_DIR/vinix-aarch64.iso}"
. "$SCRIPT_DIR/build-support/limine-binary.sh"

case "$BUILD_DIR" in
    ''|/|"$SCRIPT_DIR")
        echo "ERROR: refusing unsafe aarch64 ISO build directory: $BUILD_DIR" >&2
        exit 1
        ;;
esac
mkdir -p "$BUILD_DIR"
ISO_STAGING_DIR="$(mktemp -d "$BUILD_DIR/.iso-staging.XXXXXX")"
ISO_ROOT="$ISO_STAGING_DIR/iso-root"
IMAGE_ID_DIR="$ISO_STAGING_DIR/image-id"
OUTPUT_ISO_TMP=""
cleanup() {
    rm -rf "$ISO_STAGING_DIR"
    if [ -n "$OUTPUT_ISO_TMP" ]; then
        rm -f "$OUTPUT_ISO_TMP"
    fi
}
trap cleanup EXIT

for command_name in curl xorriso mcopy; do
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "ERROR: required command not found: $command_name" >&2
        exit 1
    }
done
for input in "$KERNEL" "$INITRAMFS" "$SCRIPT_DIR/build-support/limine.conf"; do
    if [ ! -f "$input" ]; then
        echo "ERROR: required ISO input not found: $input" >&2
        exit 1
    fi
done

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

LIMINE_DIR="$(limine_binary_dir "$BUILD_DIR/limine")"
"$SCRIPT_DIR/scripts/build-limine-aarch64.sh" >&2
BOOTAA64="$SCRIPT_DIR/boot-image/limine-bin/BOOTAA64.EFI"
if ! LC_ALL=C grep -aqF "Limine $LIMINE_BINARY_VERSION (aarch64, UEFI)" "$BOOTAA64"; then
    echo "ERROR: $BOOTAA64 is not Limine $LIMINE_BINARY_VERSION" >&2
    exit 1
fi
# The release's EFI boot image, with its arm64 loader replaced by the patched one.
mkdir -p "$BUILD_DIR/limine"
UEFI_CD="$BUILD_DIR/limine/limine-uefi-cd.bin"
cp "$LIMINE_DIR/limine-uefi-cd.bin" "$UEFI_CD"
chmod u+w "$UEFI_CD"
MTOOLS_SKIP_CHECK=1 mcopy -o -i "$UEFI_CD" "$BOOTAA64" ::/EFI/BOOT/BOOTAA64.EFI

mkdir -p "$ISO_ROOT/boot" "$ISO_ROOT/EFI/BOOT"
install -m644 "$KERNEL" "$ISO_ROOT/boot/vinix"
install -m644 "$INITRAMFS" "$ISO_ROOT/boot/initramfs.tar"
# The image goes in compressed (below); Limine loads it as it is.
sed 's#^\(    module_path: boot():/boot/initramfs\.tar\)$#\1.gz#' \
    "$SCRIPT_DIR/build-support/limine.conf" > "$ISO_ROOT/boot/limine.conf"
grep -q 'module_path: boot():/boot/initramfs\.tar\.gz$' "$ISO_ROOT/boot/limine.conf" || {
    echo "ERROR: limine.conf has no module_path for boot/initramfs.tar" >&2
    exit 1
}
# A machine booted from the ISO keeps its system on a blank disk if it has
# one, installing it there on the first boot (kernel/sysdisk). The entry is the
# file's last, so the option goes at the end.
printf '    cmdline: vinix.disk=auto\n' >> "$ISO_ROOT/boot/limine.conf"
# The image's identity, which a system installed from it keeps in
# /.vinix-image-id: an ISO with a different image updates that system. Taken
# from the image's contents, so an unchanged image rebuilt is no update.
mkdir -p "$IMAGE_ID_DIR"
sha256_file "$INITRAMFS" | cut -c1-16 > "$IMAGE_ID_DIR/.vinix-image-id"
COPYFILE_DISABLE=1 tar --format=ustar -rf "$ISO_ROOT/boot/initramfs.tar" \
    -C "$IMAGE_ID_DIR" ./.vinix-image-id
# Ship the image gzip-compressed, as Ubuntu, Debian and Arch ship their
# initramfs compressed: the bootloader reads about a third of the bytes and the
# kernel inflates them (kernel/initramfs/gzip.v). The header's comment field
# carries the image id, so a machine booting the system installed on its disk
# can compare ids without inflating the image.
echo "==> Compressing the image..."
gzip -9 -n -c "$ISO_ROOT/boot/initramfs.tar" > "$ISO_ROOT/boot/initramfs.plain.gz"
if [ "$(od -An -tx1 -j3 -N1 "$ISO_ROOT/boot/initramfs.plain.gz" | tr -d ' \n')" != 00 ]; then
    echo "ERROR: gzip -n wrote optional header fields; cannot add the image id" >&2
    exit 1
fi
{
    # ID1 ID2, deflate, FCOMMENT, no mtime, maximum compression, Unix.
    printf '\037\213\010\020\000\000\000\000\002\003'
    printf 'vinix-image-id=%s\000' "$(cat "$IMAGE_ID_DIR/.vinix-image-id")"
    tail -c +11 "$ISO_ROOT/boot/initramfs.plain.gz"
} > "$ISO_ROOT/boot/initramfs.tar.gz"
rm -f "$ISO_ROOT/boot/initramfs.tar" "$ISO_ROOT/boot/initramfs.plain.gz"
install -m644 "$UEFI_CD" "$ISO_ROOT/boot/limine-uefi-cd.bin"
install -m644 "$BOOTAA64" "$ISO_ROOT/EFI/BOOT/BOOTAA64.EFI"

mkdir -p "$(dirname "$OUTPUT_ISO")"
OUTPUT_ISO_TMP="$(mktemp "$(dirname "$OUTPUT_ISO")/.vinix-aarch64.iso.XXXXXX")"
echo "==> Assembling $OUTPUT_ISO..."
xorriso -as mkisofs -R -r -J \
    --efi-boot boot/limine-uefi-cd.bin \
    -efi-boot-part --efi-boot-image --protective-msdos-label \
    "$ISO_ROOT" -o "$OUTPUT_ISO_TMP"
mv -f "$OUTPUT_ISO_TMP" "$OUTPUT_ISO"
echo "    $OUTPUT_ISO ($(wc -c < "$OUTPUT_ISO" | tr -d ' ') bytes)"
