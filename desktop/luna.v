// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// Luna, for the Windows XP theme: a window's blue title bar and frame, its
// three square caption buttons, and the blue taskbar with its green Start
// button.
//
// None of it is a picture. Each surface is a gradient given as stops, the
// way the bitmaps of Windows XP's own blue style run, and the buttons and
// their marks are shapes drawn over it.
module main

import math
import ui2

// LunaStop is a colour and how far along a gradient it is, in thousandths.
struct LunaStop {
	at    int
	color u32
}

// A focused window's title bar, top to bottom: the bright band under the top
// edge, the long blue, the lighter swell low down, and the dark foot.
const luna_title_active = [LunaStop{0, 0x0058ee}, LunaStop{40, 0x3593ff}, LunaStop{60, 0x288eff},
	LunaStop{80, 0x127dff}, LunaStop{100, 0x036ffc}, LunaStop{140, 0x0262ee},
	LunaStop{200, 0x0057e5}, LunaStop{240, 0x0054e3}, LunaStop{560, 0x0055eb},
	LunaStop{660, 0x005bf5}, LunaStop{760, 0x026afe}, LunaStop{860, 0x0062ef},
	LunaStop{920, 0x0052d6}, LunaStop{940, 0x0040ab}, LunaStop{1000, 0x003092}]
// An unfocused one keeps the shape and loses the colour.
const luna_title_inactive = [LunaStop{0, 0x7697e7}, LunaStop{30, 0x7e9ee3}, LunaStop{60, 0x94afe8},
	LunaStop{80, 0x97b4e9}, LunaStop{140, 0x82a5e4}, LunaStop{170, 0x7c9fe2},
	LunaStop{250, 0x7996de}, LunaStop{560, 0x7b99e1}, LunaStop{810, 0x82a9e9},
	LunaStop{890, 0x80a5e7}, LunaStop{940, 0x7b96e1}, LunaStop{970, 0x7a93df},
	LunaStop{1000, 0xabbae3}]
// The frame's four columns, from the window's edge inward. Light falls from
// the upper left, so the left side is brighter than the right and the bottom.
const luna_frame_left = [u32(0x0831d9), 0x166aee, 0x0855dd, 0x0855dd]!
const luna_frame_right = [u32(0x00138c), 0x001ea0, 0x003bda, 0x0046e0]!
const luna_frame_left_inactive = [u32(0x6582f5), 0x8ba3f0, 0x7b96e8, 0x7b96e8]!
const luna_frame_right_inactive = [u32(0x5f72d6), 0x6a80dc, 0x7089e2, 0x7b96e8]!
// The line around the title bar and its round corners.
const luna_title_edge = u32(0x0831d9)
const luna_title_edge_inactive = u32(0x6582f5)
// A focused window's white title sits on this.
const luna_title_shadow = u32(0x0a246a)

// A caption button's face is lit from the upper left: these run from its
// lower right corner outward. Minimise and maximise are blue, close is red.
const luna_button_face = [LunaStop{0, 0x0054e9}, LunaStop{550, 0x2263d5}, LunaStop{700, 0x4479e4},
	LunaStop{900, 0xa3bbec}, LunaStop{1000, 0xffffff}]
const luna_close_face = [LunaStop{0, 0xcc4600}, LunaStop{550, 0xdc6527}, LunaStop{700, 0xcd7546},
	LunaStop{900, 0xffccb2}, LunaStop{1000, 0xffffff}]
// The white line round a button and its mark, and what both fade to on an
// unfocused window, whose buttons are washed with its title's own blue.
const luna_button_edge = u32(0xffffff)
const luna_button_edge_inactive = u32(0xdbe4f8)
const luna_button_wash = u32(0x8aa5e6)
const luna_button_wash_alpha = u32(120)
// Under the pointer a button is a fifth brighter; held down, a tenth darker.
const luna_button_hover_alpha = u32(46)
const luna_button_pressed_alpha = u32(34)

