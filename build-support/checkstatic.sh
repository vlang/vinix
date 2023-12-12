#! /bin/sh

set -e

TMPDIR="$(mktemp -d)"
./jinx install "$TMPDIR" '*'
find "$TMPDIR"/ -name '*.a'
rm -rf "$TMPDIR"
