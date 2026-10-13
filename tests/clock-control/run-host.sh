#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/time"
cp "$root/kernel/time/discipline.v" "$root/tests/clock-control/discipline_test.v" "$work/time/"
# Stage the production value type and arithmetic, excluding kernel timers.
"$root/build-support/source-tools/run" clock "$root/kernel/time/time.v" "$work/time/spec.v"
VMODULES="$work" "${V:-v}" -new-compiler "$work/time/discipline_test.v"
"$root/tests/security-policy/run.sh"
