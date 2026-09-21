#!/bin/sh
# Guest integration test for an on-demand Alpine GIMP installation.
set -eu

export PATH=/bin:/sbin:/usr/bin:/usr/sbin
export HOME=/root
export SSL_CA_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

echo "VINIX GIMP PACKAGE TEST"

if [ ! -x /usr/bin/Xorg ]; then
	echo "GIMP test needs the Vinix Xorg build (run build-x11-aarch64.sh first)" >&2
	exit 1
fi
if [ -e /usr/bin/gimp ]; then
	echo "GIMP was preinstalled; this test requires a clean base image" >&2
	exit 1
fi

pkg install gimp

test -x /usr/bin/gimp
test -x /usr/bin/run-gimp
test -f /etc/gimp/2.0/vinix-sessionrc
test -d /usr/lib/gimp/2.0/plug-ins
test -f /usr/share/applications/gimp.desktop
test -s /usr/share/gimp/2.0/icons/Symbolic/icon-theme.cache
test -s /usr/share/mime/mime.cache
/usr/bin/gdk-pixbuf-thumbnailer -s 16 \
	/usr/share/gimp/2.0/icons/Symbolic/16x16/apps/gimp-tool-crop.png \
	/tmp/gimp-icon-smoke.png
test -s /tmp/gimp-icon-smoke.png
echo "PASS pkg installed GIMP and its GTK runtime"

mkdir -p /tmp/.X11-unix /var/lib/xkb
display=:10
# A persistent /root can shadow the copy the image ships there.
if [ -x /usr/share/vinix/x-window-check.py ]; then
	x_window_check=/usr/share/vinix/x-window-check.py
else
	x_window_check=/root/x-window-check.py
fi
/usr/bin/Xorg "$display" +iglx -noreset \
	</dev/null >/var/log/Xorg.gimp-package-test.log 2>&1 &
xorg_pid=$!

cleanup() {
	[ -z "${gimp_pid:-}" ] || kill "$gimp_pid" 2>/dev/null || true
	kill "$xorg_pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

i=0
while [ ! -e /tmp/.X11-unix/X10 ] && [ "$i" -lt 20 ]; do
	sleep 1
	i=$((i + 1))
done
if [ ! -e /tmp/.X11-unix/X10 ]; then
	cat /var/log/Xorg.gimp-package-test.log >&2
	echo "Xorg did not become ready" >&2
	exit 1
fi

DISPLAY="$display" run-gimp >/tmp/gimp.log 2>&1 &
gimp_pid=$!
mapped=false
i=0
# A first launch probes GIMP's complete plug-in set. Vinix QEMU currently runs
# one guest CPU, so leave enough time for that one-time registry build.
while [ "$i" -lt 180 ]; do
	if ! kill -0 "$gimp_pid" 2>/dev/null; then
		cat /tmp/gimp.log >&2
		echo "GIMP exited before showing its editor window" >&2
		exit 1
	fi
	if "$x_window_check" "$display" 'GIMP'; then
		mapped=true
		break
	fi
	sleep 1
	i=$((i + 1))
done
if [ "$mapped" != true ]; then
	cat /tmp/gimp.log >&2
	echo "GIMP did not map an editor window" >&2
	exit 1
fi

grep -q '(position 0 0)' /root/.config/GIMP/2.10/sessionrc
grep -q '(size 1280 900)' /root/.config/GIMP/2.10/sessionrc

echo "PASS GIMP opened an editor window"
echo "VINIX GIMP PACKAGE TEST: PASS"
