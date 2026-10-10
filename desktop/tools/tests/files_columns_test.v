// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

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

fn files_columns_tree_has_view_button(element ui2.Element, action string, icon string, selected bool) bool {
	for child in element.children {
		if child.id == action {
			return child.image_path == icon && child.text == ''
				&& child.accessibility_label != ''
				&& (child.accessibility_value == 'selected') == selected
		}
	}
	return false
}

fn files_columns_tree_path_view(element ui2.Element, path string) ?ui2.Element {
	if element.tooltip == path && element.kind == .view {
		return element
	}
	for child in element.children {
		if found := files_columns_tree_path_view(child, path) {
			return found
		}
	}
	return none
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
	for index in 0 .. 20 {
		os.write_file(os.join_path(root, 'alpha', 'item-${index}.txt'), 'hello') or { panic(err) }
	}
	defer { os.rmdir_all(root) or {} }

	mut app := FileBrowserApp{}
	app.browser.read(root.clone())
	assert app.browser.error == ''
	app.set_view_mode(.columns)
	assert app.view_mode == .columns
	base_columns := app.columns.len
	assert base_columns > 2
	assert app.columns[0].browser.path == '/'
	assert app.columns.last().browser.path == root

	alpha_column := app.columns.len - 1
	alpha := files_columns_entry_index(&app.columns[alpha_column], 'alpha')
	assert alpha >= 0
	alpha_action := app.columns.last().browser.entries[alpha].row_action
	app.handle(alpha_action)!
	assert app.columns.len == base_columns + 1
	assert app.columns[app.columns.len - 2].selected_row == alpha
	assert app.columns.last().browser.path == os.join_path(root, 'alpha')

	nested_column := app.columns.len - 1
	nested := files_columns_entry_index(&app.columns[nested_column], 'nested')
	assert nested >= 0
	nested_action := app.columns.last().browser.entries[nested].row_action
	app.handle(nested_action)!
	assert app.columns.len == base_columns + 2
	assert app.columns.last().browser.path == os.join_path(root, 'alpha', 'nested')

	// The full path stays in the toolbar, and the columns begin below it.
	tree := app.build(ui2.rect(0, 0, 460, 330))!
	selected_path := os.join_path(root, 'alpha', 'nested')
	assert files_columns_tree_has_text(tree, selected_path)
	path_view := files_columns_tree_path_view(tree, selected_path) or { panic('missing path') }
	assert int(path_view.frame.x) == files_path_left
	assert int(path_view.frame.y) == files_path_top
	assert app.rows_top == files_header_height()
	assert app.column_offset == app.max_column_offset()
	assert app.max_column_offset() > 0
	assert files_columns_tree_has_view_button(tree, files_action_view_list, 'builtin:list_view',
		false)
	assert files_columns_tree_has_view_button(tree, files_action_view_columns, 'builtin:column_view',
		true)
	assert !files_columns_tree_has_text(tree, '-')
	assert !files_columns_tree_has_text(tree, '+')
	free_tree(tree)
	content_left := files_content_left(460)
	assert app.path_offset == app.max_path_offset()
	assert app.path_offset > 0
	path_x := files_path_left + 20
	path_y := files_path_top + 10
	app.pointer_event(.down, .left, 0, path_x, path_y, 460, 330)
	app.pointer_event(.move, .no_button, 0, path_x + 200, path_y, 460, 330)
	app.pointer_event(.up, .left, 0, path_x + 200, path_y, 460, 330)
	assert app.path_offset < app.max_path_offset()
	app.column_offset = files_clamp((app.columns.len - 2) * app.column_width,
		app.max_column_offset())
	app.pointer_event(.scroll, .no_button, -1, content_left + 10, app.rows_top + 10, 460, 330)
	assert app.columns[app.columns.len - 2].browser.scroll == 2
	bar_x := content_left + app.column_width - files_scrollbar_width - 2
	bar_position, _ := files_scroll_thumb(app.rows_height, app.visible_rows,
		app.columns[app.columns.len - 2].browser.entries.len, 2)
	app.pointer_event(.down, .left, 0, bar_x + 2, app.rows_top + bar_position + 1, 460, 330)
	app.pointer_event(.move, .no_button, 0, bar_x + 2, app.rows_top + app.rows_height + 10, 460, 330)
	app.pointer_event(.up, .left, 0, bar_x + 2, app.rows_top + app.rows_height + 10, 460, 330)
	assert app.columns[app.columns.len - 2].browser.scroll == app.columns[app.columns.len - 2].browser.entries.len - app.visible_rows
	app.column_offset = app.max_column_offset()
	track := app.viewport_width - 2 * files_padding
	thumb_x, _ := files_scroll_thumb(track, app.viewport_width, app.columns.len * app.column_width,
		app.column_offset)
	bar_y := 330 - files_horizontal_bar_height + 8
	app.pointer_event(.down, .left, 0, content_left + files_padding + thumb_x + 1, bar_y, 460, 330)
	app.pointer_event(.move, .no_button, 0, content_left + files_padding + 1, bar_y, 460, 330)
	app.pointer_event(.up, .left, 0, content_left + files_padding + 1, bar_y, 460, 330)
	assert app.column_offset == 0
	app.pointer_event(.down, .left, 0, 460 - files_padding - 2, bar_y, 460, 330)
	app.pointer_event(.up, .left, 0, 460 - files_padding - 2, bar_y, 460, 330)
	assert app.column_offset == app.max_column_offset()

	app.handle(files_action_view_columns)!
	assert app.columns.len == base_columns + 2
	app.handle(files_action_view_list)!
	assert app.view_mode == .list
	assert app.columns.len == 0
	assert app.browser.path == os.join_path(root, 'alpha', 'nested')
	assert app.browser.entries.len == 0
	list_tree := app.build(ui2.rect(0, 0, 460, 330))!
	assert files_columns_tree_has_view_button(list_tree, files_action_view_list,
		'builtin:list_view', true)
	assert files_columns_tree_has_view_button(list_tree, files_action_view_columns,
		'builtin:column_view', false)
	free_tree(list_tree)
	app.handle(files_action_view_list)!
	assert app.view_mode == .list
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

fn test_horizontal_swipes_pan_columns_in_both_themes_without_scrolling_rows() {
	root := os.join_path(os.temp_dir(), 'vinix-files-horizontal-scroll-test')
	os.mkdir_all(os.join_path(root, 'child')) or { panic(err) }
	for index in 0 .. 20 {
		os.write_file(os.join_path(root, 'item-${index}.txt'), 'hello') or { panic(err) }
	}
	defer {
		files_follow_theme(.default_)
		os.rmdir_all(root) or {}
	}
	for theme in [ThemeKind.default_, .macos] {
		files_follow_theme(theme)
		mut app := FilesContextApp{}
		app.files.browser.read(root.clone())
		app.files.set_view_mode(.columns)
		free_tree(app.build(ui2.rect(0, 0, 700, 400))!)
		maximum := app.files.max_column_offset()
		assert maximum > 48
		x := files_content_left(700) + 10
		y := app.files.rows_top + 10
		last := app.files.columns.len - 1
		app.files.columns[last].browser.scroll = 2
		path := app.files.current_path().clone()
		app.pointer_event(.horizontal_scroll, .no_button, -1, x, y, 700, 400)
		assert app.files.column_offset == maximum - 48
		free_tree(app.build(ui2.rect(0, 0, 700, 400))!)
		assert app.files.column_offset == maximum - 48
		assert app.files.columns[last].browser.scroll == 2
		assert app.files.current_path() == path
		app.pointer_event(.horizontal_scroll, .no_button, 1, x, y, 700, 400)
		assert app.files.column_offset == maximum
		app.pointer_event(.horizontal_scroll, .no_button, 100, x, y, 700, 400)
		assert app.files.column_offset == maximum
		app.pointer_event(.horizontal_scroll, .no_button, -100, x, y, 700, 400)
		assert app.files.column_offset == 0
		app.pointer_event(.horizontal_scroll, .no_button, 1, 700 - 10, y, 700, 400)
		assert app.files.column_offset == 48

		// The sidebar, toolbar and open overlays do not pan the column strip.
		app.pointer_event(.horizontal_scroll, .no_button, 1, 10, y, 700, 400)
		app.pointer_event(.horizontal_scroll, .no_button, 1, x, app.files.rows_top - 1, 700, 400)
		assert app.files.column_offset == 48
		app.trash_open = true
		app.pointer_event(.horizontal_scroll, .no_button, 1, x, y, 700, 400)
		assert app.files.column_offset == 48
		app.trash_open = false
		app.files.column_offset = maximum
		// Vertical wheels still scroll just the column beneath the pointer.
		app.pointer_event(.scroll, .no_button, -1, 700 - 30, y, 700, 400)
		assert app.files.column_offset == maximum
		assert app.files.columns[last].browser.scroll == 4
		app.files.set_view_mode(.list)
		free_tree(app.build(ui2.rect(0, 0, 700, 400))!)
		app.files.browser.scroll = 2
		app.pointer_event(.horizontal_scroll, .no_button, 1, x, y, 700, 400)
		assert app.files.browser.scroll == 2
		unsafe { path.free() }
		app.close_app()
	}
}

fn test_pointer_poll_accepts_legacy_and_horizontal_packets() {
	for length in [32, 36] {
		mut descriptors := [2]i32{}
		assert C.pipe(&descriptors[0]) == 0
		mut device := PointerDevice{fd: int(descriptors[0])}
		packet := PointerPacket{x: 123, y: 456, max_x: 32767, max_y: 32767, scroll: -2, scroll_x: 3}
		assert desktop_write(int(descriptors[1]), &packet, u64(length)) == length
		read := device.poll() or { panic('pointer packet lost') }
		assert read.x == 123 && read.y == 456 && read.scroll == -2
		assert read.scroll_x == if length == 36 { 3 } else { 0 }
		device.close()
		desktop_close(int(descriptors[1]))
	}
}

fn test_horizontal_scroll_keeps_older_app_transports_alive() {
	mut app := RemoteApp{pointer: true, tree_stale: false}
	app.pointer_event(.horizontal_scroll, .no_button, 1, 10, 10, 700, 400)
	assert !app.closed && !app.tree_stale
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
