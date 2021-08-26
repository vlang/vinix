#!/bin/sh

set -ex

BUILD_DIR="$1"
SOURCE_DIR="$2"
SYSROOT="$3"

cp -rf "$SOURCE_DIR"/sysroot/. "$SYSROOT"/ || true
( cd "$SYSROOT" && tar -cf "$BUILD_DIR"/initramfs.tar . )
rm -rf pack
mkdir -p pack/boot
cp "$BUILD_DIR"/initramfs.tar "$SYSROOT"/boot/vinix.elf "$SOURCE_DIR"/v-logo.bmp pack/
cp "$SOURCE_DIR"/limine.cfg "$BUILD_DIR"/tools/host-limine/share/limine/limine.sys "$BUILD_DIR"/tools/host-limine/share/limine/limine-cd.bin "$BUILD_DIR"/tools/host-limine/share/limine/limine-eltorito-efi.bin pack/boot/
xorriso -as mkisofs -b /boot/limine-cd.bin -no-emul-boot -boot-load-size 4 -boot-info-table --efi-boot /boot/limine-eltorito-efi.bin -efi-boot-part --efi-boot-image --protective-msdos-label pack -o vinix.iso
"$BUILD_DIR"/tools/host-limine/bin/limine-install vinix.iso
