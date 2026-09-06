#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# VFLAGS may select the compiler/backend/sanitizers. No C-only fallback.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
v=${V:-v}
command -v "$v" >/dev/null 2>&1 || { echo 'ERROR: V is required.' >&2; exit 1; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir "$work/clients"
for name in device_io.v platform.c.v backlight_client.v battery_client.v; do
    cp "$root/desktop/$name" "$work/clients/"
done
cp "$root/desktop/tools/tests/device_io_mock.v" "$work/clients/"
for name in backlight_client battery_client platform; do
    cp "$root/desktop/tools/tests/${name}_test.v" "$work/clients/"
    # Invoke the test file directly so older vtest runners cannot lose the
    # shell quoting around a module path containing '|'. V runs its tests.
    "$v" -gc none -enable-globals -stats \
        -path "@vlib|@vmodules|$root/kernel/modules" "$work/clients/${name}_test.v"
done
if [ "${CLIENTS_ONLY:-0}" = 1 ]; then exit 0; fi
[ -f "$root/third_party/ui2/v.mod" ] || {
    echo 'ERROR: Settings UI tests require third_party/ui2.' >&2; exit 1;
}
# Settings is a category of the whole desktop application now, so the UI tests
# build against the real thing rather than a hand-picked subset.
# Staged exactly as the real build stages it, ui2 example and all, so the
# tests build against the desktop that ships. main.v is then dropped: its
# fn main() would collide with the test runner's.
mkdir "$work/ui"
python3 "$root/desktop/tools/stage_app.py" "$work/ui" "$root/desktop" \
    "$root/third_party/ui2/examples/calculator" >/dev/null
rm -f "$work/ui/main.v"
cp "$root/desktop/tools/tests/settings_test.v" "$work/ui/"
# Both sets share fixture_app and element_named in one translation unit.
sed '1,/^import ui2$/d' "$root/desktop/tools/tests/battery_test.v" >> "$work/ui/settings_test.v"
printf "Module { name: 'settings_tests' }\n" > "$work/ui/v.mod"
"$v" -gc none -enable-globals -stats -d ui2_headless \
    -path "@vlib|@vmodules|$root/third_party" "$work/ui/settings_test.v"
