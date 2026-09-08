// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// The Start menu. Its two-column layout follows Windows 7: frequently used
// programs on a light pane, system destinations on the tinted pane, an All
// Programs view, search at the bottom and a session button in the lower right.
module main

import ui2

const action_start_toggle = 'start.toggle'
const action_start_panel = 'start.panel'
const action_start_all = 'start.all'
const action_start_back = 'start.back'
const action_start_search = 'start.search'
const action_start_files = 'start.files'
const action_start_settings = 'start.settings'
const action_start_terminal = 'start.terminal'
const action_start_activity = 'start.activity'
const action_start_system = 'start.system'
const action_start_welcome = 'start.welcome'
const action_start_shutdown = 'start.shutdown'
const action_start_launch_prefix = 'start.launch.'

const start_button_width = 42
const start_menu_preferred_width = 460
const start_menu_preferred_height = 548
const start_menu_margin = 8
const start_menu_left_width = 280
const start_menu_row_height = 34
const start_menu_search_height = 32
const start_menu_max_query = 48

// The opening page is deliberately short, like Windows 7's recent-programs
// list. All Programs and search both expose every installed application.
const start_menu_favorites = [0, 3, 1, 2, 6, 7, 8, 9, 10, 11]

// This blue-grey shell remains recognizable against every wallpaper and both
// chrome themes. The light program pane supplies the high-density reading
// surface used by the original menu.
const start_menu_shell = u32(0x294a73)
const start_menu_left = u32(0xf7f9fc)
const start_menu_item_hover = u32(0xdceafb)
const start_menu_text = u32(0x243044)
const start_menu_muted = u32(0x738096)
const start_menu_right_text = u32(0xf5f8fc)
const start_menu_right_hover = u32(0x41658f)
const start_menu_separator = u32(0xd7dce5)
const start_menu_search_bg = u32(0xffffff)
const start_menu_power = u32(0x3d6592)
const start_menu_power_hover = u32(0x527ba9)

fn (d &Desktop) start_menu_rect() ui2.Rect {
	mut width := start_menu_preferred_width
	if width > d.canvas.width - 2 * start_menu_margin {
		width = d.canvas.width - 2 * start_menu_margin
	}
	mut height := start_menu_preferred_height
	available_height := d.canvas.height - taskbar_height - start_menu_margin
	if height > available_height {
		height = available_height
	}
	if width < 1 {
		width = 1
	}
	if height < 1 {
		height = 1
	}
	mut x := if d.theme().dock {
		(d.canvas.width - width) / 2
	} else {
		taskbar_padding
	}
	if x + width > d.canvas.width - start_menu_margin {
		x = d.canvas.width - start_menu_margin - width
	}
	if x < start_menu_margin {
		x = start_menu_margin
	}
	return ui2.rect(f64(x), f64(d.canvas.height - taskbar_height - height), f64(width), f64(height))
}

fn (mut d Desktop) toggle_start_menu() {
	if d.start_menu_open {
		d.close_start_menu()
		return
	}
	d.start_menu_open = true
	d.start_menu_all_apps = false
	d.start_menu_searching = false
	d.free_start_menu_query()
	d.start_menu_query = []u8{cap: start_menu_max_query}
	// Search only appends and removes bytes; no slices escape from this buffer.
	// Marking that fact lets V release an old allocation if this ever grows.
	unsafe { d.start_menu_query.flags.set(.noslices) }
	d.dirty = true
}

fn (mut d Desktop) close_start_menu() {
	if !d.start_menu_open {
		return
	}
	d.start_menu_open = false
	d.start_menu_all_apps = false
	d.start_menu_searching = false
	d.free_start_menu_query()
	d.hover = ''
	d.dirty = true
}

fn (mut d Desktop) free_start_menu_query() {
	if d.start_menu_query.cap > 0 {
		unsafe { d.start_menu_query.free() }
		d.start_menu_query = []u8{}
	}
}

