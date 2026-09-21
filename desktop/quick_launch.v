// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// Quick Launch: a Spotlight-style application search overlay.
module main

import ui2

const quick_launch_key = '\x1b[32;9u'
const quick_launch_cmd_release = '\x1b[57444;1:3u'
const quick_launch_cmd_tab = '\x1b[9;9u'
const quick_launch_cmd_shift_tab = '\x1b[9;10u'
const quick_launch_down_keys = ['\x1b[B', '\x1bOB']
const quick_launch_up_keys = ['\x1b[A', '\x1bOA']
const quick_launch_panel_action = 'switch.-1'
const quick_launch_backdrop_action = 'switch.-2'
const quick_launch_max_results = 7
const quick_launch_panel_width = 620
const quick_launch_search_height = 58
const quick_launch_row_height = 48
const quick_launch_panel_padding = 12
const quick_launch_bg = u32(0xf4f4f6)
const quick_launch_field_bg = u32(0xffffff)
const quick_launch_text = u32(0x22252b)
const quick_launch_muted = u32(0x737985)
const quick_launch_hover = u32(0xe5e7eb)

// toggle_quick_launch is the global Cmd-Space action. The normal window
// switcher owns the keyboard path already, so the launcher can appear even
// while a terminal or editor has keyboard focus.
fn (mut d Desktop) toggle_quick_launch() {
	if d.switcher.quick_launch {
		d.switcher_close()
		return
	}
	if d.switcher.active {
		d.switcher_close()
	}
	if d.start_menu_open {
		d.close_start_menu()
	}
	d.quick_launch_reset_query()
	for d.switcher.ids.len < available_apps.len {
		d.switcher.ids << '${action_switch_prefix}${d.switcher.ids.len}'
	}
	d.switcher.quick_launch = true
	d.switcher.active = true
	d.switcher.shown = true
	d.switcher.index = 0
	d.set_hover('')
	d.dirty = true
}

fn (mut d Desktop) quick_launch_reset_query() {
	d.quick_launch_free_query()
	d.switcher.query = []u8{cap: start_menu_max_query}
	// The launcher only appends and removes bytes. No slice escapes from this
	// buffer, so replacing it later can release the old allocation directly.
	unsafe { d.switcher.query.flags |= .noslices }
}

fn (mut d Desktop) quick_launch_free_query() {
	if d.switcher.query.cap > 0 {
		unsafe { d.switcher.query.free() }
		d.switcher.query = []u8{}
	}
}

fn (d &Desktop) quick_launch_query_text() string {
	if d.switcher.query.len == 0 {
		return ''
	}
	return unsafe { tos(d.switcher.query.data, d.switcher.query.len) }
}

fn (d &Desktop) quick_launch_match_count() int {
	query := d.quick_launch_query_text()
	mut count := 0
	for factory in available_apps {
		if start_menu_matches(factory.title, query) {
			count++
		}
	}
	return count
}

fn (d &Desktop) quick_launch_visible_limit() int {
	// Leave room above and below the panel on short displays. Normal laptop
	// desktops still get the full seven Spotlight-style result rows.
	mut rows := (d.canvas.height - 150 - quick_launch_search_height) / quick_launch_row_height
	if rows > quick_launch_max_results {
		rows = quick_launch_max_results
	}
	if rows < 1 {
		rows = 1
	}
	return rows
}

fn (d &Desktop) quick_launch_visible_count() int {
	count := d.quick_launch_match_count()
	limit := d.quick_launch_visible_limit()
	return if count < limit { count } else { limit }
}

// quick_launch_app_index maps a visible result number back to the one canonical
// application registry. Quick Launch deliberately has no second app database.
fn (d &Desktop) quick_launch_app_index(result_index int) ?int {
	if result_index < 0 {
		return none
	}
	query := d.quick_launch_query_text()
	mut result := 0
	for app_index, factory in available_apps {
		if !start_menu_matches(factory.title, query) {
			continue
		}
		if result == result_index {
			return app_index
		}
		result++
	}
	return none
}

fn (mut d Desktop) quick_launch_move_selection(step int) {
	count := d.quick_launch_visible_count()
	if count == 0 {
		d.switcher.index = 0
		return
	}
	d.switcher.index = ((d.switcher.index + step) % count + count) % count
	d.dirty = true
}

fn (mut d Desktop) quick_launch_launch_selected() {
	// An empty Spotlight field is a suggestion list, not an accidental Files
	// shortcut. Typing at least one character makes Return launch the selection.
	if d.switcher.query.len == 0 {
		return
	}
	app_index := d.quick_launch_app_index(d.switcher.index) or { return }
	d.switcher_close()
	d.launch_index(app_index)
}

// quick_launch_take_keys owns all keyboard input while the overlay is open.
// It also recognises the global Cmd sequences so switching or toggling remains
// possible without first dismissing the launcher.
fn (mut d Desktop) quick_launch_take_keys(input string) string {
	mut i := 0
	for i < input.len {
		ch := input[i]
		if ch == 0x1b {
			taken := d.quick_launch_take_sequence(input, i)
			if taken > seq_none {
				i += taken
				if !d.switcher.quick_launch {
					return ''
				}
				continue
			}
			if taken == seq_partial {
				d.switcher.pending = input[i..]
				return ''
			}
			// A bare Escape is the standard Spotlight dismissal gesture.
			d.switcher_close()
			return ''
		}
		match ch {
			8, 127 {
				if d.switcher.query.len > 0 {
					d.switcher.query.delete_last()
					d.switcher.index = 0
					d.dirty = true
				}
			}
			`\n`, `\r` {
				d.quick_launch_launch_selected()
				return ''
			}
			`\t` {
				d.quick_launch_move_selection(1)
			}
			else {
				if ch >= 0x20 && ch < 0x7f && d.switcher.query.len < start_menu_max_query {
					d.switcher.query << ch
					d.switcher.index = 0
					d.dirty = true
				}
			}
		}
		i++
	}
	return ''
}

