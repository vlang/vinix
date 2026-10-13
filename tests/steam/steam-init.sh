#!/bin/sh
# Steam bring-up init for --guest-init boots.
#
# It runs as PID 1 in place of the desktop so the launch can be driven and
# reported on the serial console. First the ground Steam stands on: both
# translators running glibc programs from the staged Debian root. Then the
# client itself, started the way the desktop starts it, through the X11
# bridge on a private Xvfb display, held through the first client window. The
# updater can detach from steam.sh while it downloads the current client, so
# the hosted command keeps the display alive after steam.sh returns.

export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export HOME=/root
export TERM=linux
export LD_LIBRARY_PATH=/usr/lib:/usr/lib/xorg/modules
export LIBGL_DRIVERS_PATH=/usr/lib/xorg/modules/dri:/usr/lib/dri
export XDG_RUNTIME_DIR=/run/user/0
export SSL_CA_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

fail() {
	echo "VINIX STEAM: FAIL $*"
	echo "VINIX STEAM TEST: FAIL"
	exit 1
}

echo
echo "VINIX STEAM TEST: START"

[ -x /usr/bin/steam ] || fail "no /usr/bin/steam"
[ -x /usr/bin/steam-smoke ] || fail "no /usr/bin/steam-smoke"
[ -x /usr/bin/vinix-wine-host ] || fail "no /usr/bin/vinix-wine-host"
[ -x /usr/bin/qemu-i386 ] || fail "no /usr/bin/qemu-i386"

mkdir -p /tmp /run /dev/shm /var/log /var/lib/xkb
# A disk-root test keeps its large client on ext2. Clear runtime sockets and
# PID files at each boot, and give Xvfb temporary socket and framebuffer space.
if [ -f /.vinix-image-id ]; then
	mount -t tmpfs tmpfs /run || fail "could not mount temporary runtime storage"
	mount -t tmpfs tmpfs /tmp || fail "could not mount temporary X11 storage"
fi
mkdir -p /run/user/0
mkdir -p /tmp/.X11-unix
chmod 1777 /tmp /dev/shm /tmp/.X11-unix

# The client's update goes through Valve's CDN, so give the guest a resolver
# for QEMU's user network before it asks.
if [ ! -s /etc/resolv.conf ]; then
	echo "nameserver 10.0.2.3" > /etc/resolv.conf
fi

/usr/bin/steam-smoke 2>&1 | tee /tmp/steam-smoke.log
grep -q '^VINIX STEAM SMOKE TEST: PASS$' /tmp/steam-smoke.log ||
	fail "the runtime smoke test failed"
echo "VINIX STEAM PASS: translated glibc runtime"

# Steam's thread synchronisation uses System V semaphores. Check the value
# operations and a real cross-process wake before waiting for its updater.
/usr/bin/steam-syscall-probe semaphores || fail "System V semaphore operations failed"
echo "VINIX STEAM PASS: System V semaphore wake"

# Chromium uses eventfd for its completion ports, and the client reads large
# files into pages that have not been faulted in yet. Exercise both syscall
# paths before the long client startup so an EFAULT regression fails promptly.
/usr/bin/steam-syscall-probe lazy-buffer || fail "eventfd or file buffer copy failed"
echo "VINIX STEAM PASS: eventfd and lazy file buffer"

# A closed Chromium IPC peer leaves EPOLLHUP ready. recvmsg must drain its
# buffered bytes and then return EOF, or the browser loops on EAGAIN forever.
/usr/bin/steam-syscall-probe unix-hangup || fail "Unix recvmsg hangup failed"
echo "VINIX STEAM PASS: Unix recvmsg hangup"

# QEMU translates IPv4 recvmsg control messages. Return the actual ancillary
# length (zero here) so it never interprets the caller's spare buffer as data.
/bin/busybox timeout 5 /usr/bin/steam-syscall-probe ipv4-ancillary || fail "IPv4 recvmsg ancillary length failed"
echo "VINIX STEAM PASS: IPv4 recvmsg ancillary length"

# A browser thread may use an empty ppoll as a timed sleep. Returning at once
# makes its event loop spin and can starve the translated client.
/bin/busybox timeout 5 /usr/bin/steam-syscall-probe ppoll || fail "empty ppoll sleep failed"
echo "VINIX STEAM PASS: empty ppoll sleeps"

