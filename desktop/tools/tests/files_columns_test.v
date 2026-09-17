// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

fn files_columns_tree_has_text(element ui2.Element, text string) bool {
	if element.text == text {
		return true
	}
	for child in element.children {
		if files_columns_tree_has_text(child, text) {
			return true
		}
	}
	return false
}

fn files_columns_entry_index(column &MillerColumn, name string) int {
	for index, entry in column.browser.entries {
		if entry.name == name {
			return index
		}
	}
	return -1
}

fn test_file_browser_miller_columns_follow_directory_selection() {
	root := os.join_path(os.temp_dir(), 'vinix-files-columns-test')
	os.rmdir_all(root) or {}
	os.mkdir_all(os.join_path(root, 'alpha', 'nested')) or { panic(err) }
	os.mkdir_all(os.join_path(root, 'beta')) or { panic(err) }
	os.write_file(os.join_path(root, 'alpha', 'readme.txt'), 'hello') or { panic(err) }
	defer { os.rmdir_all(root) or {} }

	mut app := FileBrowserApp{}
	app.browser.read(root.clone())
	assert app.browser.error == ''
	app.set_view_mode(.columns)
	assert app.view_mode == .columns
	assert app.columns.len == 2
	assert app.columns.last().browser.path == root

	alpha_column := app.columns.len - 1
	alpha := files_columns_entry_index(&app.columns[alpha_column], 'alpha')
	assert alpha >= 0
	alpha_action := app.columns.last().browser.entries[alpha].row_action
	app.handle(alpha_action)!
	assert app.columns.len == 3
	assert app.columns[app.columns.len - 2].selected_row == alpha
	assert app.columns.last().browser.path == os.join_path(root, 'alpha')

	nested_column := app.columns.len - 1
	nested := files_columns_entry_index(&app.columns[nested_column], 'nested')
	assert nested >= 0
	nested_action := app.columns.last().browser.entries[nested].row_action
	app.handle(nested_action)!
	assert app.columns.len == 4
	assert app.columns.last().browser.path == os.join_path(root, 'alpha', 'nested')

	// The default 460-pixel Files window has room for two Miller columns. At
	// the deepest point those are alpha and nested, with List offered as the
	// way back to the ordinary single-directory view.
	tree := app.build(ui2.rect(0, 0, 460, 330))!
	assert files_columns_tree_has_text(tree, 'alpha')
	assert files_columns_tree_has_text(tree, 'nested')
	assert files_columns_tree_has_text(tree, 'List')
	free_tree(tree)

	app.handle(files_action_view_toggle)!
	assert app.view_mode == .list
	assert app.columns.len == 0
	assert app.browser.path == os.join_path(root, 'alpha', 'nested')
	assert app.browser.entries.len == 0
	app.browser.free_entries()
}

fn test_miller_row_actions_keep_column_identity() {
	action := '${files_action_column_row}42.7'
	parsed := parse_miller_row_action(action) or { panic('row action did not parse') }
	assert parsed.column_id == 42
	assert parsed.row == 7
	if unexpected := parse_miller_row_action('files.row.7') {
		assert unexpected.column_id == 0
	}
}

fn test_file_browser_up_keeps_an_owned_parent_path() {
	root := os.join_path(os.temp_dir(), 'vinix-files-up-test')
	child := os.join_path(root, 'child')
	os.rmdir_all(root) or {}
	os.mkdir_all(child) or { panic(err) }
	defer { os.rmdir_all(root) or {} }

	mut browser := FileBrowser{}
	browser.read(child.clone())
	assert browser.path == child
	browser.go_up()
	// go_up used to retain a slice of the path it had just freed. Reading the
	// value here is deliberately enough for an address sanitizer to catch that
	// use-after-free, while the equality protects the normal manual-free build.
	assert browser.path == root
	assert browser.error == ''
	browser.free_entries()
	unsafe {
		browser.path.free()
		browser.error.free()
	}
}

fn test_create_context_menu_uses_collision_safe_names() {
	root := os.join_path(os.temp_dir(), 'vinix-create-context-test')
	os.rmdir_all(root) or {}
	os.mkdir_all(root) or { panic(err) }
	defer { os.rmdir_all(root) or {} }

	folder1 := create_unique_item(root, .folder)!
	folder2 := create_unique_item(root, .folder)!
	file1 := create_unique_item(root, .file)!
	file2 := create_unique_item(root, .file)!

	assert os.is_dir(os.join_path(root, 'New Folder'))
	assert os.is_dir(os.join_path(root, 'New Folder (2)'))
	assert os.is_file(os.join_path(root, 'New File'))
	assert os.is_file(os.join_path(root, 'New File (2)'))
	unsafe {
		folder1.free()
		folder2.free()
		file1.free()
		file2.free()
	}
}

fn test_files_create_enters_rename_mode_and_commits_name() {
	root := os.join_path(os.temp_dir(), 'vinix-files-create-rename-test')
	os.rmdir_all(root) or {}
	os.mkdir_all(root) or { panic(err) }
	defer { os.rmdir_all(root) or {} }

	mut app := FilesContextApp{}
	app.files.browser.read(root.clone())
	app.create_item(.file)!
	assert app.rename_path == os.join_path(root, 'New File')
	assert rename_buffer_text(app.rename_text) == 'New File'
	assert app.rename_select_all

	// The first typed byte replaces the selected default name; Return commits.
	app.rename_key_input('renamed.txt\r')!
	assert app.rename_path == ''
	assert os.is_file(os.join_path(root, 'renamed.txt'))
	assert !os.exists(os.join_path(root, 'New File'))

	app.clear_context_path()
	app.files.browser.free_entries()
	unsafe {
		app.files.browser.path.free()
		app.files.browser.error.free()
		app.rename_text.free()
	}
}

fn test_file_context_copy_cut_paste_and_delete_directory_tree() {
	root := os.join_path(os.temp_dir(), 'vinix-file-context-ops-test')
	source := os.join_path(root, 'source')
	copy_parent := os.join_path(root, 'copy-parent')
	cut_parent := os.join_path(root, 'cut-parent')
	os.rmdir_all(root) or {}
	os.mkdir_all(os.join_path(source, 'nested')) or { panic(err) }
	os.mkdir_all(copy_parent) or { panic(err) }
	os.mkdir_all(cut_parent) or { panic(err) }
	os.write_file(os.join_path(source, 'nested', 'hello.txt'), 'hello') or { panic(err) }
	defer {
		file_context_clipboard_clear()
		os.rmdir_all(root) or {}
	}

	assert file_context_clipboard_store(.copy, source)
	copied := paste_file_clipboard(copy_parent)!
	assert os.is_dir(copied)
	assert os.read_file(os.join_path(copied, 'nested', 'hello.txt'))! == 'hello'
	assert os.is_dir(source)

	assert file_context_clipboard_store(.cut, copied)
	moved := paste_file_clipboard(cut_parent)!
	assert !os.exists(copied)
	assert os.read_file(os.join_path(moved, 'nested', 'hello.txt'))! == 'hello'
	assert !file_context_clipboard_available()

	file_context_remove_path(moved)!
	assert !os.exists(moved)
	unsafe {
		copied.free()
		moved.free()
	}
}