// The taskbar, top to bottom.
const luna_bar = [LunaStop{0, 0x1f2f86}, LunaStop{30, 0x3165c4}, LunaStop{60, 0x3682e5},
	LunaStop{100, 0x4490e6}, LunaStop{120, 0x3883e5}, LunaStop{150, 0x2b71e0},
	LunaStop{180, 0x2663da}, LunaStop{200, 0x235bd6}, LunaStop{230, 0x2258d5},
	LunaStop{380, 0x2157d6}, LunaStop{540, 0x245ddb}, LunaStop{860, 0x2562df},
	LunaStop{890, 0x245fdc}, LunaStop{920, 0x2158d4}, LunaStop{950, 0x1d4ec0},
	LunaStop{980, 0x1941a5}, LunaStop{1000, 0x1941a5}]
// The notification area and the clock sit in a lighter blue.
const luna_tray = [LunaStop{0, 0x0c59b9}, LunaStop{60, 0x139ee9}, LunaStop{100, 0x18b5f2},
	LunaStop{140, 0x139beb}, LunaStop{190, 0x1290e8}, LunaStop{630, 0x0d8dea},
	LunaStop{810, 0x0d9ff1}, LunaStop{880, 0x0f9eed}, LunaStop{910, 0x119be9},
	LunaStop{940, 0x1392e2}, LunaStop{970, 0x137ed7}, LunaStop{1000, 0x095bc9}]
const luna_tray_edge = u32(0x1042af)
const luna_tray_shine = u32(0x18bbff)
// The Start button's green.
const luna_start = [LunaStop{0, 0x3f9a3c}, LunaStop{70, 0x84d17e}, LunaStop{140, 0x5fbb5b},
	LunaStop{320, 0x46a444}, LunaStop{700, 0x3a9338}, LunaStop{900, 0x2f842f},
	LunaStop{1000, 0x236d24}]
const luna_start_edge = u32(0x1c5a1e)
// Its right end is rounded this far; its left is the screen's edge. The mark
// and the word on it are white on this shadow.
const luna_start_radius = 12
const luna_start_shadow = u32(0x1b5a1d)
const luna_start_mark = 22
const luna_start_text_size = 18
const luna_start_hover_alpha = u32(40)
const luna_start_pressed_alpha = u32(52)
// A button on the bar: a window's, at rest, under the pointer, and pressed in
// for the window that is in front.
const luna_bar_button = u32(0x3c81f3)
const luna_bar_button_hover = u32(0x53a3ff)
const luna_bar_button_pressed = u32(0x1e52b7)
const luna_bar_button_radius = 3

// The Start menu's shell: the header its user tile sits in, the foot the
// session buttons sit in, and the blue between them.
const luna_menu_header = [LunaStop{0, 0x1868ce}, LunaStop{120, 0x0e60cb}, LunaStop{200, 0x0e60cb},
	LunaStop{320, 0x1164cf}, LunaStop{470, 0x1b6cd3}, LunaStop{600, 0x2476dc},
	LunaStop{770, 0x3482e3}, LunaStop{900, 0x428ee9}, LunaStop{1000, 0x4791eb}]
const luna_menu_foot = [LunaStop{0, 0x4282d6}, LunaStop{50, 0x418ae3}, LunaStop{170, 0x418ae3},
	LunaStop{290, 0x3482e3}, LunaStop{490, 0x2374df}, LunaStop{620, 0x196edb},
	LunaStop{750, 0x1468d5}, LunaStop{880, 0x0f61cb}, LunaStop{1000, 0x0f61cb}]
const luna_menu_edge = u32(0x0a48b4)
const luna_menu_radius = 6
// The line under the header, strongest a third of the way along it.
const luna_menu_orange = u32(0xf59a3a)
// The small coloured squares Windows XP sets its marks on, lit from the upper
// left: All Programs' arrow, and the session buttons.
const luna_tile_green_light = u32(0x7fd873)
const luna_tile_green = u32(0x2c8a2c)
const luna_tile_red_light = u32(0xf5927c)
const luna_tile_red = u32(0xb92f18)
const luna_tile_yellow_light = u32(0xfbd978)
const luna_tile_yellow = u32(0xcf8610)

