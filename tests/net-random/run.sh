#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Compile the production V cores and the independent V oracle.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
. "$root/build-support/find-v.sh"
export VINIX_V_COMPILER="$V"
exec python3 "$root/tests/net-random/run.py" "$@"
