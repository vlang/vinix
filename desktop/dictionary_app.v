// SPDX-License-Identifier: GPL-2.0-or-later
// Offline exact and prefix lookup with bounded definition/history storage.
module main

const dictionary_result_actions = ['dictionary.result.0', 'dictionary.result.1',
	'dictionary.result.2', 'dictionary.result.3', 'dictionary.result.4', 'dictionary.result.5',
	'dictionary.result.6', 'dictionary.result.7', 'dictionary.result.8', 'dictionary.result.9',
	'dictionary.result.10', 'dictionary.result.11', 'dictionary.result.12', 'dictionary.result.13',
	'dictionary.result.14', 'dictionary.result.15']!
const dictionary_field_limit = 512
const dictionary_history_limit = 32

struct DictionaryApp {
mut:
	source DictionarySource
	path []u8
	query []u8
	key []u8
	export_path []u8
	definition string
	lines []ConsoleLine
	selected int = -1
	first int
	match_count int
	page int
	list_rows int = 16
	rows int = 12
	scroll int
	columns int
	count_text string
	status string = 'dictionary.unavailable'
	focus int = 1
	select_all bool
	pending [4]u8
	pending_len int
	escape [16]u8
	escape_len int
	history []string
	history_index int = -1
}

fn new_dictionary_app(path string, export_path string) DictionaryApp {
	mut app := DictionaryApp{
		path: []u8{cap: dictionary_field_limit}
		query: []u8{cap: dictionary_key_limit}
		key: []u8{cap: dictionary_key_limit}
		export_path: []u8{cap: dictionary_field_limit}
		lines: []ConsoleLine{cap: 512}
		history: []string{cap: dictionary_history_limit}
	}
	unsafe { app.path.flags |= .noslices; app.query.flags |= .noslices; app.key.flags |= .noslices
		app.export_path.flags |= .noslices; app.lines.flags |= .noslices; app.history.flags |= .noslices }
	editor_append(mut app.path, path)
	editor_append(mut app.export_path, export_path)
	editor_append(mut app.query, 'computer')
	app.load_source()
	return app
}

fn open_dictionary_app(mut _ Desktop) !NativeApp {
	home := if desktop_user_home.len > 0 { desktop_user_home } else { desktop_home }
	canonical := reminders_canonical_home(home)
	defer { unsafe { canonical.free() } }
	path := if canonical.len > 0 { disk_utility_join_path(canonical, 'dictionary-definition.txt') } else { '' }
	defer { unsafe { path.free() } }
	app := new_dictionary_app(dictionary_default_path, path)
	return &app
}

fn (mut app DictionaryApp) load_source() bool {
	next := dictionary_read_source(editor_bytes_text(app.path)) or {
		app.status = 'dictionary.unavailable'
		return false
	}
	app.source.close()
	app.source = next
	for word in app.history { unsafe { word.free() } }
	app.history.clear()
	app.history_index = -1
	unsafe { app.count_text.free(); app.definition.free() }
	app.definition = ''
	app.selected = -1
	app.lines.clear()
	app.scroll = 0
	app.count_text = app.source.count.str()
	app.refilter()
	app.lookup(true)
	return true
}

fn (mut app DictionaryApp) refilter() {
	app.key.clear()
	mut space := false
	for byte in app.query {
		if byte == ` ` || byte == `_` {
			space = app.key.len > 0
		} else {
			if space { app.key << ` `; space = false }
			app.key << if byte >= `A` && byte <= `Z` { byte + 32 } else { byte }
		}
	}
	app.page = 0
	app.first = app.source.lower_bound(editor_bytes_text(app.key))
	app.refresh_matches()
}

fn (mut app DictionaryApp) refresh_matches() {
	app.match_count = 0
	query := editor_bytes_text(app.key)
	for offset in 0 .. app.list_rows {
		index := app.first + app.page + offset
		if index >= app.source.count || !app.source.word(index).starts_with(query) { break }
		app.match_count++
	}
}

