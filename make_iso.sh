#!/bin/bash

set -e
cd "${0%/*}"

KERNEL=build/kernel.elf
grub-file --is-x86-multiboot2 $KERNEL || (echo "[!] Not a valid multiboot kernel!" ; exit 1)

mkdir -p build/iso
mkdir -p build/iso/boot/grub

cp $KERNEL build/iso/kernel.elf

cat > build/iso/boot/grub/grub.cfg << EOF
loadfont "unicode"
insmod all_video
insmod gfxterm

set gfxmode=auto
set gfxpayload=keep
terminal_output gfxterm

echo "Booting the vOS kernel"
multiboot2 /kernel.elf
boot
EOF

grub-mkrescue -o build/boot.iso build/iso
echo "[*] Done, boot image saved to 'build/boot.iso'!"