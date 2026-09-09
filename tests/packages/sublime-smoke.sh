#!/bin/sh
# Guest integration test for an on-demand Sublime Text installation.
set -eu

export PATH=/bin:/sbin:/usr/bin:/usr/sbin
export HOME=/root
export SSL_CA_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

echo "VINIX SUBLIME TEXT PACKAGE TEST"

if [ ! -x /usr/bin/Xorg ]; then
	echo "Sublime test needs the Vinix Xorg build (run build-x11-aarch64.sh first)" >&2
	exit 1
fi
if [ -e /opt/sublime_text ] || [ -e /lib/ld-linux-aarch64.so.1 ]; then
	echo "Sublime Text or gcompat was preinstalled; this test needs a clean base" >&2
	exit 1
fi

pkg install sublime-text

test -x /usr/bin/subl
test -x /opt/sublime_text/sublime_text
test -x /opt/sublime_text/plugin_host-3.8
test -f /lib/ld-linux-aarch64.so.1
test ! -L /lib/ld-linux-aarch64.so.1
test -f /usr/lib/libLLVM.so.19.1
test ! -L /usr/lib/libLLVM.so.19.1
test -d /dev/shm
test -f /usr/share/applications/sublime_text.desktop
test "$(subl --version)" = "Sublime Text Build 4200"
echo "PASS pkg installed the glibc-compatible Sublime runtime"

printf 'Sublime Text on Vinix\n' >/tmp/sublime-smoke.txt
mkdir -p /tmp/.X11-unix /var/lib/xkb
display=:9
/usr/bin/Xorg "$display" +iglx -noreset \
	</dev/null >/var/log/Xorg.sublime-package-test.log 2>&1 &
xorg_pid=$!

cleanup() {
	[ -z "${sublime_pid:-}" ] || kill "$sublime_pid" 2>/dev/null || true
	kill "$xorg_pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

i=0
while [ ! -e /tmp/.X11-unix/X9 ] && [ "$i" -lt 20 ]; do
	sleep 1
	i=$((i + 1))
done
if [ ! -e /tmp/.X11-unix/X9 ]; then
	cat /var/log/Xorg.sublime-package-test.log >&2
	echo "Xorg did not become ready" >&2
	exit 1
fi

# Run Sublime without test instrumentation, then inspect Xorg for a mapped
# editor window. LD_PRELOAD is deliberately avoided here because it is also
# inherited by Sublime's font/Pango worker threads.
DISPLAY="$display" subl --multiinstance --foreground --safe-mode -n \
	/tmp/sublime-smoke.txt >/tmp/sublime.log 2>&1 &
sublime_pid=$!

mapped=false
i=0
while [ "$i" -lt 20 ]; do
	if ! kill -0 "$sublime_pid" 2>/dev/null; then
		cat /tmp/sublime.log >&2
		echo "Sublime Text exited before showing its editor window" >&2
		exit 1
	fi
	if /root/x-window-check.py "$display" 'Sublime Text'; then
		mapped=true
		break
	fi
	sleep 1
	i=$((i + 1))
done
if [ "$mapped" != true ]; then
	cat /tmp/sublime.log >&2
	echo "Sublime Text did not map an editor window" >&2
	exit 1
fi

echo "PASS Sublime Text opened an editor window"
echo "VINIX SUBLIME TEXT PACKAGE TEST: PASS"
