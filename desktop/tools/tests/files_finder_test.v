// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

fn finder_test_find(element ui2.Element, id string) ?ui2.Element {
	if element.id == id {
		return element
	}
	for child in element.children {
		if found := finder_test_find(child, id) {
			return found
		}
	}
	return none
}

// A home with Documents holding a folder and two files, two of the three
// names containing "li". It is the only thing in its parent, so the parent's
// column shows it without scrolling; each test removes that parent after.
fn finder_test_home(name string) string {
	os.rmdir_all(os.join_path(os.temp_dir(), name)) or {}
	root := os.join_path(os.temp_dir(), name, 'home')
	for child in ['Documents', 'Downloads', 'Music'] {
		os.mkdir_all(os.join_path(root, child)) or { panic(err) }
	}
	os.mkdir_all(os.join_path(root, 'Documents', 'library')) or { panic(err) }
	os.write_file(os.join_path(root, 'Documents', 'list.txt'), 'list') or { panic(err) }
	os.write_file(os.join_path(root, 'Documents', 'notes.txt'), 'notes') or { panic(err) }
	return root
}

fn test_finder_toolbar_leads_the_tree_and_names_the_folder() {
	root := finder_test_home('vinix-finder-toolbar-test')
	defer {
		files_follow_theme(.default_)
		os.rmdir_all(os.dir(root)) or {}
	}
	desktop_use_user_home(root.clone())
	files_follow_theme(.macos)
	mut app := FileBrowserApp{}
	app.browser.read(root.clone())
	tree := app.build(ui2.rect(0, 0, 800, 500))!
	toolbar := tree.children[0]
	assert toolbar.id == app_toolbar_id
	assert int(toolbar.frame.height) == finder_toolbar_height
	assert toolbar.text == os.file_name(root)
	assert toolbar.image_path == 'builtin:finder_folder'
	back := finder_test_find(toolbar, files_action_back) or { panic('no Back') }
	assert !back.enabled
	assert finder_test_find(toolbar, files_action_search) != none
	assert finder_test_find(toolbar, files_action_view_columns) != none
	// The title bar names the folder, so there is no Up or path strip.
	assert finder_test_find(tree, files_action_up) == none
	assert tree.box.bg == files_row_base
	sidebar := finder_test_find(tree, 'files.sidebar') or { panic('no sidebar') }
	assert int(sidebar.frame.width) == finder_sidebar_width
	assert sidebar.box.bg == finder_sidebar_bg
	home := finder_test_find(sidebar, 'files.location.home') or { panic('no Home') }
	assert !home.box.transparent && home.box.bg == finder_sidebar_selected
	free_tree(tree)

	files_follow_theme(.default_)
	plain := app.build(ui2.rect(0, 0, 800, 500))!
	assert plain.children[0].id != app_toolbar_id
	assert finder_test_find(plain, files_action_up) != none
	free_tree(plain)
}

fn test_finder_back_and_forward_retrace_the_folders_visited() {
	root := finder_test_home('vinix-finder-history-test')
	defer {
		files_follow_theme(.default_)
		os.rmdir_all(os.dir(root)) or {}
	}
	documents := os.join_path(root, 'Documents')
	music := os.join_path(root, 'Music')
	files_follow_theme(.macos)
	mut app := FileBrowserApp{}
	app.browser.read(root.clone())
	free_tree(app.build(ui2.rect(0, 0, 800, 500))!)
	app.navigate_to(documents)
	tree := app.build(ui2.rect(0, 0, 800, 500))!
	back := finder_test_find(tree, files_action_back) or { panic('no Back') }
	forward := finder_test_find(tree, files_action_forward) or { panic('no Forward') }
	assert back.enabled && !forward.enabled
	assert tree.children[0].text == 'Documents'
	free_tree(tree)

	app.handle(files_action_back)!
	assert app.current_path() == root
	free_tree(app.build(ui2.rect(0, 0, 800, 500))!)
	assert app.history_back.len == 0 && app.history_forward.len == 1
	app.handle(files_action_forward)!
	assert app.current_path() == documents
	free_tree(app.build(ui2.rect(0, 0, 800, 500))!)

	// Moving somewhere new after going back forgets where Forward led.
	app.handle(files_action_back)!
	free_tree(app.build(ui2.rect(0, 0, 800, 500))!)
	app.navigate_to(music)
	free_tree(app.build(ui2.rect(0, 0, 800, 500))!)
	assert app.history_forward.len == 0
	assert app.history_back.len == 1 && app.history_back[0] == root

	// Column view keeps the same history: a folder picked in a column is a move.
	app.set_view_mode(.columns)
	free_tree(app.build(ui2.rect(0, 0, 900, 500))!)
	app.handle(files_action_back)!
	assert app.current_path() == root
	assert app.columns.last().browser.path == root
}

