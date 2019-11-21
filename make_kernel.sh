#!/bin/bash

set -e
cd "${0%/*}"

meson kernel/build kernel && ninja -C kernel/build && echo "[*] Done, kernel saved to 'kernel/build/kernel.elf'!"
