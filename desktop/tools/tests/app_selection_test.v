// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

module main

import os
import ui2

fn app_selection_test_element(root ui2.Element, name string) ?ui2.Element {
	if root.id == name || root.action_id == name {
		return root
	}
	for child in root.children {
		if found := app_selection_test_element(child, name) {
			return found
		}
	}
	return none
}

fn app_selection_test_has_action_prefix(root ui2.Element, prefix string) bool {
	if root.action_id.starts_with(prefix) || root.id.starts_with(prefix) {
		return true
	}
	for child in root.children {
		if app_selection_test_has_action_prefix(child, prefix) {
			return true
		}
	}
	return false
}

fn app_selection_test_has_image(root ui2.Element, path string) bool {
	if root.image_path == path {
		return true
	}
	return root.children.any(app_selection_test_has_image(it, path))
}

fn app_selection_test_has_text(root ui2.Element, text string) bool {
	if root.text == text {
		return true
	}
	return root.children.any(app_selection_test_has_text(it, text))
}

fn app_selection_test_desktop() Desktop {
	return Desktop{
		canvas: Canvas{
			width:  1024
			height: 720
			scale:  1
		}
	}
}

// Host tests must not depend on which of these happen to exist on the build
// machine, so start from a state where nothing is installed.
fn app_selection_test_state() AppSelectionState {
	mut state := new_app_selection_state()
	for i in 0 .. state.installed.len {
		state.installed[i] = false
	}
	state.focus = 0
	return state
}

fn app_selection_test_button_label(state AppSelectionState) string {
	desktop := app_selection_test_desktop()
	begin_frame_elements()
	root := state.element(&desktop)
	defer { free_tree(root) }
	button := app_selection_test_element(root, action_apps_install) or {
		panic('missing install button')
	}
	return button.text
}

fn test_app_selection_offers_the_optional_apps_this_machine_can_install() {
	assert first_run_app_catalogue.map(it.title) == ['Firefox', 'Chromium', 'VOffice', 'Minecraft']
	assert first_run_app_catalogue.map(it.package_name) == ['firefox', 'chromium', 'voffice',
		'minecraft']
	$if arm64 {
		assert first_run_apps.map(it.title) == ['Firefox', 'Chromium', 'VOffice', 'Minecraft']
	} $else {
		// VOffice and Minecraft are only packaged for AArch64.
		assert first_run_apps.map(it.title) == ['Firefox', 'Chromium']
	}
	assert app_selection_install_labels.len >= first_run_apps.len + 1

	desktop := app_selection_test_desktop()
	state := app_selection_test_state()
	begin_frame_elements()
	root := state.element(&desktop)
	defer { free_tree(root) }

	assert root.kind == .screen
	assert app_selection_test_element(root, 'apps.window') != none
	for app in first_run_apps {
		row := app_selection_test_element(root, app.action) or { panic('missing ${app.title}') }
		assert row.clickable && row.enabled
		assert !app_selection_test_has_image(row, 'builtin:check')
	}
	assert app_selection_test_element(root, action_apps_install) != none
	assert app_selection_test_element(root, 'taskbar') == none
	assert !app_selection_test_has_action_prefix(root, 'task.')
	assert !app_selection_test_has_action_prefix(root, 'shortcut.')
	assert !app_selection_test_has_action_prefix(root, 'win.')
}

fn test_app_selection_clicks_toggle_apps_and_confirm() {
	mut state := app_selection_test_state()
	assert app_selection_test_button_label(state) == 'Continue'
	assert state.packages().len == 0

	state.handle_action('apps.toggle.chromium')
	state.handle_action('apps.toggle.firefox')
	state.handle_action('apps.toggle.chromium')
	assert state.selected_count() == 1
	assert app_selection_test_button_label(state) == 'Install 1 app'
	desktop := app_selection_test_desktop()
	begin_frame_elements()
	root := state.element(&desktop)
	firefox := app_selection_test_element(root, 'apps.toggle.firefox') or { panic('missing row') }
	chromium := app_selection_test_element(root, 'apps.toggle.chromium') or { panic('missing row') }
	assert app_selection_test_has_image(firefox, 'builtin:check')
	assert !app_selection_test_has_image(chromium, 'builtin:check')
	free_tree(root)

	state.handle_action('apps.toggle.chromium')
	assert app_selection_test_button_label(state) == 'Install 2 apps'
	// Installed in the order offered, not the order clicked.
	assert state.packages() == ['firefox', 'chromium']
	assert !state.complete
	$if arm64 {
		state.handle_action('apps.toggle.minecraft')
		assert state.packages() == ['firefox', 'chromium', 'minecraft']
		state.handle_action('apps.toggle.minecraft')
	}

	state.handle_action('unrelated.action')
	assert state.selected_count() == 2
	state.handle_action(action_apps_install)
	assert state.complete
}

