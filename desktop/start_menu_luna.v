// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// Windows XP's Start menu, for the Windows XP theme.
//
// It holds what the desktop's own menu holds (start_menu.v) and does what it
// does; only where things are and how they are dressed is Windows XP's. The
// user's tile and name are in a blue header with an orange line under it. The
// programs are a white column of 32-pixel icons, what is pinned in bold, with
// All Programs and its green arrow at the foot. The places are a pale blue
// column of dark blue names, the first group in bold. The session buttons are
// in the blue foot with their coloured squares. A row under the pointer is
// the selection's blue with white text. luna.v paints the header, the line
// and the foot; everything else here is plain elements.
module main

import ui2

const luna_menu_width = 440
// The program column's share of that; the places take the rest.
const luna_menu_left_width = 232
const luna_menu_header_rows = 64
const luna_menu_line_rows = 2
const luna_menu_foot_rows = 40
// The user's picture, and the pale frame Windows XP puts round it.
const luna_menu_user_size = 48
const luna_menu_user_frame = u32(0xdfe8fb)
const luna_menu_user_tile = u32(0x2f6fde)
// Rows: a program's icon, a place's, and the height of a place's row.
const luna_menu_program_icon = 32
const luna_menu_place_icon = 24
const luna_menu_place_height = 34
// A builtin glyph standing in for a program's artwork.
const luna_menu_glyph = u32(0x2a5fc4)
const luna_menu_pane = u32(0xffffff)
const luna_menu_select = u32(0x316ac5)
const luna_menu_select_text = u32(0xffffff)
const luna_menu_search = u32(0xeef3fb)
const luna_menu_places = u32(0xd3e5fa)
const luna_menu_places_edge = u32(0x95bdee)
const luna_menu_places_text = u32(0x00136b)
const luna_menu_places_muted = u32(0x5a78b4)
const luna_menu_places_rule = u32(0xa3c3ed)
// A session button under the pointer, and its coloured square.
const luna_menu_foot_hover = u32(0x4a93ee)
const luna_menu_session_icon = 22

// luna_menu_pane_height is the height of the two columns in a menu this tall.
fn luna_menu_pane_height(height int) int {
	pane := height - luna_menu_header_rows - luna_menu_line_rows - luna_menu_foot_rows
	return if pane > 0 { pane } else { 0 }
}

// luna_menu_text_width is how wide a run of text is drawn. A desktop with no
// fonts, as some tests build, lays out as if every letter were seven pixels.
fn (d &Desktop) luna_menu_text_width(text string, style ui2.TextStyle) int {
	return if d.fonts.len > 0 { d.face_for(style).text_width(text) } else { text.len * 7 }
}

