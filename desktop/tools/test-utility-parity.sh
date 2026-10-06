#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Behavioral coverage for the desktop utility workflows in UTILITIES.md.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
v=${V:-v}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
python3 "$root/desktop/tools/stage_ui2.py" "$work/modules/ui2" "$root/third_party/ui2" "$root/desktop/tools/ui2_headless_bounds.v"
python3 "$root/desktop/tools/stage_app.py" "$work/ui" "$root/desktop" "$root/third_party/ui2/examples/calculator" >/dev/null
python3 "$root/desktop/tools/stage_host_gpu.py" "$work/ui" --v "$v"
python3 - "$work/ui" <<'PY'
from pathlib import Path
import sys
# Freeze staged symlinks so another editing session cannot mix source versions
# during the test compiler's later generation phases.
for path in Path(sys.argv[1]).iterdir():
    if path.is_symlink() and path.is_file():
        contents = path.read_bytes()
        path.unlink()
        path.write_bytes(contents)
PY
rm "$work/ui/main.v"
printf "Module { name: 'utility_parity_tests' }\n" > "$work/ui/v.mod"
# Compile related model and UI cases together, with the same complete desktop
# and compiler as production. Each file can also run independently when staged.
python3 - "$root" "$work/ui/utility_parity_test.v" <<'PY'
from pathlib import Path
import sys
root, destination = Path(sys.argv[1]), Path(sys.argv[2])
names = ['utility_parity', 'calculator_features', 'disk_usage_features',
         'editor_features', 'editor_selection', 'calendar_events', 'clock_utility', 'files_info',
         'capture_features', 'text_copy_client', 'terminal_selection']
imports, bodies = set(), []
for name in names:
    source = root / 'desktop/tools/tests' / (name + '_test.v')
    body = []
    for line in source.read_text().splitlines():
        if line.startswith('module '):
            continue
        if line.startswith('import '):
            imports.add(line)
        else:
            body.append(line)
    bodies.append('\n'.join(body))
destination.write_text('module main\n' + '\n'.join(sorted(imports)) + '\n\n' + '\n\n'.join(bodies))
PY
"$v" -new-compiler -nocache -gc none -manualfree -enable-globals -stats -d ui2_headless \
    -path "@vlib|@vmodules|$work/modules|$root|$root/third_party" "$work/ui/utility_parity_test.v"

cp "$root/desktop/tools/tests/heap_tracker.h" "$work/ui/"
for test in calculator_features_memory utility_parity_memory editor_selection_memory \
            text_copy_client_memory terminal_selection_memory; do
    cp "$root/desktop/tools/tests/${test}_test.v" "$work/ui/"
    "$v" -new-compiler -nocache -cc clang -gc none -manualfree -enable-globals -stats -d ui2_headless -d track_heap \
        -path "@vlib|@vmodules|$work/modules|$root|$root/third_party" "$work/ui/${test}_test.v"
    rm "$work/ui/${test}_test.v"
done
