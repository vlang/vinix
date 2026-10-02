// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
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
const action_start_documents = 'start.documents'
const action_start_recent = 'start.recent'
const action_start_recent_back = 'start.recent.back'
const action_start_recent_prefix = 'start.recent.'
const action_start_jump_prefix = 'start.jump.'
const app_start_jump_actions = ['start.jump.0', 'start.jump.1', 'start.jump.2', 'start.jump.3',
	'start.jump.4', 'start.jump.5', 'start.jump.6', 'start.jump.7', 'start.jump.8', 'start.jump.9',
	'start.jump.10', 'start.jump.11', 'start.jump.12', 'start.jump.13', 'start.jump.14',
	'start.jump.15', 'start.jump.16', 'start.jump.17', 'start.jump.18', 'start.jump.19',
	'start.jump.20', 'start.jump.21', 'start.jump.22', 'start.jump.23', 'start.jump.24',
	'start.jump.25', 'start.jump.26', 'start.jump.27']
const start_recent_item_actions = ['start.recent.0', 'start.recent.1', 'start.recent.2',
	'start.recent.3', 'start.recent.4', 'start.recent.5', 'start.recent.6', 'start.recent.7',
	'start.recent.8', 'start.recent.9', 'start.recent.10', 'start.recent.11']
// The Recent Items pane lists every program's history rather than one's.
const start_recent_all = -2
const start_recent_none = -1

const start_button_width = 42
const start_menu_preferred_width = 460
const start_menu_preferred_height = 548
const start_menu_margin = 8
const start_menu_left_width = 280
const start_menu_row_height = 34
const start_menu_search_height = 32
const start_menu_max_query = 48

// A new profile has no history yet. Windows 7 seeded its recent-programs list
// the same way; the first launches replace these.
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
	d.close_taskbar_preview()
	d.close_tray_flyout()
	d.start_menu_open = true
	d.start_menu_all_apps = false
	d.start_menu_searching = false
	d.set_start_menu_recent(start_recent_none)
	d.free_start_menu_query()
	d.start_menu_query = []u8{cap: start_menu_max_query}
	// Search only appends and removes bytes; no slices escape from this buffer.
	// Marking that fact lets V release an old allocation if this ever grows.
	unsafe { d.start_menu_query.flags |= .noslices }
	d.dirty = true
}