fn (mut d Desktop) luna_start_menu_element() ui2.Element {
	frame := d.start_menu_rect()
	width := int(frame.width)
	height := int(frame.height)
	body_y := luna_menu_header_rows + luna_menu_line_rows
	body_height := luna_menu_pane_height(height)
	// The menu's own blue line runs down both sides of the columns.
	mut left_width := luna_menu_left_width
	if left_width > (width - 2) * 3 / 5 {
		left_width = (width - 2) * 3 / 5
	}
	places_x := 1 + left_width
	places_width := width - 1 - places_x

	mut children := frame_elements(64)
	// The user's tile, in its pale frame, and name. The same standalone V is
	// on the Start button.
	mut mark := frame_elements(1)
	mark << ui2.button_with_image('', '', 'builtin:vinix', ui2.rect(0, 0, luna_menu_user_size,
		luna_menu_user_size), ui2.BoxStyle{
		transparent: true
	}, ui2.TextStyle{
		color: 0xffffff
	})
	mut tile := frame_elements(1)
	tile << ui2.view('start.user.tile', ui2.rect(2, 2, luna_menu_user_size, luna_menu_user_size),
		ui2.BoxStyle{
		bg:     luna_menu_user_tile
		radius: 3
	}, mark)
	children << ui2.view('start.user.badge', ui2.rect(7, 6, luna_menu_user_size + 4, luna_menu_user_size + 4),
		ui2.BoxStyle{
		bg:     luna_menu_user_frame
		radius: 4
	}, tile)
	children << ui2.label('start.user.name', 'Vinix', ui2.rect(f64(luna_menu_user_size + 20), 16,
		f64(width - luna_menu_user_size - 32), 32), ui2.TextStyle{
		color:  0xffffff
		size:   17
		bold:   true
		shadow: true
		lines:  1
	})

	children << d.start_menu_program_pane(1, body_y, left_width, body_height)
	// The places' column is behind its rows, so it comes before them.
	children << ui2.view('start.places', ui2.rect(f64(places_x), f64(body_y), f64(places_width),
		f64(body_height)), ui2.BoxStyle{
		bg: luna_menu_places
	}, [])
	children << ui2.view('start.places.edge', ui2.rect(f64(places_x), f64(body_y), 1, f64(body_height)),
		ui2.BoxStyle{
		bg: luna_menu_places_edge
	}, [])
	row_x := places_x + 5
	row_width := places_width - 10
	// A screen too short for the whole column loses its last rows.
	bottom := body_y + body_height
	if d.start_menu_recent_app != start_recent_none {
		d.luna_menu_recent_pane(mut children, row_x, body_y + 6, row_width, body_height - 12)
	} else {
		mut y := body_y + 8
		// What is the user's own, in bold as Windows XP has My Documents.
		d.luna_menu_place(mut children, action_start_files, tr('app.files'), 'asset:files', row_x,
			y, row_width, bottom, true)
		y += luna_menu_place_height
		d.luna_menu_place(mut children, action_start_documents, tr('start.documents'), 'builtin:documents',
			row_x, y, row_width, bottom, true)
		y += luna_menu_place_height
		d.luna_menu_place(mut children, action_start_recent, tr('start.recent_items'), 'builtin:clock',
			row_x, y, row_width, bottom, true)
		y += luna_menu_place_height + 4
		if y + 5 < bottom {
			children << luna_menu_rule('start.right.rule', row_x, y, row_width)
		}
		y += 5
		d.luna_menu_place(mut children, action_start_settings, tr('app.settings'), 'asset:settings',
			row_x, y, row_width, bottom, false)
		y += luna_menu_place_height
		d.luna_menu_place(mut children, action_start_system, tr('window.system'), 'builtin:window',
			row_x, y, row_width, bottom, false)
		y += luna_menu_place_height
		d.luna_menu_place(mut children, action_start_terminal, tr('app.terminal'), 'asset:terminal',
			row_x, y, row_width, bottom, false)
		y += luna_menu_place_height
		d.luna_menu_place(mut children, action_start_activity, tr('app.activity_monitor'), 'asset:activity',
			row_x, y, row_width, bottom, false)
		y += luna_menu_place_height + 4
		if y + 5 < bottom {
			children << luna_menu_rule('start.right.rule2', row_x, y, row_width)
		}
		y += 5
		// Windows XP ends its column with Help and Support and Search. Search
		// brings out the field the desktop's own menu always shows.
		d.luna_menu_place(mut children, action_start_welcome, tr('start.help'), 'builtin:window',
			row_x, y, row_width, bottom, false)
		y += luna_menu_place_height
		d.luna_menu_place(mut children, action_start_search, tr('start.find'), 'builtin:search',
			row_x, y, row_width, bottom, false)
	}

	// The session buttons run leftward from the foot's right end: Shut down
	// where Turn Off Computer is, Restart before it, and before that Sleep, on
	// a machine whose kernel can.
	foot_y := height - luna_menu_foot_rows
	mut right := width - 8
	right = d.luna_menu_session(mut children, action_start_shutdown, tr('start.shut_down'), 'builtin:luna_power',
		right, foot_y)
	right = d.luna_menu_session(mut children, action_start_restart, tr('start.restart'), 'builtin:luna_restart',
		right, foot_y)
	if d.idle.sleep_available {
		d.luna_menu_session(mut children, action_start_sleep, tr('start.sleep'), 'builtin:luna_sleep',
			right, foot_y)
	}

	// Clickable rather than a plain view so empty space in the menu consumes a
	// click instead of activating the window visible underneath it. Only the
	// upper corners are round, and luna.v cuts those.
	return ui2.clickable_view(action_start_panel, frame, ui2.BoxStyle{
		bg: start_menu_shell
	}, children)
}

// luna_menu_row appends a row of the menu. The row itself is the button, the
// selection's blue under the pointer; its icon, at its own size, and its
// label lie over it and are not what a click lands on.
fn (d &Desktop) luna_menu_row(mut children []ui2.Element, id string, title string, image string, x int,
	y int, width int, height int, icon int, bold bool, text u32) {
	lit := d.hover == id
	children << ui2.button(id, '', ui2.rect(f64(x), f64(y), f64(width), f64(height)), ui2.BoxStyle{
		bg:          luna_menu_select
		radius:      2
		transparent: !lit
	}, ui2.TextStyle{})
	children << ui2.Element{
		...ui2.image('', image, ui2.rect(f64(x + 4), f64(y + (height - icon) / 2), f64(icon),
			f64(icon)))
		text_style: ui2.TextStyle{
			color: if lit {
				luna_menu_select_text
			} else if text == start_menu_text {
				luna_menu_glyph
			} else {
				text
			}
		}
	}
	children << ui2.label('', title, ui2.rect(f64(x + icon + 12), f64(y), f64(width - icon - 16),
		f64(height)), ui2.TextStyle{
		color: if lit { luna_menu_select_text } else { text }
		size:  12
		bold:  bold
		lines: 1
	})
}

