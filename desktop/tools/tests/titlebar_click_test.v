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
