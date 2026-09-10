#!/bin/sh
# Host-side package command and friendly-alias tests.
set -eu

repo=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-pkg-test.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM

root="$work/root"
log="$work/apk.log"
installed="$work/installed-packages"
mkdir -p "$root/etc/vinix-pkg" "$root/lib/apk/db" "$work/bin"
: >"$installed"
: >"$root/lib/apk/db/installed"
printf '%s\n' 'nameserver 10.0.2.3' > "$root/etc/resolv.conf"

# Tiny deterministic stand-in for the proprietary download. The package
# frontend still exercises archive extraction, checksum verification, desktop
# integration, manifests, and removal without contacting Sublime's servers.
sublime_fixture="$work/sublime-fixture"
mkdir -p "$sublime_fixture/sublime_text/Icon"
for size in 16 32 48 128 256; do
	mkdir -p "$sublime_fixture/sublime_text/Icon/${size}x${size}"
	printf 'icon %s\n' "$size" \
		>"$sublime_fixture/sublime_text/Icon/${size}x${size}/sublime-text.png"
done
for executable in sublime_text plugin_host-3.3 plugin_host-3.8 crash_handler; do
	printf '#!/bin/sh\nexit 0\n' >"$sublime_fixture/sublime_text/$executable"
done
sublime_archive="$work/sublime-text.tar.xz"
tar -cJf "$sublime_archive" -C "$sublime_fixture" sublime_text

cat >"$work/bin/sha256sum" <<'EOF'
#!/bin/sh
if command -v sha256sum >/dev/null 2>&1; then
	exec sha256sum "$@"
fi
exec shasum -a 256 "$@"
EOF
chmod +x "$work/bin/sha256sum"
sublime_sha=$("$work/bin/sha256sum" "$sublime_archive" | awk '{print $1}')
host_curl=$(command -v curl)
host_tar=$(command -v bsdtar || command -v tar)
cat > "$root/etc/vinix-pkg/base-world" <<'EOF'
apk-tools
curl
EOF

cat > "$work/bin/apk" <<'EOF'
#!/bin/sh
case "$*" in
	*' info')
		cat "$VINIX_TEST_INSTALLED_PACKAGES"
		exit 0
		;;