fn (mut app DictionaryApp) page_by(delta int) {
	next := app.page + delta * app.list_rows
	if next < 0 { return }
	if delta > 0 {
		index := app.first + next
		if index >= app.source.count || !app.source.word(index).starts_with(editor_bytes_text(app.key)) { return }
	}
	app.page = next
	app.refresh_matches()
}

fn (mut app DictionaryApp) show(index int, remember bool) bool {
	text := app.source.read_definition(index) or { app.status = 'dictionary.read_failed'; return false }
	unsafe { app.definition.free() }
	app.definition = text
	app.selected = index
	app.scroll = 0
	app.columns = 0
	app.status = 'dictionary.ready'
	if remember {
		word := app.source.word(index)
		if app.history_index >= 0 && app.history[app.history_index] == word { return true }
		for app.history.len > app.history_index + 1 {
			unsafe { app.history.last().free() }
			app.history.delete_last()
		}
		if app.history.len == dictionary_history_limit {
			unsafe { app.history[0].free() }
			app.history.delete(0)
		}
		app.history << word.clone()
		app.history_index = app.history.len - 1
	}
	return true
}

fn (mut app DictionaryApp) lookup(remember bool) bool {
	if app.source.fd < 0 { app.status = 'dictionary.unavailable'; return false }
	if app.key.len == 0 || app.match_count == 0 {
		app.status = 'dictionary.no_match'
		return false
	}
	return app.show(app.first + app.page, remember)
}

fn (mut app DictionaryApp) visit(delta int) {
	next := app.history_index + delta
	if next < 0 || next >= app.history.len { return }
	app.query.clear()
	editor_append(mut app.query, app.history[next])
	app.refilter()
	index := app.source.lower_bound(app.history[next])
	if app.show(index, false) { app.history_index = next }
}

fn (mut app DictionaryApp) wrap(columns int) {
	if columns == app.columns { return }
	app.columns = columns
	app.lines.clear()
	mut start := 0
	mut at := 0
	mut count := 0
	mut last_space := -1
	for at < app.definition.len {
		if app.definition[at] == `\n` {
			app.lines << ConsoleLine{ start: start, end: at }
			at++; start = at; count = 0; last_space = -1
			continue
		}
		if app.definition[at] == ` ` { last_space = at }
		if count == columns {
			end := if last_space > start { last_space } else { at }
			app.lines << ConsoleLine{ start: start, end: end }
			at = if last_space > start { end + 1 } else { at }
			start = at; count = 0; last_space = -1
			continue
		}
		at += editor_utf8_length(app.definition[at]); count++
	}
	if start < app.definition.len { app.lines << ConsoleLine{ start: start, end: app.definition.len } }
	app.clamp_scroll()
}

fn (mut app DictionaryApp) clamp_scroll() {
	maximum := if app.lines.len > app.rows { app.lines.len - app.rows } else { 0 }
	if app.scroll < 0 { app.scroll = 0 }
	if app.scroll > maximum { app.scroll = maximum }
}

fn (mut app DictionaryApp) export_definition() {
	if app.selected < 0 || app.definition.len == 0 { app.status = 'dictionary.no_match'; return }
	result := notes_export(editor_bytes_text(app.export_path), app.source.word(app.selected), app.definition)
	app.status = match result {
		'notes.export_saved' { 'dictionary.exported' }
		'notes.export_exists' { 'dictionary.export_exists' }
		'notes.export_invalid' { 'dictionary.path_invalid' }
		else { 'dictionary.export_failed' }
	}
}

