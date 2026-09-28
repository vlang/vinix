#!/bin/sh
# Desktop CPU and memory measurement, for --guest-init boots. Run it with
# tests/desktop-perf/run.py, which supplies the desktop builds to compare and
# drives the pointer from the host when a scenario asks for it.
#
# Every build runs every scenario in the same boot, alternating which goes
# first in each round, so a background task or a slow host affects them alike.
# Each run starts a fresh compositor, waits for its session-ready marker, lets
# it settle and then samples the whole process tree with measure.

export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export HOME=/root
export TERM=linux
export USER=root
export LOGNAME=root
export SHELL=/bin/zsh
export LD_LIBRARY_PATH=/usr/lib:/usr/lib/xorg/modules
export XDG_RUNTIME_DIR=/run/user/0
export XDG_CONFIG_HOME=/root/.config
export XDG_CACHE_HOME=/root/.cache

perf=/opt/vinix-perf
VARIANTS=before
SCENARIOS=idle
ROUNDS=1
SETTLE=15
MEASURE=45
DESKTOP_ARGS=
. "$perf/config"

echo
echo "VINIX DESKTOP PERF: START"

mkdir -p /tmp /run /run/user/0 /dev/shm /root/.config /root/.cache
chmod 1777 /tmp /dev/shm

# A registered user skips the first-run registration screen and the app
# picker, so every run measures the ordinary desktop. Only the record's shape
# is checked at startup; nobody logs in with it.
name_hex=$(printf 'Perf User' | od -An -tx1 | tr -d ' \n')
printf 'version=1\nname=%s\nkdf=scrypt\nn=16384\nr=8\np=1\nsalt=%s\nhash=%s\n' \
	"$name_hex" 00112233445566778899aabbccddeeff \
	00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff \
	>/root/.vinix-user
chmod 600 /root/.vinix-user
rm -f /root/.vinix-first-run-apps

stop_desktop() {
	pid=$1
	# Taken first: once the compositor exits, its applications belong to init.
	children=$("$perf/measure" tree "$pid")
	touch /tmp/perf-quit
	waited=0
	while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 10 ]; do
		sleep 1
		waited=$((waited + 1))
	done
	# A focused application that takes keys receives Ctrl-Q instead of the
	# compositor. Anything still running is stopped outright.
	for child in $children $pid; do
		kill -9 "$child" 2>/dev/null
	done
	sleep 3
}

run_case() {
	variant=$1
	scenario=$2
	round=$3
	label="variant=$variant scenario=$scenario round=$round"
	# No desktop at all: what sleeping a frame at a time costs by itself.
	if [ "$scenario" = wakeups ]; then
		"$perf/measure" wakeups 16 "$MEASURE" "$label"
		return
	fi

	install -m755 "$perf/vinix-desktop-$variant" /usr/bin/vinix-desktop
	rm -f /run/vinix-desktop-ready /tmp/perf-quit
	sync
	sleep 2
	used_before=$("$perf/measure" used)
	log=/tmp/desktop-$variant-$scenario-$round.log
	case "$scenario" in
		apps)
			{ while [ ! -e /tmp/perf-quit ]; do sleep 1; done; printf '\021'; sleep 20; } |
				/usr/bin/vinix-desktop $DESKTOP_ARGS --open=Files --open=Terminal --open=Clock \
					'--open=Activity Monitor' --open=Calculator >"$log" 2>&1 &
			;;
		*)
			{ while [ ! -e /tmp/perf-quit ]; do sleep 1; done; printf '\021'; sleep 20; } |
				/usr/bin/vinix-desktop $DESKTOP_ARGS >"$log" 2>&1 &
			;;
	esac
	pid=$!

	waited=0
	while [ ! -e /run/vinix-desktop-ready ] && [ "$waited" -lt 120 ]; do
		if ! kill -0 "$pid" 2>/dev/null; then
			break
		fi
		sleep 1
		waited=$((waited + 1))
	done
	if [ ! -e /run/vinix-desktop-ready ]; then
		echo "PERF-ERROR $label the desktop was not ready after ${waited}s"
		tail -20 "$log"
		stop_desktop "$pid"
		return
	fi
	echo "PERF-READY $label after ${waited}s"
	sleep "$SETTLE"

	case "$scenario" in
		pointer|drag) echo "PERF-DRIVE $scenario $MEASURE" ;;
	esac
	"$perf/measure" sample "$pid" "$MEASURE" "$used_before" "$label"
	# The host photographs the screen, so a build that got faster by drawing
	# less than it should is caught by looking.
	echo "PERF-SHOT variant=$variant scenario=$scenario round=$round"
	sleep 3
	stop_desktop "$pid"
	frames=$(grep -o '[0-9]* frames' "$log" | tail -1)
	echo "PERF-LOG $label ${frames:-no frame count}"
	# What --stats measured, if it was asked for.
	grep '^frames=' "$log" | sed "s/^/PERF-STATS $label /"
}

round=1
while [ "$round" -le "$ROUNDS" ]; do
	# Alternate the order so neither build always runs on a freshly booted
	# machine or always follows the other.
	order=
	for variant in $VARIANTS; do
		if [ $((round % 2)) -eq 1 ]; then
			order="$order $variant"
		else
			order="$variant $order"
		fi
	done
	for scenario in $SCENARIOS; do
		for variant in $order; do
			run_case "$variant" "$scenario" "$round"
		done
	done
	round=$((round + 1))
done

echo "VINIX DESKTOP PERF: DONE"
sync
while true; do
	sleep 60
done
