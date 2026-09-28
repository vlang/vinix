#!/bin/sh
# List every heap allocation V's -warn-about-allocs finds in the kernel, for
# aarch64 and amd64, and fail if a file has more of a kind than allowed.txt
# lets it. The kernel is built with -manualfree, so an allocation nothing
# frees is a leak for good; each site allowed.txt lists is either freed by
# its owner, made once at boot, or on a panic's way out.
#
#   tests/kernel-allocs/run.sh           # list the sites, then check them
#   tests/kernel-allocs/run.sh --update  # accept the current sites
#
# V only reports an imported module whose files are under the project root,
# and the kernel build links its sources into obj/vsrc, so each arch's files
# are copied into a scratch tree first. vnew, which find-v.sh prefers,
# predates reporting imported modules at all: the v beside it is used.
set -eu

repo=$(cd "$(dirname "$0")/../.." && pwd)
kernel=$repo/kernel
allowed=$repo/tests/kernel-allocs/allowed.txt

. "$repo/build-support/find-v.sh"
case $V in
*/vnew) [ -x "${V%/vnew}/v" ] && V=${V%/vnew}/v ;;
esac

work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-kernel-allocs.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM

for arch in aarch64 x86_64; do
	src=$work/$arch
	mkdir -p "$src"
	# The file list the kernel build itself uses for this arch.
	(cd "$kernel" && make -n obj/blob.c.o ARCH=$arch V="$V" PROD=false 2>/dev/null |
		grep -o 'for f in [^;]*;' | head -1 | sed 's/^for f in //; s/;$//' | tr ' ' '\n' |
		while read -r f; do
			[ -n "$f" ] && mkdir -p "$src/$(dirname "$f")" && cp "$f" "$src/$f"
		done)
	cp "$kernel/v.mod" "$src/"
	if [ $arch = aarch64 ]; then
		flags='-arch arm64 -d aarch64 -d limine_mp'
	else
		flags='-arch amd64'
	fi
	# Type errors from a newer V than the kernel's do not stop the report.
	# shellcheck disable=SC2086
	"$V" -os vinix -enable-globals -nofloat -manualfree -message-limit 100000 -gc none \
		-target-libc-headers -no-closures -d no_backtrace $flags -warn-about-allocs \
		-o "$work/$arch.c" "$src" > "$work/$arch.log" 2>&1 || true
	grep 'allocation (' "$work/$arch.log" |
		sed -E 's|^.*vinix-kernel-allocs\.[^/]+/[^/]+/||; s|: warning: allocation \((.*)\)| \1|' \
		>> "$work/sites"
done

# A file both arches build is listed once.
sort -u "$work/sites" > "$work/sites.sorted"
cat "$work/sites.sorted"
# Per file and kind, as line numbers move with every edit.
sed -E 's/^([^:]+):[0-9]+:[0-9]+ /\1 /' "$work/sites.sorted" | sort | uniq -c |
	awk '{ n = $1; $1 = ""; sub(/^ /, ""); print $0 "\t" n }' > "$work/counts"

if [ "${1:-}" = --update ]; then
	cp "$work/counts" "$allowed"
	echo "$(wc -l < "$work/sites.sorted" | tr -d ' ') sites accepted into $allowed"
	exit 0
fi

status=0
while IFS='	' read -r site count; do
	limit=$(awk -F '\t' -v site="$site" '$1 == site { print $2 }' "$allowed")
	if [ -z "$limit" ] || [ "$count" -gt "$limit" ]; then
		echo "NEW: $site: $count, allowed ${limit:-0}" >&2
		status=1
	fi
done < "$work/counts"
if [ $status -eq 0 ]; then
	echo "OK: $(wc -l < "$work/sites.sorted" | tr -d ' ') sites, none beyond allowed.txt" >&2
fi
exit $status
