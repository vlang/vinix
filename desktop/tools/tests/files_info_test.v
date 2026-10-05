// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

fn files_info_test_find(element ui2.Element, id string) ?ui2.Element {
	if element.id == id { return element }
	for child in element.children {
		if found := files_info_test_find(child, id) { return found }
	}
	return none
}

fn files_info_test_root(name string) string {
	root := os.join_path(os.temp_dir(), name)
	os.rmdir_all(root) or {}
	os.mkdir_all(root) or { panic(err) }
	os.write_file(os.join_path(root, 'notes.txt'), 'hello info') or { panic(err) }
	os.chmod(os.join_path(root, 'notes.txt'), 0o640) or { panic(err) }
	os.mkdir_all(os.join_path(root, 'folder')) or { panic(err) }
	return root
}

fn test_files_info_permission_text_includes_octal_and_special_bits() {
	assert files_info_permissions(0o640) == '0640 (rw-r-----)'
	assert files_info_permissions(0o755) == '0755 (rwxr-xr-x)'
	assert files_info_permissions(0o4755) == '4755 (rwsr-xr-x)'
	assert files_info_permissions(0o2640) == '2640 (rw-r-S---)'
	assert files_info_permissions(0o1777) == '1777 (rwxrwxrwt)'
	assert files_info_permissions(0o1000) == '1000 (--------T)'
	assert files_info_permissions(u32(C.S_IFDIR) | 0o755) == '0755 (rwxr-xr-x)'
}

fn test_files_info_reads_real_file_metadata_and_closes_owned_strings() {
	root := files_info_test_root('vinix-files-info-metadata-test')
	defer { os.rmdir_all(root) or {} }
	path := os.join_path(root, 'notes.txt')
	mut info := FilesInfoPanel{}
	info.read(path, 0)
	assert info.open && info.path == path && info.name == 'notes.txt'
	assert info.error_key == ''
	assert info.size == 10
	assert info.permissions == '0640 (rw-r-----)'
	assert info.mode & u32(C.S_IFMT) == u32(C.S_IFREG)
	assert info.owner.contains(' / ')
	assert info.modified > 0 && info.accessed > 0 && info.changed > 0
	assert info.modified_text.len > 0 && info.accessed_text.len > 0 && info.changed_text.len > 0
	info.close()
	assert !info.open && info.path == '' && info.permissions == ''
	info.close()
	info.read(root, 0)
	assert info.mode & u32(C.S_IFMT) == u32(C.S_IFDIR)
	assert info.error_key == ''
	info.close()
}

fn test_files_info_reports_link_target_even_when_target_does_not_exist() {
	root := files_info_test_root('vinix-files-info-link-test')
	defer { os.rmdir_all(root) or {} }
	link := os.join_path(root, 'link')
	os.symlink('missing-target.txt', link) or { panic(err) }
	mut info := FilesInfoPanel{}
	info.read(link, 0)
	assert info.open && info.error_key == ''
	assert info.mode & u32(C.S_IFMT) == u32(C.S_IFLNK)
	assert info.link_target == 'missing-target.txt'
	assert info.size == u64('missing-target.txt'.len)
	info.close()
	info.read(os.join_path(root, 'nonexistent'), 0)
	assert info.open && info.error_key == 'files.info.unavailable'
	info.close()
}

fn test_files_info_uses_list_column_and_active_commander_selection() {
	root := files_info_test_root('vinix-files-info-selection-test')
	defer { os.rmdir_all(root) or {} }
	path := os.join_path(root, 'notes.txt')
	mut app := FileBrowserApp{}
	app.browser.read(root.clone())
	app.browser.selected_row = files_entry_named(app.browser.entries, 'notes.txt')
	app.handle(files_action_info)!
	assert app.info.path == path
	app.handle(files_action_info_close)!
	app.browser.selected_row = -1
	app.open_info()
	assert app.info.path == root
	app.info.close()
	app.set_view_mode(.columns)
	last := app.columns.len - 1
	app.columns[last].selected_row = files_entry_named(app.columns[last].browser.entries, 'notes.txt')
	app.open_info()
	assert app.info.path == path
	app.info.close()
	app.set_view_mode(.commander)
	app.active_pane = 1
	app.dual_right.selected_row = files_entry_named(app.dual_right.entries, 'notes.txt')
	app.dual_left.selected_row = files_entry_named(app.dual_left.entries, 'folder')
	app.open_info()
	assert app.info.path == path
	app.info.close()
}

fn test_files_info_keyboard_and_modal_preserve_folder_navigation_and_tab() {
	root := files_info_test_root('vinix-files-info-modal-test')
	defer { os.rmdir_all(root) or {} }
	mut app := FileBrowserApp{}
	app.browser.read(root.clone())
	assert !app.info_key_input('\t')
	assert app.info_key_input('\x07')
	assert app.info.open
	app.handle(files_action_up)!
	assert app.current_path() == root
	app.pointer_event(.down, .back, 0, 0, 0, 700, 500)
	assert app.current_path() == root
	assert app.info_key_input('typing is ignored')
	assert app.info_key_input('\x1b')
	assert !app.info.open
	assert app.info_key_input('\x1b[105;9u')
	assert app.info.open
	app.handle(files_action_info_close)!
	assert !app.info.open
}

fn test_files_info_toolbar_and_overlay_render_under_both_desktop_themes() {
	root := files_info_test_root('vinix-files-info-ui-test')
	defer {
		files_follow_theme(.default_)
		os.rmdir_all(root) or {}
	}
	mut app := FileBrowserApp{}
	app.browser.read(root.clone())
	for theme in [ThemeKind.default_, ThemeKind.macos] {
		files_follow_theme(theme)
		begin_frame_elements()
		tree := app.build(ui2.rect(0, 0, 800, 500))!
		assert files_info_test_find(tree, files_action_info) != none
		app.handle(files_action_info)!
		begin_frame_elements()
		opened := app.build(ui2.rect(0, 0, 800, 500))!
		assert files_info_test_find(opened, 'files.info.panel') != none
		assert files_info_test_find(opened, 'files.info.blocker') != none
		assert files_info_test_find(opened, files_action_info_close) != none
		app.handle(files_action_info_close)!
	}
}

fn test_files_context_info_keyboard_keeps_commander_tab_and_blocks_mouse_back() {
	root := files_info_test_root('vinix-files-info-context-test')
	defer {
		files_follow_theme(.default_)
		os.rmdir_all(root) or {}
	}
	mut app := FilesContextApp{}
	app.files.browser.read(root.clone())
	app.files.set_view_mode(.commander)
	app.key_input('\t')
	assert app.files.active_pane == 1
	app.set_context_path(os.join_path(root, 'notes.txt'))
	app.key_input('\x07')
	assert app.files.info.open
	app.handle(file_context_delete)!
	assert os.exists(os.join_path(root, 'notes.txt'))
	app.handle(files_action_up)!
	assert app.files.current_path() == root
	app.pointer_event(.down, .back, 0, 0, 0, 800, 500)
	assert app.files.current_path() == root
	app.key_input('\x1b')
	assert !app.files.info.open
	app.key_input('\t')
	assert app.files.active_pane == 0
	app.key_input('\x07')
	app.close_app()
	assert !app.files.info.open
}
