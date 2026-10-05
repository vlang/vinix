// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn (mut app DictionaryApp) build(size ui2.Rect) !ui2.Element {
	width := int(size.width)
	height := int(size.height)
	if width < 640 || height < 420 {
		mut message := frame_elements(1)
		message << ui2.label('', tr('dictionary.resize'), ui2.rect(14, 14, f64(width - 28), 60),
			ui2.TextStyle{color: body_muted, size: 13, lines: 3})
		return ui2.screen(app_surface, message)
	}
	list_rows := if (height - 244) / 26 < 16 { (height - 244) / 26 } else { 16 }
	if app.list_rows != list_rows { app.list_rows = list_rows; app.page = 0; app.refresh_matches() }
	app.rows = (height - 256) / 20
	app.wrap((width - 272) / 8)
	app.clamp_scroll()
	mut children := frame_elements(app.rows + app.match_count * 2 + 30)
	children << console_field('dictionary.path', editor_bytes_text(app.path), 14, 12, width - 104, app.focus == 0)
	children << console_button('dictionary.load', 'dictionary.load', width - 82, 13, 68, false)
	children << console_field('dictionary.query', editor_bytes_text(app.query), 14, 54, width - 244, app.focus == 1)
	children << console_button('dictionary.lookup', 'dictionary.lookup', width - 222, 55, 96, false)
	children << console_button('dictionary.back', 'dictionary.back', width - 118, 55, 48, false)
	children << console_button('dictionary.forward', 'dictionary.forward', width - 62, 55, 48, false)
	children << ui2.label('', tr('dictionary.matches'), ui2.rect(14, 94, 150, 24), ui2.TextStyle{color: body_muted, size: 12})
	children << ui2.label('', app.count_text, ui2.rect(160, 94, 72, 24), ui2.TextStyle{color: body_muted, size: 12})
	children << ui2.label('', app.source.word(app.selected), ui2.rect(248, 94, f64(width - 264), 24), ui2.TextStyle{color: body_text, size: 16, bold: true})
	for offset in 0 .. app.match_count {
		index := app.first + app.page + offset
		mut row := frame_elements(1)
		row << ui2.label('', app.source.word(index), ui2.rect(8, 0, 202, 24), ui2.TextStyle{color: body_text, size: 12})
		children << ui2.clickable_view(dictionary_result_actions[offset], ui2.rect(14, f64(124 + offset * 26), 218, 24),
			ui2.BoxStyle{bg: if index == app.selected { body_rule } else { body_panel }, radius: 4}, row)
	}
	for row in 0 .. app.rows {
		index := app.scroll + row
		if index >= app.lines.len { break }
		line := app.lines[index]
		children << ui2.label('', console_borrow(app.definition, line.start, line.end),
			ui2.rect(248, f64(124 + row * 20), f64(width - 264), 20),
			ui2.TextStyle{color: body_text, size: 13, font_family: 'mono'})
	}
	children << console_button('dictionary.previous', 'dictionary.previous', 14, height - 112, 102, false)
	children << console_button('dictionary.next', 'dictionary.next', 124, height - 112, 108, false)
	children << console_button('dictionary.up', 'dictionary.up', 248, height - 112, 96, false)
	children << console_button('dictionary.down', 'dictionary.down', 352, height - 112, 96, false)
	children << ui2.label('', tr('dictionary.offline'), ui2.rect(460, f64(height - 110), f64(width - 474), 28), ui2.TextStyle{color: body_muted, size: 11})
	children << console_field('dictionary.export_path', editor_bytes_text(app.export_path), 14, height - 74, width - 166, app.focus == 2)
	children << console_button('dictionary.export', 'dictionary.export', width - 144, height - 73, 130, false)
	children << ui2.label('', tr(app.status), ui2.rect(14, f64(height - 36), f64(width - 28), 24), ui2.TextStyle{color: body_muted, size: 11})
	return ui2.screen(app_surface, children)
}
