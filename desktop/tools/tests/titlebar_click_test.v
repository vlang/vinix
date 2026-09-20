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
