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

# The disposable test root starts empty. Install a syntactically valid profile
# so this run follows the ordinary desktop path and launches Files/Terminal;
# the hash is never authenticated by this boot-only reload test.
umask 077
mkdir -p /root/vinix
chmod 700 /root/vinix
printf '%s\n' \
	'version=1' \
	'name=56696e6978' \
	'kdf=scrypt' \
	'n=16384' \
	'r=8' \
	'p=1' \
	'salt=00000000000000000000000000000000' \
	'hash=0000000000000000000000000000000000000000000000000000000000000000' \
	> /root/.vinix-user
chmod 600 /root/.vinix-user

# Simulate what a failed development session leaves on a persistent disk-root:
# a replaced multicall executable and volatile /run markers. PID 1 must restore
# the packaged desktop before launching anything, even when the host image ID
# itself has not changed between boots.
[ -x /usr/libexec/vinix-desktop-system ] \
	|| fail "packaged desktop recovery copy is missing"
cp /bin/busybox /usr/bin/.vinix-desktop-stale
chmod 755 /usr/bin/.vinix-desktop-stale
mv -f /usr/bin/.vinix-desktop-stale /usr/bin/vinix-desktop
mkdir -p /run
: > /run/vinix-desktop-development
: > /run/vinix-desktop-ready

wait_for_ready_session() {
	round=$1
	attempt=0
	while [ "$attempt" -lt 45 ]; do
		if [ -s /run/vinix-desktop-ready ] \
			&& /bin/busybox pidof vinix-desktop >/dev/null 2>&1 \
			&& /bin/busybox pidof vinix-files >/dev/null 2>&1 \
			&& /bin/busybox pidof vinix-terminal >/dev/null 2>&1; then
			return 0
		fi
		sleep 1
		attempt=$((attempt + 1))
	done
	fail "round $round replacement desktop did not become ready"
}

# Build while the ordinary desktop and its application processes are running,
# exactly like the command entered in Terminal. Keeping this worker outside the
# compositor's process group lets it verify the replacement after that old
# group (including its Terminal shell) has been torn down.
(
	attempt=0
	host_url=$(cat /etc/vinix/qemu-host-source-url)
	while ! /usr/bin/curl --fail --silent --output /dev/null \
		--connect-timeout 1 --max-time 2 "${host_url%/}/health" \
		&& [ "$attempt" -lt 100 ]; do
		sleep 1
		attempt=$((attempt + 1))
	done
	[ "$attempt" -lt 100 ] || fail "QEMU host source service did not become reachable"
	/bin/busybox cmp -s /usr/libexec/vinix-desktop-system /usr/bin/vinix-desktop \
		|| fail "boot did not restore the packaged desktop"
	[ ! -e /run/vinix-desktop-development ] \
		|| fail "boot retained the stale development marker"

	old_pid=''
	attempt=0
	while [ "$attempt" -lt 30 ]; do
		old_pid=$(/bin/busybox pidof vinix-desktop 2>/dev/null || true)
		[ -n "$old_pid" ] && break
		sleep 1
		attempt=$((attempt + 1))
	done
	[ -n "$old_pid" ] || fail "initial desktop did not start"

	vinix-host-sync || fail "first host source sync"
	vinix-host-sync || fail "second host source sync"
	vinix-desktop-build || fail "desktop build and reload"
	[ -x /root/vinix-desktop ] || fail "desktop output is missing"
	wait_for_ready_session 1
	first_pid=$(/bin/busybox pidof vinix-desktop)
	first_ready_inode=$(/bin/busybox stat -c '%i' /run/vinix-desktop-ready)

	# Reload the TCC-built session once more. This is the key liveness check:
	# a first replacement wedged in app IPC cannot consume the second SIGHUP and
	# therefore cannot recreate the marker removed by the helper.
	vinix-desktop-reload /root/vinix-desktop || fail "second reload helper"
	wait_for_ready_session 2
	second_pid=$(/bin/busybox pidof vinix-desktop)
	second_ready_inode=$(/bin/busybox stat -c '%i' /run/vinix-desktop-ready)
	[ "$second_ready_inode" != "$first_ready_inode" ] \
		|| fail "second reload did not recreate the readiness marker"

	# Keep observing after both native apps have exchanged more frames.
	sleep 10
	[ -s /run/vinix-desktop-ready ] || fail "second replacement stopped responding"
	stable_ready_inode=$(/bin/busybox stat -c '%i' /run/vinix-desktop-ready)
	[ "$stable_ready_inode" = "$second_ready_inode" ] \
		|| fail "replacement reloaded again without a new request"
	/bin/busybox pidof vinix-files >/dev/null 2>&1 \
		|| fail "second replacement did not keep Files running"
	/bin/busybox pidof vinix-terminal >/dev/null 2>&1 \
		|| fail "second replacement did not keep Terminal running"
	echo "VINIX HOST DESKTOP BUILD TEST: PASS $old_pid -> $first_pid -> $second_pid"
	sync
	/sbin/poweroff -f 2>/dev/null || exit 0
) &

exec /usr/libexec/vinix-desktop-init
