#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
v=${V:-v}
command -v "$v" >/dev/null 2>&1 || {
    echo 'ERROR: V is required.' >&2
    exit 1
}
case "$(uname -m)" in
    arm64|aarch64) ;;
    *)
        echo 'SKIP: executing the test Mach-O requires an AArch64 host'
        exit 0
        ;;
esac

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
"$root/compat/macos/apps/Calculator/build.sh" "$work/Calculator.app" >/dev/null
mkdir "$work/runtime"
ln -s "$root/desktop/cocoa.v" "$work/runtime/cocoa.v"
ln -s "$root/tests/macos/runtime_test.v" "$work/runtime/main.v"
printf "Module { name: 'cocoa_runtime_test' }\n" > "$work/runtime/v.mod"

"$v" -gc none -manualfree -enable-globals -d ui2_headless \
    -path "@vlib|@vmodules|$root|$root/third_party" \
    -o "$work/runtime-test" "$work/runtime"
"$work/runtime-test" "$work/Calculator.app"
