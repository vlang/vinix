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
ui2_root=$work/ui2-source
mkdir -p "$source_root/desktop/tools" "$ui2_root/ui" \
	"$ui2_root/examples/calculator"
printf 'module main\nconst host_revision = 1\n' > "$source_root/desktop/main.v"
cp "$repo/desktop/tools/stage_app.py" "$source_root/desktop/tools/stage_app.py"
cp "$repo/desktop/tools/stage_ui2.py" "$source_root/desktop/tools/stage_ui2.py"
cp "$repo/desktop/tools/ui2_headless_bounds.v" \
	"$source_root/desktop/tools/ui2_headless_bounds.v"
printf 'Module { name: "ui2", subdirs: ["ui"] }\n' > "$ui2_root/v.mod"
printf 'module ui2\n' > "$ui2_root/ui/ui.v"
printf 'module main\n\nstruct CalculatorModel {}\n\nfn main() {}\n' \
	> "$ui2_root/examples/calculator/main.v"
printf 'third_party/\n' > "$source_root/.gitignore"
git -C "$source_root" init -q
git -C "$source_root" add .gitignore desktop/main.v

ready=$work/ready
python3 "$repo/tools/qemu-package-store.py" \
	--store "$work/packages.tar" --port 0 --ready-file "$ready" \
	--source-root "$source_root" --ui2-source "$ui2_root" \
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
test -f "$work/mnt/vinix/.vinix-build/desktop/app_calculator.v"
test -f "$work/mnt/vinix/.vinix-build/vmodules/ui2/v.mod"
test -L "$work/mnt/vinix"

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

# An unchanged checkout reuses the current immutable snapshot rather than
# recursively deleting a tree or consuming another snapshot's worth of RAM.
before=$(find "$work/mnt" -maxdepth 1 -type d -name '.vinix.snapshot.*' | wc -l)
VINIX_HOST_SOURCE_URL_FILE=$work/source-url \
VINIX_HOST_MOUNT=$work/mnt/vinix \
VINIX_HOST_CURL=$(command -v curl) \
VINIX_HOST_TAR=$(command -v tar) \
	"$repo/build-support/vinix-host-sync" >/dev/null
after=$(find "$work/mnt" -maxdepth 1 -type d -name '.vinix.snapshot.*' | wc -l)
test "$before" -eq 2
test "$after" -eq "$before"

echo "PASS QEMU host source sync"
