// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

// Search borrows title/location text and stores only inline indices. Tokens
// may match different fields; accents and Latin/Cyrillic case use the same
// allocation-free folding as the desktop launcher.
fn (a &CalendarApp) search_text() string {
	return if a.search_len == 0 { '' } else { unsafe { tos(&a.search[0], a.search_len) } }
}

fn calendar_search_matches(event CalendarEvent, query string) bool {
	mut at := 0
	for at < query.len {
		for at < query.len && query[at] == ` ` { at++ }
		start := at
		for at < query.len && query[at] != ` ` { at++ }
		if start == at { continue }
		token := calendar_borrow(query, start, at)
		if !start_menu_matches(event.title, token) && !start_menu_matches(event.location, token) {
			return false
		}
	}
	return true
}

fn calendar_search_before(left CalendarEvent, right CalendarEvent) bool {
	if left.year != right.year { return left.year < right.year }
	if left.month != right.month { return left.month < right.month }
	if left.day != right.day { return left.day < right.day }
	return left.minutes < right.minutes
}

fn calendar_search_date(event CalendarEvent) string {
	year := event.year.str()
	month := pad2(event.month)
	day := pad2(event.day)
	result := '${year}-${month}-${day}'
	unsafe { year.free() month.free() day.free() }
	return result
}

fn (mut a CalendarApp) refilter_search(reset bool) {
	a.search_count = 0
	for index in 0 .. a.events.count {
		event := a.events.items[index]
		if !calendar_search_matches(event, a.search_text()) { continue }
		mut at := a.search_count
		for at > 0 && calendar_search_before(event, a.events.items[a.search_indices[at - 1]]) {
			a.search_indices[at] = a.search_indices[at - 1]
			at--
		}
		a.search_indices[at] = index
		a.search_count++
	}
	if reset { a.search_scroll = 0 }
	a.clamp_search_scroll()
}

fn (mut a CalendarApp) clamp_search_scroll() {
	page := if a.search_visible > 0 { a.search_visible } else { 1 }
	maximum := if a.search_count > 0 { (a.search_count - 1) / page * page } else { 0 }
	if a.search_scroll < 0 { a.search_scroll = 0 }
	if a.search_scroll > maximum { a.search_scroll = maximum }
	// Resizing can change the number of rows on a page.
	a.search_scroll = a.search_scroll / page * page
}

fn (mut a CalendarApp) focus_search(selected bool) {
	a.search_active = true
	a.search_focus = true
	a.search_selected = selected
	a.search_pending_len = 0
	a.search_escape_len = 0
	a.refilter_search(false)
}

fn (mut a CalendarApp) clear_search() {
	a.search_len = 0
	a.search_active = false
	a.search_focus = false
	a.search_selected = false
	a.search_pending_len = 0
	a.search_escape_len = 0
	a.search_scroll = 0
}

fn (mut a CalendarApp) append_search(text string) {
	length := if a.search_selected { 0 } else { a.search_len }
	if length + text.len > a.search.len { return }
	a.search_len = length
	a.search_selected = false
	for byte in text { a.search[a.search_len] = byte a.search_len++ }
	a.refilter_search(true)
}

fn (mut a CalendarApp) search_byte(byte u8) {
	if a.search_pending_len > 0 {
		if editor_utf8_follows(a.search_pending[0], a.search_pending_len, byte) {
			a.search_pending[a.search_pending_len] = byte
			a.search_pending_len++
			if a.search_pending_len == editor_utf8_length(a.search_pending[0]) {
				a.append_search(unsafe { tos(&a.search_pending[0], a.search_pending_len) })
				a.search_pending_len = 0
			}
			return
		}
		a.search_pending_len = 0
	}
	if byte == 8 || byte == 127 {
		if a.search_selected { a.search_len = 0 a.search_selected = false }
		else {
			mut from := a.search_len - 1
			for from > 0 && a.search[from] & 0xc0 == 0x80 { from-- }
			if from >= 0 { a.search_len = from }
		}
		a.refilter_search(true)
	} else if byte >= 32 && byte < 127 {
		a.append_search(unsafe { tos(&byte, 1) })
	} else if editor_utf8_length(byte) > 1 {
		a.search_pending[0] = byte
		a.search_pending_len = 1
	}
}

