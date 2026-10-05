#!/bin/sh
# In-guest check that the staged Minecraft client and its musl runtime are
# usable, without needing a display or an account.
set -eu

output=$(minecraft --check)
printf '%s\n' "$output"
case "$output" in
    *Minecraft*'client and game data are ready'*) ;;
    *)
        echo "MINECRAFT SMOKE: FAIL (client identity missing)" >&2
        exit 1
        ;;
esac

# LWJGL's AArch64 natives are glibc objects; gcompat is what lets them load.
for library in /lib/libgcompat.so.0 /lib/libc.so.6 /usr/lib/libjemalloc.so.2 \
    /usr/lib/libopenal.so.1; do
    if [ ! -f "$library" ]; then
        echo "MINECRAFT SMOKE: FAIL (missing $library)" >&2
        exit 1
    fi
done

# llvmpipe, not softpipe, is what reaches the OpenGL 3.2 core profile the
# client asks for.
if [ ! -f /usr/lib/gallium-pipe/pipe_swrast.so ]; then
    echo "MINECRAFT SMOKE: FAIL (no software Gallium pipe)" >&2
    exit 1
fi

echo "MINECRAFT SMOKE: PASS"
