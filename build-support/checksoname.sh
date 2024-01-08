#! /bin/sh

TMPDIR="$(mktemp -d)"
./jinx install "$TMPDIR" '*'
rm -rf "$TMPDIR/bin" "$TMPDIR/sbin" "$TMPDIR/lib" "$TMPDIR/lib64" "$TMPDIR/usr/sbin" "$TMPDIR/usr/lib64"
for f in $(find "$TMPDIR" -name '*.so*' -type f); do
    if ! readelf --dynamic "$f" >/dev/null 2>&1; then
        continue
    fi
    if ! readelf --dynamic "$f" | grep -q 'SONAME'; then
        echo "$f has no soname"
    fi
done
rm -rf "$TMPDIR"
