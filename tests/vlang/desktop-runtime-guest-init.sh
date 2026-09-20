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
	# the handoff also exercises teardown of a populated process group. Repeat
	# the operation: the interactive development workflow rebuilds the desktop
	# many times without rebooting, and the second teardown used to overlap the
	# replacement session closely enough to wedge the guest.
	sleep 15
	for round in 1 2; do
		old_pid=$(/bin/busybox pidof vinix-desktop 2>/dev/null || true)
		[ -n "$old_pid" ] || fail "round $round has no running desktop"
		vinix-desktop-reload /root/vinix-desktop || fail "round $round reload helper"
		# A guest-wide reload deadlock prevents this watchdog from being
		# scheduled. Reaching these checks proves the replacement session and
		# kernel stayed live after all old application children exited.
		sleep 15
		new_pid=$(/bin/busybox pidof vinix-desktop 2>/dev/null || true)
		[ -n "$new_pid" ] || fail "round $round replacement desktop did not start"
		[ "$new_pid" != "$old_pid" ] || fail "round $round kept the old desktop"
		/bin/busybox pidof vinix-terminal >/dev/null 2>&1 \
			|| fail "round $round replacement desktop did not reopen Terminal"
	done
	echo "VINIX DESKTOP RUNTIME TEST: PASS"
	sync
	/sbin/poweroff -f 2>/dev/null || exit 0
) &

exec /usr/libexec/vinix-desktop-init
