#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
v=${V:-v}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
python3 "$root/desktop/tools/stage_ui2.py" "$work/modules/ui2" "$root/third_party/ui2" "$root/desktop/tools/ui2_headless_bounds.v"
python3 "$root/desktop/tools/stage_app.py" "$work/ui" "$root/desktop" "$root/third_party/ui2/examples/calculator" >/dev/null
rm "$work/ui/main.v"
printf "Module { name: 'activity_tests' }\n" > "$work/ui/v.mod"
# Compile the related cases together to validate their shared integration and
# avoid repeatedly compiling the entire desktop for each small test module.
python3 - "$root" "$work/ui/activity_test.v" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
files = [root / 'desktop/tools/tests/activity_kill_test.v', root / 'desktop/tools/tests/activity_controls_test.v']
files += [path for path in sorted(root.glob('tests/activity_*_test.v')) if 'lifetime' not in path.name and 'memory' not in path.name]
imports = set()
bodies = []
for path in files:
    body = []
    for line in path.read_text().splitlines():
        if line.startswith('module '):
            continue
        if line.startswith('import '):
            imports.add(line)
        else:
            body.append(line)
    bodies.append('\n'.join(body))
Path(sys.argv[2]).write_text('module main\n' + '\n'.join(sorted(imports)) + '\n\n' + '\n\n'.join(bodies))
PY
"$v" -new-compiler -nocache -gc none -manualfree -enable-globals -stats -d ui2_headless \
    -path "@vlib|@vmodules|$work/modules|$root|$root/third_party" "$work/ui/activity_test.v"

cp "$root/desktop/tools/tests/heap_tracker.h" "$work/ui/"
for source in "$root/tests/activity_lifetime_test.v" "$root/desktop/tools/tests/activity_resources_memory_test.v"; do
    cp "$source" "$work/ui/"
    "$v" -new-compiler -nocache -cc clang -gc none -manualfree -enable-globals -stats -d ui2_headless -d track_heap \
        -path "@vlib|@vmodules|$work/modules|$root|$root/third_party" "$work/ui/$(basename "$source")"
done
