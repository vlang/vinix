// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// Windows XP's Start menu, for the Windows XP theme.
//
// The reference layout has two equal columns, without a user banner: programs
// on white, XP's destinations on pale blue, and Log Off / Turn Off Computer
// in the blue footer. Other themes keep start_menu.v's destinations.
module main

import ui2

const luna_menu_width = 408
const luna_menu_height = 488
// The program column's share of that; the places take the rest.
const luna_menu_left_width = 203
const luna_menu_header_rows = 0
const luna_menu_line_rows = 2
const luna_menu_foot_rows = 44
// Rows: a program's icon, a place's, and the height of a place's row.
const luna_menu_program_icon = 32
const luna_menu_place_icon = 26
const luna_menu_place_height = 32
const luna_menu_program_height = 43
const luna_menu_favorites = [1, 0, 3, 2, 6, 7, 8, 9, 10, 11]
// A builtin glyph standing in for a program's artwork.
const luna_menu_glyph = u32(0x2a5fc4)
const luna_menu_pane = u32(0xffffff)
const luna_menu_select = u32(0x316ac5)
const luna_menu_select_text = u32(0xffffff)
const luna_menu_search = u32(0xeef3fb)
const luna_menu_places = u32(0xd3e5fb)
const luna_menu_places_edge = u32(0x95bdee)
const luna_menu_places_text = u32(0x153d70)
const luna_menu_program_text = u32(0x202020)
const luna_menu_places_muted = u32(0x5a78b4)
const luna_menu_places_rule = u32(0xa3c3ed)
// A session button under the pointer, and its coloured square.
const luna_menu_foot_hover = u32(0x4a93ee)
const luna_menu_session_icon = 26

const action_start_pictures = 'start.pictures'
const action_start_music = 'start.music'
const action_start_computer = 'start.computer'
const action_start_network = 'start.network'
const action_start_defaults = 'start.defaults'
const action_start_connect = 'start.connect'
const action_start_printers = 'start.printers'
const action_start_run = 'start.run'
const action_start_logoff = 'start.logoff'
const action_start_power = 'start.power'
const action_start_power_panel = 'start.power.panel'

struct LunaMenuPlace {
	action string
	key    string
	image  string
	bold   bool
	arrow  bool
	rule   bool
}

const luna_menu_links = [
	LunaMenuPlace{action_start_documents, 'start.xp.documents', 'builtin:luna_documents', true, false, false},
	LunaMenuPlace{action_start_recent, 'start.xp.recent', 'builtin:luna_recent', true, true, false},
	LunaMenuPlace{action_start_pictures, 'start.xp.pictures', 'builtin:luna_pictures', true, false, false},
	LunaMenuPlace{action_start_music, 'start.xp.music', 'builtin:luna_music', true, false, false},
	LunaMenuPlace{action_start_computer, 'start.xp.computer', 'builtin:luna_computer', true, false, false},
	LunaMenuPlace{action_start_network, 'start.xp.network', 'builtin:luna_network', true, false, true},
	LunaMenuPlace{action_start_settings, 'start.xp.control_panel', 'builtin:luna_control', false, false, false},
	LunaMenuPlace{action_start_defaults, 'start.xp.defaults', 'builtin:luna_defaults', false, false, false},
	LunaMenuPlace{action_start_connect, 'start.xp.connect', 'builtin:luna_connect', false, true, false},
	LunaMenuPlace{action_start_printers, 'start.xp.printers', 'builtin:luna_printer', false, false, true},
	LunaMenuPlace{action_start_welcome, 'start.xp.help', 'builtin:luna_help', false, false, false},
	LunaMenuPlace{action_start_search, 'start.find', 'builtin:luna_search', false, false, false},
	LunaMenuPlace{action_start_run, 'start.xp.run', 'builtin:luna_run', false, false, false},
]!

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
	left_width := (width - 2) / 2
	places_x := 1 + left_width
	places_width := width - 1 - places_x

	mut children := frame_elements(80)
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
	row_x := places_x + 4
	row_width := places_width - 8
	// A screen too short for the whole column loses its last rows.
	bottom := body_y + body_height
	if d.start_menu_recent_app != start_recent_none {
		d.luna_menu_recent_pane(mut children, row_x, body_y + 6, row_width, body_height - 12)
	} else {
		mut y := body_y + 4
		for link in luna_menu_links {
			d.luna_menu_place(mut children, link.action, tr(link.key), link.image, row_x, y,
				row_width, bottom, link.bold)
			if link.arrow && y + luna_menu_place_height <= bottom {
				children << ui2.Element{
					...ui2.image('', 'builtin:luna_submenu', ui2.rect(f64(row_x + row_width - 12), f64(y + 11), 8, 10))
					text_style: ui2.TextStyle{
						color: if d.hover == link.action {
							luna_menu_select_text
						} else {
							luna_menu_places_text
						}
					}
				}
			}
			y += luna_menu_place_height
			if link.rule {
				if y + 10 < bottom {
					children << luna_menu_rule('', row_x + 24, y + 4, row_width - 38)
				}
				y += 10
			}
		}
	}

	foot_y := height - luna_menu_foot_rows
	mut right := width - 8
	right = d.luna_menu_session(mut children, action_start_power, tr('start.xp.turn_off'), 'builtin:luna_power',
		right, foot_y)
	d.luna_menu_session(mut children, action_start_logoff, tr('start.xp.log_off'), 'builtin:luna_logoff',
		right, foot_y)
	if d.start_menu_power_open {
		d.luna_menu_power_choices(mut children, width, foot_y)
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
			} else if text == luna_menu_program_text {
				luna_menu_glyph
			} else {
				text
			}
		}
	}
	style := ui2.TextStyle{
		color: if lit { luna_menu_select_text } else { text }
		size:  12
		bold:  bold
		lines: 1
	}
	text_x := x + icon + 8
	text_width := width - icon - 12
	if id == action_start_defaults {
		cut := d.luna_menu_line_break(title, text_width, style)
		if cut > 0 && cut < title.len {
			mut next := cut
			for next < title.len && title[next] == ` ` { next++ }
			first := unsafe { tos(title.str, cut) }
			second := unsafe { tos(title.str + next, title.len - next) }
			line_height := if d.fonts.len > 0 { d.face_for(style).line_height } else { 14 }
			top := y + (height - line_height * 2) / 2
			children << ui2.label('start.defaults.line1', first, ui2.rect(f64(text_x), f64(top), f64(text_width), f64(line_height)), style)
			children << ui2.label('start.defaults.line2', second, ui2.rect(f64(text_x), f64(top + line_height), f64(text_width), f64(line_height)), style)
			return
		}
	}
	subtitle := id == app_start_actions[1] && height == luna_menu_program_height
	children << ui2.label('', title, ui2.rect(f64(text_x), f64(if subtitle { y + 3 } else { y }),
		f64(text_width), f64(if subtitle { 18 } else { height })), style)
}

