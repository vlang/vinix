#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
task_build=$(mktemp -d "${TMPDIR:-/tmp}/vinix-audit-collector.XXXXXX")
trap 'rm -rf "$task_build"' EXIT HUP INT TERM
python3 "$task_root/build-support/security-tools/compile-v-core.py" audit "$task_build/core.c" -d security_no_main
"${CC:-cc}" -std=c11 -Wall -Wextra -Werror -O2 -fsanitize=address,undefined \
    -D_GNU_SOURCE -DVINIX_V_RUNTIME -I"$task_root/tools/security-audit" -c "$task_build/core.c" -o "$task_build/core.o"
"${CC:-cc}" -std=c11 -Wall -Wextra -Werror -O2 -fsanitize=address,undefined \
    "$task_root/tests/security-audit/collector_test.c" "$task_build/core.o" -o "$task_build/test"
"$task_build/test"
python3 "$task_root/build-support/security-tools/compile-v-core.py" audit "$task_build/collector.c"
"${CC:-cc}" -std=c11 -Wall -Wextra -Werror -O2 -fsanitize=address,undefined \
    -D_GNU_SOURCE -DVINIX_V_RUNTIME -I"$task_root/tools/security-audit" "$task_build/collector.c" -o "$task_build/collector"
if [ "$(id -u)" -ne 0 ]; then
    if "$task_build/collector" --once >"$task_build/output" 2>&1; then
        echo 'non-root collector unexpectedly succeeded' >&2
        exit 1
    fi
    rg -q 'root required' "$task_build/output"
fi
