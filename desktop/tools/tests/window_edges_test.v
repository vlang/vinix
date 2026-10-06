// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn edge_test_desktop() Desktop {
	return Desktop{
		canvas: Canvas{
			width:  800
			height: 600
		}
	}
}

fn edge_test_targets(mut desktop Desktop, id int) {
	index := desktop.window_index(id) or { panic('missing edge test window') }
	frame := desktop.window_element(index)
	desktop.targets.clear()
	desktop.record_subtree_targets(&frame, desktop.windows[index].x, desktop.windows[index].y,
		desktop.windows[index].width, desktop.windows[index].height)
	free_tree(frame)
}

fn edge_test_start(mut desktop Desktop, id int, edge string) (int, int) {
	edge_test_targets(mut desktop, id)
	index := desktop.window_index(id) or { panic('missing edge test window') }
	window := desktop.windows[index]
	x := match edge {
		'w' { window.x }
		'e' { window.x + window.width - 1 }
		else { window.x + window.width / 2 }
	}
	y := match edge {
		'n' { window.y }
		's' { window.y + window.height - 1 }
		else { window.y + window.height / 2 }
	}
	assert desktop.hit_action(x, y) == 'win.${id}.resize_${edge}'
	desktop.on_pointer_down(x, y)
	assert desktop.drag.kind == .resize
	desktop.buttons = button_left
	return x, y
}

fn test_all_window_edges_expose_axis_specific_grips() {
	for theme in [ThemeKind.default_, ThemeKind.macos] {
		for side in [ButtonSide.left, ButtonSide.right] {
			mut desktop := edge_test_desktop()
			desktop.settings.theme = theme
			desktop.settings.button_side = side
			id := desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
			edge_test_targets(mut desktop, id)
			assert desktop.hit_action(320, 80) == 'win.${id}.resize_n'
			assert desktop.hit_action(320, 339) == 'win.${id}.resize_s'
			assert desktop.hit_action(120, 210) == 'win.${id}.resize_w'
			assert desktop.hit_action(519, 210) == 'win.${id}.resize_e'
			assert desktop.hit_action(320, 82) == 'win.${id}.resize_n'
			assert desktop.hit_action(320, 80 + desktop.theme().title_height / 2) == 'win.${id}.titlebar'
			assert desktop.hit_action(320, 210) == 'win.${id}.body'
			frame := desktop.window_element(0)
			mut edges := 0
			for child in frame.children {
				if child.id in ['win.${id}.resize_n', 'win.${id}.resize_s'] {
					assert child.cursor == ui2.cursor_resize_ns
					edges++
				} else if child.id in ['win.${id}.resize_w', 'win.${id}.resize_e'] {
					assert child.cursor == ui2.cursor_resize_ew
					edges++
				}
			}
			assert edges == 4
			free_tree(frame)
		}
	}
}

fn test_horizontal_edge_resize_keeps_height_and_opposite_edge() {
	for edge in ['w', 'e'] {
		mut desktop := edge_test_desktop()
		id := desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
		x, y := edge_test_start(mut desktop, id, edge)
		desktop.on_pointer_move(x + if edge == 'w' { -80 } else { 80 }, y + 150)
		index := desktop.window_index(id) or { panic('missing resized window') }
		assert desktop.windows[index].width == 480
		assert desktop.windows[index].height == 260
		assert desktop.windows[index].y == 80
		if edge == 'w' {
			assert desktop.windows[index].x == 40
			assert desktop.windows[index].x + desktop.windows[index].width == 520
		} else {
			assert desktop.windows[index].x == 120
		}
		desktop.buttons = 0
		desktop.on_pointer_up(x, y)
		assert desktop.drag.kind == .none_
		assert desktop.windows[index].restore_width == 480
		assert desktop.windows[index].restore_height == 260
		assert desktop.windows[index].restore_x == desktop.windows[index].x
	}
}

fn test_vertical_edge_resize_keeps_width_and_opposite_edge() {
	for edge in ['n', 's'] {
		mut desktop := edge_test_desktop()
		id := desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
		x, y := edge_test_start(mut desktop, id, edge)
		desktop.on_pointer_move(x + 250, y + if edge == 'n' { -50 } else { 50 })
		index := desktop.window_index(id) or { panic('missing resized window') }
		assert desktop.windows[index].width == 400
		assert desktop.windows[index].x == 120
		assert desktop.windows[index].height == 310
		if edge == 'n' {
			assert desktop.windows[index].y == 30
			assert desktop.windows[index].y + desktop.windows[index].height == 340
		} else {
			assert desktop.windows[index].y == 80
		}
		desktop.buttons = 0
		desktop.on_pointer_up(x, y)
		assert desktop.drag.kind == .none_
		assert desktop.windows[index].restore_width == 400
		assert desktop.windows[index].restore_height == 310
		assert desktop.windows[index].restore_y == desktop.windows[index].y
	}
}

