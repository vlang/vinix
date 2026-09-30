// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn set_titlebar_test_target(mut desktop Desktop, id int) {
	index := desktop.window_index(id) or { panic('missing test window') }
	window := desktop.windows[index]
	target := HitTarget{
		action_id: 'win.${id}.titlebar'
		x: window.x
		y: window.y
		width: window.width
		height: desktop.theme().title_height
	}
	if desktop.targets.len == 0 {
		desktop.targets << target
	} else {
		desktop.targets[0] = target
	}
}

fn test_titlebar_double_click_matches_maximize_button() {
	mut desktop := Desktop{
		canvas: Canvas{
			width: 800
			height: 600
		}
	}
	id := desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
	set_titlebar_test_target(mut desktop, id)
	title_height := desktop.theme().title_height
	first_x := 200
	first_y := 80 + title_height / 2
	mut click := TitlebarClick{}

	// A tiny movement between the two presses is still a double click. The
	// first press starts the normal title-bar drag, so make that jitter real and
	// verify the eventual maximize still remembers the pre-click restore frame.
	click = desktop.titlebar_pointer_down_at(click, first_x, first_y, 1_000)
	desktop.buttons = button_left
	desktop.on_pointer_move(first_x + 2, first_y + 2)
	desktop.buttons = 0
	desktop.on_pointer_up(first_x + 2, first_y + 2)
	set_titlebar_test_target(mut desktop, id)
	click = desktop.titlebar_pointer_down_at(click, first_x + 2, first_y + 2, 1_300)
	assert click.window_id == 0
	assert desktop.windows.last().maximized
	assert desktop.windows.last().x == 0
	assert desktop.windows.last().y == 0
	assert desktop.windows.last().width == 800
	assert desktop.windows.last().height == 600 - taskbar_height
	assert desktop.windows.last().restore_x == 120
	assert desktop.windows.last().restore_y == 80
	assert desktop.windows.last().restore_width == 400
	assert desktop.windows.last().restore_height == 260
	assert desktop.drag.kind == .none_
	desktop.on_pointer_up(first_x + 2, first_y + 2)

	// Do the same while maximized. A normal drag would restore the window on
	// the first movement; the matching second press must still finish exactly
	// where the maximize button's restore action would have put it.
	set_titlebar_test_target(mut desktop, id)
	max_x := 400
	max_y := title_height / 2
	click = desktop.titlebar_pointer_down_at(click, max_x, max_y, 2_000)
	desktop.buttons = button_left
	desktop.on_pointer_move(max_x + 2, max_y + 2)
	assert !desktop.windows.last().maximized
	desktop.buttons = 0
	desktop.on_pointer_up(max_x + 2, max_y + 2)
	set_titlebar_test_target(mut desktop, id)
	click = desktop.titlebar_pointer_down_at(click, max_x + 2, max_y + 2, 2_300)
	assert click.window_id == 0
	assert !desktop.windows.last().maximized
	assert desktop.windows.last().x == 120
	assert desktop.windows.last().y == 80
	assert desktop.windows.last().width == 400
	assert desktop.windows.last().height == 260
	assert desktop.drag.kind == .none_
}

fn test_titlebar_double_click_limits_time_and_pointer_slop() {
	previous := TitlebarClick{
		window_id: 7
		x: 100
		y: 50
		at_ms: 1_000
	}
	assert titlebar_click_matches(previous, 7, 105, 45, 1_500)
	assert !titlebar_click_matches(previous, 7, 106, 50, 1_100)
	assert !titlebar_click_matches(previous, 7, 100, 50, 1_501)
	assert !titlebar_click_matches(previous, 8, 100, 50, 1_100)
	assert !titlebar_click_matches(previous, 7, 100, 50, 900)
}

