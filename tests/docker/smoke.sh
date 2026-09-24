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

# -t gives the container a pty. The shell sees a terminal on stdin and can
# reopen it as /dev/tty; the pty turns the newline into CRLF on the way out.
output=$(docker run --rm -t "$image" sh -c '[ -t 0 ] && [ -t 1 ] && : < /dev/tty && echo tty-ok') ||
	fail "docker run -t"
[ "$output" = "$(printf 'tty-ok\r')" ] || fail "unexpected -t output: $output"
pass "container ran with a terminal"

# A container is its own pid namespace: its first process is 1 and its /proc
# lists nothing from outside, dockerd included.
output=$(docker run --rm "$image" sh -c 'echo $$; cat /proc/[0-9]*/comm | grep -c dockerd; true') ||
	fail "docker run pid namespace"
[ "$output" = "$(printf '1\n0')" ] || fail "unexpected pid namespace view: $output"
pass "container has its own pid namespace"

# cpu.max: a busy loop held to a fifth of a CPU is throttled, and over two
# seconds uses well under the full second or two it would take unlimited.
output=$(docker run --rm --cpus 0.2 "$image" sh -c \
	'sh -c "while :; do :; done" & busy=$!; sleep 2; kill $busy; cat /sys/fs/cgroup/cpu.stat') ||
	fail "docker run --cpus"
throttled=$(echo "$output" | awk '$1 == "nr_throttled" { print $2 }')
usage=$(echo "$output" | awk '$1 == "usage_usec" { print $2 }')
[ "${throttled:-0}" -gt 0 ] || fail "--cpus 0.2 was never throttled: $output"
[ "${usage:-0}" -lt 1200000 ] || fail "--cpus 0.2 used ${usage}us of CPU in 2s: $output"
pass "cpu.max throttles a busy container"

# pids.max: forks past the limit fail with EAGAIN.
output=$(docker run --rm --pids-limit 12 "$image" sh -c \
	'n=0; while [ $n -lt 20 ]; do sleep 2 & n=$((n+1)); done; wait' 2>&1) || true
case "$output" in
*fork*) ;;
*) fail "--pids-limit 12 let 20 processes start: $output" ;;
esac
pass "pids.max refuses forks past the limit"

# memory.max: a container that keeps allocating is killed once it goes over,
# and docker reports a SIGKILL (137).
rc=0
docker run --rm --memory 32m "$image" sh -c 'x=x; while :; do x=$x$x; done' >/dev/null 2>&1 || rc=$?
[ "$rc" = 137 ] || fail "--memory 32m: a runaway allocation ended with $rc, not 137"
pass "memory.max kills a container that goes over"

# cgroup.freeze: docker pause stops a container, unpause lets it carry on, and
# a paused container can still be removed.
docker run -d --name ticker "$image" sh -c 'while :; do echo tick; sleep 1; done' >/dev/null ||
	fail "docker run -d"
sleep 3
docker pause ticker >/dev/null || fail "docker pause"
paused=$(docker logs ticker 2>&1 | wc -l)
sleep 3
still=$(docker logs ticker 2>&1 | wc -l)
[ "$still" -le $((paused + 1)) ] || fail "a paused container kept running: $paused -> $still lines"
docker unpause ticker >/dev/null || fail "docker unpause"
sleep 3
resumed=$(docker logs ticker 2>&1 | wc -l)
[ "$resumed" -gt "$still" ] || fail "an unpaused container did not carry on: $still -> $resumed lines"
docker pause ticker >/dev/null || fail "docker pause, second time"
docker rm -f ticker >/dev/null || fail "docker rm -f of a paused container"
pass "docker pause freezes a container and unpause resumes it"

echo "DOCKER SMOKE: PASS"
