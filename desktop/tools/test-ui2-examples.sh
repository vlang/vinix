#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ui2_source=${VINIX_UI2_SOURCE:-}
if [ -z "$ui2_source" ] && [ -f "$root/../ui2/v.mod" ]; then
	ui2_source=$root/../ui2
fi
ui2_source=${ui2_source:-$root/third_party/ui2}
v=${V:-v}
work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-ui2-test.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

python3 - "$root/desktop/ui2_examples.txt" "$ui2_source/examples" <<'PY'
from pathlib import Path
import sys
expected = Path(sys.argv[1]).read_text().splitlines()
found = sorted(path.name for path in Path(sys.argv[2]).iterdir()
               if path.is_dir() and (path / 'main.v').is_file())
if expected != found:
    raise SystemExit('ui2 example manifest does not match source checkout')
print('PASS ui2 example inventory (%d)' % len(found))
PY

python3 "$root/desktop/tools/build_ui2_examples.py" \
	--host --repo "$root" --ui2-source "$ui2_source" \
	--output "$work/bin" --work "$work/build" --v "$v"
python3 "$root/desktop/tools/test_ui2_backend.py" "$work"/bin/vinix-ui2-*
