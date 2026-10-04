#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/time"
cp "$root/kernel/time/discipline.v" "$root/tests/clock-control/discipline_test.v" "$work/time/"
# Stage the production value type and arithmetic, excluding kernel timers.
python3 - "$root/kernel/time/time.v" "$work/time/spec.v" <<'PY'
import pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text()
start = source.index('pub struct TimeSpec')
end = source.index('__global (', start)
pathlib.Path(sys.argv[2]).write_text('module time\n' + source[start:end])
PY
VMODULES="$work" "${V:-v}" -new-compiler test "$work/time/discipline_test.v"
"$root/tests/security-policy/run.sh"
