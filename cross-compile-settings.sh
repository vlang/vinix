#!/bin/sh
# Build the committed Settings for AArch64 and publish it to running QEMU
# guests, which install it at /usr/bin/vinix-settings without restarting Vinix.
exec "$(dirname "$0")/cross-compile-app.sh" settings