# Chromium creates shared-memory segments above 16 MiB. They must live on
# tmpfs: devtmpfs regular files grow as one contiguous allocation and can
# stall when its heap cannot extend one to the requested size.
/usr/bin/steam-syscall-probe shared-mapping || fail "large shared-memory file failed"
echo "VINIX STEAM PASS: large shared-memory mapping"

# A persistent /root can shadow the copy the image ships there.
if [ -x /usr/share/vinix/x-window-check ]; then
	x_window_check=/usr/share/vinix/x-window-check
else
	x_window_check=/root/x-window-check
fi

display=:99
surface=/tmp/vinix-steam
steam_log=/tmp/steam.log
# The bridge treats end of file on stdin as "the window closed", so its input
# pipe has to stay open for as long as the test runs. The disk image already
# contains an installed client; skip its full checksum and updater passes so
# this boot measures UI startup within the VM timeout.
cat > /tmp/steam-test-fast <<'STEAM_TEST_FAST'
#!/bin/sh
# This VM has no udev joystick service. Avoid SDL's repeated HIDAPI scan while
# the web UI initializes.
export SDL_JOYSTICK_HIDAPI=0
export SDL_JOYSTICK_DISABLE_UDEV=1
exec /usr/bin/steam-hosted -noverifyfiles -nobootstrapperupdate
STEAM_TEST_FAST
chmod 0755 /tmp/steam-test-fast
sleep 3600 | /usr/bin/vinix-wine-host "$display" "$surface" 1280x900x24 \
	/tmp/steam-test-fast >"$steam_log" 2>&1 &
host_pid=$!

echo "VINIX STEAM: launching the client through the desktop's X11 bridge"

# Keep one X11 connection open while waiting. Reopening the GLX display for
# every check makes its server retain memory on each client disconnect.
window_log=/tmp/steam-window-check.log
"$x_window_check" "$display" 'Steam' 1800 >"$window_log" 2>&1 &
window_watch_pid=$!

surfaced=false
mapped=false
exited=false
i=0
started="$(date +%s)"
# The updater downloads the current client before it opens a window.
while [ "$i" -lt 1800 ]; do
	if ! kill -0 "$host_pid" 2>/dev/null; then
		exited=true
		break
	fi
	if grep -Eq 'Fatal [Ee]rror:|Fatal assert; application exiting|Could not load module|Failed to load steamui\.so|qemu: uncaught target signal' "$steam_log" 2>/dev/null; then
		tail -30 "$steam_log"
		fail "the client reported a fatal startup error"
	fi
	if [ "$surfaced" != true ] && [ -e "$surface/Xvfb_screen0" ]; then
		surfaced=true
		echo "VINIX STEAM PASS: the hosted display has a framebuffer"
	fi
	if grep -q '^WINDOW=' "$window_log" 2>/dev/null; then
		mapped=true
		break
	fi
	if ! kill -0 "$window_watch_pid" 2>/dev/null; then
		# Xlib's default handler exits if a window disappears halfway through
		# the tree walk. Reopen the display for this rare race rather than
		# treating a watcher failure as a client failure.
		"$x_window_check" "$display" 'Steam' 1800 >>"$window_log" 2>&1 &
		window_watch_pid=$!
	fi
	sleep 1
	i=$(( $(date +%s) - started ))
done

kill "$window_watch_pid" 2>/dev/null || true
wait "$window_watch_pid" 2>/dev/null || true

echo "--- steam log ---"
grep -v "ELF auxval" "$steam_log" 2>/dev/null | tail -60
echo "--- end steam log ---"

if [ "$mapped" = true ]; then
	if grep -Eq 'Fatal [Ee]rror:|Fatal assert; application exiting|Could not load module|Failed to load steamui\.so|qemu: uncaught target signal' "$steam_log" 2>/dev/null; then
		fail "the mapped window is a client startup error"
	fi
	echo "VINIX STEAM PASS: client window mapped after ${i}s"
	echo "VINIX STEAM TEST: PASS"
elif [ "$exited" = true ]; then
	fail "the client exited after ${i}s without showing a window"
else
	fail "no Steam window appeared within ${i}s"
fi
