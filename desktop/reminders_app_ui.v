// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn (mut app RemindersApp) focus_field(field int) {
	if field < 2 && !app.editing { return }
	app.focus = field
	app.select_all = false
	app.pending_len = 0
}

fn (mut app RemindersApp) handle(event_id string) ! {
	app.pending_len = 0
	if event_id.starts_with('reminders.row.') {
		if app.editing { return }
		index := calendar_integer(console_borrow(event_id, 14, event_id.len)) or { return }
		if index >= 0 && index < app.data.count {
			app.selected = index
			app.confirming_delete = false
		}
		return
	}
	match event_id {
		'reminders.new' { if !app.editing { app.begin_edit(-1) } }
		'reminders.edit' {
			if !app.editing {
				if app.selected < 0 { app.status = 'reminders.select_task' } else { app.begin_edit(app.selected) }
			}
		}
		'reminders.save' { app.save_edit() }
		'reminders.cancel' { app.cancel_edit() app.status = 'reminders.ready' }
		'reminders.toggle' { if !app.editing { app.confirming_delete = false app.toggle_selected() } }
		'reminders.delete' {
			if !app.editing {
				if app.selected < 0 { app.status = 'reminders.select_task' }
				else { app.confirming_delete = true app.status = 'reminders.confirm_delete' }
			}
		}
		'reminders.delete_confirm' { app.delete_selected() }
		'reminders.delete_cancel' { app.confirming_delete = false app.status = 'reminders.ready' }
		'reminders.reload' { app.reload() }
		'reminders.title' { app.focus_field(0) }
		'reminders.due' { app.focus_field(1) }
		'reminders.search' { app.focus_field(2) }
		'reminders.export_path' { app.focus_field(3) }
		'reminders.export_text' { app.export_visible(false) }
		'reminders.export_csv' { app.export_visible(true) }
		'reminders.filter.all', 'reminders.filter.open', 'reminders.filter.completed', 'reminders.filter.overdue' {
			app.filter = match event_id { 'reminders.filter.open' { RemindersFilter.open } 'reminders.filter.completed' { RemindersFilter.completed } 'reminders.filter.overdue' { RemindersFilter.overdue } else { RemindersFilter.all } }
			app.scroll = 0
			app.refilter()
		}
		'reminders.previous' { app.scroll -= app.page_rows app.clamp_scroll() }
		'reminders.next' { app.scroll += app.page_rows app.clamp_scroll() }
		else {}
	}
}

fn (mut app RemindersApp) append_character(character string) {
	if character.len == 2 && character[0] == 0xc2 && character[1] <= 0x9f { return }
	match app.focus {
		0 { if app.editing { console_edit_character(mut app.title_input, character, reminders_title_limit, app.select_all) } }
		1 { if app.editing { console_edit_character(mut app.due_input, character, 16, app.select_all) } }
		2 { console_edit_character(mut app.search_input, character, reminders_title_limit, app.select_all) app.refilter() }
		3 { console_edit_character(mut app.export_input, character, 4096, app.select_all) }
		else { return }
	}
	app.select_all = false
}

fn (mut app RemindersApp) paste_input(text string) {
	app.pending_len = 0
	match app.focus {
		0 { if app.editing { console_paste_field(mut app.title_input, text, reminders_title_limit, app.select_all) } }
		1 { if app.editing { console_paste_field(mut app.due_input, text, 16, app.select_all) } }
		2 { console_paste_field(mut app.search_input, text, reminders_title_limit, app.select_all) app.refilter() }
		3 { console_paste_field(mut app.export_input, text, 4096, app.select_all) }
		else { return }
	}
	app.select_all = false
}

