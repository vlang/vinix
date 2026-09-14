#!/bin/sh
# Exercise the Minecraft launcher's argument expansion on the build host, with
# a stub JVM standing in for the game. No Minecraft files are needed.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/bin" "$work/game" "$work/user"

cat > "$work/game/launch.env" <<EOF
MC_VERSION='26.2'
MC_VERSION_TYPE='release'
MC_MAIN_CLASS='net.minecraft.client.main.Main'
MC_ASSET_INDEX='32'
MC_GAME_ROOT='$work/game'
MC_JAVA_MAJOR='25'
MC_CLASSPATH='$work/game/libraries/org/lwjgl/lwjgl/3.4.1/lwjgl-3.4.1-natives-linux-arm64.jar:$work/game/versions/26.2/26.2.jar'
MC_JVM_ARGS='-Dorg.lwjgl.system.SharedLibraryExtractPath=\${natives_directory}/lwjgl -Dminecraft.launcher.brand=\${launcher_name}'
MC_GAME_ARGS_DEMO='--username \${auth_player_name} --version \${version_name} --gameDir \${game_directory} --assetsDir \${assets_root} --assetIndex \${assets_index_name} --uuid \${auth_uuid} --accessToken \${auth_access_token} --versionType \${version_type} --demo'
MC_GAME_ARGS_FULL='--username \${auth_player_name} --version \${version_name} --gameDir \${game_directory} --assetsDir \${assets_root} --assetIndex \${assets_index_name} --uuid \${auth_uuid} --accessToken \${auth_access_token} --versionType \${version_type}'
EOF

cat > "$work/bin/java" <<'EOF'
#!/bin/sh
if [ "${1:-}" = -version ]; then
    echo 'openjdk version "25" 2026-09-16'
    exit 0
fi
printf 'display=%s\n' "${DISPLAY:-}"
printf 'software=%s\n' "${LIBGL_ALWAYS_SOFTWARE:-}"
printf 'gallium=%s\n' "${GALLIUM_DRIVER:-}"
printf 'indirect=%s\n' "${LIBGL_ALWAYS_INDIRECT:-}"
printf 'args=%s\n' "$*"
EOF
chmod +x "$work/bin/java"

launcher="$root/build-support/minecraft/run-minecraft"
common_env="VINIX_MINECRAFT_ROOT=$work/game VINIX_MINECRAFT_JAVA=$work/bin/java VINIX_MINECRAFT_USER_DIR=$work/user"

# --check reports the staged version without needing a display.
output=$(env $common_env "$launcher" --check)
case "$output" in
    *'Minecraft 26.2 (release)'*'no account signed in'*'ready'*) ;;
    *) echo "check failed: $output" >&2; exit 1 ;;
esac

# With no account, the launcher starts Mojang's free demo and expands every
# placeholder Mojang's template uses.
output=$(env $common_env DISPLAY=:7 "$launcher")
case "$output" in
    *'display=:7'*'software=1'*'gallium=llvmpipe'*'--demo'*) ;;
    *) echo "demo launch failed: $output" >&2; exit 1 ;;
esac
if printf '%s' "$output" | grep -q '\${'; then
    echo "unexpanded placeholder in launch: $output" >&2
    exit 1
fi
printf '%s\n' "$output" | grep -q '^indirect=$'
printf '%s' "$output" | grep -q 'net.minecraft.client.main.Main'
printf '%s' "$output" | grep -q 'natives-linux-arm64'
# musl needs Alpine's OpenAL and jemalloc instead of LWJGL's bundled copies.
printf '%s' "$output" | grep -q 'org.lwjgl.openal.libname=/usr/lib/libopenal.so.1'
# LWJGL's own jemalloc cannot be loaded here at all; use the libc allocator.
printf '%s' "$output" | grep -q 'org.lwjgl.system.allocator=system'
# LWJGL aborts with "Unknown platform: Vinix" unless it is told the ABI name.
printf '%s' "$output" | grep -q '\-Dos.name=Linux'

# The full game requires a real session; refuse rather than fabricate one.
if env $common_env DISPLAY=:7 "$launcher" --play >/dev/null 2>&1; then
    echo "--play unexpectedly launched without an account" >&2
    exit 1
fi

# A signed-in account plays the full game, with its own credentials.
cat > "$work/user/vinix-session.env" <<'EOF'
MC_PLAYER_NAME='Steve'
MC_PLAYER_UUID='0123456789abcdef0123456789abcdef'
MC_PLAYER_XUID='2535400000000000'
MC_ACCESS_TOKEN='test.access.token'
EOF
output=$(env $common_env DISPLAY=:7 "$launcher" --play)
case "$output" in
    *'--username Steve'*'--accessToken test.access.token'*) ;;
    *) echo "full launch failed: $output" >&2; exit 1 ;;
esac
case "$output" in
    *--demo*) echo "full launch unexpectedly entered the demo" >&2; exit 1 ;;
esac

# --demo stays available to a signed-in account, and never sends its token.
output=$(env $common_env DISPLAY=:7 "$launcher" --demo)
case "$output" in
    *'--demo'*) ;;
    *) echo "explicit demo failed: $output" >&2; exit 1 ;;
esac
if printf '%s' "$output" | grep -q 'test.access.token'; then
    echo "demo launch leaked the account token" >&2
    exit 1
fi

output=$(env $common_env "$launcher" --check)
case "$output" in
    *'signed in as Steve'*) ;;
    *) echo "check did not report the account: $output" >&2; exit 1 ;;
esac

env $common_env "$launcher" --logout >/dev/null
[ ! -f "$work/user/vinix-session.env" ]

# With no DISPLAY the launcher brings up Xorg and re-enters as the X client.
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
    *'display=:0'*'--demo'*) ;;
    *) echo "Xorg handoff failed: $output" >&2; exit 1 ;;
esac

echo 'minecraft launcher tests: PASS'
