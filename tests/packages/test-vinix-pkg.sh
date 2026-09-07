#!/bin/sh
# Host-side package command and friendly-alias tests.
set -eu

repo=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-pkg-test.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM

root="$work/root"
log="$work/apk.log"
mkdir -p "$root/etc/vinix-pkg" "$work/bin"
cat > "$root/etc/vinix-pkg/base-world" <<'EOF'
apk-tools
curl
EOF

cat > "$work/bin/apk" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$VINIX_TEST_APK_LOG"
case "$*" in
	*' add gtk+3.0-demo') echo 'OK: test transaction committed' ;;
esac
exit 0
EOF
chmod +x "$work/bin/apk"

run_pkg() {
	VINIX_PKG_APK="$work/bin/apk" \
	VINIX_PKG_ROOT="$root" \
	VINIX_TEST_APK_LOG="$log" \
		"$repo/build-support/vinix-pkg" "$@"
}

run_pkg install gtk

sed -n '1p' "$log" | grep -q -- \
	'--root .* --no-cache --no-progress --no-scripts add apk-tools curl'
sed -n '2p' "$log" | grep -q -- \
	'--root .* --no-cache --no-progress --no-scripts add adwaita-icon-theme font-dejavu gtk+3.0 libarchive-tools$'
sed -n '3p' "$log" | grep -q -- \
	'--root .* --no-cache --no-progress --no-scripts add gtk+3.0-demo$'
test -f "$root/var/lib/vinix-pkg/base-ready"

run_pkg install nano
test "$(wc -l < "$log" | tr -d ' ')" = 4
sed -n '4p' "$log" | grep -q -- '--no-cache --no-progress --no-scripts add nano$'

run_pkg install gnumeric
sed -n '5p' "$log" | grep -q -- \
	'--no-cache --no-progress --no-scripts add adwaita-icon-theme font-dejavu gnumeric$'

run_pkg remove gnumeric
sed -n '6p' "$log" | grep -q -- \
	'--no-progress --no-scripts del gnumeric adwaita-icon-theme font-dejavu$'

run_pkg remove gtk
sed -n '7p' "$log" | grep -q -- \
	'--no-progress --no-scripts del gtk+3.0-demo$'
sed -n '8p' "$log" | grep -q -- \
	'--no-progress --no-scripts del gtk+3.0 adwaita-icon-theme font-dejavu libarchive-tools$'

run_pkg update
sed -n '9p' "$log" | grep -q -- ' update$'

echo "VINIX PACKAGE COMMAND TEST: PASS"
