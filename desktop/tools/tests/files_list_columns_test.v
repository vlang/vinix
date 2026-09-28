// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

fn files_list_find_id(tree ui2.Element, id string) ?ui2.Element {
	if tree.id == id { return tree }
	for child in tree.children {
		if found := files_list_find_id(child, id) { return found }
	}
	return none
}

fn files_list_has_text(tree ui2.Element, text string) bool {
	if tree.text == text { return true }
	for child in tree.children {
		if files_list_has_text(child, text) { return true }
	}
	return false
}

fn files_list_entry(browser &FileBrowser, name string) ?FileEntry {
	for entry in browser.entries {
		if entry.name == name { return entry }
	}
	return none
}

fn files_list_names(browser &FileBrowser) []string {
	mut names := []string{cap: browser.entries.len}
	for entry in browser.entries { names << entry.name }
	return names
}

fn test_files_list_formats_kind_and_modified_time() {
	assert files_list_modified_text(0, 0) == '01 Jan 1970 00:00'
	assert files_list_modified_text(0, 3 * 3600) == '01 Jan 1970 03:00'
	assert files_list_modified_text(-1, 0) == '—'
	assert files_list_kind_text('picture.PNG', false) == 'PNG image'
	assert files_list_kind_text('notes.py', false) == 'Python script'
	assert files_list_kind_text('archive.tar', false) == 'tar archive'
	assert files_list_kind_text('plain', false) == 'Document'
	assert files_list_kind_text('folder.png', true) == 'Folder'
}

fn test_files_list_reads_metadata_and_draws_responsive_columns() ! {
	root := os.join_path(os.temp_dir(), 'vinix-files-list-columns-test')
	os.rmdir_all(root) or {}
	os.mkdir_all(os.join_path(root, 'folder'))!
	os.write_file(os.join_path(root, 'picture.png'), 'png')!
	os.write_file(os.join_path(root, 'notes.py'), 'print(1)')!
	defer { os.rmdir_all(root) or {} }

	mut app := FileBrowserApp{}
	app.settings = default_files_settings()
	app.browser.tz_offset_seconds = 3 * 3600
	app.browser.read(root.clone())
	picture := files_list_entry(&app.browser, 'picture.png') or { panic('missing image') }
	assert picture.kind_text == 'PNG image'
	info := desktop_stat(os.join_path(root, 'picture.png')) or { panic('missing image stat') }
	assert picture.modified_text == files_list_modified_text(info.modified, 3 * 3600)
	folder := files_list_entry(&app.browser, 'folder') or { panic('missing folder') }
	assert folder.kind_text == 'Folder'

	wide := app.build(ui2.rect(0, 0, 1000, 360))!
	assert app.rows_top == files_header_height + files_list_header_height
	name := files_list_find_id(wide, 'files.list.header.name') or { panic('missing Name header') }
	modified := files_list_find_id(wide, 'files.list.header.modified') or {
		panic('missing Date Modified header')
	}
	size := files_list_find_id(wide, 'files.list.header.size') or { panic('missing Size header') }
	kind := files_list_find_id(wide, 'files.list.header.kind') or { panic('missing Kind header') }
	assert name.frame.x < modified.frame.x
	assert modified.frame.x < size.frame.x
	assert size.frame.x < kind.frame.x
	assert files_list_has_text(wide, picture.modified_text)
	assert files_list_has_text(wide, 'PNG image')
	free_tree(wide)

	narrow := app.build(ui2.rect(0, 0, 420, 360))!
	assert files_list_find_id(narrow, 'files.list.header.name') != none
	assert files_list_find_id(narrow, 'files.list.header.size') != none
	assert files_list_find_id(narrow, 'files.list.header.modified') == none
	assert files_list_find_id(narrow, 'files.list.header.kind') == none
	free_tree(narrow)

	app.set_view_mode(.columns)
	columns := app.build(ui2.rect(0, 0, 1000, 360))!
	assert app.rows_top == files_header_height
	assert files_list_find_id(columns, 'files.list.header.name') == none
	free_tree(columns)
}

fn test_files_list_header_clicks_sort_and_keep_row_actions_in_sync() ! {
	root := os.join_path(os.temp_dir(), 'vinix-files-list-sort-test')
	os.rmdir_all(root) or {}
	os.mkdir_all(os.join_path(root, 'adir'))!
	os.mkdir_all(os.join_path(root, 'zdir'))!
	os.write_file(os.join_path(root, 'alpha.txt'), 'aa')!
	os.write_file(os.join_path(root, 'beta.png'), '0123456789')!
	os.write_file(os.join_path(root, 'gamma.txt'), '12345')!
	defer { os.rmdir_all(root) or {} }

	mut app := FileBrowserApp{}
	app.settings = default_files_settings()
	app.browser.read(root.clone())
	assert files_list_names(&app.browser) == ['adir', 'zdir', 'alpha.txt', 'beta.png', 'gamma.txt']
	for index in 2 .. app.browser.entries.len {
		app.browser.entries[index].modified = match app.browser.entries[index].name {
			'alpha.txt' { 10 }
			'beta.png' { 30 }
			else { 20 }
		}
	}
	app.browser.selected_row = 4
	app.browser.hover_row = 3
	tree := app.build(ui2.rect(0, 0, 1000, 350))!
	header := files_list_find_id(tree, files_action_sort_size) or { panic('Size title is not clickable') }
	assert header.clickable
	assert header.accessibility_label == 'Sort by Size'
	free_tree(tree)

	app.handle(files_action_sort_size)!
	assert files_list_names(&app.browser) == ['adir', 'zdir', 'alpha.txt', 'gamma.txt', 'beta.png']
	assert !app.browser.sort_descending
	assert app.browser.selected_row == 3
	assert app.browser.hover_row == 4
	for index, entry in app.browser.entries {
		assert entry.row_action == '${files_action_row}${index}'
	}
	ascending := app.build(ui2.rect(0, 0, 1000, 350))!
	ascending_title := files_list_find_id(ascending, files_action_sort_size) or {
		panic('missing Size title')
	}
	assert ascending_title.accessibility_value == 'ascending'
	free_tree(ascending)
	app.handle(files_action_sort_size)!
	assert app.browser.sort_descending
	assert files_list_names(&app.browser) == ['adir', 'zdir', 'beta.png', 'gamma.txt', 'alpha.txt']
	descending := app.build(ui2.rect(0, 0, 1000, 350))!
	descending_title := files_list_find_id(descending, files_action_sort_size) or {
		panic('missing Size title')
	}
	assert descending_title.accessibility_value == 'descending'
	free_tree(descending)
	app.handle(files_action_sort_modified)!
	assert files_list_names(&app.browser) == ['adir', 'zdir', 'alpha.txt', 'gamma.txt', 'beta.png']
	app.handle(files_action_sort_kind)!
	assert files_list_names(&app.browser) == ['adir', 'zdir', 'beta.png', 'alpha.txt', 'gamma.txt']
	app.handle(files_action_sort_name)!
	assert files_list_names(&app.browser) == ['adir', 'zdir', 'alpha.txt', 'beta.png', 'gamma.txt']
	app.handle(files_action_sort_name)!
	assert files_list_names(&app.browser) == ['zdir', 'adir', 'gamma.txt', 'beta.png', 'alpha.txt']
	assert app.browser.sort_descending
	app.browser.read(root.clone())
	assert files_list_names(&app.browser) == ['zdir', 'adir', 'gamma.txt', 'beta.png', 'alpha.txt']
	app.handle('${files_action_row}0')!
	assert app.browser.path == os.join_path(root, 'zdir')
}
