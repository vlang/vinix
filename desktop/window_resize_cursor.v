// SPDX-License-Identifier: GPL-2.0-or-later
module main

// The backing covers the normal pointer and the resize arrows' one-pixel
// outline, so changing shape or moving the pointer erases every old pixel.
const cursor_backing_inset = 9
const cursor_backing_width = cursor_backing_inset + catalina_cursor_width + 1
const cursor_backing_height = cursor_backing_inset + catalina_cursor_height + 1

enum WindowResizeCursor {
	none_
	horizontal
	vertical
	nwse
	nesw
}

fn window_resize_cursor_for_action(action string) WindowResizeCursor {
	if !window_resize_action(action) {
		return .none_
	}
	if action.ends_with('.resize_w') || action.ends_with('.resize_e') {
		return .horizontal
	}
	if action.ends_with('.resize_n') || action.ends_with('.resize_s') {
		return .vertical
	}
	if action.ends_with('.resize_ne') || action.ends_with('.resize_sw') {
		return .nesw
	}
	return .nwse
}

fn (d &Desktop) window_resize_cursor_kind() WindowResizeCursor {
	if d.window_overlay_active() {
		return .none_
	}
	if d.drag.kind == .resize {
		if !d.drag.resize_horizontal {
			return .vertical
		}
		if !d.drag.resize_vertical {
			return .horizontal
		}
		return if d.drag.resize_left == d.drag.resize_top { .nwse } else { .nesw }
	}
	action, world := d.hit_action_world(d.pointer_x, d.pointer_y)
	if world != .desktop {
		return .none_
	}
	return window_resize_cursor_for_action(action)
}

// The arrows occupy a 17-pixel square with their hotspot in the middle.
// Computing coverage retains no per-frame masks or temporary strings.
fn window_resize_cursor_pixel(kind WindowResizeCursor, x int, y int) bool {
	if x < 0 || x > 16 || y < 0 || y > 16 {
		return false
	}
	mut col := x
	mut row := y
	if kind == .vertical {
		col, row = y, x
	}
	if kind == .horizontal || kind == .vertical {
		distance := if row > 8 { row - 8 } else { 8 - row }
		return (col >= 4 && col <= 12 && distance <= 1)
			|| (col <= 4 && distance <= col)
			|| (col >= 12 && distance <= 16 - col)
	}
	if kind == .nesw {
		col = 16 - col
	}
	if kind == .nwse || kind == .nesw {
		distance := if col > row { col - row } else { row - col }
		return (col >= 2 && col <= 14 && row >= 2 && row <= 14 && distance <= 1)
			|| (col >= 2 && row >= 2 && col + row <= 9)
			|| (col <= 14 && row <= 14 && col + row >= 23)
	}
	return false
}

fn (mut d Desktop) draw_window_resize_cursor(kind WindowResizeCursor) {
	for row in -1 .. 18 {
		for col in -1 .. 18 {
			core := window_resize_cursor_pixel(kind, col, row)
			mut outline := false
			if !core {
				for dy in -1 .. 2 {
					for dx in -1 .. 2 {
						if window_resize_cursor_pixel(kind, col + dx, row + dy) {
							outline = true
						}
					}
				}
			}
			if core || outline {
				d.canvas.blend_pixel(d.pointer_x + col - 8, d.pointer_y + row - 8,
					if core { u32(0x000000) } else { u32(0xffffff) }, 255)
			}
		}
	}
}