fn test_titlebar_drag_can_move_partly_offscreen() {
	mut desktop := Desktop{
		canvas: Canvas{
			width: 800
			height: 600
		}
	}
	id := desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
	set_titlebar_test_target(mut desktop, id)
	title_y := 80 + desktop.theme().title_height / 2

	// Taking the pointer to the left edge carries the frame beyond it instead
	// of pinning x at zero. Enough title bar remains visible to recover it.
	desktop.on_pointer_down(300, title_y)
	desktop.buttons = button_left
	desktop.on_pointer_move(0, title_y)
	left_index := desktop.window_index(id) or { panic('missing dragged window') }
	assert desktop.windows[left_index].x < 0
	assert desktop.windows[left_index].x + desktop.windows[left_index].width >= 60
	desktop.buttons = 0
	// Release one pixel inside the edge so this test can keep exercising free
	// off-screen movement; exact-edge release is covered by the snap tests.
	desktop.on_pointer_up(1, title_y)

	// The right edge behaves the same way.
	set_titlebar_test_target(mut desktop, id)
	desktop.on_pointer_down(100, title_y)
	desktop.buttons = button_left
	desktop.on_pointer_move(799, title_y)
	right_index := desktop.window_index(id) or { panic('missing dragged window') }
	assert desktop.windows[right_index].x + desktop.windows[right_index].width > 800
	assert desktop.windows[right_index].x <= 800 - 60
	desktop.buttons = 0
	desktop.on_pointer_up(798, title_y)

	// Downward movement can hide the body too. The title bar remains above the
	// taskbar, so the window can still be dragged back onto the desktop.
	set_titlebar_test_target(mut desktop, id)
	current := desktop.window_index(id) or { panic('missing dragged window') }
	grab_x := desktop.windows[current].x + 30
	desktop.on_pointer_down(grab_x, title_y)
	desktop.buttons = button_left
	desktop.on_pointer_move(grab_x, 599)
	down_index := desktop.window_index(id) or { panic('missing dragged window') }
	assert desktop.windows[down_index].y == 600 - taskbar_height - desktop.theme().title_height
	assert desktop.windows[down_index].y + desktop.windows[down_index].height > 600
}

fn drag_window_to(mut desktop Desktop, id int, x int, y int) {
	set_titlebar_test_target(mut desktop, id)
	index := desktop.window_index(id) or { panic('missing dragged window') }
	press_x := desktop.windows[index].x + desktop.windows[index].width / 2
	press_y := desktop.windows[index].y + desktop.theme().title_height / 2
	desktop.on_pointer_down(press_x, press_y)
	desktop.buttons = button_left
	desktop.on_pointer_move(x, y)
	desktop.buttons = 0
	desktop.on_pointer_up(x, y)
}

fn test_titlebar_drag_snaps_to_screen_edges_and_restores_when_pulled_away() {
	mut desktop := Desktop{
		canvas: Canvas{
			width:  801
			height: 600
		}
	}
	id := desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)

	drag_window_to(mut desktop, id, 0, 300)
	mut index := desktop.window_index(id) or { panic('missing left-snapped window') }
	assert desktop.windows[index].snap == .left
	assert !desktop.windows[index].maximized
	assert desktop.windows[index].x == 0
	assert desktop.windows[index].y == 0
	assert desktop.windows[index].width == 400
	assert desktop.windows[index].height == 600 - taskbar_height
	assert desktop.windows[index].restore_width == 400
	assert desktop.windows[index].restore_height == 260

	// Pulling a half-screen window away restores its normal dimensions while
	// keeping the pointer at the same proportional place on the title bar.
	set_titlebar_test_target(mut desktop, id)
	desktop.on_pointer_down(200, desktop.theme().title_height / 2)
	desktop.buttons = button_left
	desktop.on_pointer_move(500, 100)
	index = desktop.window_index(id) or { panic('missing restored window') }
	assert desktop.windows[index].snap == .none_
	assert desktop.windows[index].width == 400
	assert desktop.windows[index].height == 260
	assert desktop.windows[index].x == 300
	desktop.buttons = 0
	desktop.on_pointer_up(500, 100)

	drag_window_to(mut desktop, id, 800, 300)
	index = desktop.window_index(id) or { panic('missing right-snapped window') }
	assert desktop.windows[index].snap == .right
	assert !desktop.windows[index].maximized
	assert desktop.windows[index].x == 400
	assert desktop.windows[index].y == 0
	assert desktop.windows[index].width == 401
	assert desktop.windows[index].height == 600 - taskbar_height

	// Maximizing a snapped window and restoring it must return to the normal
	// frame, not treat the half-screen frame as its new restore geometry.
	desktop.toggle_maximize(id)
	index = desktop.window_index(id) or { panic('missing maximized snapped window') }
	assert desktop.windows[index].maximized
	desktop.toggle_maximize(id)
	index = desktop.window_index(id) or { panic('missing restored snapped window') }
	assert !desktop.windows[index].maximized
	assert desktop.windows[index].snap == .none_
	assert desktop.windows[index].width == 400
	assert desktop.windows[index].height == 260
}