esac
printf '%s\n' "$*" >> "$VINIX_TEST_APK_LOG"
case "$*" in
	*' update')
		if [ -n "${VINIX_TEST_FAIL_UPDATE_ONCE:-}" ] \
			&& [ ! -f "$VINIX_TEST_FAIL_UPDATE_ONCE" ]; then
			: > "$VINIX_TEST_FAIL_UPDATE_ONCE"
			echo 'WARNING: temporary error (try again later)' >&2
			exit 1
		fi
		mkdir -p "$VINIX_TEST_ROOT/var/cache/apk"
		: > "$VINIX_TEST_ROOT/var/cache/apk/APKINDEX.test.tar.gz"
		;;
	*' cache download '*)
		output=
		previous=
		for argument in "$@"; do
			if [ "$previous" = output ]; then
				output=$argument
				break
			fi
			[ "$argument" != --cache-dir ] || previous=output
		done
		index_found=false
		for index in "$output"/APKINDEX.*.tar.gz; do
			[ ! -f "$index" ] || index_found=true
		done
		if [ "$index_found" != true ]; then
			echo 'apk download cache is missing repository indexes' >&2
			exit 89
		fi
		if [ -n "${VINIX_TEST_FAIL_FETCH_ONCE:-}" ] \
			&& [ ! -f "$VINIX_TEST_FAIL_FETCH_ONCE" ]; then
			: > "$VINIX_TEST_FAIL_FETCH_ONCE"
			: > "$output/downloaded-before-retry.apk"
			echo 'ERROR: test-package: temporary error (try again later)' >&2
			exit 1
		fi
		if [ -n "${VINIX_TEST_REQUIRE_RETAINED_ARCHIVE:-}" ] \
			&& [ ! -f "$output/downloaded-before-retry.apk" ]; then
			echo 'apk cache retry discarded an already downloaded archive' >&2
			exit 88
		fi
		if [ -n "${VINIX_TEST_INSTALL_RETRY_MARKER:-}" ]; then
			if [ -f "$VINIX_TEST_INSTALL_RETRY_MARKER" ]; then
				if [ -f "$output/damaged-install.apk" ]; then
					echo 'apk install retry retained a damaged archive' >&2
					exit 87
				fi
			else
				: > "$output/damaged-install.apk"
			fi
		fi
		;;
	*' --no-network --no-progress --no-scripts add '*)
		if [ -n "${VINIX_TEST_INSTALL_RETRY_MARKER:-}" ] \
			&& [ ! -f "$VINIX_TEST_INSTALL_RETRY_MARKER" ]; then
			: > "$VINIX_TEST_INSTALL_RETRY_MARKER"
			echo 'ERROR: damaged-install: BAD signature' >&2
			exit 1
		fi
		seen_add=false
		for argument in "$@"; do
			if [ "$seen_add" = true ]; then
				printf '%s\n' "$argument" >>"$VINIX_TEST_INSTALLED_PACKAGES"
				case "$argument" in
					blender)
						mkdir -p "$VINIX_TEST_ROOT/usr/bin" \
							"$VINIX_TEST_ROOT/usr/lib" \
							"$VINIX_TEST_ROOT/usr/share/applications" \
							"$VINIX_TEST_ROOT/usr/share/blender/4.3"
						printf '#!/bin/sh\nprintf "Blender 4.3.0\\n"\n' \
							>"$VINIX_TEST_ROOT/usr/bin/blender"
						chmod 0755 "$VINIX_TEST_ROOT/usr/bin/blender"
						printf 'Blender dependency\n' \
							>"$VINIX_TEST_ROOT/usr/lib/libblender-dependency.so.1.0"
						ln -sf libblender-dependency.so.1.0 \
							"$VINIX_TEST_ROOT/usr/lib/libblender-dependency.so.1"
						: >"$VINIX_TEST_ROOT/usr/share/applications/blender.desktop"
						: >"$VINIX_TEST_ROOT/usr/share/blender/4.3/payload"
						printf 'P:%s\nF:usr/bin\nR:blender\nF:usr/lib\nR:libblender-dependency.so.1\nR:libblender-dependency.so.1.0\nF:usr/share/applications\nR:blender.desktop\nF:usr/share/blender/4.3\nR:payload\n\n' \
							"$argument"
						;;
					gtk+3.0)
						printf 'P:%s\nF:usr/lib\nR:libgtk-3.so.0\n\n' "$argument"
						;;
					gnumeric)
						printf 'P:%s\nF:usr/bin\nR:gnumeric\n\n' "$argument"
						;;
					*)
						printf 'P:%s\nF:usr/share/%s\nR:payload\n\n' \
							"$argument" "$argument"
						;;
				esac >>"$VINIX_TEST_ROOT/lib/apk/db/installed"
			elif [ "$argument" = add ]; then
				seen_add=true
			fi
		done
		if printf '%s\n' "$*" | grep -q ' gcompat '; then
			mkdir -p "$VINIX_TEST_ROOT/lib"
			printf 'gcompat\n' >"$VINIX_TEST_ROOT/lib/libgcompat.so.0"
			ln -sf libgcompat.so.0 "$VINIX_TEST_ROOT/lib/ld-linux-aarch64.so.1"
		fi
		LC_ALL=C sort -u -o "$VINIX_TEST_INSTALLED_PACKAGES" \
			"$VINIX_TEST_INSTALLED_PACKAGES"
		;;
esac
exit 0
EOF
chmod +x "$work/bin/apk"

run_pkg() {
	VINIX_PKG_APK="$work/bin/apk" \
	VINIX_PKG_ROOT="$root" \
	VINIX_PKG_RESOLV_CONF="${VINIX_PKG_RESOLV_CONF:-$root/etc/resolv.conf}" \
	VINIX_PKG_CURL="${VINIX_PKG_CURL:-$host_curl}" \
	VINIX_PKG_BSDTAR="${VINIX_PKG_BSDTAR:-$host_tar}" \
	VINIX_PKG_SHA256SUM="${VINIX_PKG_SHA256SUM:-$work/bin/sha256sum}" \
	VINIX_PKG_BUSYBOX= \
	VINIX_TEST_APK_LOG="$log" \
	VINIX_TEST_ROOT="$root" \
	VINIX_TEST_INSTALLED_PACKAGES="$installed" \
		"$repo/build-support/vinix-pkg" "$@"
}

run_pkg install gtk

sed -n '2p' "$log" | grep -q -- \
	'--cache-dir .* --no-progress cache download apk-tools curl$'
sed -n '3p' "$log" | grep -q -- \
	'--cache-dir .* --no-network --no-progress --no-scripts add apk-tools curl$'
sed -n '4p' "$log" | grep -q -- \
	'--cache-dir .* --no-progress cache download adwaita-icon-theme font-dejavu gtk+3.0 libarchive-tools$'
