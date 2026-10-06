// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn (a &SettingsApp) search_field() ui2.Element {
	mut children := frame_elements(1)
	children << ui2.text_field('', tr('settings.search.placeholder'), editor_bytes_text(a.search),
		ui2.rect(7, 0, 102, 30), ui2.BoxStyle{ transparent: true },
		ui2.TextStyle{ color: body_text, size: 12 }, 0)
	return ui2.clickable_view('settings.search.field', ui2.rect(8, 12, 116, 30),
		ui2.BoxStyle{
			bg:            body_panel
			radius:        5
			border_color:  if a.search_focused { app_accent } else { body_rule }
			border_top:    1
			border_bottom: 1
			border_left:   1
			border_right:  1
		}, children)
}

fn (mut a SettingsApp) search_pane(width int, height int) []ui2.Element {
	inner := if width > 32 { width - 32 } else { 1 }
	text_width := if inner > 20 { inner - 20 } else { 1 }
	mut rows := (height - 124) / 44
	if rows < 1 { rows = 1 }
	if rows > settings_search_actions.len { rows = settings_search_actions.len }
	if rows != a.search_rows {
		a.search_rows = rows
		a.search_page = (a.search_selected / rows) * rows
	}
	mut out := frame_elements(rows + 6)
	out << settings_heading(tr('settings.search.heading'), 16, width)
	out << settings_note(tr('settings.search.hint'), 40, width)
	if width >= 300 {
		out << console_button('settings.search.clear', 'settings.search.clear', width - 92, 12, 76, false)
	}
	if a.search_count == 0 {
		out << ui2.label('settings.search.empty', tr('settings.search.empty'),
			ui2.rect(16, 76, f64(inner), 48),
			ui2.TextStyle{ color: body_muted, size: 13, lines: 2 })
		return out
	}
	for offset in 0 .. rows {
		index := a.search_page + offset
		if index >= a.search_count { break }
		entry := settings_search_entries[a.search_results[index]]
		mut labels := frame_elements(2)
		labels << ui2.label('', tr(entry.title), ui2.rect(10, 2, f64(text_width), 20),
			ui2.TextStyle{ color: body_text, size: 13, bold: true })
		labels << ui2.label('', entry.category.title(), ui2.rect(10, 22, f64(text_width), 16),
			ui2.TextStyle{ color: body_muted, size: 11 })
		out << ui2.clickable_view(settings_search_actions[offset],
			ui2.rect(16, f64(68 + offset * 44), f64(inner), 40),
			ui2.BoxStyle{ bg: if index == a.search_selected {
				settings_category_selected
			} else {
				body_panel
			}, radius: 5 }, labels)
	}
	if a.search_count > rows && inner >= 100 {
		button_width := if inner >= 224 { 108 } else { (inner - 8) / 2 }
		out << console_button('settings.search.previous', 'settings.search.previous', 16, height - 40, button_width, false)
		out << console_button('settings.search.next', 'settings.search.next', 24 + button_width, height - 40, button_width, false)
	}
	return out
}
