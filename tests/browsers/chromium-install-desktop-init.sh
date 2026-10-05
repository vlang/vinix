#!/bin/sh
# Diagnostic boot used to verify a repository-installed Chromium in the real
# desktop without carrying the large package overlay through another boot.
set -eu

export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export HOME=/root
export TERM=linux
export LD_LIBRARY_PATH=/usr/lib:/usr/lib/xorg/modules
export SSL_CA_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

mkdir -p /tmp /dev/shm
chmod 1777 /tmp /dev/shm

install_chromium() {
	# Let the desktop and its hosted X server load the image's GTK stack first.
	# Installing Chromium then mirrors the user-facing workflow: the package
	# replaces those files on disk, while the already-running desktop keeps its
	# mapped libraries and Chromium starts with its coherent Alpine closure.
	sleep 60
	echo "VINIX CHROMIUM SCREENSHOT: installing Chromium"
	desktop_pid=$(/bin/busybox pidof vinix-desktop || true)
	/bin/busybox killall vinix-files 2>/dev/null || true
	/bin/busybox killall vinix-calculator 2>/dev/null || true
	/bin/busybox killall vinix-terminal 2>/dev/null || true
	if [ -n "$desktop_pid" ]; then
		/bin/busybox renice 19 -p "$desktop_pid" || true
	fi
	install_status=0
	pkg install chromium || install_status=$?
	if [ -n "$desktop_pid" ]; then
		/bin/busybox renice 0 -p "$desktop_pid" || true
	fi
	echo "VINIX CHROMIUM SCREENSHOT: install finished ($install_status)"
}

release_font_cache() {
	# fc-cache is only a startup optimization. When it overlaps SwiftShader on
	# this four-CPU screenshot VM it can starve the compositor completely, so
	# let Chromium's required GTK caches finish and stop this optional last step.
	while ! /bin/busybox pidof fc-cache >/dev/null 2>&1; do
		sleep 2
	done
	sleep 10
	echo "VINIX CHROMIUM SCREENSHOT: font cache is warm enough"
	/bin/busybox killall fc-cache || true
}

install_chromium &
release_font_cache &
echo "VINIX CHROMIUM SCREENSHOT: starting desktop"
exec /usr/libexec/vinix-desktop-init
