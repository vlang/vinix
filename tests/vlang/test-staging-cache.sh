#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-staging-cache-test.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

mkdir -p "$work/source" "$work/downloads" "$work/staging/usr/bin"
printf 'source\n' > "$work/source/app.v"
ln -s "$work/source" "$work/linked-source"
printf 'archive\n' > "$work/downloads/package.apk"
printf '#!/bin/sh\nexit 0\n' > "$work/staging/usr/bin/app"
chmod 755 "$work/staging/usr/bin/app"

cache() {
    python3 "$repo/build-support/staging-cache.py" "$1" \
        --state "$work/cache-key" --staging "$work/staging" \
        --value alpine-v3.22 --source "$work/linked-source" \
        --metadata "$work/downloads" --executable usr/bin/app
}

if cache check; then exit 1; fi
cache record
cache check

printf 'changed\n' >> "$work/source/app.v"
if cache check; then exit 1; fi
cache record
cache check

printf 'changed\n' >> "$work/downloads/package.apk"
if cache check; then exit 1; fi
cache record
cache check

rm "$work/staging/usr/bin/app"
if cache check; then exit 1; fi

echo 'PASS application staging cache'
