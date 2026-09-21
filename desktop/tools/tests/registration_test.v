// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

module main

import os
import ui2

fn registration_test_element_named(root ui2.Element, name string) ?ui2.Element {
	if root.id == name || root.action_id == name {
		return root
	}
	for child in root.children {
		if found := registration_test_element_named(child, name) {
			return found
		}
	}
	return none
}

fn registration_test_has_action_prefix(root ui2.Element, prefix string) bool {
	if root.action_id.starts_with(prefix) {
		return true
	}
	for child in root.children {
		if registration_test_has_action_prefix(child, prefix) {
			return true
		}
	}
	return false
}

fn registration_test_home(name string) string {
	home := os.join_path(os.temp_dir(), 'vinix-registration-${name}-${os.getpid()}')
	os.mkdir(home) or { panic(err) }
	return home
}

fn registration_test_desktop() Desktop {
	return Desktop{
		canvas: Canvas{
			width:  1024
			height: 720
			scale:  1
		}
	}
}

fn test_registration_form_is_the_only_first_launch_surface() {
	desktop := registration_test_desktop()
	mut state := new_registration_state()
	defer { state.close() }
	begin_frame_elements()
	root := state.element(&desktop)
	defer { free_tree(root) }

	assert root.kind == .screen
	assert registration_test_element_named(root, 'registration.window') != none
	name := registration_test_element_named(root, action_registration_name) or {
		panic('missing name field')
	}
	password := registration_test_element_named(root, action_registration_password) or {
		panic('missing password field')
	}
	confirm := registration_test_element_named(root, action_registration_confirm) or {
		panic('missing confirm field')
	}
	assert name.kind == .text_field
	assert password.kind == .text_field
	assert confirm.kind == .text_field
	assert registration_test_element_named(root, action_registration_create) != none
	assert registration_test_element_named(root, 'taskbar') == none
	assert !registration_test_has_action_prefix(root, 'task.')
	assert !registration_test_has_action_prefix(root, 'shortcut.')
	assert !registration_test_has_action_prefix(root, 'win.')
}

fn test_registration_caret_is_drawn_by_the_ui2_text_field() {
	desktop := registration_test_desktop()
	mut state := new_registration_state()
	defer { state.close() }

	begin_frame_elements()
	root := state.element(&desktop)
	name := registration_test_element_named(root, action_registration_name) or {
		panic('missing name field')
	}
	password := registration_test_element_named(root, action_registration_password) or {
		panic('missing password field')
	}
	assert name.kind == .text_field
	assert name.text == '|'
	assert name.children.len == 0
	assert password.kind == .text_field
	assert password.text == 'Enter a password'
	assert registration_test_element_named(root, 'registration.caret') == none
	free_tree(root)

	state.key_input('alex\tsecret', '')
	begin_frame_elements()
	password_root := state.element(&desktop)
	name_inactive := registration_test_element_named(password_root, action_registration_name) or {
		panic('missing name field')
	}
	password_active := registration_test_element_named(password_root, action_registration_password) or {
		panic('missing password field')
	}
	assert name_inactive.kind == .text_field
	assert name_inactive.text == 'alex'
	assert password_active.kind == .text_field
	assert password_active.text == '******|'
	assert !password_active.text.contains('secret')
	assert registration_test_element_named(password_root, 'registration.caret') == none
	free_tree(password_root)
}

fn test_registration_keyboard_cannot_dismiss_setup() {
	mut state := new_registration_state()
	defer { state.close() }

	// Ctrl-Q normally closes an unfocused desktop, while Escape often dismisses
	// modal UI. Setup owns both and deliberately does nothing with them.
	state.key_input('\x11', '')
	state.key_input('\x1b[A', '')
	assert !state.complete
	assert state.field == .name
	assert state.name.len == 0
	assert registration_text(state.name_display) == '|'
}

fn test_registration_rejects_password_mismatch() {
	home := registration_test_home('mismatch')
	defer { os.rmdir_all(home) or {} }
	mut state := new_registration_state()
	defer { state.close() }

	state.key_input('Alice\tone\ttwo\r', home)
	assert !state.complete
	assert state.field == .confirm
	assert state.error == 'Passwords do not match.'
	assert !os.exists(desktop_user_record_path(home))
}

fn test_registration_persists_verifier_and_user_home() {
	home := registration_test_home('persist')
	defer { os.rmdir_all(home) or {} }
	mut state := new_registration_state()
	defer { state.close() }

	assert !desktop_user_registered(home)
	state.key_input('Alice Example\tcorrect horse battery staple\tcorrect horse battery staple\r',
		home)
	assert state.complete
	assert desktop_user_registered(home)
	name := desktop_load_user_name(home) or { panic('saved user did not reload') }
	assert name == 'Alice Example'
	unsafe { name.free() }

	path := desktop_user_record_path(home)
	record := os.read_file(path)!
	assert !record.contains('correct horse battery staple')
	assert record.contains('kdf=scrypt')
	assert record.contains('salt=')
	assert record.contains('hash=')
	info := os.stat(path)!
	assert info.mode & 0o777 == 0o600

	user_home := desktop_user_home_path(home, 'Alice Example')
	defer { unsafe { user_home.free() } }
	assert user_home.ends_with('/alice-example')
	assert os.is_dir(user_home)
	home_info := os.stat(user_home)!
	assert home_info.mode & 0o777 == registration_user_home_mode

	// Profiles written by the first registration implementation did not have a
	// home directory. A later launch repairs that profile rather than asking the
	// user to register again.
	os.rmdir(user_home)!
	assert !os.exists(user_home)
	assert desktop_user_registered(home)
	assert os.is_dir(user_home)
	repaired := os.stat(user_home)!
	assert repaired.mode & 0o777 == registration_user_home_mode
}