fn (d &Desktop) start_menu_query_text() string {
	if d.start_menu_query.len == 0 {
		return ''
	}
	return unsafe { tos(d.start_menu_query.data, d.start_menu_query.len) }
}

fn (d &Desktop) start_menu_element() ui2.Element {
	frame := d.start_menu_rect()
	width := int(frame.width)
	height := int(frame.height)
	left_x := 7
	left_y := 7
	mut left_width := start_menu_left_width
	if left_width > width - 142 {
		left_width = width * 3 / 5
	}
	left_height := height - 14
	right_x := left_x + left_width + 9
	right_width := width - right_x - 8

	mut children := frame_elements(12)
	children << d.start_menu_program_pane(left_x, left_y, left_width, left_height)

	// The user tile occupies the place Windows 7 reserved above its system
	// links. The same standalone V is used on the Start button itself.
	badge_size := 48
	children << ui2.view('start.user.badge', ui2.rect(f64(right_x + 8), 12, f64(badge_size), f64(badge_size)), ui2.BoxStyle{
		bg: d.theme().accent
		radius: 8
	}, frame_child(ui2.button_with_image('', '', 'builtin:vinix', ui2.rect(0, 0, f64(badge_size), f64(badge_size)), ui2.BoxStyle{
		transparent: true
	}, ui2.TextStyle{
		color: 0xffffff
	})))
	children << ui2.label('start.user.name', 'Vinix', ui2.rect(f64(right_x + 64), 22, f64(right_width - 66), 28), ui2.TextStyle{
		color: start_menu_right_text
		size: 15
		bold: true
	})

	mut right_y := 82
	children << d.start_menu_right_button(action_start_files, 'Files', 'builtin:folder', right_x, right_y, right_width)
	right_y += 39
	children << d.start_menu_right_button(action_start_system, 'System', 'builtin:window', right_x, right_y, right_width)
	right_y += 39
	children << d.start_menu_right_button(action_start_settings, 'Settings', 'builtin:settings', right_x, right_y, right_width)
	right_y += 47
	children << ui2.view('start.right.rule', ui2.rect(f64(right_x + 8), f64(right_y - 5), f64(right_width - 16), 1), ui2.BoxStyle{
		bg: 0x6c86a5
	}, [])
	children << d.start_menu_right_button(action_start_terminal, 'Terminal', 'builtin:terminal', right_x, right_y, right_width)
	right_y += 39
	children << d.start_menu_right_button(action_start_activity, 'Activity Monitor', 'builtin:activity', right_x, right_y, right_width)
	right_y += 39
	children << d.start_menu_right_button(action_start_welcome, 'Help', 'builtin:window', right_x, right_y, right_width)

	power_width := if right_width > 138 { 128 } else { right_width - 8 }
	children << ui2.button(action_start_shutdown, 'Shut down', ui2.rect(f64(right_x + right_width - power_width), f64(height - 49), f64(power_width), 34), ui2.BoxStyle{
		bg: if d.hover == action_start_shutdown { start_menu_power_hover } else { start_menu_power }
		radius: 5
	}, ui2.TextStyle{
		color: start_menu_right_text
		size: 12
		bold: true
		align: .center
	})

	// Clickable rather than a plain view so empty space in the menu consumes a
	// click instead of activating the window visible underneath it.
	return ui2.clickable_view(action_start_panel, frame, ui2.BoxStyle{
		bg: start_menu_shell
		radius: 8
	}, children)
}

