#! /bin/sh

set -e

TMPDIR="$(mktemp -d)"
./jinx install "$TMPDIR" '*'
for i in $(find "$TMPDIR"/ -name '*.so*'); do readelf -d $i 2>/dev/null | grep NEEDED | grep libc.so.6 && echo $i; done
rm -rf "$TMPDIR"
