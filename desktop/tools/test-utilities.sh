#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
v=${V:-v}
command -v "$v" >/dev/null 2>&1 || {
    echo 'ERROR: V is required.' >&2
    exit 1
}
[ -f "$root/third_party/ui2/v.mod" ] || {
    echo 'ERROR: utility UI tests require third_party/ui2.' >&2
    exit 1
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir "$work/ui"
python3 "$root/desktop/tools/stage_app.py" "$work/ui" "$root/desktop" \
    "$root/third_party/ui2/examples/calculator" >/dev/null
rm -f "$work/ui/main.v"
cp "$root/desktop/tools/tests/utilities_test.v" "$work/ui/"
printf "Module { name: 'utility_tests' }\n" > "$work/ui/v.mod"

"$v" -gc none -manualfree -enable-globals -stats -d ui2_headless \
    -path "@vlib|@vmodules|$root/third_party" "$work/ui/utilities_test.v"
