#!/bin/bash

set -e
cd "${0%/*}"

KERNEL=build/meson-out/kernel.elf
grub-file --is-x86-multiboot $KERNEL || (echo "[!] Not a valid multiboot kernel!" ; exit 1)

mkdir -p build/iso
mkdir -p build/iso/boot/grub

cp $KERNEL build/iso/kernel.elf

cat > build/iso/boot/grub/grub.cfg << EOF
echo "Booting the vOS kernel"
multiboot /kernel.elf
boot
EOF

grub-mkrescue -o build/boot.iso build/iso
echo "[*] Done, boot image saved to 'build/boot.iso'!"