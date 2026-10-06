#!/bin/sh
set -eu
repo=$(cd "$(dirname "$0")/../.." && pwd)
. "$repo/build-support/find-v.sh"
export VINIX_V_COMPILER="$V"
exec python3 "$repo/tests/memory/run-runtime.py" "$@"