// luna_gradient is the colour `position` of the way through `span` steps of a
// gradient.
fn luna_gradient(stops []LunaStop, position int, span int) u32 {
	at := if span > 1 { position * 1000 / (span - 1) } else { 0 }
	for index in 1 .. stops.len {
		if at <= stops[index].at {
			from := stops[index - 1]
			to := stops[index]
			if to.at <= from.at {
				return to.color
			}
			return mix(from.color, to.color, u32((at - from.at) * 255 / (to.at - from.at)))
		}
	}
	return stops[stops.len - 1].color
}

// luna_row paints one row of a shape whose two upper corners are round.
fn (mut d Desktop) luna_row(x int, y int, w int, row int, radius int, color u32) {
	if row >= radius {
		d.canvas.fill_rect(x, y + row, w, 1, color)
		return
	}
	d.canvas.fill_rect(x + radius, y + row, w - 2 * radius, 1, color)
	for column in 0 .. radius {
		coverage := corner_coverage(f64(column) + 0.5, f64(row) + 0.5, f64(radius), f64(radius),
			f64(radius))
		if coverage == 0 {
			continue
		}
		d.canvas.blend_pixel(x + column, y + row, color, coverage)
		d.canvas.blend_pixel(x + w - 1 - column, y + row, color, coverage)
	}
}

// luna_top_edge draws the line round the top of such a shape: across it,
// round both corners, and down its sides for `rows`.
fn (mut d Desktop) luna_top_edge(x int, y int, w int, rows int, radius int, color u32) {
	saved := d.canvas.push_clip_rect(x, y, w, rows)
	d.canvas.stroke_round_rect(x, y, w, rows + radius + 1, radius, color, 255)
	d.canvas.restore_clip(saved)
}

// ── Windows ────────────────────────────────────────────────────────

// draw_luna_window paints a window's frame: the title bar with its round
// upper corners, and the blue frame down the sides of the body and under it.
// The body itself is the window's child, and a Luna window casts no shadow.
fn (mut d Desktop) draw_luna_window(el &ui2.Element, x int, y int, w int, h int) {
	theme := d.theme()
	active := el.focused
	mut body_x := x
	mut body_y := y + theme.title_height
	for i in 0 .. el.children.len {
		child := unsafe { &el.children[i] }
		if child.id.ends_with('.body') {
			body_x = x + int(child.frame.x)
			body_y = y + int(child.frame.y)
			break
		}
	}
	// A maximized window is its title bar across the screen and nothing else.
	framed := body_x > x
	rows := body_y - y
	radius := if framed { luna_corner_radius } else { 0 }
	stops := if active { luna_title_active } else { luna_title_inactive }
	for row in 0 .. rows {
		d.luna_row(x, y, w, row, radius, luna_gradient(stops, row, rows))
	}
	// A builtin glyph leading the title fills its holes with the bar's blue.
	d.walk.title_under = luna_gradient(stops, rows / 2, rows)
	if !framed {
		return
	}
	d.luna_top_edge(x, y, w, rows, radius, if active { luna_title_edge } else { luna_title_edge_inactive })
	left := if active { luna_frame_left } else { luna_frame_left_inactive }
	right := if active { luna_frame_right } else { luna_frame_right_inactive }
	border := body_x - x
	below := y + h - body_y
	for column in 0 .. border {
		ring := if column < left.len { column } else { left.len - 1 }
		// The sides stop where the bottom's rows of the same ring begin.
		d.canvas.fill_rect(x + column, body_y, 1, below - column, left[ring])
		d.canvas.fill_rect(x + w - 1 - column, body_y, 1, below - column, right[ring])
		d.canvas.fill_rect(x + column, y + h - 1 - column, w - 2 * column, 1, right[ring])
	}
}

enum LunaCaption {
	minimize
	maximize
	close
}