fn test_finder_columns_have_finder_widths_rows_and_selections() {
	root := finder_test_home('vinix-finder-columns-test')
	defer {
		files_follow_theme(.default_)
		os.rmdir_all(os.dir(root)) or {}
	}
	files_follow_theme(.macos)
	mut app := FileBrowserApp{}
	app.browser.read(root.clone())
	app.set_view_mode(.columns)
	free_tree(app.build(ui2.rect(0, 0, 1000, 500))!)
	assert app.column_width == finder_column_width + finder_scroller_width
	home_column := app.columns.len - 1
	row := app.find_miller_entry(home_column, 'Documents')
	assert row >= 0
	action := app.columns[home_column].browser.entries[row].row_action
	app.handle(action)!
	tree := app.build(ui2.rect(0, 0, 1000, 500))!
	assert app.columns.last().browser.path == os.join_path(root, 'Documents')
	// The deepest selection is Finder's blue, one that led to it is grey.
	selected := finder_test_find(tree, action) or { panic('no Documents row') }
	assert !selected.box.transparent && selected.box.bg == finder_selection
	assert int(selected.frame.width) == finder_column_width
	assert int(selected.frame.height) == finder_row_height - 1
	assert int(selected.frame.y) == finder_toolbar_height + 1 + row * finder_row_height
	parent := app.columns[home_column - 1]
	led := finder_test_find(tree, parent.browser.entries[parent.selected_row].row_action) or {
		panic('no selected parent row')
	}
	assert !led.box.transparent && led.box.bg == finder_selection_inactive
	// Columns sit side by side at Finder's pitch, each followed by its scroller.
	x0 := int(selected.frame.x)
	child := finder_test_find(tree, app.columns.last().browser.entries[0].row_action) or {
		panic('no row in the last column')
	}
	assert int(child.frame.x) == x0 + finder_column_width + finder_scroller_width
	assert int(child.frame.x) + finder_column_width <= 1000
	free_tree(tree)
}

