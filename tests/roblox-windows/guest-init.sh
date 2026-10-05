#!/bin/sh
# Test-only PID 1: Roblox's Windows Player under Wine on a private Xvfb
# display, with what it and Wine report on the serial console.
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export HOME=/root USER=root LOGNAME=root SHELL=/bin/sh TERM=linux
export LD_LIBRARY_PATH=/usr/lib:/usr/lib/xorg/modules
export LIBGL_DRIVERS_PATH=/usr/lib/xorg/modules/dri:/usr/lib/dri
. /opt/roblox-test/config.sh

mkdir -p /tmp/.X11-unix /run/user/0 /dev/shm /var/log /var/lib/xkb
chmod 1777 /tmp /tmp/.X11-unix /dev/shm
[ -s /etc/resolv.conf ] || echo 'nameserver 10.0.2.3' > /etc/resolv.conf

echo ROBLOX-WINDOWS-START
uname -a
if [ "$TEST_SHELL" = 1 ]; then
    exec /bin/sh </dev/console >/dev/console 2>&1
fi

# The ground the client stands on: the translator, Wine and a Win64 process.
if ! WINEDEBUG=-all /usr/bin/wine64 /usr/share/wine/vinix-wine-smoke.exe; then
    echo "ROBLOX-WINDOWS-FAIL Wine cannot run its Win64 smoke test"
    exec /bin/sh </dev/console >/dev/console 2>&1
fi
WINEDEBUG=-all /usr/bin/wineserver -w
echo ROBLOX-WINDOWS-WINE-READY

cat > /opt/roblox-test/launch <<'EOF'
#!/bin/sh
. /opt/roblox-test/config.sh
if [ "$TEST_STRACE" = 1 ]; then
    # The translator names each system call it cannot translate. Keep those
    # and nothing else: the client's own calls would bury them. The client
    # is stopped once enough have been seen to say what it is doing.
    # shellcheck disable=SC2086
    QEMU_STRACE=1 WINEDEBUG=-all /usr/bin/wine64 "$TEST_EXECUTABLE" $TEST_ARGUMENTS 2>&1 |
        grep -m 200 -o 'Unknown syscall -\{0,1\}[0-9]*' >/tmp/roblox-wine.log
    echo strace > /tmp/roblox-status
else
    export WINEDEBUG="$TEST_WINEDEBUG"
    # shellcheck disable=SC2086
    /usr/bin/wine64 "$TEST_EXECUTABLE" $TEST_ARGUMENTS >/tmp/roblox-wine.log 2>&1
    echo "$?" > /tmp/roblox-status
fi
# The client hands over to other processes of the same Wine server.
WINEDEBUG=-all /usr/bin/wineserver -w
EOF
chmod 755 /opt/roblox-test/launch
: > /tmp/roblox-wine.log
# A traced client can write a line per exception; the console gets the start.
tail -f /tmp/roblox-wine.log | head -n 200 &

# The host treats the end of its input as a request to stop.
sleep 100000 | /usr/bin/vinix-wine-host :77 /tmp/roblox-fb "$TEST_GEOMETRY" \
    /opt/roblox-test/launch --game-input >/tmp/roblox-host.log 2>&1 &

upload() {
    wget -q -O /dev/null --post-file="$1" "$TEST_UPLOAD/$2" 2>/dev/null
}

elapsed=0
frame=0
while [ "$elapsed" -lt "$TEST_SECONDS" ]; do
    sleep 15
    elapsed=$((elapsed + 15))
    echo "ROBLOX-WINDOWS-TICK $elapsed"
    if ps | grep -q '[R]obloxPlayerBet'; then
        echo ROBLOX-WINDOWS-ALIVE
    fi
    if [ -f /tmp/roblox-fb/Xvfb_screen0 ] && [ $((elapsed % 60)) -eq 0 ]; then
        frame=$((frame + 1))
        upload /tmp/roblox-fb/Xvfb_screen0 "frame-$frame.xwd"
    fi
    if [ -f /tmp/roblox-status ]; then
        echo "ROBLOX-WINDOWS-EXITED status=$(cat /tmp/roblox-status)"
        break
    fi
done

echo ROBLOX-WINDOWS-PROCESSES
ps
echo ROBLOX-WINDOWS-HOST-LOG
cat /tmp/roblox-host.log
# Roblox writes its own account of a start below the user's local data.
number=0
for log in /root/.wine-x86_64/drive_c/users/*/AppData/Local/Roblox/logs/*; do
    [ -f "$log" ] || continue
    number=$((number + 1))
    echo "ROBLOX-WINDOWS-CLIENT-LOG $log"
    tail -n 60 "$log"
    upload "$log" "client-$number.log"
done
[ -f /tmp/roblox-fb/Xvfb_screen0 ] && upload /tmp/roblox-fb/Xvfb_screen0 frame-final.xwd
tail -c 1000000 /tmp/roblox-wine.log > /tmp/roblox-wine-tail.log
upload /tmp/roblox-wine-tail.log wine.log
echo ROBLOX-WINDOWS-DONE
while :; do sleep 30; done
