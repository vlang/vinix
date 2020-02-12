#!/bin/bash

set -e
cd "${0%/*}"

if [[ -f "build/meson-out/kernel.elf" ]]; then
    KERNEL=build/meson-out/kernel.elf    
elif [[ -f "build/kernel.elf" ]]; then
    KERNEL=build/kernel.elf
else 
    echo "[!] No kernel binary found."
    exit 1
fi

echo "[*] Using kernel: $KERNEL"

grub-file --is-x86-multiboot2 $KERNEL || (echo "[!] Not a valid multiboot kernel!" ; exit 1)

echo "[*] Generating filesystem tree..."
mkdir -p build/iso
mkdir -p build/iso/boot/grub

cp $KERNEL build/iso/kernel.elf

echo "[*] Generating GRUB configuration..."
cat > build/iso/boot/grub/grub.cfg << EOF
loadfont "unicode"
insmod efi_gop
insmod gfxterm

#set gfxmode=auto
set gfxpayload=keep
terminal_output gfxterm

echo "Booting the vOS kernel"
multiboot2 /kernel.elf cmdlinetest=ok
boot
EOF

echo "[*] Creating ISO image..."
grub-mkrescue -o build/boot.iso build/iso

echo "[*] Done, boot image saved to 'build/boot.iso'!"