#!/bin/sh
# Test-only PID 1: run Valve's real Steam API without the Dota engine.
set -eu
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
export HOME=/home/dota2 USER=root LOGNAME=root SHELL=/bin/sh TERM=linux
mkdir -p /tmp/.X11-unix /run/user/0 /home/dota2
chmod 1777 /tmp /tmp/.X11-unix
echo VINIX-DOTA2-STEAM-SMOKE-START
uname -a
export LD_LIBRARY_PATH=/usr/lib
/usr/bin/Xvfb :99 -screen 0 640x480x24 -nolisten tcp -ac -extension MIT-SHM \
    >/tmp/steam-smoke-xvfb.log 2>&1 &
sleep 2
export DISPLAY=:99 XDG_RUNTIME_DIR=/run/user/0
unset LD_LIBRARY_PATH LD_PRELOAD QEMU_LD_PREFIX QEMU_SET_ENV
runtime=/usr/libexec/vinix-dota2/root
export VINIX_X86_64_ROOT="$runtime" VINIX_I386_ROOT="$runtime"
export VINIX_X86_MULTIARCH=1 VINIX_ALLOW_WX=1 QEMU_CPU=Haswell
export SteamAppId=570 SteamGameId=570 VALVE_TESTMODE=1
export LP_NUM_THREADS=2 MESA_SHADER_CACHE_DISABLE=true
export VK_ICD_FILENAMES="$runtime/usr/share/vulkan/icd.d/lvp_icd.x86_64.json"
export SSL_CERT_FILE="$runtime/etc/ssl/certs/ca-certificates.crt"
unset QEMU_STRACE
[ "$(cat /etc/steam-smoke-strace)" != 1 ] || export QEMU_STRACE=1
libraries="/home/dota2/.steam/sdk64:$runtime/usr/lib/x86_64-linux-gnu:$runtime/lib/x86_64-linux-gnu"
if [ "$(cat /etc/steam-smoke-game-priority)" = 1 ]; then
    libraries="/usr/libexec/vinix-dota2/smoke/game-bin:$runtime/usr/lib/x86_64-linux-gnu:$runtime/lib/x86_64-linux-gnu:/home/dota2/.steam/sdk64"
    ulimit -Sn 2048
    ulimit -Ss 2048
fi
preloads="$runtime/usr/lib/x86_64-linux-gnu/libvinix-steam-robust.so:$runtime/usr/lib/x86_64-linux-gnu/libvinix-dota2-mmap32.so:$runtime/usr/lib/x86_64-linux-gnu/libmpg123.so.0"
if [ "$(cat /etc/steam-smoke-pin-nm)" = 1 ]; then
    preloads="$preloads:$runtime/usr/lib/x86_64-linux-gnu/libnm.so.0"
fi
extra_preloads=$(cat /etc/steam-smoke-extra-preload)
[ -z "$extra_preloads" ] || preloads="$preloads:$extra_preloads"
export VINIX_X86_64_PRELOAD="$preloads"
mode=$(cat /etc/steam-smoke-mode)
if [ "$(cat /etc/steam-smoke-load-tier0)" = 1 ]; then
    set -- /usr/libexec/vinix-dota2/smoke/game-bin/libtier0.so
else
    set --
fi
debug=$(cat /etc/steam-smoke-ld-debug)
set -- /usr/bin/steam-smoke /usr/libexec/vinix-dota2/smoke/libsteam_api.so "$mode" "$@"
. /etc/steam-smoke-game-env.sh
status=0
/usr/bin/qemu-x86_64 -B 0x100000000 -L "$runtime" \
    -E "LD_LIBRARY_PATH=$libraries" -E "LD_PRELOAD=$preloads" -E "LD_DEBUG=$debug" \
    "$@" || status=$?
echo "VINIX-DOTA2-STEAM-SMOKE-EXIT: $status"
echo VINIX-DOTA2-STEAM-SMOKE-END
while :; do sleep 60; done