fn test_titlebar_drag_to_top_maximizes_on_release() {
	mut desktop := Desktop{
		canvas: Canvas{
			width:  800
			height: 600
		}
	}
	id := desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
	set_titlebar_test_target(mut desktop, id)
	desktop.on_pointer_down(320, 80 + desktop.theme().title_height / 2)
	desktop.buttons = button_left
	desktop.on_pointer_move(400, 0)
	mut index := desktop.window_index(id) or { panic('missing dragged window') }
	assert !desktop.windows[index].maximized

	// The real pointer pump observes the released button level during its move
	// pass before dispatching the release edge, so exercise that path directly.
	desktop.buttons = 0
	desktop.on_pointer_move(400, 0)
	index = desktop.window_index(id) or { panic('missing maximized window') }
	assert desktop.windows[index].maximized
	assert desktop.windows[index].snap == .none_
	assert desktop.windows[index].x == 0
	assert desktop.windows[index].y == 0
	assert desktop.windows[index].width == 800
	assert desktop.windows[index].height == 600 - taskbar_height
	assert desktop.drag.kind == .none_
}

fn test_edge_snap_uses_last_position_seen_while_button_was_held() {
	mut desktop := Desktop{
		canvas: Canvas{
			width:  800
			height: 600
		}
	}
	id := desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
	title_y := 80 + desktop.theme().title_height / 2
	set_titlebar_test_target(mut desktop, id)
	desktop.on_pointer_down(320, title_y)
	desktop.buttons = button_left
	desktop.on_pointer_move(0, title_y)

	// A wrapped button-up coordinate on the opposite edge must not turn a
	// left snap into a right snap.
	desktop.buttons = 0
	desktop.on_pointer_move(799, title_y)
	mut index := desktop.window_index(id) or { panic('missing left-snapped window') }
	assert desktop.windows[index].snap == .left
	assert desktop.windows[index].x == 0
	assert desktop.windows[index].width == 400

	// Likewise, wrapping from the top to the bottom while releasing must keep
	// the maximize gesture captured at the top edge.
	set_titlebar_test_target(mut desktop, id)
	desktop.on_pointer_down(200, desktop.theme().title_height / 2)
	desktop.buttons = button_left
	desktop.on_pointer_move(400, 0)
	desktop.buttons = 0
	desktop.on_pointer_move(400, 599)
	index = desktop.window_index(id) or { panic('missing maximized window') }
	assert desktop.windows[index].maximized
	assert desktop.windows[index].x == 0
	assert desktop.windows[index].y == 0
	assert desktop.windows[index].width == 800
	assert desktop.windows[index].height == 600 - taskbar_height
}

fn test_clicking_an_edge_touching_titlebar_does_not_snap_without_a_drag() {
	mut desktop := Desktop{
		canvas: Canvas{
			width:  800
			height: 600
		}
	}
	id := desktop.spawn('Welcome', .welcome, 120, 0, 400, 260)
	set_titlebar_test_target(mut desktop, id)
	x := 320
	y := 0
	desktop.on_pointer_move(x, y)
	desktop.on_pointer_down(x, y)
	desktop.on_pointer_up(x, y)
	index := desktop.window_index(id) or { panic('missing clicked window') }
	assert !desktop.windows[index].maximized
	assert desktop.windows[index].snap == .none_
	assert desktop.windows[index].x == 120
	assert desktop.windows[index].y == 0
}

fn set_resize_test_target(mut desktop Desktop, id int) {
	index := desktop.window_index(id) or { panic('missing test window') }
	window := desktop.windows[index]
	set_corner_test_target(mut desktop, window.id_resize, window.x + window.width - window_resize_grip_size,
		window.y + window.height - window_resize_grip_size)
}

