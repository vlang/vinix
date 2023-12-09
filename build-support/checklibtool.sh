#! /bin/sh

set -e

TMPDIR="$(mktemp -d)"
./jinx install "$TMPDIR" '*'
find "$TMPDIR"/ -name '*.la'
rm -rf "$TMPDIR"
