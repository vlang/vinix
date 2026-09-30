#!/bin/sh
# Build the committed Activity Monitor for AArch64 and publish it to running
# QEMU guests, which install it at /usr/bin/vinix-activity without restarting
# Vinix.
exec "$(dirname "$0")/cross-compile-app.sh" activity
