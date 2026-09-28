#!/bin/sh
# Build the committed Files app for AArch64 and publish it to running QEMU
# guests, which install it at /usr/bin/vinix-files without restarting Vinix.
exec "$(dirname "$0")/cross-compile-app.sh" files
