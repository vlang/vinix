#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Native image, log, information, storage and productivity models and IPC.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
v=${V:-v}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
python3 "$root/desktop/tools/stage_ui2.py" "$work/modules/ui2" "$root/third_party/ui2" "$root/desktop/tools/ui2_headless_bounds.v"
python3 "$root/desktop/tools/stage_app.py" "$work/ui" "$root/desktop" "$root/third_party/ui2/examples/calculator" >/dev/null
python3 - "$work/ui" <<'PY'
from pathlib import Path
import sys
for path in Path(sys.argv[1]).iterdir():
    if path.is_symlink() and path.is_file():
        contents = path.read_bytes()
        path.unlink()
        path.write_bytes(contents)
PY
rm "$work/ui/main.v"
printf "Module { name: 'native_utility_tests' }\n" > "$work/ui/v.mod"
python3 - "$root" "$work/ui/native_utility_test.v" <<'PY'
from pathlib import Path
import sys
root, destination = Path(sys.argv[1]), Path(sys.argv[2])
names = ['preview_app', 'console_app', 'system_information', 'utilities',
         'archive_app', 'disk_utility', 'backup_app', 'notes_app', 'reminders_app',
         'grapher_app', 'quick_launch', 'i18n']
imports, bodies = set(), []
for name in names:
    body = []
    for line in (root / 'desktop/tools/tests' / (name + '_test.v')).read_text().splitlines():
        if line.startswith('module '):
            continue
        if line.startswith('import '):
            imports.add(line)
        else:
            body.append(line)
    bodies.append('\n'.join(body))
destination.write_text('module main\n' + '\n'.join(sorted(imports)) + '\n\n' + '\n\n'.join(bodies))
PY
"$v" -new-compiler -nocache -cc clang -gc none -manualfree -enable-globals -stats -d ui2_headless \
    -path "@vlib|@vmodules|$work/modules|$root|$root/third_party" "$work/ui/native_utility_test.v"
cp "$root/desktop/tools/tests/heap_tracker.h" "$work/ui/"
for test in preview_app_memory console_app_memory system_information_memory native_paste_memory \
            archive_app_memory disk_utility_memory backup_app_memory native_poll_memory \
            notes_app_memory reminders_app_memory grapher_app_memory; do
    cp "$root/desktop/tools/tests/${test}_test.v" "$work/ui/"
    "$v" -new-compiler -nocache -cc clang -gc none -manualfree -enable-globals -stats -d ui2_headless -d track_heap \
        -path "@vlib|@vmodules|$work/modules|$root|$root/third_party" "$work/ui/${test}_test.v"
    rm "$work/ui/${test}_test.v"
done
if [ "${SKIP_NATIVE_IPC:-0}" != 1 ]; then
    cp "$root/desktop/tools/tests/app_process_integration.v" "$work/ui/main.v"
    "$v" -new-compiler -nocache -cc clang -gc none -manualfree -enable-globals -d ui2_headless \
        -path "@vlib|@vmodules|$work/modules|$root|$root/third_party" -o "$work/app-process-integration" "$work/ui"
    "$work/app-process-integration"
fi