// luna_face_color is a caption button's face at one of its pixels: lit from
// the upper left, brighter under the pointer, darker held down, and washed
// out on a window that is not the focused one.
fn luna_face_color(stops []LunaStop, column int, row int, w int, h int, hovered bool, pressed bool, active bool) u32 {
	from_x := f64(column * 10 - w * 9)
	from_y := f64(row * 10 - h * 9)
	farthest := math.sqrt(f64(w * 9 * w * 9 + h * 9 * h * 9))
	distance := math.sqrt(from_x * from_x + from_y * from_y)
	mut color := luna_gradient(stops, int(distance * 1000 / farthest), 1001)
	if pressed {
		color = blend(color, 0x000000, luna_button_pressed_alpha)
	} else if hovered {
		color = blend(color, 0xffffff, luna_button_hover_alpha)
	} else if !active {
		color = blend(color, luna_button_wash, luna_button_wash_alpha)
	}
	return color
}

// draw_luna_caption_button paints one of Windows XP's caption buttons: the
// square with its white line, and the white mark on it.
fn (mut d Desktop) draw_luna_caption_button(el &ui2.Element, x int, y int, w int, h int) {
	kind := if el.id.ends_with('.close') {
		LunaCaption.close
	} else if el.id.ends_with('.maximize') {
		LunaCaption.maximize
	} else {
		LunaCaption.minimize
	}
	active := !d.inactive_window
	hovered := d.hover == el.id
	pressed := hovered && d.buttons & button_left != 0
	stops := if kind == .close { luna_close_face } else { luna_button_face }
	lit := active || hovered
	edge := if lit { luna_button_edge } else { luna_button_edge_inactive }
	for row in 0 .. h {
		for column in 0 .. w {
			px := x + column
			py := y + row
			whole := round_rect_coverage(px, py, x, y, w, h, luna_caption_radius)
			if whole == 0 {
				continue
			}
			inside := round_rect_coverage(px, py, x + 1, y + 1, w - 2, h - 2, luna_caption_radius - 1)
			if inside > 0 {
				d.canvas.blend_pixel(px, py, luna_face_color(stops, column, row, w, h, hovered,
					pressed, active), inside)
			}
			if whole > inside {
				d.canvas.blend_pixel(px, py, edge, whole - inside)
			}
		}
	}
	mark := edge
	match kind {
		.minimize {
			// A bar low on the left.
			d.canvas.fill_rect(x + 5, y + 13, 8, 3, mark)
		}
		.maximize {
			if el.image_path == 'builtin:restore' {
				// Two smaller windows, the front one covering the back one's
				// lower left.
				d.draw_luna_window_mark(x + 8, y + 4, 8, 8, 2, mark)
				for row in 9 .. 15 {
					for column in 6 .. 12 {
						d.canvas.fill_rect(x + column, y + row, 1, 1, luna_face_color(stops,
							column, row, w, h, hovered, pressed, active))
					}
				}
				d.draw_luna_window_mark(x + 5, y + 8, 8, 8, 2, mark)
			} else {
				d.draw_luna_window_mark(x + 5, y + 5, 11, 11, 3, mark)
			}
		}
		.close {
			d.draw_luna_close_mark(x, y, w, h, mark)
		}
	}
}

// draw_luna_window_mark is the maximise mark: a little window, a thin frame
// under a title bar `bar` rows thick.
fn (mut d Desktop) draw_luna_window_mark(x int, y int, w int, h int, bar int, color u32) {
	d.canvas.fill_rect(x, y, w, bar, color)
	d.canvas.fill_rect(x, y + bar, 1, h - bar, color)
	d.canvas.fill_rect(x + w - 1, y + bar, 1, h - bar, color)
	d.canvas.fill_rect(x, y + h - 1, w, 1, color)
}