fn (d &Desktop) start_menu_program_pane(x int, y int, width int, height int) ui2.Element {
	mut children := frame_elements(24)
	search_y := height - start_menu_search_height - 8
	if d.start_menu_query.len > 0 {
		d.start_menu_filtered_programs(mut children, 8, search_y - 5, width)
	} else if d.start_menu_all_apps {
		children << ui2.button(action_start_back, '<  Back', ui2.rect(7, 7, f64(width - 14), 30), ui2.BoxStyle{
			bg: if d.hover == action_start_back { start_menu_item_hover } else { start_menu_left }
			radius: 4
		}, ui2.TextStyle{
			color: start_menu_text
			size: 12
			bold: true
			align: .left
		})
		d.start_menu_all_programs(mut children, 40, search_y - 5, width)
	} else {
		mut row_y := 9
		for index in start_menu_favorites {
			if index >= available_apps.len || row_y + 38 > search_y - 39 {
				break
			}
			children << d.start_menu_app_button(index, 7, row_y, width - 14, 38)
			row_y += 38
		}
		all_y := search_y - 39
		children << ui2.view('start.programs.rule', ui2.rect(12, f64(all_y - 2), f64(width - 24), 1), ui2.BoxStyle{
			bg: start_menu_separator
		}, [])
		children << ui2.button(action_start_all, 'All Programs  >', ui2.rect(7, f64(all_y + 2), f64(width - 14), 33), ui2.BoxStyle{
			bg: if d.hover == action_start_all { start_menu_item_hover } else { start_menu_left }
			radius: 4
		}, ui2.TextStyle{
			color: start_menu_text
			size: 12
			bold: true
			align: .right
		})
	}

	search_text := if d.start_menu_query.len > 0 {
		d.start_menu_query_text()
	} else {
		'Search programs and files'
	}
	children << ui2.button_with_image(action_start_search, search_text, 'builtin:search', ui2.rect(7, f64(search_y), f64(width - 14), f64(start_menu_search_height)), ui2.BoxStyle{
		bg: if d.start_menu_searching { u32(0xffffff) } else { start_menu_search_bg }
		radius: 4
	}, ui2.TextStyle{
		color: if d.start_menu_query.len > 0 { start_menu_text } else { start_menu_muted }
		size: 11
		align: .left
	})

	return ui2.view('start.programs', ui2.rect(f64(x), f64(y), f64(width), f64(height)), ui2.BoxStyle{
		bg: start_menu_left
		radius: 6
	}, children)
}

fn (d &Desktop) start_menu_all_programs(mut children []ui2.Element, top int, bottom int, width int) {
	count := available_apps.len
	if count == 0 || bottom <= top {
		return
	}
	mut row_height := (bottom - top) / count
	if row_height > start_menu_row_height {
		row_height = start_menu_row_height
	}
	if row_height < 1 {
		row_height = 1
	}
	mut row_y := top
	for index in 0 .. count {
		children << d.start_menu_app_button(index, 7, row_y, width - 14, row_height)
		row_y += row_height
	}
}

fn (d &Desktop) start_menu_filtered_programs(mut children []ui2.Element, top int, bottom int,
	width int) {
	mut count := 0
	for factory in available_apps {
		if start_menu_matches(factory.title, d.start_menu_query_text()) {
			count++
		}
	}
	if count == 0 {
		children << ui2.label('start.no_results', 'No programs found', ui2.rect(18, f64(top + 12), f64(width - 36), 24), ui2.TextStyle{
			color: start_menu_muted
			size: 12
		})
		return
	}
	mut row_height := (bottom - top) / count
	if row_height > 38 {
		row_height = 38
	}
	if row_height < 1 {
		row_height = 1
	}
	mut row_y := top
	for index, factory in available_apps {
		if !start_menu_matches(factory.title, d.start_menu_query_text()) {
			continue
		}
		children << d.start_menu_app_button(index, 7, row_y, width - 14, row_height)
		row_y += row_height
	}
}

fn (d &Desktop) start_menu_app_button(index int, x int, y int, width int, height int) ui2.Element {
	factory := &available_apps[index]
	id := app_start_actions[index]
	return ui2.button_with_image(id, factory.title, factory.icon, ui2.rect(f64(x), f64(y), f64(width), f64(height)), ui2.BoxStyle{
		bg: if d.hover == id { start_menu_item_hover } else { start_menu_left }
		radius: 4
	}, ui2.TextStyle{
		color: start_menu_text
		size: 12
		align: .left
	})
}

