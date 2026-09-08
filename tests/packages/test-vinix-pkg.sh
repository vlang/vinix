#!/bin/sh
# Host-side package command and friendly-alias tests.
set -eu

repo=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-pkg-test.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM

root="$work/root"
log="$work/apk.log"
mkdir -p "$root/etc/vinix-pkg" "$work/bin"
printf '%s\n' 'nameserver 10.0.2.3' > "$root/etc/resolv.conf"
cat > "$root/etc/vinix-pkg/base-world" <<'EOF'
apk-tools
curl
EOF

cat > "$work/bin/apk" <<'EOF'
#!/bin/sh
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
		;;
esac
exit 0
EOF
chmod +x "$work/bin/apk"

run_pkg() {
	VINIX_PKG_APK="$work/bin/apk" \
	VINIX_PKG_ROOT="$root" \
	VINIX_PKG_RESOLV_CONF="${VINIX_PKG_RESOLV_CONF:-$root/etc/resolv.conf}" \
	VINIX_TEST_APK_LOG="$log" \
	VINIX_TEST_ROOT="$root" \
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

run_pkg install nano
sed -n '8p' "$log" | grep -q -- \
	'--cache-dir .* --no-progress cache download nano$'
sed -n '9p' "$log" | grep -q -- \
	'--cache-dir .* --no-network --no-progress --no-scripts add nano$'

run_pkg install gnumeric
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

echo "VINIX PACKAGE COMMAND TEST: PASS"
