#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
v=${V:-v}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
"$root/desktop/tools/stage_ui2" "$work/modules/ui2" "$root/third_party/ui2" "$root/desktop/tools/ui2_headless_bounds.v"
"$root/desktop/tools/stage_app" "$work/ui" "$root/desktop" "$root/third_party/ui2/examples/calculator" >/dev/null
"$root/desktop/tools/stage_host_gpu" "$work/ui" --v "$v"
"$root/build-support/run-v-tool.sh" "$root/desktop/tools/native-utility-source.v" materialize "$work/ui"
rm "$work/ui/main.v"
printf "Module { name: 'activity_tests' }\n" > "$work/ui/v.mod"
# Compile the related cases together to validate their shared integration and
# avoid repeatedly compiling the entire desktop for each small test module.
"$root/build-support/run-v-tool.sh" "$root/desktop/tools/native-utility-source.v" merge-activity "$root" "$work/ui/activity_test.v"
"$v" -new-compiler -nocache -gc none -manualfree -enable-globals -stats -d ui2_headless \
    -path "@vlib|@vmodules|$work/modules|$root|$root/third_party" "$work/ui/activity_test.v"

cp "$root/desktop/tools/tests/heap_tracker.h" "$work/ui/"
for source in "$root/tests/activity_lifetime_test.v" "$root/desktop/tools/tests/activity_resources_memory_test.v" "$root/desktop/tools/tests/activity_preferences_memory_test.v"; do
    cp "$source" "$work/ui/"
    "$v" -new-compiler -nocache -cc clang -gc none -manualfree -enable-globals -stats -d ui2_headless -d track_heap \
        -path "@vlib|@vmodules|$work/modules|$root|$root/third_party" "$work/ui/$(basename "$source")"
done
