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
	*' add gtk+3.0-demo') echo 'OK: test transaction committed' ;;
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
	'--root .* --no-progress --no-scripts add apk-tools curl'
sed -n '3p' "$log" | grep -q -- \
	'--root .* --no-progress --no-scripts add adwaita-icon-theme font-dejavu gtk+3.0 libarchive-tools$'
sed -n '4p' "$log" | grep -q -- \
	'--root .* --no-progress --no-scripts add gtk+3.0-demo$'
sed -n '1p' "$log" | grep -q -- ' update$'
test -f "$root/var/lib/vinix-pkg/base-ready"

run_pkg install nano
test "$(wc -l < "$log" | tr -d ' ')" = 5
sed -n '5p' "$log" | grep -q -- '--no-progress --no-scripts add nano$'

run_pkg install gnumeric
sed -n '6p' "$log" | grep -q -- \
	'--no-progress --no-scripts add adwaita-icon-theme font-dejavu gnumeric$'

run_pkg remove gnumeric
sed -n '7p' "$log" | grep -q -- \
	'--no-progress --no-scripts del gnumeric adwaita-icon-theme font-dejavu$'

run_pkg remove gtk
sed -n '8p' "$log" | grep -q -- \
	'--no-progress --no-scripts del gtk+3.0-demo$'
sed -n '9p' "$log" | grep -q -- \
	'--no-progress --no-scripts del gtk+3.0 adwaita-icon-theme font-dejavu libarchive-tools$'

run_pkg update
sed -n '10p' "$log" | grep -q -- ' update$'

# A transient repository failure is retried, and the successful refresh is
# cached before apk is asked to resolve the requested package.
rm -f "$root"/var/cache/apk/APKINDEX.*.tar.gz
retry_marker="$work/update-failed-once"
VINIX_TEST_FAIL_UPDATE_ONCE="$retry_marker" \
	VINIX_PKG_NETWORK_RETRY_DELAY=0 run_pkg install curl \
	>"$work/retry.log" 2>&1
grep -q 'package network operation failed; retrying (1/3)' "$work/retry.log"
sed -n '11p' "$log" | grep -q -- ' update$'
sed -n '12p' "$log" | grep -q -- ' update$'
sed -n '13p' "$log" | grep -q -- '--no-progress --no-scripts add curl$'

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
test "$(wc -l < "$log" | tr -d ' ')" = 13

echo "VINIX PACKAGE COMMAND TEST: PASS"
