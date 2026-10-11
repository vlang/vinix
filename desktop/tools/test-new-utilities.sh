#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Native image, log, information, storage and productivity models and IPC.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
v=${V:-v}
"$root/build-support/run-v-tool.sh" "$root/build-support/dictionary/test-data.v"
"$root/build-support/run-v-tool.sh" "$root/desktop/tools/utilitysource/core_test.v"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
"$root/desktop/tools/stage_ui2" "$work/modules/ui2" "$root/third_party/ui2" "$root/desktop/tools/ui2_headless_bounds.v"
"$root/desktop/tools/stage_app" "$work/ui" "$root/desktop" "$root/third_party/ui2/examples/calculator" >/dev/null
"$root/desktop/tools/stage_host_gpu" "$work/ui" --v "$v"
"$root/build-support/run-v-tool.sh" "$root/desktop/tools/native-utility-source.v" materialize "$work/ui"
rm "$work/ui/main.v"
printf "Module { name: 'native_utility_tests' }\n" > "$work/ui/v.mod"
"$root/build-support/run-v-tool.sh" "$root/desktop/tools/native-utility-source.v" merge "$root" "$work/ui/native_utility_test.v"
"$v" -new-compiler -nocache -cc clang -gc none -manualfree -enable-globals -stats -d ui2_headless \
    -path "@vlib|@vmodules|$work/modules|$root|$root/third_party" "$work/ui/native_utility_test.v"
cp "$root/desktop/tools/tests/heap_tracker.h" "$work/ui/"
for test in preview_app_memory console_app_memory system_information_memory native_paste_memory \
            archive_app_memory disk_utility_memory backup_app_memory native_poll_memory \
            notes_app_memory reminders_app_memory grapher_app_memory calculator_features_memory \
            color_meter_memory color_clipboard_memory clock_utility_memory native_close_memory start_menu_paging_memory \
            dictionary_memory editor_workflow_memory editor_selection_memory calendar_ics_memory calendar_search_memory \
            utility_parity_memory files_trash_memory \
            text_copy_client_memory terminal_selection_memory; do
    cp "$root/desktop/tools/tests/${test}_test.v" "$work/ui/"
    "$v" -new-compiler -nocache -cc clang -gc none -manualfree -enable-globals -stats -d ui2_headless -d track_heap \
        -path "@vlib|@vmodules|$work/modules|$root|$root/third_party" "$work/ui/${test}_test.v"
    rm "$work/ui/${test}_test.v"
done
if [ "${SKIP_NATIVE_IPC:-0}" != 1 ]; then
    cp "$root/desktop/tools/tests/app_process_integration.v" "$work/ui/main.v"
    "$v" -new-compiler -nocache -cc clang -gc none -manualfree -enable-globals -d ui2_headless \
        -path "@vlib|@vmodules|$work/modules|$root|$root/third_party" -o "$work/app-process-integration" "$work/ui"
    "$work/app-process-integration"
fi
