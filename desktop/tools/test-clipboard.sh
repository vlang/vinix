#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
v=${V:-v}
work=$(mktemp -d /tmp/vinix-clipboard-tests.XXXXXX)
server_pid=
cleanup() {
    [ -z "$server_pid" ] || kill "$server_pid" 2>/dev/null || true
    rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM
"$root/tests/packages/test-qemu-package-store" --install-fixture "$work/source-fixture"
"$work/source-fixture" --clipboard-only
"$work/source-fixture" --clipboard-server "$work/port" &
server_pid=$!
for attempt in 1 2 3 4 5 6 7 8 9 10; do
    [ ! -s "$work/port" ] || break
    sleep 0.1
done
export VINIX_CLIPBOARD_TEST_URL="http://127.0.0.1:$(cat "$work/port")/clipboard"
"$root/desktop/tools/stage_ui2" "$work/modules/ui2" \
    "$root/third_party/ui2" "$root/desktop/tools/ui2_headless_bounds.v"
"$root/desktop/tools/stage_app" "$work/ui" "$root/desktop" \
    "$root/third_party/ui2/examples/calculator" >/dev/null
"$root/desktop/tools/stage_host_gpu" "$work/ui" --v "$v"
rm "$work/ui/main.v"
for name in clipboard editor_utf8 terminal_utf8; do
    cp "$root/desktop/tools/tests/${name}_test.v" "$work/ui/"
    "$v" -new-compiler -nocache -gc none -manualfree -enable-globals -d ui2_headless \
        -path "@vlib|@vmodules|$work/modules|$root|$root/third_party" "$work/ui/${name}_test.v"
    rm "$work/ui/${name}_test.v"
done
