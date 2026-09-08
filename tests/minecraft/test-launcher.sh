#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/bin" "$work/game" "$work/user"
: > "$work/game/game.conf"
cp "$root/build-support/minecraft/minetest.conf" "$work/default.conf"

cat > "$work/bin/minetest" <<'EOF'
#!/bin/sh
if [ "${1:-}" = --version ]; then
    echo 'Minetest 5.9.1 (Linux)'
    exit 0
fi
printf 'display=%s\n' "${DISPLAY:-}"
printf 'software=%s\n' "${LIBGL_ALWAYS_SOFTWARE:-}"
printf 'indirect=%s\n' "${LIBGL_ALWAYS_INDIRECT:-}"
printf 'audio=%s\n' "${SDL_AUDIODRIVER:-}"
printf 'args=%s\n' "$*"
EOF
chmod +x "$work/bin/minetest"

launcher="$root/build-support/minecraft/run-minecraft"
common_env="VINIX_MINECRAFT_BIN=$work/bin/minetest VINIX_MINECRAFT_GAME_PATH=$work/game VINIX_MINECRAFT_USER_PATH=$work/user VINIX_MINECRAFT_DEFAULTS=$work/default.conf"

output=$(env $common_env "$launcher" --check)
case "$output" in
    *'Minetest 5.9.1'*'C++ client and game data are ready'*) ;;
    *) echo "launcher check failed: $output" >&2; exit 1 ;;
esac

output=$(env $common_env DISPLAY=:7 "$launcher")
case "$output" in
    *'display=:7'*'software=1'*'indirect='*'audio=dummy'*'--gameid minetest --go'*) ;;
    *) echo "world launch failed: $output" >&2; exit 1 ;;
esac
printf '%s\n' "$output" | grep -q '^indirect=$'
grep -q '^gameid = minetest$' "$work/user/worlds/Vinix World/world.mt"
cmp -s "$work/default.conf" "$work/user/minetest.conf"

output=$(env $common_env DISPLAY=:7 "$launcher" --menu)
case "$output" in
    *'args=--config '*);;
    *) echo "menu launch failed: $output" >&2; exit 1 ;;
esac
case "$output" in
    *--go*) echo "menu unexpectedly entered a world" >&2; exit 1 ;;
esac

cat > "$work/xinitrc" <<EOF
#!/bin/sh
exec "$launcher" --x11-client
EOF
chmod +x "$work/xinitrc"
cat > "$work/bin/startx" <<'EOF'
#!/bin/sh
export DISPLAY=:0
exec "$1"
EOF
chmod +x "$work/bin/startx"
output=$(env $common_env \
    VINIX_MINECRAFT_STARTX="$work/bin/startx" \
    VINIX_MINECRAFT_XINITRC="$work/xinitrc" \
    "$launcher")
case "$output" in
    *'display=:0'*'--gameid minetest --go'*) ;;
    *) echo "Xorg handoff failed: $output" >&2; exit 1 ;;
esac

echo 'minecraft launcher tests: PASS'