// draw_luna_close_mark is the thick white cross. It is measured against the
// backing pixels, so its diagonals stay smooth at either scale.
fn (mut d Desktop) draw_luna_close_mark(x int, y int, w int, h int, color u32) {
	scale := f64(d.canvas.scale)
	center_x := (f64(x) + f64(w) / 2) * scale
	center_y := (f64(y) + f64(h) / 2) * scale
	reach := 4.2 * scale
	stroke := 1.15 * scale
	first_x := int(center_x - reach - stroke) - 1
	last_x := int(center_x + reach + stroke) + 1
	first_y := int(center_y - reach - stroke) - 1
	last_y := int(center_y + reach + stroke) + 1
	for py in first_y .. last_y + 1 {
		for px in first_x .. last_x + 1 {
			sample_x := f64(px) + 0.5 - center_x
			sample_y := f64(py) + 0.5 - center_y
			falling := distance_to_segment(sample_x, sample_y, -reach, -reach, reach, reach)
			rising := distance_to_segment(sample_x, sample_y, reach, -reach, -reach, reach)
			distance := if falling < rising { falling } else { rising }
			if distance >= stroke + 0.5 {
				continue
			}
			coverage := if distance <= stroke - 0.5 { u32(255) } else { u32((stroke + 0.5 - distance) * 255) }
			d.canvas.blend_physical_pixel(px, py, color, coverage)
		}
	}
}

// ── Taskbar ────────────────────────────────────────────────────────

// draw_luna_taskbar paints the blue bar.
fn (mut d Desktop) draw_luna_taskbar(x int, y int, w int, h int) {
	for row in 0 .. h {
		d.canvas.fill_rect(x, y + row, w, 1, luna_gradient(luna_bar, row, h))
	}
}

// draw_luna_tray paints the lighter panel behind the notification area and
// the clock, with the dark line and the bright one that set it off.
fn (mut d Desktop) draw_luna_tray(x int, y int, w int, h int) {
	for row in 0 .. h {
		d.canvas.fill_rect(x, y + row, w, 1, luna_gradient(luna_tray, row, h))
	}
	d.canvas.fill_rect(x, y, 1, h, luna_tray_edge)
	d.canvas.blend_rect(x + 1, y + 1, 1, h - 2, luna_tray_shine, 150)
}

// draw_luna_bar_box paints a control on the taskbar or in the Start menu's
// shell the way Luna has it, rather than as the flat colour its element
// declares. The colour says which state the control is in.
fn (mut d Desktop) draw_luna_bar_box(el &ui2.Element, x int, y int, w int, h int, bg u32) {
	theme := d.theme()
	if d.walk.on_menu {
		// A row of the Start menu that is drawn at all is under the pointer,
		// in the colour its element says: start_menu_luna.v.
		d.canvas.fill_round_rect(x, y, w, h, int(el.box.radius), bg)
		return
	}
	mut fill := luna_bar_button
	mut pressed := false
	if bg == theme.taskbar_item_hover {
		fill = luna_bar_button_hover
	} else if bg == theme.taskbar_item_active || bg == theme.accent {
		fill = luna_bar_button_pressed
		pressed = true
	} else if bg == theme.taskbar_item_bg {
		if el.id == action_show_desktop {
			// At rest the corner is the tray's own blue.
			return
		}
	} else {
		// A colour with a meaning of its own, such as a button asking for
		// attention.
		fill = bg
	}
	radius := if w > 2 * luna_bar_button_radius && h > 2 * luna_bar_button_radius {
		luna_bar_button_radius
	} else {
		0
	}
	d.canvas.fill_round_rect(x, y, w, h, radius, fill)
	if w < 6 || h < 6 {
		return
	}
	if pressed {
		// Pressed in: shaded along the top and the left.
		d.canvas.blend_rect(x + 1, y + 1, w - 2, 1, 0x000000, 90)
		d.canvas.blend_rect(x + 1, y + 2, 1, h - 3, 0x000000, 60)
	} else {
		// Raised: lit along the top and the left, shaded opposite.
		d.canvas.blend_rect(x + 2, y + 1, w - 4, 1, 0xffffff, 80)
		d.canvas.blend_rect(x + 1, y + 2, 1, h - 4, 0xffffff, 44)
		d.canvas.blend_rect(x + w - 2, y + 2, 1, h - 4, 0x000000, 56)
		d.canvas.blend_rect(x + 2, y + h - 2, w - 4, 1, 0x000000, 56)
	}
}

// luna_start_width is how wide the Start button is: its mark, the word and
// the round end.
fn (d &Desktop) luna_start_width() int {
	style := ui2.TextStyle{
		size: luna_start_text_size
		bold: true
	}
	return 12 + luna_start_mark + 6 + d.luna_menu_text_width(tr('start.button'), style) + 18
}