fn (mut a CalendarApp) paste_search(text string) {
	if !a.search_focus { return }
	a.search_pending_len = 0
	// A rejected paste leaves the selected query intact. Normalize line breaks
	// to token separators and append only complete, validated UTF-8 runes.
	mut bytes := [128]u8{}
	mut length := 0
	mut at := 0
	for at < text.len {
		byte := text[at]
		if byte < 32 || byte == 127 {
			if byte == `\n` || byte == `\r` || byte == `\t` {
				if length == bytes.len { return }
				bytes[length] = ` `
				length++
			}
			at++
			continue
		}
		size := editor_utf8_length(byte)
		if size == 0 { at++ continue }
		if at + size > text.len { break }
		mut valid := true
		for next in 1 .. size {
			if !editor_utf8_follows(byte, next, text[at + next]) { valid = false break }
		}
		if !valid { at++ continue }
		if length + size > bytes.len { return }
		for next in 0 .. size { bytes[length] = text[at + next] length++ }
		at += size
	}
	if length > 0 { a.append_search(unsafe { tos(&bytes[0], length) }) }
}

// Retain fragmented terminal CSI/SS3 sequences across IPC messages. Neither
// their suffixes nor paste controls can become query text or editor commands.
fn (mut a CalendarApp) search_escape_byte(byte u8) bool {
	if a.search_escape_len == 0 { return false }
	if a.search_escape_len == 1 && byte != `[` && byte != `O` {
		a.expire_search_escape(~u64(0))
		return false
	}
	if a.search_escape_len == a.search_escape.len {
		if byte >= 0x40 && byte <= 0x7e { a.search_escape_len = 0 }
		return true
	}
	a.search_escape[a.search_escape_len] = byte
	a.search_escape_len++
	if a.search_escape_len > 2 && byte >= 0x40 && byte <= 0x7e {
		sequence := unsafe { tos(&a.search_escape[0], a.search_escape_len) }
		match sequence {
			'\x1b[5~', '\x1b[A', '\x1bOA' { a.search_scroll -= a.search_visible }
			'\x1b[6~', '\x1b[B', '\x1bOB' { a.search_scroll += a.search_visible }
			'\x1b[H', '\x1b[1~', '\x1bOH' { a.search_scroll = 0 }
			'\x1b[F', '\x1b[4~', '\x1bOF' { a.search_scroll = calendar_events_limit }
			else {}
		}
		a.clamp_search_scroll()
		a.search_escape_len = 0
	}
	return true
}

fn (mut a CalendarApp) expire_search_escape(now u64) bool {
	if a.search_escape_len == 0 || (now != ~u64(0) && now >= a.search_escape_ms
		&& now - a.search_escape_ms < 100) { return false }
	changed := a.search_escape_len == 1 && a.search_active
	if a.search_escape_len == 1 { a.clear_search() }
	a.search_escape_len = 0
	return changed
}

fn (mut a CalendarApp) search_key_input(input string) {
	a.expire_search_escape(desktop_monotonic_ms())
	for byte in input {
		if a.search_escape_byte(byte) { continue }
		if byte == 0x1b {
			a.search_pending_len = 0
			a.search_escape[0] = byte
			a.search_escape_len = 1
			a.search_escape_ms = desktop_monotonic_ms()
			continue
		}
		if byte == 6 { a.focus_search(true) continue }
		if !a.search_focus { continue }
		if byte == 1 {
			a.search_pending_len = 0
			a.search_selected = true
		} else if byte < 32 && byte != 8 {
			a.search_pending_len = 0
		} else {
			a.search_byte(byte)
		}
	}
}

fn (mut a CalendarApp) poll() bool { return a.expire_search_escape(desktop_monotonic_ms()) }

fn (a &CalendarApp) next_poll_ms() u64 {
	return if a.search_escape_len > 0 { u64(100) } else { u64(2000) }
}

fn (a &CalendarApp) append_search_field(mut children []ui2.Element, width int) {
	text := a.search_text()
	mut characters := 0
	for byte in text { if byte & 0xc0 != 0x80 { characters++ } }
	children << ui2.label('calendar.search.label', tr('calendar.search.label'), ui2.rect(18, 52, 72, 28), ui2.TextStyle{color: body_muted, size: 12})
	children << ui2.Element{
		...ui2.text_field('calendar.search', '', text, ui2.rect(98, 52, f64(width - 236), 28),
			ui2.BoxStyle{bg: calendar_button, radius: 5}, ui2.TextStyle{color: body_text, size: 12}, 0)
		focused: a.search_focus
		text_selection: ui2.TextSelection{anchor: if a.search_focus && a.search_selected { 0 } else { characters }, caret: characters}
		tooltip: tr('calendar.search.hint')
	}
	children << calendar_event_button('calendar.search.clear', tr('calendar.search.clear'), width - 130, 52, 112, false)
}