fn (mut app RemindersApp) key_input(input string) {
	if input == '\x1b[5~' { app.handle('reminders.previous') or {} return }
	if input == '\x1b[6~' { app.handle('reminders.next') or {} return }
	if input.len > 1 && input[0] == 0x1b { app.pending_len = 0 return }
	for byte in input {
		if app.pending_len > 0 {
			if editor_utf8_follows(app.pending[0], app.pending_len, byte) {
				app.pending[app.pending_len] = byte
				app.pending_len++
				if app.pending_len == editor_utf8_length(app.pending[0]) {
					app.append_character(unsafe { tos(&app.pending[0], app.pending_len) })
					app.pending_len = 0
				}
				continue
			}
			app.pending_len = 0
		}
		if byte == 0x1b { app.cancel_edit() }
		else if byte == `\t` { app.focus_field(if app.editing { (app.focus + 1) % 4 } else { if app.focus == 2 { 3 } else { 2 } }) }
		else if byte == `\r` || byte == `\n` { if app.focus < 2 { app.save_edit() } }
		else if byte == 0x01 { app.select_all = true }
		else if byte == 0x7f || byte == 0x08 {
			match app.focus {
				0 { if app.editing { console_backspace(mut app.title_input, app.select_all) } }
				1 { if app.editing { console_backspace(mut app.due_input, app.select_all) } }
				2 { console_backspace(mut app.search_input, app.select_all) app.refilter() }
				3 { console_backspace(mut app.export_input, app.select_all) }
				else {}
			}
			app.select_all = false
		} else if byte >= 0x20 && byte < 0x7f { app.append_character(unsafe { tos(&byte, 1) }) }
		else if editor_utf8_length(byte) > 1 { app.pending[0] = byte app.pending_len = 1 }
	}
}

fn reminders_csv_field(mut bytes []u8, field string) {
	bytes << `"`
	for byte in field {
		if byte == `"` { bytes << `"` }
		bytes << byte
	}
	bytes << `"`
}

fn (app &RemindersApp) visible_text(csv bool) string {
	mut bytes := []u8{cap: reminders_record_limit}
	unsafe { bytes.flags |= .noslices }
	if csv {
		for index, key in ['reminders.csv_title', 'reminders.csv_due', 'reminders.csv_completed']! {
			if index > 0 { bytes << `,` }
			reminders_csv_field(mut bytes, tr(key))
		}
		bytes << `\n`
	}
	for slot in 0 .. app.match_count {
		item := &app.data.items[app.matches[slot]]
		if csv {
			reminders_csv_field(mut bytes, item.title)
			bytes << `,`
			reminders_csv_field(mut bytes, item.due)
			bytes << `,`
			bytes << if item.completed { u8(`1`) } else { u8(`0`) }
		} else {
			editor_append(mut bytes, if item.completed { '[x] ' } else { '[ ] ' })
			editor_append(mut bytes, item.title)
			if item.due.len > 0 { bytes << `\t` editor_append(mut bytes, item.due) }
		}
		bytes << `\n`
	}
	result := editor_bytes_text(bytes).clone()
	unsafe { bytes.free() }
	return result
}

fn (mut app RemindersApp) export_visible(csv bool) {
	data := app.visible_text(csv)
	defer { unsafe { data.free() } }
	app.status = reminders_write_export(editor_bytes_text(app.export_input), data)
}

