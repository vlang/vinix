#!/bin/sh
# The desktop host must survive Valve's detached updater and launch the newly
# installed client once, then close when that client exits.
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
hosted_command=${VINIX_STEAM_HOSTED_COMMAND:-"$repo/tests/steam/hosted-command/run"}
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
printf '<%s>\n' "$*" >> "$HOME/args"
if [ "$count" -eq 1 ] && [ "${INSTALL_ON_FIRST:-0}" -eq 1 ]; then
    mkdir -p "$HOME/.local/share/Steam/package"
    echo installed > "$HOME/.local/share/Steam/package/steam_client_ubuntu12.installed"
fi
if [ "$count" -eq 1 ] && [ "${UPDATE_ON_FIRST:-0}" -eq 1 ]; then
    mkdir -p "$HOME/.local/share/Steam/logs"
    echo 'Update complete, launching Steam...' >> "$HOME/.local/share/Steam/logs/bootstrap_log.txt"
    # Valve's updater restores the original CSS before the hosted retry.
    echo '.label{font-size:12px;color:#afafaf;text-transform:uppercase;letter-spacing:.02em;user-select:none}' > "$HOME/.local/share/Steam/steamui/css/chunk.css"
fi
sleep 1 </dev/null >/dev/null 2>&1 &
echo "$!" > "$HOME/.steam/steam.pid"
FAKE
chmod 0755 "$VINIX_STEAM_LAUNCHER"

INSTALL_ON_FIRST=1 "$hosted_command" "$repo/build-support/steam/steam-hosted"
[ "$(cat "$HOME/count")" = 2 ] || {
    echo 'the hosted launcher did not restart after the first update' >&2
    exit 1
}
[ "$(sed -n '1p' "$HOME/args")" = '<>' ] || exit 1
[ "$(sed -n '2p' "$HOME/args")" = '<-noverifyfiles -nobootstrapperupdate>' ] || exit 1

echo 0 > "$HOME/count"
rm "$HOME/args"
mkdir -p "$HOME/.local/share/Steam/steamui/css"
echo '.label{font-size:12px;color:#afafaf;text-transform:uppercase;letter-spacing:.02em;user-select:none}' > "$HOME/.local/share/Steam/steamui/css/chunk.css"
INSTALL_ON_FIRST=0 "$hosted_command" "$repo/build-support/steam/steam-hosted"
[ "$(cat "$HOME/count")" = 1 ] || {
    echo 'an installed client was launched more than once' >&2
    exit 1
}
[ "$(cat "$HOME/args")" = '<-noverifyfiles -nobootstrapperupdate>' ] || exit 1
grep -Fq 'font-family:DejaVu Sans,Arial,Helvetica,sans-serif' "$HOME/.local/share/Steam/steamui/css/chunk.css" || {
    echo 'the installed client login label font was not adjusted' >&2
    exit 1
}

echo 0 > "$HOME/count"
rm "$HOME/args"
UPDATE_ON_FIRST=1 "$hosted_command" "$repo/build-support/steam/steam-hosted"
[ "$(cat "$HOME/count")" = 2 ] || {
    echo 'the hosted launcher did not restart after repairing an installed client' >&2
    exit 1
}
[ "$(wc -l < "$HOME/args" | tr -d ' ')" = 2 ] || exit 1
[ "$(sed -n '1p' "$HOME/args")" = '<-noverifyfiles -nobootstrapperupdate>' ] || exit 1
[ "$(sed -n '2p' "$HOME/args")" = '<-noverifyfiles -nobootstrapperupdate>' ] || exit 1
grep -Fq 'font-family:DejaVu Sans,Arial,Helvetica,sans-serif' "$HOME/.local/share/Steam/steamui/css/chunk.css" || {
    echo 'the login label font was not adjusted after the update' >&2
    exit 1
}
echo 'Steam hosted launcher tests passed.'