fn (mut app DictionaryApp) handle(event_id string) ! {
	app.pending_len = 0
	if event_id.starts_with('dictionary.result.') {
		for offset, action in dictionary_result_actions {
			if event_id == action && offset < app.match_count { app.show(app.first + app.page + offset, true); return }
		}
		return
	}
	match event_id {
		'dictionary.path' { app.focus = 0; app.select_all = false }
		'dictionary.query' { app.focus = 1; app.select_all = false }
		'dictionary.export_path' { app.focus = 2; app.select_all = false }
		'dictionary.load' { app.load_source() }
		'dictionary.lookup' { app.lookup(true) }
		'dictionary.back' { app.visit(-1) }
		'dictionary.forward' { app.visit(1) }
		'dictionary.previous' { app.page_by(-1) }
		'dictionary.next' { app.page_by(1) }
		'dictionary.up' { app.scroll -= app.rows; app.clamp_scroll() }
		'dictionary.down' { app.scroll += app.rows; app.clamp_scroll() }
		'dictionary.export' { app.export_definition() }
		else {}
	}
}

fn (mut app DictionaryApp) paste_input(text string) {
	match app.focus {
		0 { console_paste_field(mut app.path, text, dictionary_field_limit, app.select_all) }
		1 { console_paste_field(mut app.query, text, dictionary_key_limit, app.select_all); app.refilter() }
		2 { console_paste_field(mut app.export_path, text, dictionary_field_limit, app.select_all) }
		else { return }
	}
	app.select_all = false
	app.pending_len = 0
}

fn (mut app DictionaryApp) key_input(input string) {
	mut at := 0
	for at < input.len {
		byte := input[at]
		at++
		if app.escape_len > 0 {
			if app.escape_len == 1 && byte != `[` {
				app.escape_len = 0; app.focus = -1; app.select_all = false
			} else {
				app.escape[app.escape_len] = byte; app.escape_len++
				if (byte >= `A` && byte <= `Z`) || (byte >= `a` && byte <= `z`) || byte == `~` {
					sequence := unsafe { tos(&app.escape[0], app.escape_len) }
					match sequence {
						'\x1b[5~' { app.page_by(-1) }
						'\x1b[6~' { app.page_by(1) }
						'\x1b[A', '\x1b[B' {
							if app.match_count > 0 {
								first := app.first + app.page
								last := first + app.match_count - 1
								index := if app.selected < first || app.selected > last { first }
									else if byte == `A` { if app.selected > first { app.selected - 1 } else { first } }
									else { if app.selected < last { app.selected + 1 } else { last } }
								app.show(index, true)
							}
						}
						else {}
					}
					app.escape_len = 0
				} else if app.escape_len == app.escape.len { app.escape_len = 0 }
				continue
			}
		}
		if app.pending_len > 0 {
			if editor_utf8_follows(app.pending[0], app.pending_len, byte) {
				app.pending[app.pending_len] = byte; app.pending_len++
				if app.pending_len == editor_utf8_length(app.pending[0]) {
					app.paste_input(unsafe { tos(&app.pending[0], app.pending_len) })
				}
				continue
			}
			app.pending_len = 0
		}
		match byte {
			0x01 { app.select_all = true }
			0x1b { app.escape[0] = byte; app.escape_len = 1; app.pending_len = 0 }
			`\t` { app.focus = (app.focus + 1) % 3; app.select_all = false }
			`\r`, `\n` {
				if app.focus == 0 { app.load_source() } else if app.focus == 2 { app.export_definition() } else { app.lookup(true) }
			}
			0x08, 0x7f {
				match app.focus {
					0 { console_backspace(mut app.path, app.select_all) }
					1 { console_backspace(mut app.query, app.select_all); app.refilter() }
					2 { console_backspace(mut app.export_path, app.select_all) }
					else {}
				}
				app.select_all = false
			}
			else {
				if byte >= 0x20 && byte < 0x7f { app.paste_input(unsafe { tos(&byte, 1) }) }
				else if editor_utf8_length(byte) > 1 { app.pending[0] = byte; app.pending_len = 1 }
			}
		}
	}
}

fn (mut app DictionaryApp) close_app() {
	app.source.close()
	// V3's string-array free releases its elements as well as its buffer.
	unsafe { app.history.free(); app.path.free(); app.query.free(); app.key.free(); app.export_path.free()
		app.definition.free(); app.count_text.free(); app.lines.free() }
	app = DictionaryApp{}
}