fn set_corner_test_target(mut desktop Desktop, action_id string, x int, y int) {
	target := HitTarget{
		action_id: action_id
		x:         x
		y:         y
		width:     window_resize_grip_size
		height:    window_resize_grip_size
	}
	if desktop.targets.len == 0 {
		desktop.targets << target
	} else {
		desktop.targets[0] = target
	}
}

// record_window_test_targets collects the hit targets the window's real frame
// produces, as the render pass does.
fn record_window_test_targets(mut desktop Desktop, id int) {
	index := desktop.window_index(id) or { panic('missing test window') }
	frame := desktop.window_element(index)
	desktop.targets.clear()
	desktop.record_subtree_targets(&frame, desktop.windows[index].x, desktop.windows[index].y,
		desktop.windows[index].width, desktop.windows[index].height)
	free_tree(frame)
}

fn test_every_corner_of_a_normal_window_is_a_resize_grip() {
	for side in [ButtonSide.right, ButtonSide.left] {
		for theme in [ThemeKind.default_, ThemeKind.macos] {
			mut desktop := Desktop{
				canvas: Canvas{
					width:  800
					height: 600
				}
			}
			desktop.settings.theme = theme
			desktop.settings.button_side = side
			id := desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
			record_window_test_targets(mut desktop, id)
			index := desktop.window_index(id) or { panic('missing test window') }
			window := desktop.windows[index]
			left := window.x
			top := window.y
			right := window.x + window.width - 1
			bottom := window.y + window.height - 1
			assert desktop.hit_action(right, bottom) == window.id_resize
			assert desktop.hit_action(left, bottom) == window.id_resize_sw
			assert desktop.hit_action(left, top) == window.id_resize_nw
			assert desktop.hit_action(right, top) == window.id_resize_ne
			// The upper grips run along the top and side edges only, leaving
			// the buttons, the title and the bar's drag where they were.
			assert desktop.hit_action(left + window_resize_grip_size - 1, top) == window.id_resize_nw
			assert desktop.hit_action(left, top + window_resize_grip_size - 1) == window.id_resize_nw
			assert desktop.hit_action(right, top + window_resize_grip_size - 1) == window.id_resize_ne
			assert desktop.hit_action(left + window_resize_edge_size, top + window_resize_edge_size) != window.id_resize_nw
			assert desktop.hit_action(right - window_resize_edge_size, top + window_resize_edge_size) != window.id_resize_ne
			buttons := [window.id_close, window.id_maximize, window.id_minimize]
			for target in desktop.targets {
				if target.action_id in buttons {
					assert desktop.hit_action(target.x, target.y) == target.action_id
					assert desktop.hit_action(target.x + target.width - 1, target.y) == target.action_id
				}
			}
		}
	}
}

fn test_maximized_window_has_no_resize_grips() {
	mut desktop := Desktop{
		canvas: Canvas{
			width:  800
			height: 600
		}
	}
	id := desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
	desktop.maximize(id)
	record_window_test_targets(mut desktop, id)
	for target in desktop.targets {
		assert !window_resize_action(target.action_id)
	}
}

fn test_upper_left_corner_moves_the_top_and_left_edges() {
	mut desktop := Desktop{
		canvas: Canvas{
			width:  800
			height: 600
		}
	}
	id := desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
	index := desktop.window_index(id) or { panic('missing resized window') }
	set_corner_test_target(mut desktop, desktop.windows[index].id_resize_nw, 120, 80)
	desktop.on_pointer_down(121, 81)
	assert desktop.drag.kind == .resize
	desktop.buttons = button_left
	desktop.on_pointer_move(71, 41)
	assert desktop.windows[index].x == 70
	assert desktop.windows[index].y == 40
	assert desktop.windows[index].width == 450
	assert desktop.windows[index].height == 300
	// Shrinking stops at the minimum size with the lower-right corner still
	// where it was.
	desktop.on_pointer_move(700, 500)
	assert desktop.windows[index].width == window_min_width
	assert desktop.windows[index].height == desktop.theme().title_height + window_min_body_height
	assert desktop.windows[index].x + desktop.windows[index].width == 520
	assert desktop.windows[index].y + desktop.windows[index].height == 340
	// Growing stops at the screen's top and left edges, so the title bar
	// stays reachable.
	desktop.on_pointer_move(-50, -50)
	assert desktop.windows[index].x == 0
	assert desktop.windows[index].y == 0
	assert desktop.windows[index].width == 520
	assert desktop.windows[index].height == 340
	desktop.buttons = 0
	desktop.on_pointer_up(-50, -50)
	assert desktop.drag.kind == .none_
	assert desktop.windows[index].restore_x == 0
	assert desktop.windows[index].restore_y == 0
	assert desktop.windows[index].restore_width == 520
	assert desktop.windows[index].restore_height == 340
}

