#!/bin/sh
# Firefox bring-up init for --guest-init boots.
#
# It runs as PID 1 in place of the desktop so a Firefox launch can be driven and
# reported on the serial console. The browser is started exactly as the desktop
# starts it: through the X11 bridge, on a private Xvfb display.

export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export HOME=/root
export TERM=linux
export LD_LIBRARY_PATH=/usr/lib:/usr/lib/xorg/modules
export LIBGL_DRIVERS_PATH=/usr/lib/xorg/modules/dri:/usr/lib/dri
export XDG_RUNTIME_DIR=/run/user/0
export SSL_CA_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

fail() {
	echo "VINIX FIREFOX: FAIL $*"
	echo "VINIX FIREFOX TEST: FAIL"
	exit 1
}

echo
echo "VINIX FIREFOX TEST: START"

[ -x /usr/bin/run-firefox ] || fail "no /usr/bin/run-firefox"
[ -x /usr/bin/vinix-wine-host ] || fail "no /usr/bin/vinix-wine-host"
if [ ! -x /usr/lib/firefox-esr/firefox-esr ] && [ ! -x /usr/lib/firefox/firefox ]; then
	fail "no Firefox application directory"
fi

mkdir -p /tmp /run/user/0 /dev/shm /var/log /tmp/.X11-unix /var/lib/xkb
chmod 1777 /tmp /dev/shm /tmp/.X11-unix

# A persistent /root can shadow the copy the image ships there.
if [ -x /usr/share/vinix/x-window-check.py ]; then
	x_window_check=/usr/share/vinix/x-window-check.py
else
	x_window_check=/root/x-window-check.py
fi

display=:99
surface=/tmp/vinix-firefox
# The bridge treats end of file on stdin as "the window closed", so its input
# pipe has to stay open for as long as the test runs.
sleep 3600 | /usr/bin/vinix-wine-host "$display" "$surface" 1280x900x24 \
	/usr/bin/run-firefox >/tmp/firefox.log 2>&1 &
host_pid=$!

echo "VINIX FIREFOX: launching the browser through the desktop's X11 bridge"

surfaced=false
mapped=false
exited=false
i=0
while [ "$i" -lt 300 ]; do
	if ! kill -0 "$host_pid" 2>/dev/null; then
		exited=true
		break
	fi
	if [ "$surfaced" != true ] && [ -e "$surface/Xvfb_screen0" ]; then
		surfaced=true
		echo "VINIX FIREFOX PASS: the hosted display has a framebuffer"
	fi
	if /usr/bin/python3 "$x_window_check" "$display" 'Mozilla Firefox' 2>/dev/null; then
		mapped=true
		break
	fi
	sleep 1
	i=$((i + 1))
done

echo "--- firefox log ---"
grep -v "ELF auxval" /tmp/firefox.log 2>/dev/null | tail -40
echo "--- end firefox log ---"

if [ "$mapped" = true ]; then
	echo "VINIX FIREFOX PASS: browser window mapped after ${i}s"
	# A mapped window is not a browser anyone can use: Firefox maps its
	# toplevel long before it draws into it. What a user waits for is the page,
	# so hold the launch to that — the framebuffer holding more than one flat
	# colour.
	painted=false
	k=0
	while [ "$k" -lt 240 ]; do
		colours=$(/usr/bin/python3 -c '
import mmap, sys
# Look at the surface the way the compositor does — through a shared mapping.
# Reading the file instead returns what is on the disk behind it, which is not
# what the X server has drawn. Sampling rather than scanning keeps this cheap
# enough to run once a second beside the browser it is watching.
f = open(sys.argv[1], "rb")
f.seek(0, 2)
size = f.tell()
view = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
seen = set()
for i in range(1000):
    at = 4096 + (size - 8192) * i // 1000
    block = view[at:at + 64]
    for offset in range(0, len(block) - 3, 4):
        seen.add(block[offset:offset + 3])
print(len(seen))' "$surface/Xvfb_screen0" 2>/dev/null)
		[ -n "$colours" ] || colours=0
		if [ "$colours" -gt 8 ]; then
			painted=true
			break
		fi
		sleep 1
		k=$((k + 1))
	done
	if [ "$painted" != true ]; then
		fail "the browser window stayed blank for ${k}s after it was mapped"
	fi
	echo "VINIX FIREFOX PASS: the page was drawn ${k}s after the window appeared"
	echo "VINIX FIREFOX TEST: PASS"
elif [ "$exited" = true ]; then
	fail "the browser exited after ${i}s without showing a window"
else
	fail "no Firefox window appeared within ${i}s"
fi