fn test_each_edge_respects_minimum_size_and_usable_screen() {
	for edge in ['n', 's', 'w', 'e'] {
		mut desktop := edge_test_desktop()
		id := desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
		x, y := edge_test_start(mut desktop, id, edge)
		shrink_x := if edge == 'w' {
			1_100
		} else if edge == 'e' {
			-100
		} else {
			x
		}
		shrink_y := if edge == 'n' {
			1_100
		} else if edge == 's' {
			-100
		} else {
			y
		}
		desktop.on_pointer_move(shrink_x, shrink_y)
		index := desktop.window_index(id) or { panic('missing resized window') }
		if edge in ['w', 'e'] {
			assert desktop.windows[index].width == window_min_width
			assert desktop.windows[index].height == 260
		} else {
			assert desktop.windows[index].height == desktop.theme().title_height + window_min_body_height
			assert desktop.windows[index].width == 400
		}
		grow_x := if edge == 'w' {
			-100
		} else if edge == 'e' {
			1_100
		} else {
			x
		}
		grow_y := if edge == 'n' {
			-100
		} else if edge == 's' {
			1_100
		} else {
			y
		}
		desktop.on_pointer_move(grow_x, grow_y)
		match edge {
			'w' {
				assert desktop.windows[index].x == 0
			}
			'e' {
				assert desktop.windows[index].x + desktop.windows[index].width == 800
			}
			'n' {
				assert desktop.windows[index].y == 0
			}
			's' {
				assert desktop.windows[index].y + desktop.windows[index].height == 600 - taskbar_height
			}
			else {}
		}
	}
}

fn test_edge_resize_preserves_untouched_dimension_of_partly_offscreen_window() {
	mut desktop := edge_test_desktop()
	id := desktop.spawn('Welcome', .welcome, -50, 80, 400, 700)
	x, y := edge_test_start(mut desktop, id, 'e')
	desktop.on_pointer_move(x + 20, y + 50)
	index := desktop.window_index(id) or { panic('missing resized window') }
	assert desktop.windows[index].width == 420
	assert desktop.windows[index].height == 700
	assert desktop.windows[index].y == 80
	assert desktop.windows[index].x == -50
}

fn test_arranged_windows_have_no_edge_resize_targets() {
	mut desktop := edge_test_desktop()
	id := desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
	desktop.snap_window(id, .left)
	edge_test_targets(mut desktop, id)
	for target in desktop.targets {
		assert !window_resize_action(target.action_id)
	}
	desktop.maximize(id)
	edge_test_targets(mut desktop, id)
	for target in desktop.targets {
		assert !window_resize_action(target.action_id)
	}
}

fn test_resize_cursor_tracks_axes_and_keeps_direction_during_capture() {
	assert window_resize_cursor_for_action('win.1.resize_w') == .horizontal
	assert window_resize_cursor_for_action('win.1.resize_e') == .horizontal
	assert window_resize_cursor_for_action('win.1.resize_n') == .vertical
	assert window_resize_cursor_for_action('win.1.resize_s') == .vertical
	assert window_resize_cursor_for_action('win.1.resize_nw') == .nwse
	assert window_resize_cursor_for_action('win.1.resize') == .nwse
	assert window_resize_cursor_for_action('win.1.resize_ne') == .nesw
	assert window_resize_cursor_for_action('win.1.resize_sw') == .nesw
	assert window_resize_cursor_for_action('win.1.titlebar') == .none_
	mut desktop := edge_test_desktop()
	id := desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
	x, y := edge_test_start(mut desktop, id, 'w')
	desktop.on_pointer_move(x + 50, y + 50)
	assert desktop.window_resize_cursor_kind() == .horizontal
	desktop.drag = Drag{}
	desktop.targets = [HitTarget{
		action_id: 'win.1.resize_w'
		world:     .application
		x:         0
		y:         0
		width:     800
		height:    600
	}]
	assert desktop.window_resize_cursor_kind() == .none_
}

fn test_resize_cursor_backing_erases_every_pixel_at_both_scales() {
	background := u32(0x445566)
	for scale in [1, 2] {
		for kind in [WindowResizeCursor.horizontal, .vertical, .nwse, .nesw] {
			mut desktop := Desktop{
				canvas:    new_scaled_canvas(80, 80, 80 * scale, 80 * scale, scale)
				pointer_x: 25
				pointer_y: 25
			}
			defer {
				unsafe {
					free(desktop.canvas.pixels)
					desktop.cursor_backing.pixels.free()
				}
			}
			desktop.canvas.clear(background)
			desktop.save_cursor_backing(Clip{ x: 0, y: 0, w: 80, h: 80 })
			desktop.draw_window_resize_cursor(kind)
			box := desktop.cursor_backing.box
			for py in 0 .. 80 * scale {
				for px in 0 .. 80 * scale {
					if unsafe { desktop.canvas.pixels[py * desktop.canvas.stride + px] } != background {
						assert px >= box.x * scale && px < (box.x + box.w) * scale
						assert py >= box.y * scale && py < (box.y + box.h) * scale
					}
				}
			}
			desktop.copy_cursor_backing(box, box, false)
			for py in 0 .. 80 * scale {
				for px in 0 .. 80 * scale {
					assert unsafe { desktop.canvas.pixels[py * desktop.canvas.stride + px] } == background
				}
			}
		}
	}
}

fn test_modal_window_controls_keep_cursor_visible_over_a_game_surface() {
	for overview in [true, false] {
		mut desktop := Desktop{
			canvas: new_canvas(80, 80)
			pointer_x: 40
			pointer_y: 40
		}
		defer { unsafe { free(desktop.canvas.pixels) } }
		background := u32(0x123456)
		desktop.canvas.fill_rect(0, 0, 80, 80, background)
		id := desktop.spawn('Game', .welcome, 0, 0, 80, 80)
		index := desktop.window_index(id) or { panic('missing game') }
		desktop.windows[index].hide_body_cursor = true
		desktop.draw_cursor()
		for i in 0 .. 80 * 80 {
			assert unsafe { desktop.canvas.pixels[i] } == background
		}
		desktop.overview.active = overview
		desktop.window_layout.active = !overview
		desktop.draw_cursor()
		mut painted := false
		for i in 0 .. 80 * 80 {
			if unsafe { desktop.canvas.pixels[i] } != background {
				painted = true
				break
			}
		}
		assert painted
	}
}