fn (mut d Desktop) close_start_menu() {
	if !d.start_menu_open {
		return
	}
	d.start_menu_open = false
	d.start_menu_all_apps = false
	d.start_menu_searching = false
	d.set_start_menu_recent(start_recent_none)
	d.free_start_menu_query()
	d.set_hover('')
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

	if d.start_menu_recent_app != start_recent_none {
		d.start_menu_recent_pane(mut children, right_x, 76, right_width, height - 62 - 76)
	} else {
		mut right_y := 76
		children << d.start_menu_right_button(action_start_files, tr('app.files'), 'builtin:folder', right_x, right_y, right_width)
		right_y += 37
		children << d.start_menu_right_button(action_start_documents, tr('start.documents'), 'builtin:documents', right_x, right_y, right_width)
		right_y += 37
		children << d.start_menu_right_button(action_start_recent, tr('start.recent_items'), 'builtin:clock', right_x, right_y, right_width)
		right_y += 45
		children << ui2.view('start.right.rule', ui2.rect(f64(right_x + 8), f64(right_y - 5), f64(right_width - 16), 1), ui2.BoxStyle{
			bg: 0x6c86a5
		}, [])
		children << d.start_menu_right_button(action_start_settings, tr('app.settings'), 'builtin:settings', right_x, right_y, right_width)
		right_y += 37
		children << d.start_menu_right_button(action_start_system, tr('window.system'), 'builtin:window', right_x, right_y, right_width)
		right_y += 45
		children << ui2.view('start.right.rule2', ui2.rect(f64(right_x + 8), f64(right_y - 5), f64(right_width - 16), 1), ui2.BoxStyle{
			bg: 0x6c86a5
		}, [])
		children << d.start_menu_right_button(action_start_terminal, tr('app.terminal'), 'builtin:terminal', right_x, right_y, right_width)
		right_y += 37
		children << d.start_menu_right_button(action_start_activity, tr('app.activity_monitor'), 'builtin:activity', right_x, right_y, right_width)
		right_y += 37
		children << d.start_menu_right_button(action_start_welcome, tr('start.help'), 'builtin:window', right_x, right_y, right_width)
	}

	power_width := if right_width > 138 { 128 } else { right_width - 8 }
	children << ui2.button(action_start_shutdown, tr('start.shut_down'), ui2.rect(f64(right_x + right_width - power_width), f64(height - 49), f64(power_width), 34), ui2.BoxStyle{
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
		children << ui2.button(action_start_back, tr('start.back'), ui2.rect(7, 7, f64(width - 14), 30), ui2.BoxStyle{
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
		// Pinned programs first, then the recently used ones below a rule, as
		// Windows 7 arranged its left column.
		mut row_y := 9
		limit := search_y - 39
		for index in d.start_pins {
			if index < 0 || index >= available_apps.len || row_y + 38 > limit {
				continue
			}
			d.start_menu_app_row(mut children, index, 7, row_y, width - 14, 38)
			row_y += 38
		}
		if d.start_pins.len > 0 && row_y + 8 < limit {
			children << ui2.view('start.pins.rule', ui2.rect(12, f64(row_y + 3), f64(width - 24), 1), ui2.BoxStyle{
				bg: start_menu_separator
			}, [])
			row_y += 8
		}
		recent := if d.recent_programs.len > 0 { d.recent_programs } else { start_menu_favorites }
		for index in recent {
			if index < 0 || index >= available_apps.len || d.start_is_pinned(index) {
				continue
			}
			if row_y + 38 > limit {
				break
			}
			d.start_menu_app_row(mut children, index, 7, row_y, width - 14, 38)
			row_y += 38
		}
		all_y := search_y - 39
		children << ui2.view('start.programs.rule', ui2.rect(12, f64(all_y - 2), f64(width - 24), 1), ui2.BoxStyle{
			bg: start_menu_separator
		}, [])
		children << ui2.button(action_start_all, tr('start.all_programs'), ui2.rect(7, f64(all_y + 2), f64(width - 14), 33), ui2.BoxStyle{
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
		tr('start.search')
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
		if app_matches(factory.title, d.start_menu_query_text()) {
			count++
		}
	}
	if count == 0 {
		children << ui2.label('start.no_results', tr('start.no_results'), ui2.rect(18, f64(top + 12), f64(width - 36), 24), ui2.TextStyle{
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
		if !app_matches(factory.title, d.start_menu_query_text()) {
			continue
		}
		children << d.start_menu_app_button(index, 7, row_y, width - 14, row_height)
		row_y += row_height
	}
}

fn (d &Desktop) start_menu_app_button(index int, x int, y int, width int, height int) ui2.Element {
	factory := &available_apps[index]
	id := app_start_actions[index]
	return ui2.button_with_image(id, app_title_text(factory.title), factory.icon, ui2.rect(f64(x), f64(y), f64(width), f64(height)), ui2.BoxStyle{
		bg: if d.hover == id { start_menu_item_hover } else { start_menu_left }
		radius: 4
	}, ui2.TextStyle{
		color: start_menu_text
		size: 12
		align: .left
	})
}

// start_menu_app_row is a program's row with, for a program that keeps a
// history, the arrow that shows its recent items in the right column.
fn (d &Desktop) start_menu_app_row(mut children []ui2.Element, index int, x int, y int, width int,
	height int) {
	children << d.start_menu_app_button(index, x, y, width, height)
	if !jump_list_has_recent(available_apps[index].process_name) {
		return
	}
	id := app_start_jump_actions[index]
	open := d.start_menu_recent_app == index
	children << ui2.button_with_image(id, '', 'builtin:arrow_right', ui2.rect(f64(x + width - 30),
		f64(y + 4), 26, f64(height - 8)), ui2.BoxStyle{
		bg:          start_menu_item_hover
		radius:      4
		transparent: !open && d.hover != id
	}, ui2.TextStyle{
		color: start_menu_muted
	})
}

// start_menu_recent_pane replaces the system links with a program's recent
// items, or with every program's for Recent Items.
fn (d &Desktop) start_menu_recent_pane(mut children []ui2.Element, x int, y int, width int,
	height int) {
	title := if d.start_menu_recent_app >= 0 && d.start_menu_recent_app < available_apps.len {
		app_title_text(available_apps[d.start_menu_recent_app].title)
	} else {
		tr('start.recent_items')
	}
	children << ui2.button_with_image(action_start_recent_back, title, 'builtin:arrow_left', ui2.rect(f64(x),
		f64(y), f64(width), 30), ui2.BoxStyle{
		bg:     if d.hover == action_start_recent_back { start_menu_right_hover } else { start_menu_shell }
		radius: 4
	}, ui2.TextStyle{
		color: start_menu_right_text
		size:  12
		bold:  true
		align: .left
	})
	children << ui2.view('start.recent.rule', ui2.rect(f64(x + 8), f64(y + 35), f64(width - 16), 1), ui2.BoxStyle{
		bg: 0x6c86a5
	}, [])
	if d.start_menu_recent_items.len == 0 {
		children << ui2.label('start.recent.empty', tr('start.recent_empty'), ui2.rect(f64(x + 10),
			f64(y + 44), f64(width - 20), 22), ui2.TextStyle{
			color: 0xb9c7d9
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
		children << d.start_menu_right_button(start_recent_item_actions[slot], d.start_menu_recent_titles[slot],
			if d.start_menu_recent_dirs[slot] { 'builtin:folder' } else { 'builtin:file' }, x,
			row_y, width)
		row_y += 34
	}
}

// set_start_menu_recent reads the history once when the pane opens, rather
// than from disk on every redraw.
fn (mut d Desktop) set_start_menu_recent(app int) {
	if app == d.start_menu_recent_app {
		return
	}
	free_recent_items(d.start_menu_recent_items)
	unsafe {
		// []string.free releases every title as well as the array.
		d.start_menu_recent_titles.free()
		d.start_menu_recent_dirs.free()
	}
	d.start_menu_recent_items = []RecentItem{}
	d.start_menu_recent_titles = []string{}
	d.start_menu_recent_dirs = []bool{}
	d.start_menu_recent_app = app
	d.dirty = true
	if app == start_recent_none {
		return
	}
	name := if app >= 0 && app < available_apps.len { available_apps[app].process_name } else { '' }
	d.start_menu_recent_items = recent_items_for(d.home, name, start_recent_item_actions.len)
	for item in d.start_menu_recent_items {
		d.start_menu_recent_titles << recent_item_title(item.path)
		d.start_menu_recent_dirs << if info := desktop_stat(item.path) { info.is_dir } else { false }
	}
}

// Resting on a program's arrow shows its recent items; moving to another
// program puts the system links back, as the Windows 7 menu did.
fn (mut d Desktop) update_start_menu_hover() {
	if !d.start_menu_open {
		return
	}
	if d.hover.starts_with(action_start_jump_prefix) {
		d.set_start_menu_recent(d.hover[action_start_jump_prefix.len..].int())
		return
	}
	if d.start_menu_recent_app >= 0 && d.hover.starts_with(action_start_launch_prefix) {
		index := d.hover[action_start_launch_prefix.len..].int()
		if index != d.start_menu_recent_app {
			d.set_start_menu_recent(start_recent_none)
		}
	}
}

fn (d &Desktop) start_context_entries(index int) []ui2.MenuEntry {
	mut entries := []ui2.MenuEntry{cap: 4}
	entries << ui2.MenuEntry{
		id:    start_context_open
		title: tr('start.context.open')
	}
	entries << if d.start_is_pinned(index) {
		ui2.MenuEntry{
			id:    start_context_unpin_start
			title: tr('start.context.unpin_start')
		}
	} else {
		ui2.MenuEntry{
			id:    start_context_pin_start
			title: tr('start.context.pin_start')
		}
	}
	entries << if d.taskbar_is_pinned(index) {
		ui2.MenuEntry{
			id:    start_context_unpin_taskbar
			title: tr('start.context.unpin_taskbar')
		}
	} else {
		ui2.MenuEntry{
			id:    start_context_pin_taskbar
			title: tr('start.context.pin_taskbar')
		}
	}
	if shortcut_order_contains(d.recent_programs, index) && !d.start_is_pinned(index) {
		entries << ui2.MenuEntry{
			id:    start_context_forget
			title: tr('start.context.forget')
		}
	}
	return entries
}

fn (mut d Desktop) start_context_action(action string, index int) {
	if index < 0 || index >= available_apps.len {
		return
	}
	match action {
		start_context_open {
			d.close_start_menu()
			d.launch_index(index)
		}
		start_context_pin_start {
			d.pin_start_app_in(d.home, index)
		}
		start_context_unpin_start {
			d.unpin_start_app_in(d.home, index)
		}
		start_context_pin_taskbar {
			d.pin_taskbar_app_in(d.home, index)
		}
		start_context_unpin_taskbar {
			d.unpin_taskbar_app_in(d.home, index)
		}
		start_context_forget {
			d.forget_recent_program_in(d.home, index)
		}
		else {}
	}
	d.dirty = true
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
// app_matches finds a program by what it is called in either the desktop's
// language or English, so a Russian user can type «каль» or «calc».
fn app_matches(title string, query string) bool {
	return start_menu_matches(title, query) || start_menu_matches(app_title_text(title), query)
}

// start_menu_matches is a substring search that ignores case and accents,
// rune by rune and without allocating: «ТЕРМ» finds Терминал, and
// «configuracion» finds Configuración.
fn start_menu_matches(title string, query string) bool {
	if query.len == 0 {
		return true
	}
	mut start := 0
	for start < title.len {
		mut t := start
		mut q := 0
		for q < query.len && t < title.len {
			title_rune, title_size := next_rune(title, t)
			query_rune, query_size := next_rune(query, q)
			if start_menu_fold(title_rune) != start_menu_fold(query_rune) {
				break
			}
			t += title_size
			q += query_size
		}
		if q >= query.len {
			return true
		}
		_, size := next_rune(title, start)
		start += size
	}
	return false
}

// start_menu_fold maps a letter to its lower-case, unaccented form for the
// scripts the desktop's languages use.
@[inline]
fn start_menu_fold(r u32) u32 {
	if r < 0x80 {
		return if r >= `A` && r <= `Z` { r + 32 } else { r }
	}
	if r >= 0x400 && r <= 0x45f {
		// Ё and ё search as Е and е.
		if r == 0x401 || r == 0x451 {
			return 0x435
		}
		if r >= 0x410 && r <= 0x42f {
			return r + 0x20
		}
		return if r < 0x410 { r + 0x50 } else { r }
	}
	return match r {
		0xc0, 0xc1, 0xc2, 0xc3, 0xc4, 0xc5, 0xe0, 0xe1, 0xe2, 0xe3, 0xe4, 0xe5 { u32(`a`) }
		0xc7, 0xe7 { u32(`c`) }
		0xc8, 0xc9, 0xca, 0xcb, 0xe8, 0xe9, 0xea, 0xeb { u32(`e`) }
		0xcc, 0xcd, 0xce, 0xcf, 0xec, 0xed, 0xee, 0xef { u32(`i`) }
		0xd1, 0xf1 { u32(`n`) }
		0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6 { u32(`o`) }
		0xd9, 0xda, 0xdb, 0xdc, 0xf9, 0xfa, 0xfb, 0xfc { u32(`u`) }
		0xdd, 0xfd, 0xff { u32(`y`) }
		else { r }
	}
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
					if app_matches(factory.title, d.start_menu_query_text()) {
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
		action_start_recent {
			d.set_start_menu_recent(start_recent_all)
		}
		action_start_recent_back {
			d.set_start_menu_recent(start_recent_none)
		}
		action_start_documents {
			d.close_start_menu()
			files_index := shortcut_app_index_named('vinix-files')
			documents := user_folder_path('Documents')
			ensure_directory(documents) or {}
			d.open_path_in_app(files_index, documents)
			unsafe { documents.free() }
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
			d.request_power_off()
		}
		else {
			if action.starts_with(action_start_launch_prefix) {
				index := action[action_start_launch_prefix.len..].int()
				d.close_start_menu()
				d.launch_index(index)
			} else if action.starts_with(action_start_jump_prefix) {
				// A click on the arrow does what resting on it does.
				d.set_start_menu_recent(action[action_start_jump_prefix.len..].int())
			} else if action.starts_with(action_start_recent_prefix) {
				d.open_start_recent_item(action[action_start_recent_prefix.len..].int())
			}
		}
	}
}

// open_start_recent_item opens a history entry with the program that
// recorded it, in a new window of that program.
fn (mut d Desktop) open_start_recent_item(slot int) {
	if slot < 0 || slot >= d.start_menu_recent_items.len {
		return
	}
	item := d.start_menu_recent_items[slot]
	app := shortcut_app_index_named(item.app)
	path := item.path.clone()
	d.close_start_menu()
	if app >= 0 {
		d.open_path_in_app(app, path)
	}
	unsafe { path.free() }
}
