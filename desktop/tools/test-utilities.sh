#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
v=${V:-v}
command -v "$v" >/dev/null 2>&1 || {
    echo 'ERROR: V is required.' >&2
    exit 1
}
[ -f "$root/third_party/ui2/v.mod" ] || {
    echo 'ERROR: utility UI tests require third_party/ui2.' >&2
    exit 1
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
python3 "$root/desktop/tools/stage_ui2.py" \
    "$work/modules/ui2" "$root/third_party/ui2" \
    "$root/desktop/tools/ui2_headless_bounds.v"
mkdir "$work/ui"
python3 "$root/desktop/tools/stage_app.py" "$work/ui" "$root/desktop" \
    "$root/third_party/ui2/examples/calculator" >/dev/null
rm -f "$work/ui/main.v"
cp "$root/desktop/tools/tests/utilities_test.v" "$work/ui/"
printf "Module { name: 'utility_tests' }\n" > "$work/ui/v.mod"

# Rebuild handoff owns a one-shot terminal snapshot as well as its elapsed-time
# record. Keep its parser and row serialization cases isolated from the broad
# utility suite so this test file does not overlap application catalog changes.
cp "$root/desktop/tools/tests/terminal_rebuild_test.v" "$work/ui/"
"$v" -new-compiler -nocache -gc none -manualfree -enable-globals -stats -d ui2_headless \
    -path "@vlib|@vmodules|$work/modules|$root|$root/third_party" "$work/ui/terminal_rebuild_test.v"
rm -f "$work/ui/terminal_rebuild_test.v"

# The staged Calculator uses ui2's compile-time `$vml` lowering, which is
# provided by V's current compiler. Keep test and production compilation on
# the same frontend.
"$v" -new-compiler -nocache -gc none -manualfree -enable-globals -stats -d ui2_headless \
    -path "@vlib|@vmodules|$work/modules|$root|$root/third_party" "$work/ui/utilities_test.v"
rm -f "$work/ui/utilities_test.v"

cp "$root/desktop/tools/tests/taskbar_pinning_test.v" "$work/ui/"
"$v" -new-compiler -nocache -gc none -manualfree -enable-globals -stats -d ui2_headless \
    -path "@vlib|@vmodules|$work/modules|$root|$root/third_party" "$work/ui/taskbar_pinning_test.v"
rm -f "$work/ui/taskbar_pinning_test.v"

# Quick Launch shares the switcher's global keyboard path. Keep its Cmd-Space,
# query filtering and modal overlay cases isolated from the broader utility
# suite so sequence state cannot leak between tests.
cp "$root/desktop/tools/tests/quick_launch_test.v" "$work/ui/"
"$v" -new-compiler -nocache -gc none -manualfree -enable-globals -stats -d ui2_headless \
    -path "@vlib|@vmodules|$work/modules|$root|$root/third_party" "$work/ui/quick_launch_test.v"
rm -f "$work/ui/quick_launch_test.v"

# Keep the title-bar gesture cases in their own test entry point so their
# synthetic pointer timing does not add state to the broader utility suite.
cp "$root/desktop/tools/tests/titlebar_click_test.v" "$work/ui/"
"$v" -new-compiler -nocache -gc none -manualfree -enable-globals -stats -d ui2_headless \
    -path "@vlib|@vmodules|$work/modules|$root|$root/third_party" "$work/ui/titlebar_click_test.v"
rm -f "$work/ui/titlebar_click_test.v"

# Workspaces and keyboard tiling are compositor state rather than application
# behavior. Keep their focus, visibility, pager and geometry cases together.
cp "$root/desktop/tools/tests/workspace_test.v" "$work/ui/"
"$v" -new-compiler -nocache -gc none -manualfree -enable-globals -stats -d ui2_headless \
    -path "@vlib|@vmodules|$work/modules|$root|$root/third_party" "$work/ui/workspace_test.v"
rm -f "$work/ui/workspace_test.v"

# First-launch registration owns the whole compositor until its profile is
# durable. Exercise its exclusive tree, non-dismissible input and verifier file
# separately because it intentionally never enters the normal desktop loop.
cp "$root/desktop/tools/tests/registration_test.v" "$work/ui/"
"$v" -new-compiler -nocache -gc none -manualfree -enable-globals -stats -d ui2_headless \
    -path "@vlib|@vmodules|$work/modules|$root|$root/third_party" "$work/ui/registration_test.v"
rm -f "$work/ui/registration_test.v"

# The app picker follows registration with the same exclusive ownership of the
# display and keyboard, then hands its choice to the first Terminal.
cp "$root/desktop/tools/tests/app_selection_test.v" "$work/ui/"
"$v" -new-compiler -nocache -gc none -manualfree -enable-globals -stats -d ui2_headless \
    -path "@vlib|@vmodules|$work/modules|$root|$root/third_party" "$work/ui/app_selection_test.v"
rm -f "$work/ui/app_selection_test.v"

# Miller columns use real directory listings and their own retained navigation
# state, so exercise them independently from the broader utility model tests.
cp "$root/desktop/tools/tests/files_columns_test.v" "$work/ui/"
"$v" -new-compiler -nocache -gc none -manualfree -enable-globals -stats -d ui2_headless \
    -path "@vlib|@vmodules|$work/modules|$root|$root/third_party" "$work/ui/files_columns_test.v"
rm -f "$work/ui/files_columns_test.v"

cp "$root/desktop/tools/tests/files_sidebar_test.v" "$work/ui/"
"$v" -new-compiler -nocache -gc none -manualfree -enable-globals -stats -d ui2_headless \
    -path "@vlib|@vmodules|$work/modules|$root|$root/third_party" "$work/ui/files_sidebar_test.v"
rm -f "$work/ui/files_sidebar_test.v"

cp "$root/desktop/tools/tests/files_settings_test.v" "$work/ui/"
"$v" -new-compiler -nocache -gc none -manualfree -enable-globals -stats -d ui2_headless \
    -path "@vlib|@vmodules|$work/modules|$root|$root/third_party" "$work/ui/files_settings_test.v"
rm -f "$work/ui/files_settings_test.v"

cp "$root/desktop/tools/tests/files_commander_test.v" "$work/ui/"
"$v" -new-compiler -nocache -gc none -manualfree -enable-globals -stats -d ui2_headless \
    -path "@vlib|@vmodules|$work/modules|$root|$root/third_party" "$work/ui/files_commander_test.v"
rm -f "$work/ui/files_commander_test.v"

cp "$root/desktop/tools/tests/files_settings_process_integration.v" "$work/ui/main.v"
"$v" -new-compiler -nocache -gc none -manualfree -enable-globals -d ui2_headless \
    -path "@vlib|@vmodules|$work/modules|$root|$root/third_party" -o "$work/files-settings-process" "$work/ui"
"$work/files-settings-process"
rm -f "$work/ui/main.v"

cp "$root/desktop/tools/tests/files_quicklook_test.v" "$work/ui/"
"$v" -new-compiler -nocache -gc none -manualfree -enable-globals -stats -d ui2_headless \
    -path "@vlib|@vmodules|$work/modules|$root|$root/third_party" "$work/ui/files_quicklook_test.v"
rm -f "$work/ui/files_quicklook_test.v"

cp "$root/desktop/tools/tests/files_mouse_back_test.v" "$work/ui/"
"$v" -new-compiler -nocache -gc none -manualfree -enable-globals -stats -d ui2_headless \
    -path "@vlib|@vmodules|$work/modules|$root|$root/third_party" "$work/ui/files_mouse_back_test.v"
rm -f "$work/ui/files_mouse_back_test.v"

# Build a real executable as well as V's generated test runner. It execs
# itself twice in native-app mode and verifies UI, actions, state sync and
# clean shutdown across actual process boundaries.
cp "$root/desktop/tools/tests/app_process_integration.v" "$work/ui/main.v"
"$v" -new-compiler -nocache -gc none -manualfree -enable-globals -d ui2_headless \
    -path "@vlib|@vmodules|$work/modules|$root|$root/third_party" -o "$work/app-process-integration" "$work/ui"
"$work/app-process-integration"
