#!/bin/sh
# Boot with --guest-init to verify the packaged OBS GUI and its capture screen.
set -eu

export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export HOME=/root
export TERM=linux
export LD_LIBRARY_PATH=/usr/lib:/usr/lib/xorg/modules
export LIBGL_DRIVERS_PATH=/usr/lib/xorg/modules/dri:/usr/lib/dri
export SSL_CA_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
# This boot is disposable; avoid uploading OBS's large package closure.
export VINIX_PKG_STORE_FILE=/tmp/vinix-obs-no-package-store

fail() {
	echo "VINIX OBS TEST: FAIL $*"
	[ ! -d /tmp/vinix-obs-test ] || ls -la /tmp/vinix-obs-test
	[ ! -e /run/vinix-obs-screen ] || ls -l /run/vinix-obs-screen
	ps -ef | grep -E 'obs|Xvfb' || true
	/usr/share/vinix/x-window-check :99 '' 2>/dev/null || true
	if [ -d /root/.config/obs-studio/logs ]; then
		for log in /root/.config/obs-studio/logs/*; do
			[ ! -f "$log" ] || tail -40 "$log"
		done
	fi
	[ ! -f /tmp/obs-host.log ] || tail -40 /tmp/obs-host.log
	exit 1
}

echo "VINIX OBS TEST: START"
[ -x /usr/bin/run-obs ] || fail "OBS launcher missing"
[ -r /usr/lib/vinix-obs-compat.so ] || fail "OBS compatibility library missing"
[ -x /usr/bin/vinix-wine-host ] || fail "X11 host missing"
mkdir -p /tmp /dev/shm /run/user/0 /tmp/.X11-unix /var/lib/xkb
chmod 1777 /tmp /dev/shm /tmp/.X11-unix

pkg install obs-studio || fail "package install failed"
[ -x /usr/bin/obs ] || fail "OBS executable missing"
[ -x /usr/bin/obs-ffmpeg-mux ] || fail "OBS muxer missing"

sleep 3600 | /usr/bin/vinix-wine-host :99 /tmp/vinix-obs-test 1280x900x24 \
	/usr/bin/run-obs --obs >/tmp/obs-host.log 2>&1 &
host_pid=$!
trap 'kill "$host_pid" 2>/dev/null || true' EXIT INT TERM

i=0
while [ "$i" -lt 180 ]; do
	if ! kill -0 "$host_pid" 2>/dev/null; then
		fail "OBS host exited before opening a window"
	fi
	if [ -e /tmp/vinix-obs-test/Xvfb_screen0 ] \
		&& [ -e /tmp/vinix-obs-test/Xvfb_screen1 ] \
		&& [ -e /run/vinix-obs-screen ] \
		&& /usr/share/vinix/x-window-check :99 'OBS' 2>/dev/null; then
		break
	fi
	sleep 1
	i=$((i + 1))
done
[ "$i" -lt 180 ] || fail "OBS did not map its window and capture screen"
sleep 5
kill -0 "$host_pid" 2>/dev/null || fail "OBS exited after mapping its window"
/usr/share/vinix/x-window-check :99 'OBS' 2>/dev/null \
	|| fail "OBS window did not stay mapped"
grep -q 'Switched to scene' /root/.config/obs-studio/logs/* \
	|| fail "OBS did not finish loading its default scene"

/usr/share/vinix/surface-probe obs-capture /run/vinix-obs-screen || fail "X11 capture screen or MIT-SHM unavailable"

# A mapped OBS window can still be stuck before Qt paints its controls. The
# XWD screen is shared memory, so watch its pixels until the UI appears.
/usr/share/vinix/surface-probe obs-paint /tmp/vinix-obs-test/Xvfb_screen0 || fail "OBS window stayed blank"

echo "VINIX OBS TEST: PASS"
