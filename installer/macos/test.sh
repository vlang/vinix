#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SCRIPT_DIR="$ROOT/installer/macos"
TEST_DIR="$ROOT/build/vinix-installer-tests"
V=${V:-}
. "$ROOT/build-support/find-v.sh"

[ -f "$ROOT/third_party/ui2/v.mod" ] || {
    echo "ERROR: clone ui2 into third_party/ui2 before testing the installer." >&2
    exit 1
}

"$V" fmt -verify "$SCRIPT_DIR/main.v" "$SCRIPT_DIR/installer_test.v"
/bin/mkdir -p "$TEST_DIR"
# Build the test harness directly. V's aggregate `test` runner currently loses
# quoting around `|` in a custom module path when it spawns the per-file job.
"$V" -path "@vlib|@vmodules|$ROOT/third_party" \
    -o "$TEST_DIR/installer-test" "$SCRIPT_DIR/installer_test.v"
"$TEST_DIR/installer-test"
PYTHONPYCACHEPREFIX="$TEST_DIR/python-cache" \
    /usr/bin/python3 -m py_compile "$SCRIPT_DIR/vinix_auto.py"
"$SCRIPT_DIR/install-vinix.sh" --help >/dev/null
if "$SCRIPT_DIR/install-vinix.sh" --confirmed --disk disk0oops --space-gb 32 \
    --payload "$ROOT" 2>/dev/null; then
    echo "ERROR: malformed whole-disk identifier was accepted." >&2
    exit 1
fi
echo "Vinix macOS installer tests: PASS"
