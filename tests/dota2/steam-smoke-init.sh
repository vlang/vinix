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
preloads="$runtime/usr/lib/x86_64-linux-gnu/libvinix-steam-robust.so:$runtime/usr/lib/x86_64-linux-gnu/libmpg123.so.0"
mode=$(cat /etc/steam-smoke-mode)
status=0
/usr/bin/qemu-x86_64 -B 0x100000000 -L "$runtime" \
    -E "LD_LIBRARY_PATH=$libraries" -E "LD_PRELOAD=$preloads" \
    /usr/bin/steam-smoke /usr/libexec/vinix-dota2/smoke/libsteam_api.so "$mode" || status=$?
echo "VINIX-DOTA2-STEAM-SMOKE-EXIT: $status"
echo VINIX-DOTA2-STEAM-SMOKE-END
while :; do sleep 60; done
