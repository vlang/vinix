#!/bin/sh
# Exercise a supervisor reload with a preinstalled /root/vinix-desktop.
# Intended for run-desktop-aarch64.sh --guest-init diagnostics.
set -eu

export HOME=/root
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export TERM=linux

fail() {
	echo "VINIX DESKTOP RUNTIME TEST: FAIL $*"
	/sbin/poweroff -f 2>/dev/null || exit 1
}

echo
echo "VINIX DESKTOP RUNTIME TEST: START"
[ -x /root/vinix-desktop ] || fail "desktop binary is missing"
(
	# Let the original compositor render and launch its default application so
	# the handoff also exercises teardown of a populated process group.
	sleep 15
	vinix-desktop-reload /root/vinix-desktop || fail "reload helper"
	# A guest-wide reload deadlock prevents this watchdog from being scheduled.
	# Reaching the marker proves the replacement session and kernel stayed live.
	sleep 15
	/bin/busybox pidof vinix-terminal >/dev/null 2>&1 \
		|| fail "replacement desktop did not reopen Terminal"
	echo "VINIX DESKTOP RUNTIME TEST: PASS"
	sync
	/sbin/poweroff -f 2>/dev/null || exit 0
) &

exec /usr/libexec/vinix-desktop-init
