#!/bin/sh
# Chromium bring-up init for --guest-init boots.
#
# It runs as PID 1 in place of the desktop so that a Chromium launch can be
# driven and reported on the serial console, without a compositor, a window
# manager or any human input in the way. The browser is started exactly as the
# desktop starts it: through the X11 bridge, on a private Xvfb display.

export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export HOME=/root
export TERM=linux
export LD_LIBRARY_PATH=/usr/lib:/usr/lib/xorg/modules
export LIBGL_DRIVERS_PATH=/usr/lib/xorg/modules/dri:/usr/lib/dri
export XDG_RUNTIME_DIR=/run/user/0
export SSL_CA_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

fail() {
	echo "VINIX CHROMIUM: FAIL $*"
	echo "VINIX CHROMIUM TEST: FAIL"
	exit 1
}

echo
echo "VINIX CHROMIUM TEST: START"

[ -x /usr/lib/chromium/chrome ] || fail "no /usr/lib/chromium/chrome"
[ -x /usr/bin/run-chromium ] || fail "no /usr/bin/run-chromium"
[ -x /usr/bin/vinix-wine-host ] || fail "no /usr/bin/vinix-wine-host"

mkdir -p /tmp /run/user/0 /dev/shm /var/log /tmp/.X11-unix /var/lib/xkb
chmod 1777 /tmp /dev/shm /tmp/.X11-unix

# The cheapest end-to-end check that Chromium's own executable loads, relocates
# and reaches main() under Vinix.
echo "VINIX CHROMIUM: version"
if /usr/lib/chromium/chrome --version >/tmp/version.txt 2>&1; then
	cat /tmp/version.txt
	echo "VINIX CHROMIUM PASS: version"
else
	cat /tmp/version.txt
	fail "chrome --version exited non-zero"
fi

# Headless is the same browser without the X11 and GTK layers, so a failure
# here separates Chromium's own multi-process startup from the display stack.
echo "VINIX CHROMIUM: headless"
/usr/lib/chromium/chrome --headless --no-sandbox --disable-gpu --no-zygote \
	--disable-dev-shm-usage --user-data-dir=/tmp/headless-profile \
	--dump-dom file:///usr/share/vinix/chromium-smoke.html \
	>/tmp/headless.html 2>/tmp/headless.log || true
if grep -q 'Chromium is running on Vinix' /tmp/headless.html 2>/dev/null; then
	echo "VINIX CHROMIUM PASS: headless rendered the page"
else
	echo "--- headless log ---"
	tail -60 /tmp/headless.log 2>/dev/null
	echo "--- end headless log ---"
	echo "VINIX CHROMIUM: headless did not render"
fi

# The desktop hosts every X11 application through this bridge: it owns the
# private Xvfb display, publishes its framebuffer as an XWD file for the
# compositor to map, and forwards pointer and keyboard events back. Driving the
# browser the same way is the difference between testing what ships and testing
# a display this file invented.
display=:99
surface=/tmp/vinix-chromium
# The bridge treats end of file on stdin as "the window closed", so its input
# pipe has to stay open for as long as the test runs.
sleep 3600 | /usr/bin/vinix-wine-host "$display" "$surface" 1280x900x24 \
	/usr/bin/run-chromium >/tmp/chromium.log 2>&1 &
host_pid=$!

echo "VINIX CHROMIUM: launching the browser through the desktop's X11 bridge"

surfaced=false
mapped=false
exited=false
i=0
# A first launch builds the font and profile caches on a guest with one CPU.
while [ "$i" -lt 300 ]; do
	if ! kill -0 "$host_pid" 2>/dev/null; then
		exited=true
		break
	fi
	if [ "$surfaced" != true ] && [ -e "$surface/Xvfb_screen0" ]; then
		surfaced=true
		echo "VINIX CHROMIUM PASS: the hosted display has a framebuffer"
	fi
	if /usr/bin/python3 /root/x-window-check.py "$display" 'Chromium' 2>/dev/null; then
		mapped=true
		break
	fi
	sleep 1
	i=$((i + 1))
done

echo "--- chromium log ---"
tail -80 /tmp/chromium.log 2>/dev/null
echo "--- end chromium log ---"

if [ "$mapped" = true ]; then
	echo "VINIX CHROMIUM PASS: browser window mapped"
	echo "VINIX CHROMIUM TEST: PASS"
elif [ "$exited" = true ]; then
	fail "the browser exited after ${i}s without showing a window"
else
	fail "no Chromium window appeared within ${i}s"
fi
