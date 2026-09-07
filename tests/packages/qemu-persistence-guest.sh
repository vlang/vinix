#!/bin/sh
# Minimal in-guest save/reload probe used by the QEMU integration test.
set -eu

marker=/usr/lib/libgtk-persistence-test.so
if [ -s "$marker" ]; then
	/bin/busybox grep -q persistent-gtk-marker "$marker"
	echo "QEMU PACKAGE PERSISTENCE: RELOAD PASS"
	exit 0
fi

echo "QEMU PACKAGE PERSISTENCE: waiting for DHCP"
attempt=0
while [ ! -s /etc/resolv.conf ] && [ "$attempt" -lt 60 ]; do
	/bin/busybox sleep 1
	attempt=$((attempt + 1))
done
test -s /etc/resolv.conf
/bin/busybox mkdir -p /etc/apk /lib/apk/db /usr/lib /tmp
printf '%s\n' gtk+3.0 >/etc/apk/world
printf '%s\n' installed-gtk-database >/lib/apk/db/installed
printf '%s\n' persistent-gtk-marker >"$marker"
# Reproduce apk's current mode-restoration gap for a preinstalled curl. The
# persistence helper must repair it before uploading.
[ ! -f /usr/bin/curl ] || /bin/busybox chmod 0644 /usr/bin/curl
/usr/libexec/vinix-persist-packages save
echo "QEMU PACKAGE PERSISTENCE: SAVE PASS"
