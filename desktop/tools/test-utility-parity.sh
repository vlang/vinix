#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Behavioral coverage for the desktop utility workflows in UTILITIES.md.
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
printf "Module { name: 'utility_parity_tests' }\n" > "$work/ui/v.mod"
# Compile related model and UI cases together, with the same complete desktop
# and compiler as production. Each file can also run independently when staged.
"$root/build-support/run-v-tool.sh" "$root/desktop/tools/native-utility-source.v" merge-parity "$root" "$work/ui/utility_parity_test.v"
"$v" -new-compiler -nocache -gc none -manualfree -enable-globals -stats -d ui2_headless \
    -path "@vlib|@vmodules|$work/modules|$root|$root/third_party" "$work/ui/utility_parity_test.v"

cp "$root/desktop/tools/tests/heap_tracker.h" "$work/ui/"
for test in calculator_features_memory utility_parity_memory calendar_search_memory editor_selection_memory \
            text_copy_client_memory terminal_selection_memory clock_utility_memory capture_features_memory; do
    cp "$root/desktop/tools/tests/${test}_test.v" "$work/ui/"
    "$v" -new-compiler -nocache -cc clang -gc none -manualfree -enable-globals -stats -d ui2_headless -d track_heap \
        -path "@vlib|@vmodules|$work/modules|$root|$root/third_party" "$work/ui/${test}_test.v"
    rm "$work/ui/${test}_test.v"
done
