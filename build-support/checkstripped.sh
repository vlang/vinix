#! /bin/sh

set -e

TMPDIR="$(mktemp -d)"
./jinx install "$TMPDIR" '*'
for f in $(find "$TMPDIR"); do file "$f" | grep 'not stripped' || true; done
rm -rf "$TMPDIR"
