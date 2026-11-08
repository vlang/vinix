#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
test_state=$(mktemp -d)
if [ "${KEEP_TEST_TMP:-0}" = 0 ]; then
    trap 'rm -rf "$test_state"' EXIT HUP INT TERM
else
    printf '%s\n' "$test_state"
fi
"$root/build-support/run-v-tool.sh" "$root/tests/memory-pressure/run.v" "$test_state/results"