fn test_app_selection_skips_apps_the_image_already_has() {
	mut state := app_selection_test_state()
	state.installed[0] = true
	state.focus = state.next_available(-1, 1)
	assert state.focus == 1
	state.handle_action('apps.toggle.firefox')
	assert state.selected_count() == 0
	assert state.packages().len == 0

	desktop := app_selection_test_desktop()
	begin_frame_elements()
	root := state.element(&desktop)
	defer { free_tree(root) }
	firefox := app_selection_test_element(root, 'apps.toggle.firefox') or {
		panic('missing Firefox row')
	}
	assert !firefox.clickable && !firefox.enabled
	assert app_selection_test_has_text(firefox, 'Installed')
	// Keyboard focus starts on the first app that can still be chosen.
	focus := app_selection_test_element(root, 'apps.focus') or { panic('missing focus ring') }
	chromium := app_selection_test_element(root, 'apps.toggle.chromium') or {
		panic('missing Chromium row')
	}
	assert focus.frame.y == chromium.frame.y - 1

	for i in 0 .. state.installed.len {
		state.installed[i] = true
	}
	assert state.all_installed()
	assert state.next_available(0, 1) == -1
}

fn test_app_selection_is_keyboard_driven() {
	mut state := app_selection_test_state()
	$if arm64 {
		state.installed[1] = true

		state.key_input(' ')
		assert state.selected[0]
		// Tab and Down skip the installed Chromium row; Up wraps back around.
		state.key_input('\t')
		assert state.focus == 2
		state.key_input('\x1b[B')
		assert state.focus == 3
		state.key_input('\x1b[B')
		assert state.focus == 0
		state.key_input('\x1b[A')
		assert state.focus == 3
		state.key_input('3')
		assert state.selected[2] && state.focus == 2
		state.key_input('2')
		assert !state.selected[1]
		// Control chords and stray escapes never reach desktop shortcuts or the
		// selection.
		state.key_input('\x10\x11\x1b')
		assert state.packages() == ['firefox', 'voffice']
	} $else {
		state.key_input(' ')
		assert state.selected[0]
		// Tab moves to Chromium; Down wraps back to Firefox and Up to Chromium.
		state.key_input('\t')
		assert state.focus == 1
		state.key_input('\x1b[B')
		assert state.focus == 0
		state.key_input('\x1b[A')
		assert state.focus == 1
		state.key_input('2')
		assert state.selected[1] && state.focus == 1
		// A number past the offered apps is ignored.
		state.key_input('3')
		// Control chords and stray escapes never reach desktop shortcuts or the
		// selection.
		state.key_input('\x10\x11\x1b')
		assert state.packages() == ['firefox', 'chromium']
	}
	assert !state.complete

	state.key_input('\r')
	assert state.complete
}

fn test_app_selection_pending_marker_lifecycle() {
	home := os.join_path(os.temp_dir(), 'vinix-app-selection-${os.getpid()}')
	os.mkdir(home) or { panic(err) }
	defer { os.rmdir_all(home) or {} }

	assert !desktop_app_selection_pending(home)
	assert desktop_mark_app_selection_pending(home)
	assert desktop_app_selection_pending(home)
	desktop_finish_app_selection(home)
	assert !desktop_app_selection_pending(home)
}

fn test_first_run_install_command_accepts_only_offered_packages() {
	assert first_run_install_command('') == ''
	assert first_run_install_command('gimp ; rm -rf /') == ''
	command := first_run_install_command('chromium firefox\nchromium firefox;reboot\n')
	assert command.contains('for app in chromium firefox; do pkg install "\$app"')
	assert !command.contains('reboot')
	assert command.ends_with('exec /bin/zsh -i')
	$if !arm64 {
		// Not offered here, so not installed either.
		assert first_run_install_command('voffice minecraft') == ''
	}
}

fn test_first_run_install_command_reports_failures_and_continues() {
	work := os.join_path(os.temp_dir(), 'vinix-first-run-install-${os.getpid()}')
	os.mkdir_all(os.join_path(work, 'bin')) or { panic(err) }
	defer { os.rmdir_all(work) or {} }
	fake_pkg := os.join_path(work, 'bin', 'pkg')
	log := os.join_path(work, 'pkg.log')
	os.write_file(fake_pkg, '#!/bin/sh\necho "\$*" >> "${log}"\n[ "\$2" != chromium ]\n') or {
		panic(err)
	}
	os.chmod(fake_pkg, 0o755) or { panic(err) }

	command := first_run_install_command('firefox chromium')
	// Stop where the Terminal would hand over to the interactive shell.
	script := command.replace('exec /bin/zsh -i', 'exit 0')
	result := os.execute('PATH="${work}/bin:\$PATH" sh -c ${os.quoted_path(script)}')
	assert result.exit_code == 0
	assert os.read_file(log) or { '' } == 'install firefox\ninstall chromium\n'
	assert result.output.contains('Installing the apps chosen during setup: firefox chromium')
	assert result.output.contains('Not installed: chromium. Run pkg install chromium to try again.')

	success := first_run_install_command('firefox').replace('exec /bin/zsh -i', 'exit 0')
	ok := os.execute('PATH="${work}/bin:\$PATH" sh -c ${os.quoted_path(success)}')
	assert ok.exit_code == 0
	assert ok.output.contains('The selected apps are installed.')
}
