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