fn test_finder_search_narrows_the_folder_until_escape_or_a_move() {
	root := finder_test_home('vinix-finder-search-test')
	defer {
		files_follow_theme(.default_)
		os.rmdir_all(os.dir(root)) or {}
	}
	documents := os.join_path(root, 'Documents')
	files_follow_theme(.macos)
	mut app := FileBrowserApp{}
	app.browser.read(documents.clone())
	free_tree(app.build(ui2.rect(0, 0, 800, 500))!)
	assert app.browser.entries.len == 3
	app.search_focused = true
	app.search_key_input('LI')
	assert app.browser.entries.len == 2
	assert app.browser.entries[0].name == 'library'
	assert app.browser.entries[1].name == 'list.txt'
	assert app.browser.entries[1].row_action == '${files_action_row}1'
	tree := app.build(ui2.rect(0, 0, 800, 500))!
	field := finder_test_find(tree, files_action_search) or { panic('no search field') }
	assert field.text == 'LI' && field.focused && field.text_selection.caret == 2
	free_tree(tree)
	// Backspace takes a character; Escape shows the whole folder again.
	app.search_key_input('\x7f\x7f')
	assert app.browser.entries.len == 3 && app.search.len == 0
	app.search_key_input('not')
	assert app.browser.entries.len == 1
	app.search_key_input('\x1b')
	assert app.browser.entries.len == 3 && app.search.len == 0 && !app.search_focused

	// Moving elsewhere ends the search, which was for the folder left behind.
	app.search_focused = true
	app.search_key_input('li')
	app.navigate_to(root)
	free_tree(app.build(ui2.rect(0, 0, 800, 500))!)
	assert app.search.len == 0 && app.search_column == -2
	assert app.browser.entries.len == 3

	// In column view the search narrows the last column, and a folder picked
	// from the narrowed column leaves it whole again, still selected.
	app.set_view_mode(.columns)
	free_tree(app.build(ui2.rect(0, 0, 1000, 500))!)
	app.search_focused = true
	app.search_key_input('doc')
	home := app.columns.len - 1
	assert app.columns[home].browser.entries.len == 1
	app.handle(app.columns[home].browser.entries[0].row_action)!
	free_tree(app.build(ui2.rect(0, 0, 1000, 500))!)
	assert app.search.len == 0
	assert app.columns[home].browser.entries.len == 3
	selected := app.columns[home].selected_row
	assert selected >= 0 && app.columns[home].browser.entries[selected].name == 'Documents'
	assert app.columns.last().browser.path == documents
}

fn test_macos_window_draws_the_toolbar_in_its_title_bar() {
	root := finder_test_home('vinix-finder-titlebar-test')
	defer {
		files_follow_theme(.default_)
		os.rmdir_all(os.dir(root)) or {}
	}
	desktop_use_user_home(root.clone())
	mut d := Desktop{
		canvas: Canvas{
			width:  1000
			height: 700
		}
	}
	d.settings.theme = .macos
	mut app := &FilesContextApp{
		desktop: &d
	}
	app.follow_theme()
	app.files.browser.read(root.clone())
	d.apps << app
	id := d.spawn('Files', .app, 40, 40, 800, 480)
	index := d.window_index(id) or { panic('no window') }
	d.windows[index].app_index = d.apps.len - 1
	d.focus = id
	window := d.windows[index]
	title_height := d.theme().title_height
	frame := d.window_element(index)
	title_bar := finder_test_find(frame, window.id_titlebar) or { panic('no title bar') }
	assert int(title_bar.frame.height) == title_height + finder_toolbar_height
	title := finder_test_find(title_bar, window.id_title) or { panic('no title') }
	assert title.text == os.file_name(root)
	// The toolbar's controls are in the title bar now, and only there.
	assert finder_test_find(title_bar, files_action_back) != none
	body := finder_test_find(frame, window.id_body) or { panic('no body') }
	assert int(body.frame.y) == title_height
	assert finder_test_find(body, app_toolbar_id) == none
	assert finder_test_find(body, files_action_back) == none
	divider := finder_test_find(frame, window.id_divider) or { panic('no divider') }
	assert int(divider.frame.y) == title_height + finder_toolbar_height - 1
	// The body is under the title bar that reaches down over its top.
	assert frame.children[0].id == window.id_body
	free_tree(frame)

	d.settings.theme = .default_
	app.follow_theme()
	plain := d.window_element(index)
	plain_bar := finder_test_find(plain, window.id_titlebar) or { panic('no title bar') }
	assert int(plain_bar.frame.height) == d.theme().title_height
	plain_title := finder_test_find(plain_bar, window.id_title) or { panic('no title') }
	assert plain_title.text == app_title_text('Files')
	free_tree(plain)
}

fn test_finder_look_waits_for_a_compositor_that_can_draw_it() {
	defer {
		app_compositor_features = app_features
		files_follow_theme(.default_)
	}
	// A desktop that predates Finder's toolbar sends no features.
	app_compositor_features = 0
	files_follow_theme(.macos)
	assert !files_catalina
	app_compositor_features = app_features
	files_follow_theme(.macos)
	assert files_catalina
	files_follow_theme(.default_)
	assert !files_catalina
}
