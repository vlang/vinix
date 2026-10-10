#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Alexander Medvednikov
#
# The host half of tests/cpu-power: the idle governor, the x86 idle-state
# tables and the frequency drivers' arithmetic, compiled for this machine from
# the kernel's own files. Each directory beside this script is one module,
# whose kernel sources are links into kernel/. See README.md.
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$here/../../build-support/find-v.sh"

status=0
for module in cpuidle cpufreq; do
    [ -d "$here/$module" ] || continue
    "$V" -cc cc test "$here/$module" || status=1
done
exit $status
