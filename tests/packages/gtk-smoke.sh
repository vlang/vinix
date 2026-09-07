#!/bin/sh
# Guest integration test for on-demand Alpine GTK installation.
set -eu

export PATH=/bin:/sbin:/usr/bin:/usr/sbin
export HOME=/root
export SSL_CA_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

echo "VINIX GTK PACKAGE TEST"

if [ ! -x /usr/bin/Xorg ]; then
	echo "GTK test needs the Vinix Xorg build (run build-x11-aarch64.sh first)" >&2
	exit 1
fi

if [ -e /usr/bin/gtk3-demo ] || [ -e /usr/lib/libgtk-3.so.0 ]; then
	echo "GTK was preinstalled; this test requires a GTK-free base image" >&2
	exit 1
fi
echo "PASS GTK is absent from the base image"

i=0
while [ ! -s /etc/resolv.conf ] && [ "$i" -lt 60 ]; do
	sleep 1
	i=$((i + 1))
done
if [ ! -s /etc/resolv.conf ]; then
	echo "DHCP did not install /etc/resolv.conf" >&2
	exit 1
fi

pkg install gtk

test -x /usr/bin/gtk3-demo
test -x /usr/bin/gtk3-widget-factory
test -f /usr/lib/libgtk-3.so.0
echo "PASS pkg installed GTK and its examples"

mkdir -p /tmp/.X11-unix /var/lib/xkb
display=:7
/usr/bin/Xorg "$display" +iglx -noreset \
	</dev/null >/var/log/Xorg.gtk-package-test.log 2>&1 &
xorg_pid=$!

cleanup() {
	kill "$xorg_pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

i=0
while [ ! -e /tmp/.X11-unix/X7 ] && [ "$i" -lt 20 ]; do
	sleep 1
	i=$((i + 1))
done
if [ ! -e /tmp/.X11-unix/X7 ]; then
	cat /var/log/Xorg.gtk-package-test.log >&2
	echo "Xorg did not become ready" >&2
	exit 1
fi

run_example() {
	name=$1
	shift
	success=$1
	shift
	builder_boundary=$1
	shift
	# The preload exits successfully only after the example has reached its GTK
	# interface with a live Xorg display. An earlier application failure is fatal.
	if ! LD_PRELOAD=/root/libgtk-smoke-auto-close.so \
		VINIX_GTK_SMOKE_BUILDER_BOUNDARY="$builder_boundary" \
		GDK_SYNCHRONIZE=1 DISPLAY="$display" "$@" \
		>/tmp/"$name".log 2>&1; then
		cat /tmp/"$name".log >&2
		echo "$name failed before completing its GTK event-loop test" >&2
		exit 1
	fi
	echo "PASS $name $success"
}

run_example gtk3-demo "opened a GTK window" 0 /usr/bin/gtk3-demo
run_example gtk3-widget-factory "reached GTK interface construction" 1 \
	/usr/bin/gtk3-widget-factory

echo "VINIX GTK PACKAGE TEST: PASS"
