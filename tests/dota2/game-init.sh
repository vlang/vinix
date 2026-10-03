#!/bin/sh
# Test-only PID 1. Real game output goes to serial; screenshots come from QMP.
set -eu
trap 'echo VINIX-DOTA2-PROBE-FAIL' 0
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
export HOME=/home/dota2
export USER=root LOGNAME=root SHELL=/bin/sh TERM=linux
export LD_LIBRARY_PATH=/usr/lib:/usr/lib/xorg/modules
mkdir -p /tmp/.X11-unix /run/user/0 /home/dota2 /usr/share/games/dota2
chmod 1777 /tmp /tmp/.X11-unix
echo VINIX-DOTA2-PROBE-START
uname -a
runtime=/usr/libexec/vinix-dota2/root
export VINIX_ALLOW_WX=1
QEMU_CPU=Haswell /usr/bin/qemu-x86_64 -B 0x100000000 -L "$runtime" \
    -E "LD_LIBRARY_PATH=$runtime/lib/x86_64-linux-gnu" \
    -E "LD_PRELOAD=$runtime/usr/lib/x86_64-linux-gnu/libvinix-dota2-mmap32.so" \
    /usr/libexec/vinix-dota2/mmap32-probe

# The kernel automatically mounts the game's NBD volume at /root. Move that
# read-only mount to the game path, exposing the desktop's writable RAM home.
# No game bytes are copied, and the stock desktop can keep its profile there.
mount -t qemu-persist -o remount,ro /root /root
mount --move /root /usr/share/games/dota2
[ -s /usr/share/games/dota2/game/dota/pak01_dir.vpk ]
echo VINIX-DOTA2-GAME-MOUNTED
report_memory() {
    echo VINIX-DOTA2-MEMINFO
    cat /proc/meminfo || :
}
report_memory
mkdir -p /root /root/vm /root/.config
printf '%s\n' 'version=1' 'name=564d' 'kdf=scrypt' 'n=16384' 'r=8' 'p=1' \
    'salt=00000000000000000000000000000000' \
    'hash=0000000000000000000000000000000000000000000000000000000000000000' \
    > /root/.vinix-user
chmod 600 /root/.vinix-user

/usr/bin/vinix-desktop --open='Dota 2' --stats </dev/console &
desktop_pid=$!
echo VINIX-DOTA2-DESKTOP-STARTED
log=
attempt=0
while [ -z "$log" ]; do
    sleep 1
    kill -0 "$desktop_pid" || exit 1
    for candidate in /tmp/vinix-dota2-*.log /run/vinix-hosted-x11/vinix-dota2-*.log; do
        [ ! -f "$candidate" ] || log=$candidate
    done
    attempt=$((attempt + 1))
    [ "$attempt" -lt 180 ] || exit 1
done
echo "VINIX-DOTA2-HOST-LOG: $log"
tail -f "$log" &
seen=0
memory_tick=0
while :; do
    sleep 5
    kill -0 "$desktop_pid" || exit 1
    memory_tick=$((memory_tick + 1))
    if [ "$memory_tick" -ge 6 ]; then
        report_memory
        memory_tick=0
    fi
    if [ -s /run/dota2-game.pid ]; then
        game_pid=$(cat /run/dota2-game.pid)
        if kill -0 "$game_pid"; then
            seen=1
            echo VINIX-DOTA2-GAME-ALIVE
        elif [ "$seen" = 1 ]; then
            echo VINIX-DOTA2-GAME-GONE
            exit 1
        fi
    fi
done
