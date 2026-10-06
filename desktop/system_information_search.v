// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

// Search borrows snapshot rows and translations. The query and index live in
// the model, so typing, language changes and filtering allocate no strings.
fn (app &SystemInformationApp) search_text() string {
	if app.search_len == 0 { return '' }
	return unsafe { tos(&app.search[0], app.search_len) }
}

fn system_information_search_matches(row SystemInformationLine, tab int, query string) bool {
	mut at := 0
	for at < query.len {
		for at < query.len && query[at] == ` ` { at++ }
		start := at
		for at < query.len && query[at] != ` ` { at++ }
		if at == start { continue }
		token := unsafe { tos(query.str + start, at - start) }
		if !start_menu_matches(row.text, token)
			&& !start_menu_matches(tr(system_information_tab_keys[tab]), token)
			&& !(row.key.len > 0 && start_menu_matches(tr(row.key), token))
			&& !(row.unavailable && start_menu_matches(tr('system_information.unavailable'), token)) {
			return false
		}
	}
	return true
}

fn (app &SystemInformationApp) filtered_count(tab int) int {
	return if app.search_len == 0 { app.sections[tab].rows.len } else { app.search_counts[tab] }
}

fn (mut app SystemInformationApp) refilter_search(reset bool) {
	app.search_language = desktop_language
	for tab in 0 .. 4 {
		app.search_counts[tab] = 0
		for index, row in app.sections[tab].rows {
			if system_information_search_matches(row, tab, app.search_text()) {
				app.search_indices[tab][app.search_counts[tab]] = index
				app.search_counts[tab]++
			}
		}
		if reset { app.scroll[tab] = 0 }
		app.clamp_scroll(tab)
	}
	// Jump to a matching section when typing a query into an empty section.
	// Tabs can still be selected explicitly to inspect their empty result.
	if reset && app.search_len > 0 && app.filtered_count(app.tab) == 0 {
		for tab in 0 .. 4 {
			if app.filtered_count(tab) > 0 { app.tab = tab; break }
		}
	}
}

fn (mut app SystemInformationApp) focus_search(selected bool) {
	app.search_focus = true
	app.search_selected = selected
	app.path_focus = false
	app.path_selected = false
	app.pending_len = 0
	app.escape_len = 0
}

fn (mut app SystemInformationApp) focus_path() {
	app.path_focus = true
	app.path_selected = true
	app.search_focus = false
	app.search_selected = false
	app.pending_len = 0
	app.escape_len = 0
}

fn (mut app SystemInformationApp) clear_search() {
	app.search_len = 0
	app.search_selected = false
	app.pending_len = 0
	app.escape_len = 0
	app.refilter_search(true)
}

fn (mut app SystemInformationApp) append_search(text string) {
	length := if app.search_selected { 0 } else { app.search_len }
	if length + text.len > app.search.len { return }
	app.search_len = length
	app.search_selected = false
	for ch in text { app.search[app.search_len] = ch; app.search_len++ }
	app.refilter_search(true)
}

fn (mut app SystemInformationApp) search_byte(ch u8) {
	if app.pending_len > 0 {
		if editor_utf8_follows(app.pending[0], app.pending_len, ch) {
			app.pending[app.pending_len] = ch
			app.pending_len++
			if app.pending_len == editor_utf8_length(app.pending[0]) {
				app.append_search(unsafe { tos(&app.pending[0], app.pending_len) })
				app.pending_len = 0
			}
			return
		}
		app.pending_len = 0
	}
	if ch == 8 || ch == 127 {
		if app.search_selected { app.clear_search(); return }
		mut from := app.search_len - 1
		for from > 0 && app.search[from] & 0xc0 == 0x80 { from-- }
		if from >= 0 { app.search_len = from; app.refilter_search(true) }
	} else if ch >= 32 && ch < 127 {
		app.append_search(unsafe { tos(&ch, 1) })
	} else if editor_utf8_length(ch) > 1 {
		app.pending[0] = ch
		app.pending_len = 1
	}
}