// Borrow both lines from the translated title. Prefer a word boundary, and
// split between complete UTF-8 characters when the language has no spaces.
fn (d &Desktop) luna_menu_line_break(title string, width int, style ui2.TextStyle) int {
	if d.luna_menu_text_width(title, style) <= width { return title.len }
	mut at := 0
	mut fit := 0
	mut space := 0
	for at < title.len {
		_, count := next_rune(title, at)
		end := at + count
		if d.luna_menu_text_width(unsafe { tos(title.str, end) }, style) > width { break }
		if title[at] == ` ` { space = at }
		fit = end
		at = end
	}
	return if space > 0 { space } else { fit }
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
		color: if lit { luna_menu_select_text } else { luna_menu_program_text }
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

// Keep restart and suspend available behind Turn Off Computer, as in XP.
fn (d &Desktop) luna_menu_power_choices(mut children []ui2.Element, width int, bottom int) {
	count := if d.idle.sleep_available { 3 } else { 2 }
	height := count * luna_menu_place_height + 8
	x := if width > 188 { width - 188 } else { 1 }
	popup_width := width - x - 2
	y := bottom - height
	children << ui2.clickable_view(action_start_power_panel, ui2.rect(f64(x), f64(y), f64(popup_width), f64(height)),
		ui2.BoxStyle{
			bg:            luna_menu_places
			border_color:  luna_menu_places_edge
			border_left:   1
			border_top:    1
			border_right:  1
			border_bottom: 1
		}, [])
	for slot in 0 .. count {
		action := match slot {
			0 { action_start_shutdown }
			1 { action_start_restart }
			else { action_start_sleep }
		}
		title := match slot {
			0 { tr('start.shut_down') }
			1 { tr('start.restart') }
			else { tr('start.sleep') }
		}
		icon := match slot {
			0 { 'builtin:luna_power' }
			1 { 'builtin:luna_restart' }
			else { 'builtin:luna_sleep' }
		}
		d.luna_menu_row(mut children, action, title, icon, x + 4, y + 4 + slot * luna_menu_place_height,
			popup_width - 8, luna_menu_place_height, luna_menu_session_icon, false, luna_menu_places_text)
	}
}

fn (mut d Desktop) handle_luna_start_action(action string) {
	if action == action_start_power {
		d.start_menu_power_open = !d.start_menu_power_open
		d.dirty = true
		return
	}
	d.close_start_menu()
	match action {
		action_start_pictures, action_start_music, action_start_computer {
			path := if action == action_start_computer {
				'/'.clone()
			} else {
				user_folder_path(if action == action_start_pictures { 'Pictures' } else { 'Music' })
			}
			if action != action_start_computer { ensure_directory(path) or {} }
			d.open_path_in_app(shortcut_app_index_named('vinix-files'), path)
			unsafe { path.free() }
		}
		action_start_network, action_start_connect { d.open_settings_category(.network) }
		action_start_printers { d.open_settings_category(.printers) }
		action_start_defaults { d.launch_index(shortcut_app_index_named('vinix-software')) }
		action_start_run { d.toggle_quick_launch() }
		action_start_logoff { d.end_session(.keep_running) }
		else {}
	}
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
