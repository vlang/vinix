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
	assert !desktop_app_selection_pending(home)
	state.key_input('Alice Example\tcorrect horse battery staple\tcorrect horse battery staple\r',
		home)
	assert state.complete
	assert desktop_user_registered(home)
	// Creating the user is what schedules the first-run app choice.
	assert desktop_app_selection_pending(home)
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

	user_home := desktop_user_storage_path(home, 'Alice Example')
	defer { unsafe { user_home.free() } }
	assert user_home == os.join_path(home, 'home', 'alice-example')
	assert os.is_dir(user_home)
	home_info := os.stat(user_home)!
	assert home_info.mode & 0o777 == registration_user_home_mode
	// Creating the user creates the usual folders in its home.
	for folder in desktop_user_folders {
		assert os.is_dir(os.join_path(user_home, folder.name))
	}

	// Profiles written by the first registration implementation did not have a
	// home directory. A later launch repairs that profile rather than asking the
	// user to register again.
	os.rmdir_all(user_home)!
	assert !os.exists(user_home)
	assert desktop_user_registered(home)
	assert os.is_dir(user_home)
	repaired := os.stat(user_home)!
	assert repaired.mode & 0o777 == registration_user_home_mode
	assert os.is_dir(os.join_path(user_home, 'Downloads'))
}

fn registration_test_register(home string, name string) {
	mut state := new_registration_state()
	defer { state.close() }
	state.key_input('${name}\tsecret\tsecret\r', home)
	assert state.complete
}

fn test_registered_user_home_is_linked_from_home_directory() {
	root := registration_test_home('link')
	defer { os.rmdir_all(root) or {} }
	home := os.join_path(root, 'root')
	users := os.join_path(root, 'home')
	os.mkdir(home)!
	// Folders the desktop used to keep in /root itself.
	os.mkdir(os.join_path(home, 'Desktop'))!
	os.write_file(os.join_path(home, 'Desktop', 'note.txt'), 'kept')!
	os.mkdir(os.join_path(home, 'Downloads'))!
	registration_test_register(home, 'Alice Example')

	storage := desktop_user_storage_path(home, 'Alice Example')
	defer { unsafe { storage.free() } }
	user_home := desktop_prepare_user_home(home, users)
	defer { unsafe { user_home.free() } }
	assert user_home == os.join_path(users, 'alice-example')
	assert os.is_link(user_home)
	assert os.readlink(user_home)! == storage
	for folder in desktop_user_folders {
		assert os.is_dir(os.join_path(user_home, folder.name))
		assert !os.exists(os.join_path(home, folder.name))
	}
	assert os.read_file(os.join_path(user_home, 'Desktop', 'note.txt'))! == 'kept'

	dirs := os.read_file(os.join_path(home, desktop_user_dirs_name))!
	assert dirs.contains('XDG_DESKTOP_DIR="${user_home}/Desktop"\n')
	assert dirs.contains('XDG_DOWNLOAD_DIR="${user_home}/Downloads"\n')
	assert dirs.contains('XDG_DOCUMENTS_DIR="${user_home}/Documents"\n')

	// /home may be in RAM: a later start makes the link again, replaces one
	// that points elsewhere and keeps a user-dirs file that is already there.
	os.write_file(os.join_path(home, desktop_user_dirs_name), 'mine\n')!
	os.rm(user_home)!
	os.symlink(home, user_home)!
	again := desktop_prepare_user_home(home, users)
	defer { unsafe { again.free() } }
	assert again == user_home
	assert os.readlink(user_home)! == storage
	assert os.read_file(os.join_path(home, desktop_user_dirs_name))! == 'mine\n'

	// Application processes find the same home without changing anything.
	found := desktop_find_user_home(home, users)
	defer { unsafe { found.free() } }
	assert found == user_home
	os.rm(user_home)!
	stored := desktop_find_user_home(home, users)
	defer { unsafe { stored.free() } }
	assert stored == storage
	assert !os.exists(user_home)

	desktop_use_user_home(again.clone())
	assert desktop_user_home == user_home
	assert desktop_directory == os.join_path(user_home, 'Desktop')
	assert files_locations[0].path == user_home
	assert files_locations.any(it.path == os.join_path(user_home, 'Downloads'))
}

fn test_user_home_falls_back_to_its_storage_when_the_name_is_taken() {
	root := registration_test_home('taken')
	defer { os.rmdir_all(root) or {} }
	home := os.join_path(root, 'root')
	users := os.join_path(root, 'home')
	os.mkdir(home)!
	os.mkdir(users)!
	os.mkdir(os.join_path(users, 'bob'))!
	os.write_file(os.join_path(users, 'bob', 'theirs'), 'x')!
	registration_test_register(home, 'Bob')

	user_home := desktop_prepare_user_home(home, users)
	defer { unsafe { user_home.free() } }
	storage := desktop_user_storage_path(home, 'Bob')
	defer { unsafe { storage.free() } }
	assert user_home == storage
	assert os.is_dir(os.join_path(user_home, 'Desktop'))
	assert os.exists(os.join_path(users, 'bob', 'theirs'))
	assert !os.is_link(os.join_path(users, 'bob'))
}
