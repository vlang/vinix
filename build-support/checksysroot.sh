#! /bin/sh

TMPDIR="$(mktemp -d)"
./jinx install "$TMPDIR" '*'
rm -rf "$TMPDIR/bin" "$TMPDIR/sbin" "$TMPDIR/lib" "$TMPDIR/lib64" "$TMPDIR/usr/sbin" "$TMPDIR/usr/lib64"
for f in $(find "$TMPDIR" -type f); do
    stuff="$(strings "$f" | grep '/sysroot' | grep -v Assertion | grep -v '\--enable-languages')"
    if [ -z "$stuff" ]; then
        continue
    fi
    echo "in $f"
    echo "$stuff"
done
rm -rf "$TMPDIR"
