#!/bin/sh
# Guest init that installs Chromium from the Alpine repositories the way a user
# would, and checks what `pkg install chromium` left behind.

export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export HOME=/root
export TERM=linux
export LD_LIBRARY_PATH=/usr/lib:/usr/lib/xorg/modules
export SSL_CA_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

fail() {
	echo "VINIX CHROMIUM: FAIL $*"
	echo "VINIX CHROMIUM PACKAGE TEST: FAIL"
	exit 1
}

echo
echo "VINIX CHROMIUM PACKAGE TEST: START"

[ -x /usr/bin/pkg ] || fail "no /usr/bin/pkg"
[ -x /usr/bin/run-chromium ] || fail "no /usr/bin/run-chromium"
[ -s /usr/share/vinix/chromium-smoke.html ] || fail "no /usr/share/vinix/chromium-smoke.html"
[ -s /etc/chromium/policies/managed/vinix.json ] || fail "no managed policy"
if [ -e /usr/lib/chromium/chrome ]; then
	fail "Chromium was preinstalled; this test needs an image without it"
fi
echo "VINIX CHROMIUM PASS: the image ships the launcher but not the browser"

mkdir -p /tmp /dev/shm
chmod 1777 /tmp /dev/shm

pkg install chromium || fail "pkg install chromium failed"

[ -x /usr/lib/chromium/chrome ] || fail "no /usr/lib/chromium/chrome after install"
[ -s /usr/lib/chromium/resources.pak ] || fail "no resources.pak"
[ -s /usr/lib/chromium/v8_context_snapshot.bin ] || fail "no V8 snapshot"
[ -s /usr/share/mime/mime.cache ] || fail "no MIME cache"
[ -e /usr/lib/chromium/libvk_swiftshader.so ] || fail "no CPU Vulkan device"
echo "VINIX CHROMIUM PASS: pkg installed Chromium and its runtime"

if /usr/lib/chromium/chrome --version >/tmp/version.txt 2>&1; then
	cat /tmp/version.txt
	echo "VINIX CHROMIUM PASS: the installed browser runs"
else
	cat /tmp/version.txt
	fail "the installed chrome could not report its version"
fi

echo "VINIX CHROMIUM PACKAGE TEST: PASS"
