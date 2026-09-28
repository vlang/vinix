// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

fn commander_element(tree ui2.Element, id string) ?ui2.Element {
	if tree.id == id {
		return tree
	}
	for child in tree.children {
		if found := commander_element(child, id) {
			return found
		}
	}
	return none
}

fn commander_entry_action(browser &FileBrowser, name string) string {
	for entry in browser.entries {
		if entry.name == name {
			return entry.row_action
		}
	}
	panic('missing entry ${name}')
}

fn test_commander_panes_navigate_and_scroll_independently() ! {
	root := os.join_path(os.temp_dir(), 'vinix-files-commander-test')
	left := os.join_path(root, 'left')
	right := os.join_path(root, 'right')
	os.rmdir_all(root) or {}
	os.mkdir_all(os.join_path(left, 'child'))!
	os.mkdir_all(os.join_path(right, 'other'))!
	for index in 0 .. 22 {
		os.write_file(os.join_path(right, 'item-${index}.txt'), 'hello')!
	}
	defer { os.rmdir_all(root) or {} }

	mut app := FileBrowserApp{}
	app.settings = default_files_settings()
	app.browser.read(root.clone())
	app.handle(files_action_view_commander)!
	assert app.view_mode == .commander
	assert app.dual_left.path == root
	assert app.dual_right.path == root
	assert commander_entry_action(&app.dual_left, 'left').starts_with(files_action_pane_left_row)
	assert commander_entry_action(&app.dual_right, 'right').starts_with(files_action_pane_right_row)

	app.handle(commander_entry_action(&app.dual_left, 'left'))!
	assert app.dual_left.path == left
	assert app.dual_right.path == root
	app.handle(commander_entry_action(&app.dual_right, 'right'))!
	assert app.active_pane == 1
	assert app.dual_left.path == left
	assert app.dual_right.path == right

	tree := app.build(ui2.rect(0, 0, 700, 340))!
	commander_button := commander_element(tree, files_action_view_commander) or { panic('missing commander button') }
	list_button := commander_element(tree, files_action_view_list) or { panic('missing list button') }
	assert commander_button.image_path == 'builtin:dual_pane'
	assert commander_button.accessibility_value == 'selected'
	assert commander_button.frame.x < list_button.frame.x
	left_pane := commander_element(tree, files_action_pane_left) or { panic('missing left pane') }
	right_pane := commander_element(tree, files_action_pane_right) or { panic('missing right pane') }
	assert left_pane.frame.x + left_pane.frame.width == right_pane.frame.x
	assert right_pane.frame.x + right_pane.frame.width == 700
	assert app.rows_top == files_header_height + files_pane_header_height
	free_tree(tree)

	app.pointer_event(.scroll, .no_button, -1, files_commander_pane_x(700, 1) + 30,
		app.rows_top + 15, 700, 340)
	assert app.dual_right.scroll == 2
	assert app.dual_left.scroll == 0
	app.handle(files_action_up)!
	assert app.dual_right.path == root
	assert app.dual_left.path == left
	app.handle(files_action_pane_left)!
	app.handle(files_action_up)!
	assert app.dual_left.path == root
	assert app.dual_right.path == root
}

fn test_commander_keeps_other_pane_when_changing_views() ! {
	root := os.join_path(os.temp_dir(), 'vinix-files-commander-switch-test')
	left := os.join_path(root, 'left')
	right := os.join_path(root, 'right')
	os.rmdir_all(root) or {}
	os.mkdir_all(left)!
	os.mkdir_all(right)!
	os.write_file(os.join_path(left, '.left-hidden'), 'left')!
	os.write_file(os.join_path(right, '.right-hidden'), 'right')!
	defer { os.rmdir_all(root) or {} }

	mut app := FilesContextApp{}
	app.files.settings = default_files_settings()
	app.files.browser.read(root.clone())
	app.handle_browser_action(files_action_view_commander, root)!
	assert load_files_view_mode(root) == .commander
	app.handle(commander_entry_action(&app.files.dual_left, 'left'))!
	app.handle(commander_entry_action(&app.files.dual_right, 'right'))!
	assert app.files.current_path() == right
	mut settings := default_files_settings()
	settings.show_hidden = true
	assert settings.save(root)
	app.reload_files_settings(root)
	assert commander_entry_action(&app.files.dual_left, '.left-hidden').starts_with(files_action_pane_left_row)
	assert commander_entry_action(&app.files.dual_right, '.right-hidden').starts_with(files_action_pane_right_row)
	app.create_item(.file)!
	assert os.is_file(os.join_path(right, 'New File'))
	assert commander_entry_action(&app.files.dual_right, 'New File').starts_with(files_action_pane_right_row)
	assert app.files.dual_left.path == left
	app.clear_rename()
	os.write_file(os.join_path(left, 'arrived.txt'), 'moved')!
	app.refresh_to(right.clone())
	assert commander_entry_action(&app.files.dual_left, 'arrived.txt').starts_with(files_action_pane_left_row)
	app.key_input('\t')
	assert app.files.active_pane == 0
	assert app.files.current_path() == left
	app.handle_browser_action(files_action_view_list, root)!
	assert app.files.browser.path == left
	app.files.navigate_to(root)
	app.handle_browser_action(files_action_view_commander, root)!
	assert app.files.dual_left.path == root
	assert app.files.dual_right.path == right

	mut reopened := FilesContextApp{}
	reopened.files.browser.read(root.clone())
	reopened.restore_files_view_mode(root)
	assert reopened.files.view_mode == .commander
	assert reopened.files.dual_left.path == root
	assert reopened.files.dual_right.path == root
}