fn (a &CalendarApp) build_small_calendar(width int, height int) ui2.Element {
	mut children := frame_elements(20)
	children << ui2.label('', if a.search_active { tr('calendar.search.title') } else { a.month_title },
		ui2.rect(18, 8, f64(width - 36), 24), ui2.TextStyle{color: body_heading, size: 13, bold: true})
	if a.search_active {
		children << calendar_event_button('calendar.search.back', tr('calendar.search.back'), 18, 42, width - 36, false)
	} else {
		children << calendar_event_button(calendar_action_previous, '<', 18, 42, 32, false)
		children << calendar_event_button('calendar.search', tr('calendar.search.label'), 58, 42, width - 116, false)
		children << calendar_event_button(calendar_action_next, '>', width - 50, 42, 32, false)
	}
	if height >= 122 {
		calendar_ics_explanation(mut children, 'calendar.search.enlarge', tr('calendar.search.enlarge'), width - 36, 82, 13, (height - 90) / 13)
	}
	return ui2.screen(app_surface, children)
}

fn (mut a CalendarApp) build_search(width int, height int) ui2.Element {
	// The full store can change through editing, deletion or ICS import. Rebuild
	// the inline index before every results frame so no deleted row is retained.
	a.search_visible = if height >= 210 { (height - 150) / 60 } else { 1 }
	a.refilter_search(false)
	mut children := frame_elements(8 + a.search_visible * 5)
	children << ui2.label('', tr('calendar.search.title'), ui2.rect(18, 12, f64(width - 166), 28), ui2.TextStyle{color: body_heading, size: 18, bold: true})
	children << calendar_event_button('calendar.search.back', tr('calendar.search.back'), width - 130, 12, 112, false)
	a.append_search_field(mut children, width)
	count := tr_count('calendar.search.count', i64(a.search_count))
	children << ui2.label(frame_owned_text_id, count, ui2.rect(18, 90, f64(width - 36), 24), ui2.TextStyle{color: body_muted, size: 12})
	if a.search_count == 0 {
		children << ui2.label('', tr(if a.events.read_failed { 'calendar.event.read_failed' } else { 'calendar.search.empty' }),
			ui2.rect(18, 128, f64(width - 36), 40), ui2.TextStyle{color: body_muted, size: 12})
	}
	for row := 0; row < a.search_visible && row + a.search_scroll < a.search_count; row++ {
		index := a.search_indices[row + a.search_scroll]
		event := a.events.items[index]
		y := 120 + row * 60
		date := calendar_search_date(event)
		time := calendar_event_time(event.minutes)
		children << ui2.label(frame_owned_text_id, date, ui2.rect(18, f64(y), 154, 22), ui2.TextStyle{color: body_muted, size: 11})
		children << ui2.label(frame_owned_text_id, time, ui2.rect(180, f64(y), f64(width - 198), 22), ui2.TextStyle{color: body_muted, size: 11})
		children << ui2.button(a.events.actions[index], event.title, ui2.rect(18, f64(y + 22), f64(width - 36), 22), ui2.BoxStyle{transparent: true}, ui2.TextStyle{color: body_text, size: 12})
		children << ui2.label('', event.location, ui2.rect(18, f64(y + 42), f64(width - 36), 16), ui2.TextStyle{color: body_muted, size: 10})
	}
	if a.search_count > a.search_visible {
		page := (a.search_scroll / a.search_visible + 1).str()
		pages := ((a.search_count - 1) / a.search_visible + 1).str()
		label := tr_fill2('calendar.search.page', page, pages)
		unsafe { page.free() pages.free() }
		footer := height - if height < 216 { 28 } else { 36 }
		children << calendar_event_button('calendar.search.previous', '<', 18, footer, 32, false)
		children << calendar_event_button('calendar.search.next', '>', 58, footer, 32, false)
		children << ui2.label(frame_owned_text_id, label, ui2.rect(102, f64(footer), f64(width - 120), 28), ui2.TextStyle{color: body_muted, size: 11})
	}
	return ui2.screen(app_surface, children)
}