fn (d &Desktop) start_menu_right_button(id string, title string, icon string, x int, y int,
	width int) ui2.Element {
	return ui2.button_with_image(id, title, icon, ui2.rect(f64(x), f64(y), f64(width), 35), ui2.BoxStyle{
		bg: if d.hover == id { start_menu_right_hover } else { start_menu_shell }
		radius: 4
	}, ui2.TextStyle{
		color: start_menu_right_text
		size: 12
		align: .left
	})
}

// Windows' Start search is ASCII here because the desktop's baked font is
// ASCII. Comparing folded bytes avoids allocating lowercase copies every time
// the element tree is rebuilt.
fn start_menu_matches(title string, query string) bool {
	if query.len == 0 {
		return true
	}
	if query.len > title.len {
		return false
	}
	for start in 0 .. title.len - query.len + 1 {
		mut equal := true
		for i in 0 .. query.len {
			if start_menu_lower(title[start + i]) != start_menu_lower(query[i]) {
				equal = false
				break
			}
		}
		if equal {
			return true
		}
	}
	return false
}

@[inline]
fn start_menu_lower(ch u8) u8 {
	return if ch >= `A` && ch <= `Z` { ch + 32 } else { ch }
}

// While the menu is open, typing searches immediately, Backspace edits the
// query, Return launches the first result and Escape dismisses the menu.
fn (mut d Desktop) start_menu_key_input(keys string) {
	for i := 0; i < keys.len; i++ {
		ch := keys[i]
		match ch {
			0x1b {
				d.close_start_menu()
				return
			}
			8, 127 {
				if d.start_menu_query.len > 0 {
					d.start_menu_query.delete_last()
					d.start_menu_searching = true
					d.dirty = true
				}
			}
			`\n`, `\r` {
				if d.start_menu_query.len == 0 {
					continue
				}
				for index, factory in available_apps {
					if start_menu_matches(factory.title, d.start_menu_query_text()) {
						d.close_start_menu()
						d.launch_index(index)
						return
					}
				}
			}
			else {
				if ch >= 0x20 && ch < 0x7f && d.start_menu_query.len < start_menu_max_query {
					d.start_menu_query << ch
					d.start_menu_searching = true
					d.start_menu_all_apps = false
					d.dirty = true
				}
			}
		}
	}
}

fn (mut d Desktop) handle_start_action(action string) {
	match action {
		action_start_panel, action_start_search {
			d.start_menu_searching = action == action_start_search
			d.dirty = true
		}
		action_start_all {
			d.start_menu_all_apps = true
			d.start_menu_searching = false
			d.dirty = true
		}
		action_start_back {
			d.start_menu_all_apps = false
			d.dirty = true
		}
		action_start_system {
			d.close_start_menu()
			id := d.spawn('System', .system, 170, 80, 372, 232)
			index := d.window_index(id) or { return }
			d.clamp_to_screen(index)
		}
		action_start_files, action_start_settings, action_start_terminal, action_start_activity {
			index := match action {
				action_start_files { 0 }
				action_start_terminal { 3 }
				action_start_settings { 4 }
				action_start_activity { 5 }
				else { -1 }
			}
			d.close_start_menu()
			d.launch_index(index)
		}
		action_start_welcome {
			d.close_start_menu()
			id := d.spawn('Welcome', .welcome, 150, 60, 396, 244)
			index := d.window_index(id) or { return }
			d.clamp_to_screen(index)
		}
		action_start_shutdown {
			d.close_start_menu()
			d.running = false
		}
		else {
			if action.starts_with(action_start_launch_prefix) {
				index := action[action_start_launch_prefix.len..].int()
				d.close_start_menu()
				d.launch_index(index)
			}
		}
	}
}
