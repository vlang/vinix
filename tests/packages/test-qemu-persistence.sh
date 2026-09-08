#!/bin/sh
set -eu

repo=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-qemu-persist-test.XXXXXX")
server_pid=
cleanup() {
	[ -z "$server_pid" ] || kill "$server_pid" 2>/dev/null || true
	rm -rf "$work"
}
trap cleanup EXIT INT TERM

root="$work/root"
store="$work/packages.tar"
ready="$work/ready"
mkdir -p "$root/etc/apk" "$root/etc/vinix-pkg" "$root/lib/apk/db" \
	"$root/usr/share/base" "$root/var/cache/apk"
printf 'base\n' >"$root/usr/share/base/unchanged"
printf 'old library\n' >"$root/usr/share/base/replaced"
printf 'busybox\n' >"$root/etc/apk/world"
printf 'base database\n' >"$root/lib/apk/db/installed"
(
	cd "$root"
	find etc lib usr var -type d -o -type f -o -type l
) | LC_ALL=C sort -u >"$root/etc/vinix-pkg/base-files"

# Simulate the effects of installing GTK: new payload files, an updated apk
# database and a generated cache. Downloaded repository indexes are volatile.
mkdir -p "$root/usr/lib" "$root/usr/share/icons/Adwaita" "$root/var/lib/vinix-pkg"
printf 'gtk\n' >"$root/usr/lib/libgtk-3.so"
printf 'busybox\ngtk+3.0\n' >"$root/etc/apk/world"
printf 'gtk database\n' >"$root/lib/apk/db/installed"
printf 'nameserver 10.0.2.3\n' >"$root/etc/resolv.conf"
printf 'cache\n' >"$root/usr/share/icons/Adwaita/icon-theme.cache"
printf 'index\n' >"$root/var/cache/apk/APKINDEX.test"
printf 'ready\n' >"$root/var/lib/vinix-pkg/base-ready"
printf 'usr/share/base/replaced\n' >"$root/var/lib/vinix-pkg/package-files"
printf 'new package library\n' >"$root/usr/share/base/replaced"

python3 "$repo/tools/qemu-package-store.py" \
	--store "$store" --port 0 --ready-file "$ready" \
	>"$work/server.log" 2>&1 &
server_pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
	[ -s "$ready" ] && break
	sleep 0.05
done
if [ ! -s "$ready" ]; then
	cat "$work/server.log" >&2
	exit 1
fi
printf 'http://127.0.0.1:%s\n' "$(cat "$ready")" \
	>"$root/etc/vinix-pkg/qemu-store-url"

VINIX_PERSIST_ROOT="$root" \
VINIX_PERSIST_BUSYBOX= \
VINIX_PERSIST_CURL="$(command -v curl)" \
	"$repo/build-support/vinix-persist-packages" save

tar -tf "$store" >"$work/members"
grep -qx 'usr/lib/libgtk-3.so' "$work/members"
grep -qx 'etc/apk/world' "$work/members"
grep -qx 'lib/apk/db/installed' "$work/members"
grep -qx 'usr/share/icons/Adwaita/icon-theme.cache' "$work/members"
grep -qx 'var/lib/vinix-pkg/base-ready' "$work/members"
grep -qx 'usr/share/base/replaced' "$work/members"
test "$(tar -xOf "$store" usr/share/base/replaced)" = 'new package library'
test "$(grep -cx 'usr/lib/libgtk-3.so' "$work/members")" = 1
test "$(grep -cx 'usr/share/icons/Adwaita/icon-theme.cache' "$work/members")" = 1
if grep -q 'usr/share/base/unchanged\|var/cache/apk\|qemu-store-url\|etc/resolv.conf' "$work/members"; then
	echo "unexpected base, volatile, or runtime file in package overlay" >&2
	exit 1
fi

# apk can leave the preinstalled curl without its executable bit. Verify that
# the helper repairs it before attempting the upload.
cat >"$work/curl-with-bad-mode" <<'EOF'
#!/bin/sh
exec "$VINIX_TEST_REAL_CURL" "$@"
EOF
chmod 0644 "$work/curl-with-bad-mode"
VINIX_PERSIST_ROOT="$root" \
VINIX_PERSIST_BUSYBOX= \
VINIX_PERSIST_CURL="$work/curl-with-bad-mode" \
VINIX_TEST_REAL_CURL="$(command -v curl)" \
	"$repo/build-support/vinix-persist-packages" save >/dev/null
test -x "$work/curl-with-bad-mode"

# The public pkg command persists only after successful mutating operations.
cat >"$work/core" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$VINIX_TEST_CORE_LOG"
EOF
cat >"$work/persist" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$VINIX_TEST_PERSIST_LOG"
EOF
chmod +x "$work/core" "$work/persist"
VINIX_PKG_CORE="$work/core" VINIX_PKG_PERSIST_HELPER="$work/persist" \
	VINIX_TEST_CORE_LOG="$work/core.log" VINIX_TEST_PERSIST_LOG="$work/persist.log" \
	"$repo/build-support/vinix-pkg-wrapper" install gtk
VINIX_PKG_CORE="$work/core" VINIX_PKG_PERSIST_HELPER="$work/persist" \
	VINIX_TEST_CORE_LOG="$work/core.log" VINIX_TEST_PERSIST_LOG="$work/persist.log" \
	"$repo/build-support/vinix-pkg-wrapper" search gtk
grep -qx 'install gtk' "$work/core.log"
grep -qx 'search gtk' "$work/core.log"
test "$(wc -l <"$work/persist.log" | tr -d ' ')" = 1
grep -qx save "$work/persist.log"

echo "QEMU PACKAGE PERSISTENCE TEST: PASS"
