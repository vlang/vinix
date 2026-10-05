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
python3 "$root/tests/clipboard/test_host.py"
python3 - "$root" "$work/port" <<'PY' &
import importlib.util, pathlib, sys
root = pathlib.Path(sys.argv[1])
sys.path.insert(0, str(root / 'tools'))
spec = importlib.util.spec_from_file_location('store', root / 'tools/qemu-package-store.py')
store = importlib.util.module_from_spec(spec)
spec.loader.exec_module(store)
store.read_clipboard = lambda: 'Привет\t😀\r\nsecond line'.encode()
server = store.OverlayServer(('127.0.0.1', 0), root / 'unused', 1024, None, (), None, True)
pathlib.Path(sys.argv[2]).write_text(str(server.server_port))
server.serve_forever()
PY
server_pid=$!
for attempt in 1 2 3 4 5 6 7 8 9 10; do
    [ ! -s "$work/port" ] || break
    sleep 0.1
done
export VINIX_CLIPBOARD_TEST_URL="http://127.0.0.1:$(cat "$work/port")/clipboard"
python3 "$root/desktop/tools/stage_ui2.py" "$work/modules/ui2" \
    "$root/third_party/ui2" "$root/desktop/tools/ui2_headless_bounds.v"
python3 "$root/desktop/tools/stage_app.py" "$work/ui" "$root/desktop" \
    "$root/third_party/ui2/examples/calculator" >/dev/null
python3 "$root/desktop/tools/stage_host_gpu.py" "$work/ui" --v "$v"
rm "$work/ui/main.v"
for name in clipboard editor_utf8 terminal_utf8; do
    cp "$root/desktop/tools/tests/${name}_test.v" "$work/ui/"
    "$v" -new-compiler -nocache -gc none -manualfree -enable-globals -d ui2_headless \
        -path "@vlib|@vmodules|$work/modules|$root|$root/third_party" "$work/ui/${name}_test.v"
    rm "$work/ui/${name}_test.v"
done
