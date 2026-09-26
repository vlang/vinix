#!/bin/sh
# Exercise a development reload while the GPU compositor is running.
# Intended for run-desktop-aarch64.sh gpuvm --guest-init.
set -eu

export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export HOME=/root
export TERM=linux

fail() {
	echo "VINIX GPU DESKTOP RELOAD TEST: FAIL $*"
	/sbin/poweroff -f 2>/dev/null || exit 1
}

# Bypass the interactive first-run form so the compositor starts its apps.
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

(
	[ -x /usr/bin/vinix-desktop-gpu ] || fail "GPU executable is missing"
	attempt=0
	gpu_pid=
	while [ "$attempt" -lt 120 ]; do
		if [ -s /run/vinix-desktop-ready ]; then
			for candidate in $(/bin/busybox pidof vinix-desktop-gpu 2>/dev/null || true); do
				case "$(cat "/proc/$candidate/comm" 2>/dev/null)" in
					vinix-desktop-g*) gpu_pid=$candidate; break ;;
				esac
			done
			[ -z "$gpu_pid" ] || break
		fi
		sleep 1
		attempt=$((attempt + 1))
	done
	[ -n "$gpu_pid" ] || fail "GPU compositor did not become ready"

	vinix-desktop-reload /usr/libexec/vinix-desktop-system \
		|| fail "reload helper rejected the GPU compositor"
	attempt=0
	while [ "$attempt" -lt 60 ]; do
		if [ -s /run/vinix-desktop-ready ] && \
		   [ "$(cat "/proc/$gpu_pid/comm" 2>/dev/null)" = vinix-desktop ] && \
		   /bin/busybox cmp -s /usr/libexec/vinix-desktop-system /usr/bin/vinix-desktop; then
			echo "VINIX GPU DESKTOP RELOAD TEST: PASS $gpu_pid"
			sync
			/sbin/poweroff -f 2>/dev/null || exit 0
		fi
		sleep 1
		attempt=$((attempt + 1))
	done
	fail "replacement desktop did not become ready"
) &

exec /usr/libexec/vinix-desktop-init
