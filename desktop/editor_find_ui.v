// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn editor_edit_button(action string, label string, x int, y int, width int, enabled bool) ui2.Element {
	return ui2.Element{
		...ui2.button(action, label, ui2.rect(f64(x), f64(y), f64(width), 26), ui2.BoxStyle{
			bg:     if enabled { editor_button } else { body_panel }
			radius: 5
		}, ui2.TextStyle{
			color: if enabled { app_on_accent } else { body_muted }
			size:  12
			align: .center
		})
		enabled: enabled
	}
}

fn (a &TextEditorApp) build_edit_toolbar(mut children []ui2.Element) {
	children << editor_edit_button(editor_action_undo, tr('editor.undo'), editor_padding, 45, 68,
		a.undo_history.len > 0)
	children << editor_edit_button(editor_action_redo, tr('editor.redo'), editor_padding + 74, 45, 68,
		a.redo_history.len > 0)
	children << editor_edit_button(editor_action_find, tr('editor.find'), editor_padding + 148, 45, 68,
		true)
	if a.find_open {
		children << editor_edit_button(editor_action_find_close, tr('editor.find.close'),
			editor_padding + 222, 45, 68, true)
	}
}

fn editor_find_field(action string, text []u8, x int, y int, width int, focused bool) ui2.Element {
	mut label := frame_elements(1)
	label << ui2.label('', editor_bytes_text(text), ui2.rect(5, 0, f64(width - 10), 28), ui2.TextStyle{
		color: body_text
		font_family: 'mono'
		size: 13
	})
	return ui2.clickable_view(action, ui2.rect(f64(x), f64(y), f64(width), 28), ui2.BoxStyle{
		bg:     if focused { editor_path_focus } else { body_panel }
		radius: 5
	}, label)
}

fn (a &TextEditorApp) build_find_panel(mut children []ui2.Element, width int) {
	// Fields grow with the window while the controls keep room for translation.
	field_x := 88
	controls_x := if width > 500 { width - 204 } else { 296 }
	field_width := controls_x - field_x - 8
	find_y := editor_toolbar_height + 4
	replace_y := find_y + 34
	children << ui2.label('', tr('editor.find'), ui2.rect(10, f64(find_y), 74, 28), ui2.TextStyle{
		color: body_text
		size:  12
	})
	children << ui2.label('', tr('editor.replace'), ui2.rect(10, f64(replace_y), 74, 28), ui2.TextStyle{
		color: body_text
		size:  12
	})
	children << editor_find_field(editor_action_query, a.query, field_x, find_y, field_width,
		a.focus == .query)
	children << editor_find_field(editor_action_replacement, a.replacement, field_x, replace_y,
		field_width, a.focus == .replacement)
	children << editor_edit_button(editor_action_previous, tr('editor.find.previous'), controls_x,
		find_y + 1, 92, a.query.len > 0)
	children << editor_edit_button(editor_action_next, tr('editor.find.next'), controls_x + 98,
		find_y + 1, 96, a.query.len > 0)
	children << editor_edit_button(editor_action_replace, tr('editor.replace'), controls_x,
		replace_y + 1, 92, a.query.len > 0)
	children << editor_edit_button(editor_action_replace_all, tr('editor.replace.all'), controls_x + 98,
		replace_y + 1, 96, a.query.len > 0)
}

fn (a &TextEditorApp) build_match_highlight(mut lines []ui2.Element, start int, end int, row int) {
	if a.match_start < 0 || a.match_end <= start || a.match_start > end {
		return
	}
	left := if a.match_start > start { a.match_start } else { start }
	right := if a.match_end < end { a.match_end } else { end }
	if right <= left { return }
	x := editor_padding + editor_columns(a.text, start, left) * editor_character_width
	width := editor_columns(a.text, left, right) * editor_character_width
	lines << ui2.view('editor.find.highlight', ui2.rect(f64(x),
		f64(editor_padding + row * editor_row_height), f64(width), editor_row_height), ui2.BoxStyle{
		bg: editor_path_focus
	}, [])
}
