#!/bin/sh
# Guest integration test for an on-demand Alpine Gnumeric installation.
set -eu

export PATH=/bin:/sbin:/usr/bin:/usr/sbin
export HOME=/root
export SSL_CA_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

echo "VINIX GNUMERIC PACKAGE TEST"

if [ ! -x /usr/bin/Xorg ]; then
	echo "Gnumeric test needs the Vinix Xorg build (run build-x11-aarch64.sh first)" >&2
	exit 1
fi

if [ -e /usr/bin/gnumeric ] || [ -e /usr/lib/libgtk-3.so.0 ]; then
	echo "Gnumeric or GTK was preinstalled; this test requires a toolkit-free base image" >&2
	exit 1
fi
echo "PASS Gnumeric and GTK are absent from the base image"

i=0
while [ ! -s /etc/resolv.conf ] && [ "$i" -lt 60 ]; do
	sleep 1
	i=$((i + 1))
done
if [ ! -s /etc/resolv.conf ]; then
	echo "DHCP did not install /etc/resolv.conf" >&2
	exit 1
fi

pkg install gnumeric

echo "pkg install gnumeric returned"
for executable in /usr/bin/gnumeric /usr/bin/ssconvert; do
	if [ ! -x "$executable" ]; then
		/bin/busybox ls -l /usr/bin/gnumeric* /usr/bin/ssconvert* >&2 || true
		echo "missing Gnumeric executable: $executable" >&2
		exit 1
	fi
done
for library in /usr/lib/libgtk-3.so.*.* /usr/lib/libspreadsheet-*.so; do
	if [ ! -f "$library" ]; then
		/bin/busybox ls -l /usr/lib/libgtk-3.so* /usr/lib/libspreadsheet* >&2 || true
		echo "missing Gnumeric library: $library" >&2
		exit 1
	fi
done
echo "PASS pkg installed Gnumeric and its GTK runtime"

printf 'value\n42\n' >/tmp/gnumeric-input.csv
if ! ssconvert /tmp/gnumeric-input.csv /tmp/gnumeric-output.gnumeric \
	>/tmp/ssconvert.log 2>&1; then
	cat /tmp/ssconvert.log >&2
	echo "Gnumeric could not convert a spreadsheet" >&2
	exit 1
fi
test -s /tmp/gnumeric-output.gnumeric
echo "PASS Gnumeric converted a spreadsheet"

mkdir -p /tmp/.X11-unix /var/lib/xkb
display=:8
/usr/bin/Xorg "$display" +iglx -noreset \
	</dev/null >/var/log/Xorg.gnumeric-package-test.log 2>&1 &
xorg_pid=$!

cleanup() {
	kill "$xorg_pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

i=0
while [ ! -e /tmp/.X11-unix/X8 ] && [ "$i" -lt 20 ]; do
	sleep 1
	i=$((i + 1))
done
if [ ! -e /tmp/.X11-unix/X8 ]; then
	cat /var/log/Xorg.gnumeric-package-test.log >&2
	echo "Xorg did not become ready" >&2
	exit 1
fi

# The shared test helper exits successfully after Gnumeric has shown its GTK
# window and synchronised with Xorg. Any earlier loader/startup failure wins.
if ! LD_PRELOAD=/root/libgtk-smoke-auto-close.so \
	VINIX_GTK_SMOKE_BUILDER_BOUNDARY=0 GDK_SYNCHRONIZE=1 \
	DISPLAY="$display" /usr/bin/gnumeric --no-splash \
	>/tmp/gnumeric.log 2>&1; then
	cat /tmp/gnumeric.log >&2
	echo "Gnumeric failed before showing its spreadsheet window" >&2
	exit 1
fi

echo "PASS Gnumeric opened a spreadsheet window"
echo "VINIX GNUMERIC PACKAGE TEST: PASS"