fn (mut d Desktop) quick_launch_take_sequence(input string, at int) int {
	mut partial := false

	found_toggle := match_at(input, at, quick_launch_key)
	if found_toggle > seq_none {
		if !d.switcher.quick_launch_chord_held {
			d.switcher.quick_launch_chord_held = true
			d.switcher_close()
		}
		return found_toggle
	}
	partial = partial || found_toggle == seq_partial

	found_release := match_at(input, at, quick_launch_cmd_release)
	if found_release > seq_none {
		d.switcher.quick_launch_chord_held = false
		return found_release
	}
	partial = partial || found_release == seq_partial

	found_forward := match_at(input, at, quick_launch_cmd_tab)
	if found_forward > seq_none {
		d.switcher_close()
		d.switcher_step(1)
		return found_forward
	}
	partial = partial || found_forward == seq_partial

	found_backward := match_at(input, at, quick_launch_cmd_shift_tab)
	if found_backward > seq_none {
		d.switcher_close()
		d.switcher_step(-1)
		return found_backward
	}
	partial = partial || found_backward == seq_partial

	for sequence in quick_launch_down_keys {
		found := match_at(input, at, sequence)
		if found > seq_none {
			d.quick_launch_move_selection(1)
			return found
		}
		partial = partial || found == seq_partial
	}
	for sequence in quick_launch_up_keys {
		found := match_at(input, at, sequence)
		if found > seq_none {
			d.quick_launch_move_selection(-1)
			return found
		}
		partial = partial || found == seq_partial
	}
	return if partial { seq_partial } else { seq_none }
}

// quick_launch_element is a centered search field with a short result stack,
// intentionally closer to Spotlight than to a menu. Every result is one entry
// from available_apps and therefore launches through the desktop's normal app
// path.
fn (d &Desktop) quick_launch_element() ui2.Element {
	mut width := quick_launch_panel_width
	if width > d.canvas.width - 32 {
		width = d.canvas.width - 32
	}
	if width < 1 {
		width = 1
	}
	result_count := d.quick_launch_visible_count()
	result_area_height := if result_count > 0 {
		result_count * quick_launch_row_height + 8
	} else {
		54
	}
	panel_height := quick_launch_panel_padding * 2 + quick_launch_search_height + result_area_height
	mut panel_y := d.canvas.height / 7
	if panel_y < 24 {
		panel_y = 24
	}
	if panel_y + panel_height > d.canvas.height - 24 {
		panel_y = 24
	}
	panel_x := (d.canvas.width - width) / 2

	mut panel_children := frame_elements(result_count + 3)
	query := d.quick_launch_query_text()
	search_text := if query.len > 0 { query } else { 'Search applications' }
	panel_children << ui2.button_with_image('', search_text, 'builtin:search', ui2.rect(f64(quick_launch_panel_padding), f64(quick_launch_panel_padding), f64(width - 2 * quick_launch_panel_padding), f64(quick_launch_search_height)), ui2.BoxStyle{
		bg: quick_launch_field_bg
		radius: 10
	}, ui2.TextStyle{
		color: if query.len > 0 { quick_launch_text } else { quick_launch_muted }
		size: 18
		align: .left
	})

	row_y := quick_launch_panel_padding + quick_launch_search_height + 8
	if result_count == 0 {
		panel_children << ui2.label('quick-launch.empty', 'No applications found', ui2.rect(24, f64(row_y + 9), f64(width - 48), 30), ui2.TextStyle{
			color: quick_launch_muted
			size: 13
			align: .left
		})
	} else {
		mut result := 0
		for factory in available_apps {
			if !start_menu_matches(factory.title, query) {
				continue
			}
			if result >= result_count {
				break
			}
			id := d.switcher.ids[result]
			selected := result == d.switcher.index
			hovered := d.hover == id
			panel_children << ui2.button_with_image(id, factory.title, factory.icon, ui2.rect(f64(quick_launch_panel_padding), f64(row_y + result * quick_launch_row_height), f64(width - 2 * quick_launch_panel_padding), f64(quick_launch_row_height)), ui2.BoxStyle{
				bg: if selected { d.theme().accent } else if hovered { quick_launch_hover } else { quick_launch_bg }
				radius: 7
			}, ui2.TextStyle{
				color: if selected { u32(0xffffff) } else { quick_launch_text }
				size: 14
				bold: selected
				align: .left
			})
			result++
		}
	}

	panel := ui2.clickable_view(quick_launch_panel_action, ui2.rect(f64(panel_x), f64(panel_y), f64(width), f64(panel_height)), ui2.BoxStyle{
		bg: quick_launch_bg
		radius: 13
	}, panel_children)
	return ui2.clickable_view(quick_launch_backdrop_action, ui2.rect(0, 0, f64(d.canvas.width), f64(d.canvas.height)), ui2.BoxStyle{
		transparent: true
	}, frame_child(panel))
}
