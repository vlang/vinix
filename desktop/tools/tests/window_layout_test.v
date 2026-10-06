// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn layout_test_fixture() Desktop {
	return Desktop{ canvas: Canvas{ width: 801, height: 601 } }
}

fn layout_test_element(element ui2.Element, id string) ?ui2.Element {
	if element.id == id { return element }
	for child in element.children {
		found := layout_test_element(child, id) or { continue }
		return found
	}
	return none
}

fn test_layout_shortcut_opens_visible_choices_and_preserves_super_release() {
	mut desktop := layout_test_fixture()
	id := desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
	assert desktop.take_window_layout_keys('before${key_super_z}typed') == 'before'
	assert desktop.window_layout.active
	assert desktop.window_layout.window_id == id
	assert desktop.take_window_layout_keys(quick_launch_cmd_release) == ''
	assert desktop.window_layout.active
	root := desktop.build_tree()
	panel := layout_test_element(root, window_layout_panel_id) or { panic('missing layout panel') }
	assert panel.clickable
	for action in window_layout_actions {
		choice := layout_test_element(panel, action) or { panic('missing layout choice') }
		assert choice.clickable
		assert choice.children.len == 2
	}
	free_tree(root)
	assert desktop.take_window_layout_keys('\x1bqueued typing') == ''
	assert !desktop.window_layout.active
}

fn test_layout_arrows_enter_and_atomic_chord_arrange_the_anchored_window() {
	mut desktop := layout_test_fixture()
	id := desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
	// Maximize -> Left half -> Top right in the four-column chooser.
	assert desktop.take_window_layout_keys('${key_super_z}\x1b[C\x1b[B\rqueued typing') == ''
	assert !desktop.window_layout.active
	index := desktop.window_index(id) or { panic('missing tiled window') }
	assert desktop.windows[index].snap == .top_right
	assert desktop.windows[index].x == 400
	assert desktop.windows[index].y == 0
	assert desktop.windows[index].width == 401
	assert desktop.windows[index].height == desktop_usable_height(601) / 2
	assert desktop.windows[index].restore_x == 120
	assert desktop.windows[index].restore_y == 80
}

fn test_layout_keeps_anchor_when_focus_changes_and_restores_normal_frame() {
	mut desktop := layout_test_fixture()
	one := desktop.spawn('One', .welcome, 120, 80, 400, 260)
	two := desktop.spawn('Two', .welcome, 200, 140, 300, 220)
	desktop.open_window_layout(one)
	desktop.raise(two)
	assert desktop.handle_window_layout_action('layout.left')
	mut index := desktop.window_index(one) or { panic('missing anchored window') }
	assert desktop.windows[index].snap == .left
	other := desktop.window_index(two) or { panic('missing other window') }
	assert desktop.windows[other].snap == .none_
	desktop.open_window_layout(one)
	assert desktop.window_layout.selected == 1
	assert desktop.handle_window_layout_action('layout.bottom_right')
	desktop.open_window_layout(one)
	assert desktop.handle_window_layout_action('layout.maximize')
	desktop.open_window_layout(one)
	assert desktop.window_layout.selected == 3
	assert desktop.handle_window_layout_action('layout.restore')
	index = desktop.window_index(one) or { panic('missing restored window') }
	assert !desktop.windows[index].maximized
	assert desktop.windows[index].snap == .none_
	assert desktop.windows[index].x == 120
	assert desktop.windows[index].y == 80
	assert desktop.windows[index].width == 400
	assert desktop.windows[index].height == 260
}

