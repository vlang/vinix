#!/bin/sh
# First-run setup end to end, for --guest-init boots: create the user through
# the registration screen, choose apps in the picker that follows it, and check
# that the Terminal the desktop then opens installs exactly those apps.
#
# Run it with: tests/browsers/run_vm.py --first-run
#
# Keystrokes reach the compositor through its standard input, which is where a
# desktop session reads the keyboard. A recorder named pkg is put first on PATH,
# so the boot needs no network. Set VOFFICE_BUNDLE_URL (for example to a host
# HTTP server at 10.0.2.2) to install that real VOffice bundle instead, and then
# also open VOffice Writer from Quick Launch.
VOFFICE_BUNDLE_URL=

export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export HOME=/root
export TERM=linux
export LD_LIBRARY_PATH=/usr/lib:/usr/lib/xorg/modules
export SSL_CA_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

fail() {
	echo "VINIX FIRST RUN: FAIL $*"
	echo "VINIX FIRST RUN TEST: FAIL"
	exit 1
}

wait_for() {
	waited=0
	while [ ! -e "$1" ] && [ "$waited" -lt "$2" ]; do
		sleep 1
		waited=$((waited + 1))
	done
	[ -e "$1" ]
}

echo
echo "VINIX FIRST RUN TEST: START"

[ -x /usr/bin/vinix-desktop ] || fail "no /usr/bin/vinix-desktop"
[ -x /usr/bin/pkg ] || fail "no /usr/bin/pkg"
mkdir -p /tmp /run /usr/local/bin
chmod 1777 /tmp
# A persistent home reused from an earlier boot must look like a machine that
# was never set up.
rm -f /root/.vinix-user /root/.vinix-first-run-apps /run/vinix-first-run-install \
	/run/vinix-desktop-ready

# Rows are numbered in the order the picker offers them: Firefox, Chromium,
# VOffice, Minecraft. Pick the ones this image does not already carry.
log=/tmp/first-run-pkg.log
: >"$log"
keys=
expected=
if [ ! -x /usr/lib/chromium/chrome ] && [ -z "$VOFFICE_BUNDLE_URL" ]; then
	keys=2
	expected="install chromium"
fi
[ ! -x /usr/bin/voffice-writer ] || fail "this image already carries VOffice"
keys="${keys}3"
expected="${expected:+$expected
}install voffice"

if [ -z "$VOFFICE_BUNDLE_URL" ]; then
	printf '#!/bin/sh\necho "$*" >>%s\n' "$log" >/usr/local/bin/pkg
else
	printf '#!/bin/sh\necho "$*" >>%s\nexport VINIX_VOFFICE_URL=%s\nexec /usr/bin/pkg "$@"\n' \
		"$log" "$VOFFICE_BUNDLE_URL" >/usr/local/bin/pkg
fi
chmod 755 /usr/local/bin/pkg

# Type like a user: name, Tab, password, Tab, password, Return. Once the user
# exists the picker owns the keyboard; toggle the rows by number and confirm.
{
	sleep 10
	printf 'Test User\tvinix-test\tvinix-test\r'
	wait_for /root/.vinix-user 150 || exit 0
	sleep 5
	printf '%s\r' "$keys"
	if [ -n "$VOFFICE_BUNDLE_URL" ]; then
		wait_for /usr/bin/voffice-writer 600 || exit 0
		sleep 5
		# Cmd-Space opens Quick Launch over the focused Terminal.
		printf '\033[32;9u\033[57444;1:3uVOffice Writer'
		sleep 2
		printf '\r'
	fi
	sleep 100000
} | /usr/bin/vinix-desktop &
echo "VINIX FIRST RUN: compositor started; choosing rows $keys"

wait_for /root/.vinix-user 150 || fail "registration created no user in 150s"
echo "VINIX FIRST RUN PASS: registration created the user"
[ -e /root/.vinix-first-run-apps ] || fail "creating the user did not schedule the app picker"
echo "VINIX FIRST RUN PASS: the app picker follows registration"

wait_for /run/vinix-desktop-ready 150 || fail "the desktop did not start after the app picker"
[ ! -e /root/.vinix-first-run-apps ] || fail "the app picker left its marker behind"
echo "VINIX FIRST RUN PASS: the picker finished and the desktop started"

deadline=60
[ -z "$VOFFICE_BUNDLE_URL" ] || deadline=900
waited=0
while [ "$(cat "$log")" != "$expected" ] && [ "$waited" -lt "$deadline" ]; do
	sleep 1
	waited=$((waited + 1))
done
[ "$(cat "$log")" = "$expected" ] ||
	fail "the Terminal ran [$(tr '\n' ';' <"$log")], expected [$(echo "$expected" | tr '\n' ';')]"
[ ! -e /run/vinix-first-run-install ] || fail "the Terminal did not claim the install request"
echo "VINIX FIRST RUN PASS: the Terminal installed the chosen apps"

if [ -n "$VOFFICE_BUNDLE_URL" ]; then
	wait_for /usr/bin/voffice-calc 60 || fail "pkg did not install VOffice"
	[ -s /usr/bin/assets/logo.png ] || fail "VOffice installed without its artwork"
	echo "VINIX FIRST RUN PASS: VOffice is installed"
	sleep 30
	if dd if=/dev/processes bs=65536 count=1 2>/dev/null | tr '\000' '\n' |
		grep -q voffice-writer; then
		echo "VINIX FIRST RUN PASS: VOffice Writer is running"
	else
		echo "VINIX FIRST RUN: could not confirm VOffice Writer from /dev/processes"
	fi
fi

echo "VINIX FIRST RUN TEST: PASS"
# Keep PID 1 alive while the harness stops the machine.
sleep 100000