sed -n '5p' "$log" | grep -q -- \
	'--cache-dir .* --no-network --no-progress --no-scripts add adwaita-icon-theme font-dejavu gtk+3.0 libarchive-tools$'
sed -n '6p' "$log" | grep -q -- \
	'--cache-dir .* --no-progress cache download gtk+3.0-demo$'
sed -n '7p' "$log" | grep -q -- \
	'--cache-dir .* --no-network --no-progress --no-scripts add gtk+3.0-demo$'
sed -n '1p' "$log" | grep -q -- ' update$'
test -f "$root/var/lib/vinix-pkg/base-ready"
grep -qx usr/lib/libgtk-3.so.0 "$root/var/lib/vinix-pkg/package-files"

run_pkg install nano
sed -n '8p' "$log" | grep -q -- \
	'--cache-dir .* --no-progress cache download nano$'
sed -n '9p' "$log" | grep -q -- \
	'--cache-dir .* --no-network --no-progress --no-scripts add nano$'

run_pkg install gnumeric
grep -qx usr/bin/gnumeric "$root/var/lib/vinix-pkg/package-files"
sed -n '10p' "$log" | grep -q -- \
	'--cache-dir .* --no-progress cache download adwaita-icon-theme font-dejavu gnumeric$'
sed -n '11p' "$log" | grep -q -- \
	'--cache-dir .* --no-network --no-progress --no-scripts add adwaita-icon-theme font-dejavu gnumeric$'

run_pkg remove gnumeric
sed -n '12p' "$log" | grep -q -- \
	'--no-progress --no-scripts del gnumeric adwaita-icon-theme font-dejavu$'

run_pkg remove gtk
sed -n '13p' "$log" | grep -q -- \
	'--no-progress --no-scripts del gtk+3.0-demo$'
sed -n '14p' "$log" | grep -q -- \
	'--no-progress --no-scripts del gtk+3.0 adwaita-icon-theme font-dejavu libarchive-tools$'

run_pkg update
sed -n '15p' "$log" | grep -q -- ' update$'

# Transient index and package download failures are retried.  The package
# archive completed by the first fetch remains in the same cache, and apk only
# starts its database transaction after every download has succeeded.
rm -f "$root"/var/cache/apk/APKINDEX.*.tar.gz
retry_marker="$work/update-failed-once"
fetch_retry_marker="$work/fetch-failed-once"
VINIX_TEST_FAIL_UPDATE_ONCE="$retry_marker" \
VINIX_TEST_FAIL_FETCH_ONCE="$fetch_retry_marker" \
VINIX_TEST_REQUIRE_RETAINED_ARCHIVE=1 \
	VINIX_PKG_NETWORK_RETRY_DELAY=0 run_pkg install curl \
	>"$work/retry.log" 2>&1
test "$(grep -c 'package network operation failed; retrying (1/10)' "$work/retry.log")" = 2
sed -n '16p' "$log" | grep -q -- ' update$'
sed -n '17p' "$log" | grep -q -- ' update$'
sed -n '18p' "$log" | grep -q -- \
	'--cache-dir .* --no-progress cache download curl$'
sed -n '19p' "$log" | grep -q -- \
	'--cache-dir .* --no-progress cache download curl$'
sed -n '20p' "$log" | grep -q -- \
	'--cache-dir .* --no-network --no-progress --no-scripts add curl$'
unset VINIX_TEST_FAIL_UPDATE_ONCE VINIX_TEST_FAIL_FETCH_ONCE \
	VINIX_TEST_REQUIRE_RETAINED_ARCHIVE

# A package archive can pass the download stream and fail when the offline
# transaction reopens it. Discard package files (but not indexes), resolve the
# now-smaller remaining transaction, and retry without network in apk add.
install_retry_marker="$work/install-failed-once"
if ! VINIX_TEST_INSTALL_RETRY_MARKER="$install_retry_marker" \
	VINIX_PKG_NETWORK_RETRY_DELAY=0 run_pkg install gnumeric \
	>"$work/install-retry.log" 2>&1; then
	cat "$work/install-retry.log" >&2
	exit 1
fi
grep -q 'package installation failed; refreshing downloads (1/10)' \
	"$work/install-retry.log"
sed -n '21p' "$log" | grep -q -- \
	'--cache-dir .* --no-progress cache download adwaita-icon-theme font-dejavu gnumeric$'
sed -n '22p' "$log" | grep -q -- \
	'--cache-dir .* --no-network --no-progress --no-scripts add adwaita-icon-theme font-dejavu gnumeric$'
