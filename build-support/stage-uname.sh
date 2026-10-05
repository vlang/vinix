#!/bin/sh
# Install the Vinix uname command after all Alpine package layers are merged.
set -eu
if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
    echo "usage: $0 STAGING" >&2
    exit 2
fi
staging=$(cd "$1" && pwd -P)
[ "$staging" != / ] || exit 2
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
mkdir -p "$staging/bin" "$staging/usr/bin"
temporary=$(mktemp "$staging/bin/.uname.XXXXXX")
trap 'rm -f "$temporary"' EXIT HUP INT TERM
cp "$script_dir/uname" "$temporary"
chmod 755 "$temporary"
# Rename over BusyBox's symlink; copying onto it would overwrite BusyBox.
mv -f "$temporary" "$staging/bin/uname"
ln -sf ../../bin/uname "$staging/usr/bin/uname"
