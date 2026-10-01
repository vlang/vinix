#!/bin/sh
# Same workload and software-rendering stack on Vinix and Debian's kernel.
set -eu
trap 'echo DHEWM3-FAILED' 0
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
export HOME=/home/doom
export LD_LIBRARY_PATH=/usr/lib/dhewm3:/usr/lib:/usr/lib/xorg/modules
export DISPLAY=:99
export SDL_VIDEODRIVER=x11
export LIBGL_ALWAYS_SOFTWARE=1
export LIBGL_DRIVERS_PATH=/usr/lib/xorg/modules/dri
export GALLIUM_DRIVER=llvmpipe
export LP_NUM_THREADS=4
export MESA_GLTHREAD=false
export XDG_RUNTIME_DIR=/run/user/0
MODE=benchmark
ROUNDS=3
CHECK_CLOCK=0
. /opt/dhewm3/config

if [ "$(uname -s)" = Linux ]; then
    mount -t proc proc /proc
    mount -t sysfs sysfs /sys
    mount -t devtmpfs devtmpfs /dev
fi
mkdir -p /tmp/.X11-unix /tmp/dhewm3 /dev/shm /run/user/0 "$HOME"
chown 1000:1000 "$HOME"
chmod 1777 /tmp /tmp/.X11-unix /dev/shm
echo "DHEWM3-START mode=$MODE"
uname -a
cat /etc/os-release 2>/dev/null || true
cat /proc/cpuinfo 2>/dev/null || true
if [ "$CHECK_CLOCK" = 1 ]; then
    /opt/dhewm3/clock-probe --check
else
    /opt/dhewm3/clock-probe
fi
if [ "$MODE" = clock ]; then
    echo DHEWM3-DONE
    exec /bin/sh </dev/console >/dev/console 2>&1
fi
Xvfb-glx :99 -screen 0 640x480x24 -fbdir /tmp/dhewm3 -nolisten tcp \
    -ac -noreset +extension GLX +iglx -extension MIT-SHM >/tmp/xvfb.log 2>&1 &
xpid=$!
sleep 3
glxinfo -B >/tmp/glxinfo.log 2>&1 || { cat /tmp/glxinfo.log /tmp/xvfb.log; exit 1; }
cat /tmp/glxinfo.log
cat /tmp/xvfb.log
grep -q 'OpenGL renderer string: llvmpipe' /tmp/glxinfo.log
if [ "$MODE" = record ]; then
    /opt/dhewm3/as-user run-dhewm3 +set s_noSound 1 +set com_showFPS 1 \
        +map game/demo_mars_city2 +wait 120 +recordDemo vinix-demo \
        +wait 4000 +stopRecording +quit >/tmp/game.log 2>&1 &
    gamepid=$!
    sleep 10
    echo DHEWM3-SHOT-BEGIN
    base64 /tmp/dhewm3/Xvfb_screen0
    echo DHEWM3-SHOT-END
    status=0
    wait "$gamepid" || status=$?
    cat /tmp/game.log
    [ "$status" -eq 0 ]
    echo DHEWM3-DEMO-BEGIN
    base64 "$HOME/.local/share/dhewm3/demo/demos/vinix-demo.demo"
    echo DHEWM3-DEMO-END
elif [ "$MODE" = screenshot ]; then
    /opt/dhewm3/as-user run-dhewm3 +set s_noSound 1 +playDemo vinix-demo \
        +wait 10000 +quit >/tmp/game.log 2>&1 &
    gamepid=$!
    sleep 3
    echo DHEWM3-SHOT-BEGIN
    base64 /tmp/dhewm3/Xvfb_screen0
    echo DHEWM3-SHOT-END
    kill "$gamepid"
    cat /tmp/game.log
else
    round=0
    while [ "$round" -le "$ROUNDS" ]; do
        echo "DHEWM3-RUN round=$round"
        /opt/dhewm3/as-user run-dhewm3 +set s_noSound 1 +timeDemoQuit vinix-demo
        round=$((round + 1))
    done
fi
kill "$xpid"
echo DHEWM3-DONE
exec /bin/sh </dev/console >/dev/console 2>&1