sed -n '23p' "$log" | grep -q -- \
	'--cache-dir .* --no-progress cache download adwaita-icon-theme font-dejavu gnumeric$'
sed -n '24p' "$log" | grep -q -- \
	'--cache-dir .* --no-network --no-progress --no-scripts add adwaita-icon-theme font-dejavu gnumeric$'
unset VINIX_TEST_INSTALL_RETRY_MARKER

# Do not fall through to apk with an empty package database when DHCP has not
# published a resolver yet.
rm -f "$root"/var/cache/apk/APKINDEX.*.tar.gz
if VINIX_PKG_RESOLV_CONF="$work/missing-resolv.conf" \
	VINIX_PKG_NETWORK_WAIT_SECONDS=0 run_pkg install curl \
	>"$work/no-network.log" 2>&1; then
	echo "pkg unexpectedly ran without a resolver" >&2
	exit 1
fi
grep -q 'network is not ready' "$work/no-network.log"
test "$(wc -l < "$log" | tr -d ' ')" = 24
unset VINIX_PKG_RESOLV_CONF VINIX_PKG_NETWORK_WAIT_SECONDS

if VINIX_SUBLIME_URL="file://$sublime_archive" \
	VINIX_SUBLIME_SHA256=0000000000000000000000000000000000000000000000000000000000000000 \
	run_pkg install sublime-text >"$work/sublime-bad-checksum.log" 2>&1; then
	echo "pkg accepted a Sublime Text archive with the wrong checksum" >&2
	exit 1
fi
if ! grep -q 'archive checksum mismatch' "$work/sublime-bad-checksum.log"; then
	cat "$work/sublime-bad-checksum.log" >&2
	exit 1
fi
test ! -e "$root/opt/sublime_text"

VINIX_SUBLIME_URL="file://$sublime_archive" \
VINIX_SUBLIME_SHA256="$sublime_sha" run_pkg install sublime-text
test -x "$root/opt/sublime_text/sublime_text"
test -x "$root/opt/sublime_text/plugin_host-3.8"
test -x "$root/usr/bin/subl"
test -f "$root/usr/share/applications/sublime_text.desktop"
test -f "$root/usr/share/icons/hicolor/256x256/apps/sublime-text.png"
test -d "$root/dev/shm"
test -f "$root/lib/ld-linux-aarch64.so.1"
test ! -L "$root/lib/ld-linux-aarch64.so.1"
grep -qx './opt/sublime_text/sublime_text' \
	"$root/var/lib/vinix-pkg/sublime-text.files"
run_pkg list | grep -qx sublime-text
grep -q -- \
	'--cache-dir .* --no-progress cache download adwaita-icon-theme font-dejavu gcompat gtk+3.0 libarchive-tools llvm19-libs$' \
	"$log"

run_pkg remove sublime-text
test ! -e "$root/opt/sublime_text"
test ! -e "$root/usr/bin/subl"
test ! -e "$root/var/lib/vinix-pkg/sublime-text.files"
tail -n 1 "$log" | grep -q -- \
	'--no-progress --no-scripts del gcompat gtk+3.0 adwaita-icon-theme font-dejavu libarchive-tools llvm19-libs$'

run_pkg install blender
test -x "$root/usr/bin/blender"
test -x "$root/usr/libexec/vinix-blender"
test -f "$root/usr/lib/libblender-dependency.so.1"
test ! -L "$root/usr/lib/libblender-dependency.so.1"
test -f "$root/usr/share/applications/blender.desktop"
test -f "$root/usr/share/blender/4.3/payload"
grep -q '^# Vinix Blender launcher$' "$root/usr/bin/blender"
grep -q 'vinix-blender -noaudio' "$root/usr/bin/blender"
grep -qx usr/libexec/vinix-blender \
	"$root/var/lib/vinix-pkg/package-files"
test "$("$root/usr/libexec/vinix-blender" --version)" = 'Blender 4.3.0'
tail -n 2 "$log" | sed -n '1p' | grep -q -- \
	'--cache-dir .* --no-progress cache download blender python3-pycache-pyc0$'
tail -n 1 "$log" | grep -q -- \
	'--cache-dir .* --no-network --no-progress --no-scripts add blender$'

run_pkg remove blender
test ! -e "$root/usr/libexec/vinix-blender"
tail -n 1 "$log" | grep -q -- \
	'--no-progress --no-scripts del blender$'

echo "VINIX PACKAGE COMMAND TEST: PASS"
