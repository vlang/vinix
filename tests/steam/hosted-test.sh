#!/bin/sh
# The desktop host must survive Valve's detached updater and launch the newly
# installed client once, then close when that client exits.
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-steam-hosted.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
export HOME="$work/home"
mkdir -p "$HOME/.steam"
export VINIX_STEAM_LAUNCHER="$work/fake-steam"

cat > "$VINIX_STEAM_LAUNCHER" <<'FAKE'
#!/bin/sh
count=$(cat "$HOME/count" 2>/dev/null || echo 0)
count=$((count + 1))
echo "$count" > "$HOME/count"
if [ "$count" -eq 1 ] && [ "${INSTALL_ON_FIRST:-0}" -eq 1 ]; then
    mkdir -p "$HOME/.local/share/Steam/package"
    echo installed > "$HOME/.local/share/Steam/package/steam_client_ubuntu12.installed"
fi
if [ "$count" -eq 1 ] && [ "${UPDATE_ON_FIRST:-0}" -eq 1 ]; then
    mkdir -p "$HOME/.local/share/Steam/logs"
    echo 'Update complete, launching Steam...' >> "$HOME/.local/share/Steam/logs/bootstrap_log.txt"
fi
sleep 1 </dev/null >/dev/null 2>&1 &
echo "$!" > "$HOME/.steam/steam.pid"
FAKE
chmod 0755 "$VINIX_STEAM_LAUNCHER"

INSTALL_ON_FIRST=1 python3 - "$repo/build-support/steam/steam-hosted" <<'PY'
import os
import subprocess
import sys

subprocess.run([sys.argv[1]], env=os.environ, check=True, timeout=20)
PY
[ "$(cat "$HOME/count")" = 2 ] || {
    echo 'the hosted launcher did not restart after the first update' >&2
    exit 1
}

echo 0 > "$HOME/count"
INSTALL_ON_FIRST=0 python3 - "$repo/build-support/steam/steam-hosted" <<'PY'
import os
import subprocess
import sys

subprocess.run([sys.argv[1]], env=os.environ, check=True, timeout=20)
PY
[ "$(cat "$HOME/count")" = 1 ] || {
    echo 'an installed client was launched more than once' >&2
    exit 1
}

echo 0 > "$HOME/count"
UPDATE_ON_FIRST=1 python3 - "$repo/build-support/steam/steam-hosted" <<'PY'
import os
import subprocess
import sys

subprocess.run([sys.argv[1]], env=os.environ, check=True, timeout=20)
PY
[ "$(cat "$HOME/count")" = 2 ] || {
    echo 'the hosted launcher did not restart after repairing an installed client' >&2
    exit 1
}
echo 'Steam hosted launcher tests passed.'
