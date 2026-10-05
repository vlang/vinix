#!/bin/sh
# Firefox bring-up inside a compositor-managed window, for --guest-init boots.
#
# tests/browsers/firefox-init.sh starts the browser the way the desktop starts
# it, but without the desktop: it runs the X11 bridge directly. That leaves the
# one arrangement users actually see — a browser inside a Vinix window, with
# the compositor hosting its surface — untested, which is exactly where it was
# found to be thirty times slower than the same browser on the same image.
#
# So start the real compositor, ask it to open the browser, and hold it to the
# same deadline as the unhosted launch.

export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export HOME=/root
export TERM=linux
export LD_LIBRARY_PATH=/usr/lib:/usr/lib/xorg/modules
export LIBGL_DRIVERS_PATH=/usr/lib/xorg/modules/dri:/usr/lib/dri
export XDG_RUNTIME_DIR=/run/user/0

fail() {
	echo "VINIX DESKTOP FIREFOX: FAIL $*"
	echo "VINIX DESKTOP FIREFOX TEST: FAIL"
	exit 1
}

echo
echo "VINIX DESKTOP FIREFOX TEST: START"

[ -x /usr/bin/vinix-desktop ] || fail "no /usr/bin/vinix-desktop"
[ -x /usr/bin/run-firefox ] || fail "no /usr/bin/run-firefox"
[ -x /usr/bin/vinix-wine-host ] || fail "no /usr/bin/vinix-wine-host"

mkdir -p /tmp /run/user/0 /dev/shm /var/log /tmp/.X11-unix /var/lib/xkb
chmod 1777 /tmp /dev/shm /tmp/.X11-unix

if [ -x /usr/share/vinix/x-window-check.py ]; then
	x_window_check=/usr/share/vinix/x-window-check.py
else
	x_window_check=/root/x-window-check.py
fi

/usr/bin/vinix-desktop --open=Firefox &
desktop_pid=$!
echo "VINIX DESKTOP FIREFOX: compositor started"

# The compositor names each hosted display after the process that asked for it
# and then takes the first free number from there, so the display to check is
# whichever socket its X server created.
display=""
surface=""
i=0
while [ "$i" -lt 120 ]; do
	for candidate in /tmp/vinix-firefox-*; do
		[ -e "$candidate/Xvfb_screen0" ] || continue
		surface="$candidate"
	done
	for socket in /tmp/.X11-unix/X*; do
		[ -S "$socket" ] || continue
		display=":${socket#/tmp/.X11-unix/X}"
	done
	if [ -n "$surface" ] && [ -n "$display" ]; then
		break
	fi
	sleep 1
	i=$((i + 1))
done

[ -n "$surface" ] || fail "the compositor published no hosted framebuffer in ${i}s"
[ -n "$display" ] || fail "the compositor's X server took no display in ${i}s"
echo "VINIX DESKTOP FIREFOX PASS: the hosted display has a framebuffer"
echo "VINIX DESKTOP FIREFOX: browser starting on $display, surface $surface"

# The same deadline the unhosted launch is held to, with room for the
# compositor's own start-up. A browser that is merely slow here is the defect
# this test exists for, so a generous deadline still fails a starved one.
mapped=false
j=0
while [ "$j" -lt 300 ]; do
	if ! kill -0 "$desktop_pid" 2>/dev/null; then
		fail "the compositor exited after ${j}s"
	fi
	if /usr/bin/python3 "$x_window_check" "$display" 'Firefox' 2>/dev/null; then
		mapped=true
		break
	fi
	sleep 1
	j=$((j + 1))
done

if [ "$mapped" = true ]; then
	echo "VINIX DESKTOP FIREFOX PASS: browser window mapped after ${j}s"
fi

# A mapped window is not a browser anyone can use: Firefox maps its toplevel
# long before it has drawn anything into it. What a user waits for is the page,
# so measure that — the surface the compositor shows holding more than a flat
# colour.
painted=false
k=0
while [ "$k" -lt 300 ]; do
	sample=$(/usr/bin/python3 -c '
import mmap, os, sys
# Look at the surface the way the compositor does — through a shared mapping.
# Reading the file instead did not reflect what the compositor was showing.
# Sampling rather than scanning keeps this cheap enough to run once a second
# beside the browser it is watching.
#
# The size is reported with the count so that a check which silently sampled
# the wrong span cannot pass for the wrong reason.
f = open(sys.argv[1], "rb")
size = os.fstat(f.fileno()).st_size
view = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
seen = set()
for i in range(1000):
    at = 4096 + (size - 8192) * i // 1000
    block = view[at:at + 64]
    for offset in range(0, len(block) - 3, 4):
        seen.add(block[offset:offset + 3])
print(size, len(seen))' "$surface/Xvfb_screen0" 2>/dev/null)
	set -- $sample
	surface_bytes=${1:-0}
	colours=${2:-0}
	if [ "$colours" -gt 8 ]; then
		painted=true
		break
	fi
	sleep 1
	k=$((k + 1))
done

echo "--- hosted application log ---"
tail -40 "${surface}.log" 2>/dev/null
echo "--- end hosted application log ---"

if [ "$mapped" != true ]; then
	fail "no browser window inside the desktop within ${j}s"
fi
if [ "$painted" != true ]; then
	fail "the browser window stayed blank for ${k}s after it was mapped"
fi
# A 1280x900 surface is 4.6 MB. Anything much smaller means the check sampled
# something that is not the framebuffer, and its verdict means nothing.
if [ "$surface_bytes" -lt 4000000 ]; then
	fail "the surface is only ${surface_bytes} bytes, so nothing was really checked"
fi
echo "VINIX DESKTOP FIREFOX PASS: the page was drawn ${k}s after the window appeared (${surface_bytes} bytes, ${colours} colours)"
echo "VINIX DESKTOP FIREFOX TEST: PASS"