// draw_luna_start is the green Start button in the screen's corner: square
// where it meets the screen's edge and round at its other end, with the V and
// the word in white on their shadow. It is brighter under the pointer, and
// darker, pressed in, while the menu is open.
fn (mut d Desktop) draw_luna_start(el &ui2.Element, x int, y int, w int, h int) {
	pressed := d.start_menu_open
	lit := !pressed && el.box.bg == d.theme().accent
	radius := if luna_start_radius * 2 < h { luna_start_radius } else { h / 2 }
	for row in 0 .. h {
		mut color := luna_gradient(luna_start, row, h)
		if pressed {
			color = blend(color, 0x000000, luna_start_pressed_alpha)
		} else if lit {
			color = blend(color, 0xffffff, luna_start_hover_alpha)
		}
		// The shape reaches past the left edge, so only its right end is round.
		d.canvas.fill_rect(x, y + row, w - radius, 1, color)
		for column in w - radius .. w {
			coverage := round_rect_coverage(x + column, y + row, x - radius, y, w + radius, h,
				radius)
			if coverage > 0 {
				d.canvas.blend_pixel(x + column, y + row, color, coverage)
			}
		}
	}
	saved := d.canvas.push_clip_rect(x, y, w, h)
	d.canvas.stroke_round_rect(x - radius, y, w + radius, h, radius, luna_start_edge, 150)
	d.canvas.restore_clip(saved)
	mark_x := x + 12
	mark_y := y + (h - luna_start_mark) / 2
	d.canvas.draw_vinix_v(mark_x + 1, mark_y + 1, luna_start_mark, luna_start_mark, luna_start_shadow)
	d.canvas.draw_vinix_v(mark_x, mark_y, luna_start_mark, luna_start_mark, 0xffffff)
	if el.text.len == 0 || d.fonts.len == 0 {
		return
	}
	face := d.face_for(el.text_style)
	text_x := mark_x + luna_start_mark + 6
	text_y := y + (h - face.line_height) / 2
	d.canvas.draw_text(face, text_x + 1, text_y + 1, el.text, luna_start_shadow)
	d.canvas.draw_text(face, text_x, text_y, el.text, 0xffffff)
}

// draw_luna_menu paints the Start menu's shell: its header, its foot, the
// blue between them, and the line round it with round upper corners.
fn (mut d Desktop) draw_luna_menu(x int, y int, w int, h int) {
	header := if luna_menu_header_rows < h / 2 { luna_menu_header_rows } else { h / 2 }
	foot := if luna_menu_foot_rows < h - header { luna_menu_foot_rows } else { h - header }
	for row in 0 .. h {
		// Between the header and the foot the two columns cover everything
		// but the menu's own line down each side.
		color := if row < header {
			luna_gradient(luna_menu_header, row, header)
		} else if row >= h - foot {
			luna_gradient(luna_menu_foot, row - (h - foot), foot)
		} else {
			luna_menu_edge
		}
		d.luna_row(x, y, w, row, luna_menu_radius, color)
	}
	// The orange line under the header fades out toward both of its ends.
	under := luna_gradient(luna_menu_header, header - 1, header)
	peak := w * 3 / 10
	for column in 1 .. w - 1 {
		reach := if column < peak { peak } else { w - peak }
		strength := 255 - abs_int(column - peak) * 255 / reach
		d.canvas.fill_rect(x + column, y + header, 1, luna_menu_line_rows, blend(under, luna_menu_orange,
			u32(strength)))
	}
	d.luna_top_edge(x, y, w, h, luna_menu_radius, luna_menu_edge)
	d.canvas.fill_rect(x, y + h - 1, w, 1, luna_menu_edge)
}

// draw_luna_tile paints one of the small coloured squares, lit from its
// upper left inside a pale line.
fn (mut d Desktop) draw_luna_tile(x int, y int, size int, light u32, dark u32) {
	if size < 4 {
		return
	}
	for row in 0 .. size {
		for column in 0 .. size {
			coverage := round_rect_coverage(x + column, y + row, x, y, size, size, 3)
			if coverage > 0 {
				d.canvas.blend_pixel(x + column, y + row, mix(light, dark, u32((row + column) * 255 / (2 * size - 2))),
					coverage)
			}
		}
	}
	d.canvas.stroke_round_rect(x, y, size, size, 3, 0xffffff, 120)
}

