#!/bin/sh
# Long-running QEMU integration probe. Boot a desktop initramfs with full-init.c
# and this file as /etc/vinix-boot-test.sh, then inspect the saved host overlay.
set -eu

echo "QEMU GTK PERSISTENCE: waiting for DHCP"
/bin/busybox sleep 5
pkg install gtk

test -x /usr/bin/gtk3-demo
test -x /usr/bin/gtk3-widget-factory
test -s /lib/apk/db/installed
grep -q gtk+3.0 /etc/apk/world
echo "QEMU GTK PERSISTENCE: INSTALL AND SAVE PASS"
