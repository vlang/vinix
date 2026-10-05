#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
python3 "$root/desktop/tools/stage_ui2.py" \
    "$work/modules/ui2" "$root/third_party/ui2" \
    "$root/desktop/tools/ui2_headless_bounds.v"
mkdir "$work/ui"
python3 "$root/desktop/tools/stage_app.py" "$work/ui" "$root/desktop" \
    "$root/third_party/ui2/examples/calculator" >/dev/null
cp "$root/tests/application-sandbox/calculator_rpc.v" "$work/ui/main.v"
"${V:-v}" -new-compiler -nocache -gc none -manualfree -enable-globals -d ui2_headless \
    -path "@vlib|@vmodules|$work/modules|$root|$root/third_party" \
    -o "$work/calculator-rpc" "$work/ui"
"$work/calculator-rpc"
