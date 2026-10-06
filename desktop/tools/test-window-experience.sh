#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
v=${V:-v}
desktop_source=${VINIX_DESKTOP_SOURCE:-"$root/desktop"}
if [ -n "${VINIX_UI2_SOURCE:-}" ]; then
    ui2=$VINIX_UI2_SOURCE
elif [ -f "$root/../ui2/v.mod" ]; then
    ui2=$root/../ui2
else
    ui2=$root/third_party/ui2
fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
# The disposable overlay excludes AppKit, including its bounds provider.
# Supply the same headless bridge on the macOS host used to run these tests.
sed 's/(linux || vinix)/(linux || vinix || macos)/' \
    "$root/desktop/tools/ui2_headless_bounds.v" > "$work/headless_bounds.v"
python3 "$root/desktop/tools/stage_ui2.py" "$work/modules/ui2" \
    "$ui2" "$work/headless_bounds.v"
mkdir "$work/ui"
python3 "$root/desktop/tools/stage_app.py" "$work/ui" "$desktop_source" \
    "$ui2/examples/calculator" >/dev/null
# Other sessions may edit the checkout while a test compiles. Materialize
# staged links once so each suite reads the same complete source snapshot.
python3 - "$work/ui" <<'PY'
import sys
from pathlib import Path
for path in Path(sys.argv[1]).iterdir():
    if path.is_symlink() and path.is_file():
        data = path.read_bytes()
        path.unlink()
        path.write_bytes(data)
PY
python3 "$root/desktop/tools/stage_host_gpu.py" "$work/ui" --v "$v"
rm -f "$work/ui/main.v"
printf "Module { name: 'window_experience_tests' }\n" > "$work/ui/v.mod"

suites='window_isolation window_placement window_edges window_overview window_layout window_snap_assist window_actions windows_shortcuts titlebar_click workspace taskbar_features switcher quick_launch utilities color_meter app_icon'
if [ "$#" -gt 0 ]; then
    suites="$*"
fi
for suite in $suites; do
    printf '==> Window experience: %s\n' "$suite"
    cp "$root/desktop/tools/tests/${suite}_test.v" "$work/ui/"
    "$v" -new-compiler -nocache -gc none -manualfree -enable-globals -d ui2_headless \
        -path "@vlib|$work/modules|@vmodules|$root|$root/third_party" "$work/ui/${suite}_test.v"
    rm -f "$work/ui/${suite}_test.v"
done
