// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn workspace_fixture() Desktop {
	return Desktop{
		canvas: Canvas{
			width:  801
			height: 647
		}
	}
}

fn workspace_element_named(root ui2.Element, id string) ?ui2.Element {
	if root.id == id {
		return root
	}
	for child in root.children {
		found := workspace_element_named(child, id) or { continue }
		return found
	}
	return none
}

fn test_workspaces_isolate_composition_focus_taskbar_and_switcher() {
	mut desktop := workspace_fixture()
	one := desktop.spawn('One', .welcome, 20, 20, 300, 200)
	desktop.switch_workspace(1)
	assert desktop.current_workspace == 1
	assert desktop.focus == 0
	two := desktop.spawn('Two', .notes, 40, 40, 300, 200)
	assert desktop.focus == two
	assert desktop.workspace_window_count(0) == 1
	assert desktop.workspace_window_count(1) == 1
	assert desktop.visible_window_count() == 1

	mut root := desktop.build_tree()
	assert workspace_element_named(root, 'win.${two}') != none
	assert workspace_element_named(root, 'win.${one}') == none
	assert workspace_element_named(root, 'task.${two}') != none
	assert workspace_element_named(root, 'task.${one}') == none
	active_workspace := workspace_element_named(root, workspace_action_ids[1]) or {
		panic('missing active workspace button')
	}
	assert active_workspace.box.bg == desktop.theme().accent
	free_tree(root)

	desktop.switcher_step(1)
	assert desktop.switcher.order == [two]
	desktop.switcher_close()
	desktop.switch_workspace(0)
	assert desktop.focus == one
	root = desktop.build_tree()
	assert workspace_element_named(root, 'win.${one}') != none
	assert workspace_element_named(root, 'win.${two}') == none
	free_tree(root)
}

fn test_workspace_shortcuts_switch_and_move_the_focused_window() {
	mut desktop := workspace_fixture()
	one := desktop.spawn('One', .welcome, 20, 20, 300, 200)
	two := desktop.spawn('Two', .notes, 40, 40, 300, 200)
	assert desktop.focus == two

	// Super+Shift+2 sends the focused window away but preserves unrelated bytes
	// from the same console read for the focused application.
	assert desktop.take_window_shortcuts('a${key_super_shift_workspaces[1]}b') == 'ab'
	index := desktop.window_index(two) or { panic('missing moved window') }
	assert desktop.windows[index].workspace == 1
	assert desktop.current_workspace == 0
	assert desktop.focus == one

	assert desktop.take_window_shortcuts(key_super_workspaces[1]) == ''
	assert desktop.current_workspace == 1
	assert desktop.focus == two
	// Invalid direct requests do not disturb the current workspace.
	desktop.switch_workspace(workspace_count)
	assert desktop.current_workspace == 1
}

fn test_super_arrows_tile_halves_quarters_and_restore() {
	mut desktop := workspace_fixture()
	id := desktop.spawn('Tile me', .welcome, 100, 80, 380, 240)

	assert desktop.take_window_shortcuts(key_super_left) == ''
	mut index := desktop.window_index(id) or { panic('missing tiled window') }
	assert desktop.windows[index].snap == .left
	assert desktop.windows[index].x == 0 && desktop.windows[index].y == 0
	assert desktop.windows[index].width == 400 && desktop.windows[index].height == 601

	desktop.take_window_shortcuts(key_super_up)
	index = desktop.window_index(id) or { panic('missing top-left window') }
	assert desktop.windows[index].snap == .top_left
	assert desktop.windows[index].width == 400 && desktop.windows[index].height == 300

	desktop.take_window_shortcuts(key_super_right)
	index = desktop.window_index(id) or { panic('missing top-right window') }
	assert desktop.windows[index].snap == .top_right
	assert desktop.windows[index].x == 400 && desktop.windows[index].width == 401

	desktop.take_window_shortcuts(key_super_down)
	index = desktop.window_index(id) or { panic('missing bottom-right window') }
	assert desktop.windows[index].snap == .bottom_right
	assert desktop.windows[index].y == 300 && desktop.windows[index].height == 301

	// A second Down leaves tiling and returns to the original floating frame.
	desktop.take_window_shortcuts(key_super_down)
	index = desktop.window_index(id) or { panic('missing restored window') }
	assert desktop.windows[index].snap == .none_
	assert desktop.windows[index].x == 100 && desktop.windows[index].y == 80
	assert desktop.windows[index].width == 380 && desktop.windows[index].height == 240

	// Up and Down retain their conventional maximize/restore behavior when no
	// horizontal tile supplies a side for a quarter.
	desktop.take_window_shortcuts(key_super_up)
	index = desktop.window_index(id) or { panic('missing maximized window') }
	assert desktop.windows[index].maximized
	desktop.take_window_shortcuts(key_super_down)
	index = desktop.window_index(id) or { panic('missing unmaximized window') }
	assert !desktop.windows[index].maximized
	assert desktop.windows[index].x == 100 && desktop.windows[index].y == 80
}

fn test_moving_or_closing_a_workspace_window_selects_only_a_local_successor() {
	mut desktop := workspace_fixture()
	one := desktop.spawn('One', .welcome, 20, 20, 300, 200)
	two := desktop.spawn('Two', .notes, 40, 40, 300, 200)
	desktop.move_window_to_workspace(two, 2)
	assert desktop.focus == one
	desktop.close_window(one)
	assert desktop.focus == 0
	desktop.switch_workspace(2)
	assert desktop.focus == two
}