// draw_luna_glyph draws the marks Windows XP's Start menu needs that are not
// a program's artwork: All Programs' green arrow, and the session buttons'
// squares -- red with the power mark, green with the star that means
// restart, yellow with a crescent for sleep. The white marks are measured
// against the backing pixels, so they stay smooth at either scale.
fn (mut d Desktop) draw_luna_glyph(name string, x int, y int, w int, h int) {
	size := if w < h { w } else { h }
	left := x + (w - size) / 2
	top := y + (h - size) / 2
	match name {
		'luna_arrow' { d.draw_luna_tile(left, top, size, luna_tile_green_light, luna_tile_green) }
		'luna_restart' { d.draw_luna_tile(left, top, size, luna_tile_green_light, luna_tile_green) }
		'luna_sleep' { d.draw_luna_tile(left, top, size, luna_tile_yellow_light, luna_tile_yellow) }
		else { d.draw_luna_tile(left, top, size, luna_tile_red_light, luna_tile_red) }
	}
	scale := f64(d.canvas.scale)
	unit := f64(size) * scale
	center_x := (f64(left) + f64(size) / 2) * scale
	center_y := (f64(top) + f64(size) / 2) * scale
	stroke := unit * 0.055
	first_x := left * d.canvas.scale
	first_y := top * d.canvas.scale
	for py in first_y .. first_y + size * d.canvas.scale {
		for px in first_x .. first_x + size * d.canvas.scale {
			sample_x := f64(px) + 0.5 - center_x
			sample_y := f64(py) + 0.5 - center_y
			// How far inside the mark this pixel is, negative outside it.
			mut inside := -1.0
			match name {
				'luna_arrow' {
					// A triangle pointing right: its height shrinks to the tip.
					across := sample_x + unit * 0.16
					if across >= 0 && across <= unit * 0.36 {
						half := (unit * 0.36 - across) * 0.75
						inside = half - math.abs(sample_y)
						if across < 0.5 {
							inside = math.min(inside, across)
						}
					}
				}
				'luna_restart' {
					// Three strokes crossing: the star on Windows XP's Restart.
					reach := unit * 0.27
					mut nearest := distance_to_segment(sample_x, sample_y, 0, -reach, 0, reach)
					nearest = math.min(nearest, distance_to_segment(sample_x, sample_y, -reach * 0.866,
						-reach * 0.5, reach * 0.866, reach * 0.5))
					nearest = math.min(nearest, distance_to_segment(sample_x, sample_y, -reach * 0.866,
						reach * 0.5, reach * 0.866, -reach * 0.5))
					inside = stroke - nearest
				}
				'luna_sleep' {
					// A crescent: a disc with another cut out of its upper right.
					disc := unit * 0.29 - math.sqrt(sample_x * sample_x + sample_y * sample_y)
					cut_x := sample_x - unit * 0.14
					cut_y := sample_y + unit * 0.10
					cut := math.sqrt(cut_x * cut_x + cut_y * cut_y) - unit * 0.24
					inside = math.min(disc, cut)
				}
				else {
					// The power mark: a ring open at the top, and a bar in the gap.
					radius := math.sqrt(sample_x * sample_x + sample_y * sample_y)
					ring := stroke - math.abs(radius - unit * 0.25)
					gap := sample_y < 0 && math.abs(sample_x) < unit * 0.13
					bar := stroke - distance_to_segment(sample_x, sample_y, 0, -unit * 0.34, 0,
						-unit * 0.04)
					inside = if gap { bar } else { math.max(ring, bar) }
				}
			}
			if inside <= -0.5 {
				continue
			}
			coverage := if inside >= 0.5 { u32(255) } else { u32((inside + 0.5) * 255) }
			d.canvas.blend_physical_pixel(px, py, 0xffffff, coverage)
		}
	}
}
