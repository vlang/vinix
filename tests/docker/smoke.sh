#!/bin/sh
# Docker engine smoke test. Runs inside the aarch64 Vinix userland: starts
# dockerd, loads the offline busybox image and runs containers from it.
set -eu

export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export HOME=/root

image=vinix/busybox:latest
rootfs=/usr/share/vinix-docker/busybox-rootfs.tar

fail() {
	echo "DOCKER SMOKE FAIL: $*"
	if [ -f /var/log/dockerd.log ]; then
		echo "--- dockerd.log (tail) ---"
		tail -n 60 /var/log/dockerd.log
		echo "--- end dockerd.log ---"
	fi
	exit 1
}

pass() {
	echo "DOCKER SMOKE PASS: $*"
}

vinix-dockerd start || fail "dockerd did not start"
docker version || fail "docker version"
pass "daemon answers the API"

docker import "$rootfs" "$image" || fail "docker import"
docker image inspect "$image" >/dev/null || fail "imported image is missing"
pass "image imported"

output=$(docker run --rm "$image" echo hello-from-a-container) ||
	fail "docker run echo"
[ "$output" = hello-from-a-container ] || fail "unexpected output: $output"
pass "container ran and printed its output"

echo "DOCKER SMOKE: PASS"
