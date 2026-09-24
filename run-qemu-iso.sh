#!/bin/sh
qemu-system-x86_64 -machine q35,smm=off -cpu max -m 8G -smp 4 -drive if=pflash,format=raw,unit=0,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd -cdrom vinix.iso -vga std -serial stdio