fn test_layout_pointer_choice_consumes_chrome_gesture_and_click_away_closes() {
	mut desktop := layout_test_fixture()
	id := desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
	desktop.open_window_layout(id)
	desktop.targets << HitTarget{ action_id: 'layout.right', x: 50, y: 50, width: 100, height: 80 }
	desktop.on_pointer_down(60, 60)
	assert !desktop.window_layout.active
	assert desktop.chrome_pointer_capture
	index := desktop.window_index(id) or { panic('missing pointer-tiled window') }
	assert desktop.windows[index].snap == .right
	desktop.on_pointer_up(60, 60)
	assert !desktop.chrome_pointer_capture
	desktop.open_window_layout(id)
	desktop.targets.clear()
	desktop.on_pointer_down(400, 400)
	assert !desktop.window_layout.active
}

fn test_right_click_maximize_opens_layout_only_for_desktop_chrome() {
	mut desktop := layout_test_fixture()
	id := desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
	index := desktop.window_index(id) or { panic('missing maximize target') }
	desktop.targets << HitTarget{
		action_id: desktop.windows[index].id_maximize
		x:         200
		y:         100
		width:     24
		height:    24
		world:     .application
	}
	assert !desktop.window_layout_right_down(210, 110)
	assert !desktop.window_layout.active
	desktop.targets[0] = HitTarget{ ...desktop.targets[0], world: .desktop }
	assert desktop.window_layout_right_down(210, 110)
	assert desktop.window_layout.active
	assert desktop.window_layout.window_id == id
	assert desktop.window_layout_right_release
	// A secondary click dismisses the modal overlay and consumes its release.
	desktop.window_layout_right_release = false
	assert desktop.window_layout_right_down(700, 450)
	assert !desktop.window_layout.active
	assert desktop.window_layout_right_release
}

fn test_layout_closes_other_overlays_and_invalid_anchor() {
	mut desktop := layout_test_fixture()
	id := desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
	desktop.toggle_quick_launch()
	assert desktop.switcher.active
	desktop.open_window_layout(id)
	assert !desktop.switcher.active
	assert desktop.window_layout.active
	desktop.minimize(id)
	assert desktop.window_layout_element() == none
	assert !desktop.window_layout.active
	desktop.activate(id)
	desktop.open_window_layout(id)
	desktop.close_window(id)
	assert desktop.take_window_layout_keys('app text') == 'app text'
	assert !desktop.window_layout.active
}

fn test_layout_no_focus_is_safe_and_panel_stays_above_taskbar() {
	mut desktop := layout_test_fixture()
	assert desktop.take_window_layout_keys(key_super_z) == ''
	assert !desktop.window_layout.active
	assert desktop.take_window_layout_keys('\x1b[Aplain') == '\x1b[Aplain'
	id := desktop.spawn('Welcome', .welcome, 650, 450, 300, 220)
	desktop.open_window_layout(id)
	frame := desktop.window_layout_bounds()
	assert frame.valid
	assert frame.x >= 12
	assert frame.y >= 12
	assert frame.x + frame.w <= desktop.canvas.width - 12
	assert frame.y + frame.h <= desktop_usable_height(desktop.canvas.height) - 12
	assert desktop.handle_window_layout_action(window_layout_panel_id)
	assert desktop.window_layout.active
	assert !desktop.handle_window_layout_action('application.other')
}

fn test_layout_compacts_choices_on_small_logical_desktops() {
	mut desktop := Desktop{ canvas: Canvas{ width: 320, height: 240 } }
	id := desktop.spawn('Welcome', .welcome, 20, 20, 240, 140)
	desktop.open_window_layout(id)
	panel := desktop.window_layout_element() or { panic('missing compact layout panel') }
	assert panel.frame.x >= 0
	assert panel.frame.y >= 0
	assert panel.frame.x + panel.frame.width <= 320
	assert panel.frame.y + panel.frame.height <= desktop_usable_height(240)
	for action in window_layout_actions {
		choice := layout_test_element(panel, action) or { panic('missing compact layout choice') }
		assert choice.frame.width >= 16
		assert choice.frame.height >= 24
		assert choice.frame.x + choice.frame.width <= panel.frame.width
		assert choice.frame.y + choice.frame.height <= panel.frame.height
		assert choice.children.len == 1
	}
	free_tree(panel)
}
