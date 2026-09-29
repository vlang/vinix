// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

fn files_sidebar_find(element ui2.Element, action string) ?ui2.Element {
	if element.id == action {
		return element
	}
	for child in element.children {
		if found := files_sidebar_find(child, action) {
			return found
		}
	}
	return none
}

fn test_files_sidebar_locations_and_navigation_in_both_views() {
	root := os.join_path(os.temp_dir(), 'vinix-files-sidebar-test')
	os.rmdir_all(root) or {}
	os.mkdir_all(os.join_path(root, 'child')) or { panic(err) }
	defer { os.rmdir_all(root) or {} }

	desktop_use_user_home(root.clone())
	assert files_locations.len == 7
	mut app := FileBrowserApp{}
	app.browser.read(root.clone())
	assert app.browser.error == ''
	list := app.build(ui2.rect(0, 0, 700, 400))!
	for location in files_locations {
		assert files_sidebar_find(list, location.action) != none
	}
	row := files_sidebar_find(list, app.browser.entries[0].row_action) or { panic('missing file row') }
	assert int(row.frame.x) == files_sidebar_width()
	free_tree(list)

	app.set_view_mode(.columns)
	columns := app.build(ui2.rect(0, 0, 700, 400))!
	assert app.viewport_width == 700 - files_sidebar_width()
	assert app.column_width >= files_column_min_width
	assert files_sidebar_find(columns, 'files.location.downloads') != none
	column_row := files_sidebar_find(columns, app.columns.last().browser.entries[0].row_action) or {
		panic('missing column row')
	}
	assert int(column_row.frame.x) >= files_sidebar_width()
	free_tree(columns)

	app.handle('files.location.home')!
	assert app.current_path() == root
	app.handle('files.location.computer')!
	assert app.current_path() == '/'
	assert app.columns.len == 1
	selected := app.build(ui2.rect(0, 0, 700, 400))!
	computer := files_sidebar_find(selected, 'files.location.computer') or { panic('missing Computer') }
	assert !computer.box.transparent
	free_tree(selected)

	app.handle(files_action_view_list)!
	assert app.browser.path == '/'
	compact := app.build(ui2.rect(0, 0, 320, 330))!
	assert files_sidebar_find(compact, 'files.location.home') == none
	free_tree(compact)
	app.browser.free_entries()
	unsafe { app.browser.path.free() }
}

fn test_files_list_draws_last_row_that_fits_above_window_bottom() {
	root := os.join_path(os.temp_dir(), 'vinix-files-last-row-test')
	os.rmdir_all(root) or {}
	os.mkdir_all(root) or { panic(err) }
	defer { os.rmdir_all(root) or {} }
	for index in 0 .. 14 {
		os.write_file(os.join_path(root, 'file-${index}.txt'), 'x') or { panic(err) }
	}

	mut app := FileBrowserApp{}
	app.browser.read(root.clone())
	assert app.browser.entries.len == 14
	height := files_header_height() + files_list_header_height() + 14 * files_row_height()
	tree := app.build(ui2.rect(0, 0, 700, f64(height)))!
	last := files_sidebar_find(tree, 'files.row.13') or { panic('last visible file row is missing') }
	assert app.visible_rows == 14
	assert int(last.frame.y + last.frame.height) <= height
	free_tree(tree)
	app.browser.free_entries()
	unsafe { app.browser.path.free() }
}
