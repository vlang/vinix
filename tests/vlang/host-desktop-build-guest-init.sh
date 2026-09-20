#!/bin/sh
# End-to-end QEMU check for repeated host syncs and a native desktop build.
# Intended for run-desktop-aarch64.sh --guest-init.
set -eu

export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export TERM=linux
export HOME=/root

fail() {
	echo "VINIX HOST DESKTOP BUILD TEST: FAIL $*"
	/sbin/poweroff -f 2>/dev/null || exit 1
}

echo
echo "VINIX HOST DESKTOP BUILD TEST: START"
attempt=0
host_url=$(cat /etc/vinix/qemu-host-source-url)
while ! /usr/bin/curl --fail --silent --output /dev/null \
	--connect-timeout 1 --max-time 2 "${host_url%/}/health" \
	&& [ "$attempt" -lt 100 ]; do
	sleep 1
	attempt=$((attempt + 1))
done
[ "$attempt" -lt 100 ] || fail "QEMU host source service did not become reachable"
vinix-host-sync || fail "first host source sync"
vinix-host-sync || fail "second host source sync"
vinix-desktop-build --no-reload || fail "desktop build"
[ -x /root/vinix-desktop ] || fail "desktop output is missing"
/root/vinix-desktop &
desktop_pid=$!
attempt=0
while [ "$attempt" -lt 10 ]; do
	sleep 1
	kill -0 "$desktop_pid" 2>/dev/null || fail "built desktop exited during startup"
	attempt=$((attempt + 1))
done
kill -HUP "$desktop_pid" 2>/dev/null || fail "cannot stop built desktop"
wait "$desktop_pid" || fail "built desktop did not stop cleanly"
echo "VINIX HOST DESKTOP BUILD TEST: PASS"
sync
/sbin/poweroff -f 2>/dev/null || exit 0
