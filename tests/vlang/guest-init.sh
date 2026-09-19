#!/bin/sh
# Automated AArch64 guest check for the native compiler and self-hosted
# desktop build. Intended for run-aarch64.sh --guest-init.
set -eu

export HOME=/root
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export TERM=linux

fail() {
	echo "VINIX V SELF-HOST TEST: FAIL $*"
	/sbin/poweroff -f 2>/dev/null || exit 1
}

echo
echo "VINIX V SELF-HOST TEST: START"
echo "==> Rebuilding V from its installed source tree"
v self || fail "compiler self rebuild"
[ -x /usr/lib/vlang/v_old ] || fail "self rebuild did not retain the old compiler"
echo "VINIX V SELF REBUILD TEST: PASS"
/root/v-smoke.sh || fail "native compiler smoke test"
vinix-desktop-build --no-reload || fail "desktop build"
[ -x /root/vinix-desktop ] || fail "desktop output is missing"
echo "VINIX V SELF-HOST BUILD TEST: PASS"

# Become the real desktop supervisor so the helper's SIGHUP reaches PID 1,
# just as it does from an interactive terminal. The sidecar verifies that the
# compositor PID changes after the atomic binary replacement.
(
	old_pid=''
	attempt=0
	while [ "$attempt" -lt 20 ]; do
		old_pid=$(/bin/busybox pidof vinix-desktop 2>/dev/null || true)
		[ -n "$old_pid" ] && break
		attempt=$((attempt + 1))
		sleep 1
	done
	if [ -z "$old_pid" ]; then
		echo "VINIX DESKTOP RELOAD TEST: FAIL initial desktop did not start"
		/sbin/poweroff -f 2>/dev/null || exit 1
	fi

	vinix-desktop-reload /root/vinix-desktop || {
		echo "VINIX DESKTOP RELOAD TEST: FAIL reload helper"
		/sbin/poweroff -f 2>/dev/null || exit 1
	}

	new_pid=''
	attempt=0
	while [ "$attempt" -lt 20 ]; do
		for candidate in $(/bin/busybox pidof vinix-desktop 2>/dev/null || true); do
			case " $old_pid " in
				*" $candidate "*) ;;
				*) new_pid=$candidate ;;
			esac
		done
		[ -n "$new_pid" ] && break
		attempt=$((attempt + 1))
		sleep 1
	done
	if [ -z "$new_pid" ]; then
		echo "VINIX DESKTOP RELOAD TEST: FAIL replacement desktop did not start"
		/sbin/poweroff -f 2>/dev/null || exit 1
	fi
	if [ ! -e /run/vinix-desktop-development ] \
		|| ! /bin/busybox cmp -s /root/vinix-desktop /usr/bin/vinix-desktop; then
		echo "VINIX DESKTOP RELOAD TEST: FAIL replacement was not installed"
		/sbin/poweroff -f 2>/dev/null || exit 1
	fi
	echo "VINIX DESKTOP RELOAD TEST: PASS $old_pid -> $new_pid"
	sync
	/sbin/poweroff -f 2>/dev/null || exit 0
) &

exec /usr/libexec/vinix-desktop-init