fn (mut app RemindersApp) build(size ui2.Rect) !ui2.Element {
	width := int(size.width)
	height := int(size.height)
	app.page_rows = if height > 416 { (height - 392) / 40 } else { 1 }
	if app.page_rows < 1 { app.page_rows = 1 }
	if app.page_rows > reminders_limit { app.page_rows = reminders_limit }
	app.clamp_scroll()
	mut children := frame_elements(40 + app.page_rows)
	for index, key in ['reminders.filter.all', 'reminders.filter.open', 'reminders.filter.completed', 'reminders.filter.overdue']! {
		children << console_button(key, key, 14 + index * 112, 10, 104, int(app.filter) == index)
	}
	children << ui2.label('', app.count_text, ui2.rect(474, 10, f64(width - 488), 28), ui2.TextStyle{color: body_muted, size: 12})
	children << ui2.label('', tr('reminders.search'), ui2.rect(14, 48, 120, 30), ui2.TextStyle{color: body_muted, size: 12})
	children << console_field('reminders.search', editor_bytes_text(app.search_input), 142, 46, width - 156, app.focus == 2)
	for index, key in ['reminders.new', 'reminders.edit', 'reminders.toggle', 'reminders.delete', 'reminders.reload']! {
		children << console_button(key, key, 14 + index * 138, 84, 130, false)
	}
	if app.match_count == 0 {
		children << ui2.label('', tr('reminders.no_tasks'), ui2.rect(18, 132, f64(width - 36), 36), ui2.TextStyle{color: body_muted, size: 13})
	}
	for row in 0 .. app.page_rows {
		slot := app.scroll + row
		if slot >= app.match_count { break }
		index := app.matches[slot]
		item := &app.data.items[index]
		mut content := frame_elements(3)
		content << ui2.label('', item.title, ui2.rect(8, 0, f64(width - 52), 20), ui2.TextStyle{color: body_text, size: 12})
		content << ui2.label('', if item.due.len > 0 { item.due } else { tr('reminders.no_due') }, ui2.rect(8, 20, 160, 17), ui2.TextStyle{color: body_muted, size: 11})
		content << ui2.label('', tr(app.due_status(index)), ui2.rect(178, 20, f64(width - 224), 17), ui2.TextStyle{color: if app.is_overdue(index) { u32(0xf08070) } else { body_muted }, size: 11})
		children << ui2.clickable_view(app.row_actions[index], ui2.rect(14, f64(124 + row * 40), f64(width - 28), 38), ui2.BoxStyle{bg: body_panel, radius: 4, border_color: if app.selected == index { app_accent } else { body_rule }, border_left: 1, border_right: 1, border_top: 1, border_bottom: 1}, content)
	}
	footer := height - 256
	children << console_button('reminders.previous', 'reminders.previous', 14, footer, 110, false)
	children << console_button('reminders.next', 'reminders.next', 132, footer, 110, false)
	if app.editing {
		children << ui2.label('', tr('reminders.title_field'), ui2.rect(14, f64(footer + 35), f64(width - 28), 18), ui2.TextStyle{color: body_muted, size: 11})
		children << console_field('reminders.title', editor_bytes_text(app.title_input), 14, footer + 55, width - 28, app.focus == 0)
		children << ui2.label('', tr('reminders.due_field'), ui2.rect(14, f64(footer + 91), f64(width - 28), 18), ui2.TextStyle{color: body_muted, size: 11})
		children << console_field('reminders.due', editor_bytes_text(app.due_input), 14, footer + 111, width - 268, app.focus == 1)
		children << console_button('reminders.save', 'reminders.save', width - 240, footer + 112, 112, false)
		children << console_button('reminders.cancel', 'reminders.cancel', width - 120, footer + 112, 106, false)
	} else if app.confirming_delete {
		children << ui2.label('', tr('reminders.confirm_delete'), ui2.rect(14, f64(footer + 42), f64(width - 28), 24), ui2.TextStyle{color: body_text, size: 12})
		children << console_button('reminders.delete_confirm', 'reminders.delete_confirm', 14, footer + 77, 160, false)
		children << console_button('reminders.delete_cancel', 'reminders.delete_cancel', 182, footer + 77, 150, false)
	} else {
		children << ui2.label('', tr('reminders.hint'), ui2.rect(14, f64(footer + 44), f64(width - 28), 60), ui2.TextStyle{color: body_muted, size: 12, lines: 3})
	}
	children << ui2.label('', tr(if app.read_failed { 'reminders.read_failed' } else if !app.clock_valid && app.status == 'reminders.ready' { 'reminders.clock_unavailable' } else { app.status }), ui2.rect(14, f64(height - 105), f64(width - 28), 26), ui2.TextStyle{color: body_text, size: 12})
	children << ui2.label('', tr('reminders.export_path'), ui2.rect(14, f64(height - 76), f64(width - 28), 18), ui2.TextStyle{color: body_muted, size: 11})
	children << console_field('reminders.export_path', editor_bytes_text(app.export_input), 14, height - 54, width - 264, app.focus == 3)
	children << console_button('reminders.export_text', 'reminders.export_text', width - 236, height - 53, 108, false)
	children << console_button('reminders.export_csv', 'reminders.export_csv', width - 120, height - 53, 106, false)
	return ui2.screen(app_surface, children)
}
