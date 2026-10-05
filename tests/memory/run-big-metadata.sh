#!/bin/sh
# Test the production header implementation at both native page geometries.
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
. "$repo/build-support/find-v.sh"
work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-big-metadata.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
for size in 4096 16384; do
	mkdir -p "$work/$size/memory"
	cp "$repo/kernel/memory/big_metadata.v" "$repo/tests/memory/big_metadata_test.v" "$work/$size/memory/"
	printf 'Module { name: "big_metadata_tests" }\n' > "$work/$size/v.mod"
	printf 'module memory\nconst page_size = u64(%s)\n' "$size" > "$work/$size/memory/page_size.v"
	VEXE="$V" V_MACOS_V3_NO_FALLBACK=1 V_C_ERROR_BUG_REPORT_DISABLED=1 "$V" -prod -gc none test "$work/$size/memory"
done
