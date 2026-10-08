#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu
support_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
"$support_root/build-support/run-v-tool.sh" "$support_root/tests/desktop-perf/perfreport/core_test.v"
python3 "$support_root/tests/desktop-perf/test_runner.py"