// luna_menu_place is a row of the places' column, left out when it would
// reach past the column's `bottom`.
fn (d &Desktop) luna_menu_place(mut children []ui2.Element, id string, title string, image string, x int,
	y int, width int, bottom int, bold bool) {
	if y + luna_menu_place_height > bottom {
		return
	}
	d.luna_menu_row(mut children, id, title, image, x, y, width, luna_menu_place_height - 2,
		luna_menu_place_icon, bold, luna_menu_places_text)
}

// luna_menu_plain is a label without the arrow the desktop's own menu ends
// it with, which Windows XP draws as a picture. It is a view of the same
// text, not a copy.
fn luna_menu_plain(text string) string {
	mut end := text.len
	for end > 0 && (text[end - 1] == ` ` || text[end - 1] == `>`) {
		end--
	}
	return if end > 0 { unsafe { tos(text.str, end) } } else { text }
}

fn luna_menu_rule(id string, x int, y int, width int) ui2.Element {
	return ui2.view(id, ui2.rect(f64(x + 6), f64(y), f64(width - 12), 1), ui2.BoxStyle{
		bg: luna_menu_places_rule
	}, [])
}

// luna_menu_all_programs is the row at the foot of the program column: its
// name in bold and the green arrow after it, the pair in the middle.
fn (d &Desktop) luna_menu_all_programs(mut children []ui2.Element, x int, y int, width int, height int) {
	lit := d.hover == action_start_all
	title := luna_menu_plain(tr('start.all_programs'))
	style := ui2.TextStyle{
		color: if lit { luna_menu_select_text } else { start_menu_text }
		size:  12
		bold:  true
		lines: 1
	}
	arrow := 20
	text_width := d.luna_menu_text_width(title, style)
	start := x + (width - text_width - 8 - arrow) / 2
	children << ui2.button(action_start_all, '', ui2.rect(f64(x), f64(y), f64(width), f64(height)),
		ui2.BoxStyle{
		bg:          luna_menu_select
		radius:      2
		transparent: !lit
	}, ui2.TextStyle{})
	children << ui2.label('', title, ui2.rect(f64(start), f64(y), f64(text_width + 4), f64(height)),
		style)
	children << ui2.image('', 'builtin:luna_arrow', ui2.rect(f64(start + text_width + 8), f64(y +
		(height - arrow) / 2), arrow, arrow))
}

// luna_menu_session appends a session button whose right end is at `right`:
// its coloured square and its name, lit under the pointer. It returns where
// the button before it ends.
fn (d &Desktop) luna_menu_session(mut children []ui2.Element, id string, title string, image string, right int,
	foot_y int) int {
	style := ui2.TextStyle{
		color: 0xffffff
		size:  12
		lines: 1
	}
	text_width := d.luna_menu_text_width(title, style)
	width := 6 + luna_menu_session_icon + 5 + text_width + 8
	x := right - width
	height := luna_menu_foot_rows - 10
	y := foot_y + 5
	children << ui2.button(id, '', ui2.rect(f64(x), f64(y), f64(width), f64(height)), ui2.BoxStyle{
		bg:          luna_menu_foot_hover
		radius:      3
		transparent: d.hover != id
	}, ui2.TextStyle{})
	children << ui2.image('', image, ui2.rect(f64(x + 6), f64(y + (height - luna_menu_session_icon) / 2),
		luna_menu_session_icon, luna_menu_session_icon))
	children << ui2.label('', title, ui2.rect(f64(x + 6 + luna_menu_session_icon + 5), f64(y),
		f64(text_width + 4), f64(height)), style)
	return x - 6
}

// luna_menu_recent_pane replaces the places with a program's recent items, or
// with every program's for Recent Items.
fn (d &Desktop) luna_menu_recent_pane(mut children []ui2.Element, x int, y int, width int, height int) {
	title := if d.start_menu_recent_app >= 0 && d.start_menu_recent_app < available_apps.len {
		app_title_text(available_apps[d.start_menu_recent_app].title)
	} else {
		tr('start.recent_items')
	}
	d.luna_menu_row(mut children, action_start_recent_back, title, 'builtin:arrow_left', x, y,
		width, 30, 16, true, luna_menu_places_text)
	children << luna_menu_rule('start.recent.rule', x, y + 35, width)
	if d.start_menu_recent_items.len == 0 {
		children << ui2.label('start.recent.empty', tr('start.recent_empty'), ui2.rect(f64(x + 10),
			f64(y + 44), f64(width - 20), 22), ui2.TextStyle{
			color: luna_menu_places_muted
			size:  12
		})
		return
	}
	mut row_y := y + 42
	for slot in 0 .. d.start_menu_recent_items.len {
		if slot >= start_recent_item_actions.len || slot >= d.start_menu_recent_titles.len
			|| row_y + 32 > y + height {
			break
		}
		d.luna_menu_row(mut children, start_recent_item_actions[slot], d.start_menu_recent_titles[slot],
			if d.start_menu_recent_dirs[slot] { 'builtin:folder' } else { 'builtin:file' }, x,
			row_y, width, 32, 16, false, luna_menu_places_text)
		row_y += 34
	}
}