fn (mut app SystemInformationApp) paste_search(text string) {
	app.pending_len = 0
	// Sanitize and bound a whole paste before replacing selected text. A large
	// clipboard payload cannot erase the query or leave a partial UTF-8 rune.
	mut bytes := [128]u8{}
	mut length := 0
	mut at := 0
	for at < text.len {
		ch := text[at]
		if ch < 32 || ch == 127 {
			if ch == `\n` || ch == `\r` || ch == `\t` {
				if length == bytes.len { return }
				bytes[length] = ` `
				length++
			}
			at++
			continue
		}
		size := editor_utf8_length(ch)
		if size == 0 { at++; continue }
		if at + size > text.len { break }
		mut valid := true
		for next in 1 .. size { if !editor_utf8_follows(ch, next, text[at + next]) { valid = false; break } }
		if !valid { at++; continue }
		if length + size > bytes.len { return }
		for next in 0 .. size { bytes[length] = text[at + next]; length++ }
		at += size
	}
	app.pending_len = 0
	if length > 0 { app.append_search(unsafe { tos(&bytes[0], length) }) }
}

fn (app &SystemInformationApp) search_field(width int) ui2.Element {
	text := app.search_text()
	mut count := 0
	for ch in text { if ch & 0xc0 != 0x80 { count++ } }
	return ui2.Element{
		...ui2.text_field('system_information.search', tr('system_information.search.placeholder'), text,
			ui2.rect(216, 54, f64(width - 314), 28), ui2.BoxStyle{bg: body_panel, radius: 5},
			ui2.TextStyle{color: body_text, size: 12}, 0)
		focused: app.search_focus
		text_selection: ui2.TextSelection{anchor: if app.search_focus && app.search_selected { 0 } else { count }, caret: count}
		tooltip: tr('system_information.search.hint')
	}
}

// Escape also starts terminal navigation sequences. Wait briefly for their
// bounded suffix, so an IPC message boundary cannot turn an arrow into text.
fn (mut app SystemInformationApp) escape_byte(ch u8) bool {
	if app.escape_len == 0 { return false }
	if app.escape_len == 1 && ch != `[` && ch != `O` {
		app.expire_escape(~u64(0))
		return false
	}
	if app.escape_len == app.escape.len {
		if ch >= 0x40 && ch <= 0x7e { app.escape_len = 0 }
		return true
	}
	app.escape[app.escape_len] = ch
	app.escape_len++
	if app.escape_len > 2 && ch >= 0x40 && ch <= 0x7e {
		sequence := unsafe { tos(&app.escape[0], app.escape_len) }
		match sequence {
			'\x1b[A', '\x1bOA' { app.scroll[app.tab]-- }
			'\x1b[B', '\x1bOB' { app.scroll[app.tab]++ }
			'\x1b[5~' { app.scroll[app.tab] -= app.visible_rows }
			'\x1b[6~' { app.scroll[app.tab] += app.visible_rows }
			'\x1b[H', '\x1b[1~', '\x1bOH' { app.scroll[app.tab] = 0 }
			'\x1b[F', '\x1b[4~', '\x1bOF' { app.scroll[app.tab] = system_information_row_limit }
			else {}
		}
		app.clamp_scroll(app.tab)
		app.escape_len = 0
	}
	return true
}

fn (mut app SystemInformationApp) expire_escape(now u64) bool {
	if app.escape_len == 0 || (now != ~u64(0) && now >= app.escape_ms && now - app.escape_ms < 100) {
		return false
	}
	if app.escape_len == 1 {
		if app.search_focus { app.clear_search() }
		app.search_focus = false
		app.path_focus = false
		app.pending_len = 0
	}
	app.escape_len = 0
	return true
}

fn (mut app SystemInformationApp) poll() bool { return app.expire_escape(desktop_monotonic_ms()) }

fn (app &SystemInformationApp) next_poll_ms() u64 {
	return if app.escape_len > 0 { u64(100) } else { u64(2000) }
}
