#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-host-sync-test.XXXXXX")
server_pid=
cleanup() {
	[ -z "$server_pid" ] || kill "$server_pid" 2>/dev/null || true
	rm -rf "$work"
}
trap cleanup EXIT INT TERM

source_root=$work/source
mkdir -p "$source_root/desktop" "$source_root/third_party/ui2"
printf 'module main\nconst host_revision = 1\n' > "$source_root/desktop/main.v"
printf 'Module { name: "ui2" }\n' > "$source_root/third_party/ui2/v.mod"
printf 'third_party/\n' > "$source_root/.gitignore"
git -C "$source_root" init -q
git -C "$source_root" add .gitignore desktop/main.v

ready=$work/ready
python3 "$repo/tools/qemu-package-store.py" \
	--store "$work/packages.tar" --port 0 --ready-file "$ready" \
	--source-root "$source_root" --source-extra third_party/ui2 \
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
printf 'http://127.0.0.1:%s\n' "$(cat "$ready")" > "$work/source-url"

VINIX_HOST_SOURCE_URL_FILE=$work/source-url \
VINIX_HOST_MOUNT=$work/mnt/vinix \
VINIX_HOST_CURL=$(command -v curl) \
VINIX_HOST_TAR=$(command -v tar) \
	"$repo/build-support/vinix-host-sync" >/dev/null
grep -q 'host_revision = 1' "$work/mnt/vinix/desktop/main.v"
test -f "$work/mnt/vinix/third_party/ui2/v.mod"

# The service snapshots at request time, not QEMU launch time.
printf 'module main\nconst host_revision = 2\n' > "$source_root/desktop/main.v"
VINIX_HOST_SOURCE_URL_FILE=$work/source-url \
VINIX_HOST_MOUNT=$work/mnt/vinix \
VINIX_HOST_CURL=$(command -v curl) \
VINIX_HOST_TAR=$(command -v tar) \
	"$repo/build-support/vinix-host-sync" >/dev/null
grep -q 'host_revision = 2' "$work/mnt/vinix/desktop/main.v"
if grep -q 'host_revision = 1' "$work/mnt/vinix/desktop/main.v"; then
	echo "host source mirror did not replace the old snapshot" >&2
	exit 1
fi

echo "PASS QEMU host source sync"
