#!/bin/sh
# Compile the fixture with the exact reviewed production backend and real
# native GLib/libsoup/SQLite libraries plus generated genuine JNI declarations.
set -eu
if [ "$#" -ne 1 ]; then
    echo "usage: $0 /path/to/patched-ATL/src/api-impl-jni/widgets/android_webkit_CookieManager.c" >&2
    exit 2
fi
task_source=$(realpath "$1")
task_expected=43a7357a611fd7bae1dad314850e7ed9b5d58d2f1c48b5e83386b039f7abef85
task_actual=$(sha256sum "$task_source" | cut -d ' ' -f 1)
if [ "$task_actual" != "$task_expected" ]; then
    echo "cookie-store-test: production source checksum differs from the reviewed fixture input" >&2
    exit 2
fi
task_jni_root=${ATL_COOKIE_JNI_ROOT:-$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")/include}
test -r "$task_jni_root/jni.h"
pkg-config --exists libsoup-3.0 sqlite3
task_directory=$(mktemp -d)
trap 'rm -rf "$task_directory"' EXIT HUP INT TERM
task_tests=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
${ATL_COOKIE_CC:-cc} -O2 -Wall -Wextra -Werror -Wl,-z,max-page-size=65536 \
    "-DATL_COOKIE_SOURCE=\"$task_source\"" \
    -I"$task_jni_root" -I"$task_jni_root/linux" \
    "$task_tests/atl-cookie-store-test.c" \
    $(pkg-config --cflags --libs libsoup-3.0 sqlite3) -o "$task_directory/cookie-store-test"
"$task_directory/cookie-store-test"
