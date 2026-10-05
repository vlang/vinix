#!/bin/sh
# LibreOffice bring-up init for --guest-init boots.
#
# It runs as PID 1 in place of the desktop so an office launch can be driven and
# reported on the serial console. Writer is started exactly as the desktop
# starts it: through the X11 bridge, on a private Xvfb display.
#
# A word processor is a harder first window than a browser. Before VCL draws
# anything it builds a UNO service manager out of several hundred shared
# objects, reads its configuration registry, and asks fontconfig for the whole
# font list — so this test separates "the suite started" from "the document is
# on the screen" and reports how long each took.

export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export HOME=/root
export TERM=linux
export LD_LIBRARY_PATH=/usr/lib:/usr/lib/xorg/modules
export LIBGL_DRIVERS_PATH=/usr/lib/xorg/modules/dri:/usr/lib/dri
export XDG_RUNTIME_DIR=/run/user/0

fail() {
	echo "VINIX LIBREOFFICE: FAIL $*"
	echo "VINIX LIBREOFFICE TEST: FAIL"
	exit 1
}

echo
echo "VINIX LIBREOFFICE TEST: START"

[ -x /usr/bin/run-libreoffice ] || fail "no /usr/bin/run-libreoffice"
[ -x /usr/bin/vinix-wine-host ] || fail "no /usr/bin/vinix-wine-host"
[ -x /usr/lib/libreoffice/program/soffice.bin ] \
	|| fail "no LibreOffice program directory"
[ -e /usr/lib/libreoffice/program/libvclplug_gtk3lo.so ] \
	|| fail "no GTK 3 VCL plugin"

mkdir -p /tmp /run/user/0 /dev/shm /var/log /tmp/.X11-unix /var/lib/xkb
chmod 1777 /tmp /dev/shm /tmp/.X11-unix

# A persistent /root can shadow the copy the image ships there.
if [ -x /usr/share/vinix/x-window-check.py ]; then
	x_window_check=/usr/share/vinix/x-window-check.py
else
	x_window_check=/root/x-window-check.py
fi

# VCL's own log stream. Without it a refusal to build the user interface is
# silent: the suite exits, and the only thing on the console is whatever GTK
# happened to warn about first.
export SAL_LOG="${SAL_LOG:-+WARN}"

display=:99
surface=/tmp/vinix-libreoffice
# The bridge treats end of file on stdin as "the window closed", so its input
# pipe has to stay open for as long as the test runs.
sleep 3600 | /usr/bin/vinix-wine-host "$display" "$surface" 1280x900x24 \
	/usr/bin/run-libreoffice >/tmp/libreoffice.log 2>&1 &
host_pid=$!

echo "VINIX LIBREOFFICE: launching Writer through the desktop's X11 bridge"

surfaced=false
mapped=false
exited=false
i=0
while [ "$i" -lt 600 ]; do
	if ! kill -0 "$host_pid" 2>/dev/null; then
		exited=true
		break
	fi
	if [ "$surfaced" != true ] && [ -e "$surface/Xvfb_screen0" ]; then
		surfaced=true
		echo "VINIX LIBREOFFICE PASS: the hosted display has a framebuffer"
	fi
	if /usr/bin/python3 "$x_window_check" "$display" 'LibreOffice Writer' 2>/dev/null; then
		mapped=true
		break
	fi
	sleep 1
	i=$((i + 1))
done

echo "--- libreoffice log ---"
grep -v "ELF auxval" /tmp/libreoffice.log 2>/dev/null | tail -40
echo "--- end libreoffice log ---"

if [ "$mapped" != true ]; then
	if [ "$exited" = true ]; then
		fail "LibreOffice exited after ${i}s without showing a window"
	fi
	fail "no Writer window appeared within ${i}s"
fi

echo "VINIX LIBREOFFICE PASS: Writer window mapped after ${i}s"

# A mapped window is not a document anyone can read: VCL maps its toplevel
# before it has laid the page out. Hold the launch to the pixels, and read them
# through a shared mapping — reading the surface file instead returns what is
# on the disk behind it, not what the X server drew.
painted=false
k=0
while [ "$k" -lt 300 ]; do
	colours=$(/usr/bin/python3 -c '
import mmap, sys
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
	fail "the Writer window stayed blank for ${k}s after it was mapped"
fi

echo "VINIX LIBREOFFICE PASS: the document was drawn ${k}s after the window appeared"
echo "VINIX LIBREOFFICE TEST: PASS"
