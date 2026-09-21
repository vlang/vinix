#!/bin/sh
# Guest integration test for an on-demand Alpine Blender installation.
set -eu

export PATH=/bin:/sbin:/usr/bin:/usr/sbin
export HOME=/root
export SSL_CA_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
export LIBGL_ALWAYS_SOFTWARE=1

echo "VINIX BLENDER PACKAGE TEST"

if [ -e /usr/bin/blender ] || [ -e /usr/share/blender ]; then
	echo "Blender was preinstalled; this test needs a clean base image" >&2
	exit 1
fi

i=0
while [ ! -s /etc/resolv.conf ] && [ "$i" -lt 60 ]; do
	sleep 1
	i=$((i + 1))
done
if [ ! -s /etc/resolv.conf ]; then
	echo "DHCP did not install /etc/resolv.conf" >&2
	exit 1
fi

pkg install blender

test -x /usr/bin/blender
test -x /usr/libexec/vinix-blender
test -f /usr/share/applications/blender.desktop
set -- $(blender --version)
test "$1" = Blender
echo "PASS pkg installed Blender $2 from Alpine"

if ! blender --background --factory-startup --python-expr \
	'import bpy; bpy.ops.wm.save_as_mainfile(filepath="/tmp/vinix-blender-smoke.blend")' \
	>/tmp/blender-background.log 2>&1; then
	cat /tmp/blender-background.log >&2
	echo "Blender failed to save a project in background mode" >&2
	exit 1
fi
test -s /tmp/vinix-blender-smoke.blend
echo "PASS Blender saved a project in background mode"
echo "VINIX BLENDER PACKAGE TEST: PASS"
