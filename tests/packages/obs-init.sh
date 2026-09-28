#!/bin/sh
# Boot with --guest-init to verify the packaged OBS GUI and its capture screen.
set -eu

export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export HOME=/root
export TERM=linux
export LD_LIBRARY_PATH=/usr/lib:/usr/lib/xorg/modules
export LIBGL_DRIVERS_PATH=/usr/lib/xorg/modules/dri:/usr/lib/dri
export SSL_CA_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
# This boot is disposable; avoid uploading OBS's large package closure.
export VINIX_PKG_STORE_FILE=/tmp/vinix-obs-no-package-store

fail() {
	echo "VINIX OBS TEST: FAIL $*"
	[ ! -d /tmp/vinix-obs-test ] || ls -la /tmp/vinix-obs-test
	[ ! -e /run/vinix-obs-screen ] || ls -l /run/vinix-obs-screen
	ps -ef | grep -E 'obs|Xvfb' || true
	/usr/bin/python3 /usr/share/vinix/x-window-check.py :99 '' 2>/dev/null || true
	if [ -d /root/.config/obs-studio/logs ]; then
		for log in /root/.config/obs-studio/logs/*; do
			[ ! -f "$log" ] || tail -40 "$log"
		done
	fi
	[ ! -f /tmp/obs-host.log ] || tail -40 /tmp/obs-host.log
	exit 1
}

echo "VINIX OBS TEST: START"
[ -x /usr/bin/run-obs ] || fail "OBS launcher missing"
[ -r /usr/lib/vinix-obs-compat.so ] || fail "OBS compatibility library missing"
[ -x /usr/bin/vinix-wine-host ] || fail "X11 host missing"
mkdir -p /tmp /dev/shm /run/user/0 /tmp/.X11-unix /var/lib/xkb
chmod 1777 /tmp /dev/shm /tmp/.X11-unix

pkg install obs-studio || fail "package install failed"
[ -x /usr/bin/obs ] || fail "OBS executable missing"
[ -x /usr/bin/obs-ffmpeg-mux ] || fail "OBS muxer missing"

sleep 3600 | /usr/bin/vinix-wine-host :99 /tmp/vinix-obs-test 1280x900x24 \
	/usr/bin/run-obs --obs >/tmp/obs-host.log 2>&1 &
host_pid=$!
trap 'kill "$host_pid" 2>/dev/null || true' EXIT INT TERM

i=0
while [ "$i" -lt 180 ]; do
	if ! kill -0 "$host_pid" 2>/dev/null; then
		fail "OBS host exited before opening a window"
	fi
	if [ -e /tmp/vinix-obs-test/Xvfb_screen0 ] \
		&& [ -e /tmp/vinix-obs-test/Xvfb_screen1 ] \
		&& [ -e /run/vinix-obs-screen ] \
		&& /usr/bin/python3 /usr/share/vinix/x-window-check.py :99 'OBS' 2>/dev/null; then
		break
	fi
	sleep 1
	i=$((i + 1))
done
[ "$i" -lt 180 ] || fail "OBS did not map its window and capture screen"
sleep 5
kill -0 "$host_pid" 2>/dev/null || fail "OBS exited after mapping its window"
/usr/bin/python3 /usr/share/vinix/x-window-check.py :99 'OBS' 2>/dev/null \
	|| fail "OBS window did not stay mapped"
grep -q 'Switched to scene' /root/.config/obs-studio/logs/* \
	|| fail "OBS did not finish loading its default scene"

/usr/bin/python3 - <<'PY' || fail "X11 capture screen or MIT-SHM unavailable"
import ctypes
import mmap
import struct

class XImage(ctypes.Structure):
    _fields_ = [('width', ctypes.c_int), ('height', ctypes.c_int),
                ('xoffset', ctypes.c_int), ('format', ctypes.c_int),
                ('data', ctypes.c_void_p)]

xlib = ctypes.CDLL('libX11.so.6')
xlib.XOpenDisplay.argtypes = [ctypes.c_char_p]
xlib.XOpenDisplay.restype = ctypes.c_void_p
xlib.XScreenCount.argtypes = [ctypes.c_void_p]
xlib.XScreenCount.restype = ctypes.c_int
xlib.XQueryExtension.argtypes = [ctypes.c_void_p, ctypes.c_char_p,
                                 ctypes.POINTER(ctypes.c_int),
                                 ctypes.POINTER(ctypes.c_int),
                                 ctypes.POINTER(ctypes.c_int)]
xlib.XQueryExtension.restype = ctypes.c_int
xlib.XRootWindow.argtypes = [ctypes.c_void_p, ctypes.c_int]
xlib.XRootWindow.restype = ctypes.c_ulong
xlib.XGetImage.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int,
                           ctypes.c_int, ctypes.c_uint, ctypes.c_uint,
                           ctypes.c_ulong, ctypes.c_int]
xlib.XGetImage.restype = ctypes.POINTER(XImage)
xlib.XCloseDisplay.argtypes = [ctypes.c_void_p]
display = xlib.XOpenDisplay(b':99')
if not display:
    raise SystemExit('cannot open OBS X11 display')
try:
    if xlib.XScreenCount(display) != 2:
        raise SystemExit('OBS display does not have two screens')
    major = ctypes.c_int()
    first_event = ctypes.c_int()
    first_error = ctypes.c_int()
    if not xlib.XQueryExtension(display, b'MIT-SHM',
                               ctypes.byref(major), ctypes.byref(first_event),
                               ctypes.byref(first_error)):
        raise SystemExit('MIT-SHM is unavailable to OBS')
    if xlib.XQueryExtension(display, b'RANDR',
                           ctypes.byref(major), ctypes.byref(first_event),
                           ctypes.byref(first_error)):
        raise SystemExit('RandR hides Display 1 from OBS XSHM capture')
    # The compositor writes this same XWD mapping. Confirm that a written
    # framebuffer pixel is visible through the X11 root OBS will capture.
    with open('/run/vinix-obs-screen', 'r+b') as file:
        framebuffer = mmap.mmap(file.fileno(), 0)
        header = struct.unpack_from('>I', framebuffer, 0)[0]
        colors = struct.unpack_from('>I', framebuffer, 76)[0]
        offset = header + colors * 12
        old = framebuffer[offset:offset + 4]
        marker = bytes((0x56, 0x34, 0x12, 0))
        try:
            framebuffer[offset:offset + 4] = marker
            root = xlib.XRootWindow(display, 1)
            image = xlib.XGetImage(display, root, 0, 0, 1, 1, 0xffffffff, 2)
            if not image or ctypes.string_at(image.contents.data, 4) != marker:
                raise SystemExit('compositor capture framebuffer is not visible on Display 1')
        finally:
            framebuffer[offset:offset + 4] = old
            framebuffer.close()
finally:
    xlib.XCloseDisplay(display)
PY

echo "VINIX OBS TEST: PASS"
