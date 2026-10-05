#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
task_build=$(mktemp -d "${TMPDIR:-/tmp}/vinix-audit-collector.XXXXXX")
trap 'rm -rf "$task_build"' EXIT HUP INT TERM
"${CC:-cc}" -std=c11 -Wall -Wextra -Werror -O2 \
    "$task_root/tests/security-audit/collector_test.c" -o "$task_build/test"
"$task_build/test"
"${CC:-cc}" -std=c11 -Wall -Wextra -Werror -O2 \
    "$task_root/tools/security-audit/collector.c" -o "$task_build/collector"
if [ "$(id -u)" -ne 0 ]; then
    if "$task_build/collector" --once >"$task_build/output" 2>&1; then
        echo 'non-root collector unexpectedly succeeded' >&2
        exit 1
    fi
    rg -q 'root required' "$task_build/output"
fi