fn test_upper_right_and_lower_left_corners_move_their_own_edges() {
	mut desktop := Desktop{
		canvas: Canvas{
			width:  800
			height: 600
		}
	}
	id := desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
	index := desktop.window_index(id) or { panic('missing resized window') }
	set_corner_test_target(mut desktop, desktop.windows[index].id_resize_ne, 520 - window_resize_grip_size,
		80)
	desktop.on_pointer_down(518, 82)
	desktop.buttons = button_left
	desktop.on_pointer_move(568, 52)
	assert desktop.windows[index].x == 120
	assert desktop.windows[index].y == 50
	assert desktop.windows[index].width == 450
	assert desktop.windows[index].height == 290
	desktop.buttons = 0
	desktop.on_pointer_up(568, 52)

	set_corner_test_target(mut desktop, desktop.windows[index].id_resize_sw, 120, 340 - window_resize_grip_size)
	desktop.on_pointer_down(122, 338)
	desktop.buttons = button_left
	desktop.on_pointer_move(92, 368)
	assert desktop.windows[index].x == 90
	assert desktop.windows[index].y == 50
	assert desktop.windows[index].width == 480
	assert desktop.windows[index].height == 320
	// The lower edge stops at the taskbar.
	desktop.on_pointer_move(92, 599)
	assert desktop.windows[index].y + desktop.windows[index].height == 600 - taskbar_height
	desktop.buttons = 0
	desktop.on_pointer_up(92, 599)
	assert desktop.windows[index].restore_x == 90
	assert desktop.windows[index].restore_width == 480
}

fn test_lower_right_corner_resizes_window_and_updates_restore_frame() {
	mut desktop := Desktop{
		canvas: Canvas{
			width:  800
			height: 600
		}
	}
	id := desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
	set_resize_test_target(mut desktop, id)
	desktop.on_pointer_down(519, 339)
	assert desktop.drag.kind == .resize
	desktop.buttons = button_left
	desktop.on_pointer_move(619, 399)
	index := desktop.window_index(id) or { panic('missing resized window') }
	assert desktop.windows[index].x == 120
	assert desktop.windows[index].y == 80
	assert desktop.windows[index].width == 500
	assert desktop.windows[index].height == 320
	desktop.buttons = 0
	desktop.on_pointer_up(619, 399)
	assert desktop.drag.kind == .none_
	assert desktop.windows[index].restore_x == 120
	assert desktop.windows[index].restore_y == 80
	assert desktop.windows[index].restore_width == 500
	assert desktop.windows[index].restore_height == 320
}

fn test_corner_resize_respects_minimum_size_and_usable_desktop() {
	mut desktop := Desktop{
		canvas: Canvas{
			width:  800
			height: 600
		}
	}
	id := desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
	set_resize_test_target(mut desktop, id)
	desktop.on_pointer_down(519, 339)
	desktop.buttons = button_left
	desktop.on_pointer_move(0, 0)
	mut index := desktop.window_index(id) or { panic('missing minimum-sized window') }
	assert desktop.windows[index].width == window_min_width
	assert desktop.windows[index].height == desktop.theme().title_height + window_min_body_height
	desktop.buttons = 0
	desktop.on_pointer_up(0, 0)

	set_resize_test_target(mut desktop, id)
	index = desktop.window_index(id) or { panic('missing window before growth') }
	press_x := desktop.windows[index].x + desktop.windows[index].width - 1
	press_y := desktop.windows[index].y + desktop.windows[index].height - 1
	desktop.on_pointer_down(press_x, press_y)
	desktop.buttons = button_left
	desktop.on_pointer_move(799, 599)
	index = desktop.window_index(id) or { panic('missing maximum-sized window') }
	assert desktop.windows[index].x + desktop.windows[index].width == 800
	assert desktop.windows[index].y + desktop.windows[index].height == 600 - taskbar_height
}
