#!/bin/sh
# Guest integration test for an on-demand Alpine Chromium installation.
set -eu

export PATH=/bin:/sbin:/usr/bin:/usr/sbin
export HOME=/root
export SSL_CA_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

echo "VINIX CHROMIUM PACKAGE TEST"

if [ ! -x /usr/bin/Xorg ]; then
	echo "Chromium test needs the Vinix Xorg build (run build-x11-aarch64.sh first)" >&2
	exit 1
fi
test -x /usr/bin/run-chromium
test -s /usr/share/vinix/chromium-smoke.html
test -s /etc/chromium/policies/managed/vinix.json

if [ ! -x /usr/lib/chromium/chrome ]; then
	pkg install chromium
fi

test -x /usr/lib/chromium/chrome
test -s /usr/lib/chromium/resources.pak
test -s /usr/lib/chromium/v8_context_snapshot.bin
test -s /usr/share/mime/mime.cache
echo "PASS pkg installed Chromium and its GTK runtime"

# The version banner is the cheapest end-to-end check that the browser's own
# executable loads, relocates and reaches main() under Vinix.
/usr/lib/chromium/chrome --version >/tmp/chromium-version.txt 2>/tmp/chromium-version.log || {
	cat /tmp/chromium-version.log >&2
	echo "Chromium could not report its version" >&2
	exit 1
}
grep -q Chromium /tmp/chromium-version.txt
echo "PASS $(cat /tmp/chromium-version.txt)"

mkdir -p /tmp/.X11-unix /var/lib/xkb
display=:12
# A persistent /root can shadow the copy the image ships there.
if [ -x /usr/share/vinix/x-window-check.py ]; then
	x_window_check=/usr/share/vinix/x-window-check.py
else
	x_window_check=/root/x-window-check.py
fi
/usr/bin/Xorg "$display" +iglx -noreset \
	</dev/null >/var/log/Xorg.chromium-package-test.log 2>&1 &
xorg_pid=$!

cleanup() {
	[ -z "${chromium_pid:-}" ] || kill "$chromium_pid" 2>/dev/null || true
	kill "$xorg_pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

i=0
while [ ! -e /tmp/.X11-unix/X12 ] && [ "$i" -lt 20 ]; do
	sleep 1
	i=$((i + 1))
done
if [ ! -e /tmp/.X11-unix/X12 ]; then
	cat /var/log/Xorg.chromium-package-test.log >&2
	echo "Xorg did not become ready" >&2
	exit 1
fi

DISPLAY="$display" run-chromium >/tmp/chromium.log 2>&1 &
chromium_pid=$!
mapped=false
i=0
# A first launch builds the font cache and the browser's profile, and Vinix
# QEMU currently runs one guest CPU. Leave room for that one-time work.
while [ "$i" -lt 300 ]; do
	if ! kill -0 "$chromium_pid" 2>/dev/null; then
		cat /tmp/chromium.log >&2
		echo "Chromium exited before showing its browser window" >&2
		exit 1
	fi
	if "$x_window_check" "$display" 'Chromium'; then
		mapped=true
		break
	fi
	sleep 1
	i=$((i + 1))
done
if [ "$mapped" != true ]; then
	cat /tmp/chromium.log >&2
	echo "Chromium did not map a browser window" >&2
	exit 1
fi

echo "PASS Chromium opened a browser window"
echo "VINIX CHROMIUM PACKAGE TEST: PASS"
