// SPDX-License-Identifier: GPL-2.0-or-later
// Strict RFC 5545 subset matching Calendar's one-day/floating-minute model.
module main

const calendar_ics_max_bytes = 131072
const calendar_ics_line_limit = 1024
const calendar_ics_path_limit = 1024

fn calendar_ics_utf8(text string) bool {
	mut at := 0
	for at < text.len {
		lead := text[at]
		length := editor_utf8_length(lead)
		if length == 0 || at + length > text.len || lead < 32 || lead == 127 { return false }
		for offset := 1; offset < length; offset++ {
			if !editor_utf8_follows(lead, offset, text[at + offset]) { return false }
		}
		at += length
	}
	return true
}

// Property/component names are ASCII and case-insensitive; compare without
// allocating normalized copies on each parsed line.
fn calendar_ics_name(text string, upper string) bool {
	if text.len != upper.len { return false }
	for index, byte in text {
		value := if byte >= `a` && byte <= `z` { byte - 32 } else { byte }
		if value != upper[index] { return false }
	}
	return true
}

fn calendar_ics_equal(left CalendarEvent, right CalendarEvent) bool {
	return left.year == right.year && left.month == right.month && left.day == right.day
		&& left.minutes == right.minutes && left.title == right.title && left.location == right.location
}

// Returns an owned decoded string only on success. Newlines cannot be stored
// in Calendar's title/location; reject them rather than flattening the text.
fn calendar_ics_text(text string, maximum int) (string, string) {
	mut bytes := []u8{cap: maximum + 1}
	unsafe { bytes.flags |= .noslices }
	defer { unsafe { bytes.free() } }
	mut at := 0
	for at < text.len {
		mut byte := text[at]
		if byte == `\\` {
			at++
			if at == text.len { return '', 'calendar.ics.invalid' }
			byte = text[at]
			if byte == `n` || byte == `N` { return '', 'calendar.ics.unsupported' }
			if byte != `\\` && byte != `,` && byte != `;` { return '', 'calendar.ics.invalid' }
		} else if byte == `,` || byte == `;` {
			return '', 'calendar.ics.invalid'
		}
		if bytes.len >= maximum { return '', 'calendar.ics.limit' }
		bytes << byte
		at++
	}
	borrowed := editor_bytes_text(bytes)
	if !calendar_ics_utf8(borrowed) { return '', 'calendar.ics.invalid' }
	return borrowed.clone(), ''
}

fn calendar_ics_date(text string, all_day bool, stamp bool) ?CalendarEvent {
	expected := if all_day { 8 } else if stamp { 16 } else { 15 }
	if text.len != expected || (!all_day && text[8] != `T`)
		|| (stamp && text[15] != `Z`) { return none }
	year := calendar_integer(calendar_borrow(text, 0, 4)) or { return none }
	month := calendar_integer(calendar_borrow(text, 4, 6)) or { return none }
	day := calendar_integer(calendar_borrow(text, 6, 8)) or { return none }
	if year < 1 || month < 1 || month > 12 || day < 1 || day > calendar_days_in_month(year, month) { return none }
	mut minutes := -1
	if !all_day {
		hour := calendar_integer(calendar_borrow(text, 9, 11)) or { return none }
		minute := calendar_integer(calendar_borrow(text, 11, 13)) or { return none }
		second := calendar_integer(calendar_borrow(text, 13, 15)) or { return none }
		if hour > 23 || minute > 59 || second > 59 || (!stamp && second != 0) { return none }
		minutes = hour * 60 + minute
	}
	return CalendarEvent{ year: year, month: month, day: day, minutes: minutes }
}

fn calendar_ics_next_day(start CalendarEvent, end CalendarEvent) bool {
	mut year := start.year
	mut month := start.month
	mut day := start.day + 1
	if day > calendar_days_in_month(year, month) { day = 1 month++ }
	if month > 12 { month = 1 year++ }
	return start.minutes < 0 && end.minutes < 0 && end.year == year && end.month == month && end.day == day
}

// All inputs are bounded before field allocation. Returned items are owned by
// the caller only on success; every failed parse releases completed/draft rows.
fn calendar_ics_parse(record string) (CalendarEvents, string) {
	mut model := CalendarEvents{}
	if record.len == 0 || record.len > calendar_ics_max_bytes {
		return CalendarEvents{}, if record.len > calendar_ics_max_bytes { 'calendar.ics.limit' } else { 'calendar.ics.invalid' }
	}
	mut line := []u8{cap: calendar_ics_line_limit}
	unsafe { line.flags |= .noslices }
	mut uids := [calendar_events_limit]string{}
	mut current := CalendarEvent{}
	mut uid := ''
	mut end_date := CalendarEvent{}
	mut properties := u32(0)
	mut headers := u32(0)
	mut stage := 0
	mut event_count := 0
	mut success := false
	defer {
		unsafe { line.free() current.title.free() current.location.free() uid.free() }
		for value in uids { unsafe { value.free() } }
		if !success { model.free_items() }
	}
	mut at := 0
	for at < record.len {
		line.clear()
		for {
			mut finish := at
			for finish < record.len && record[finish] != `\r` && record[finish] != `\n` { finish++ }
			if finish == record.len { return CalendarEvents{}, 'calendar.ics.invalid' }
			if line.len + finish - at > calendar_ics_line_limit { return CalendarEvents{}, 'calendar.ics.limit' }
			editor_append(mut line, calendar_borrow(record, at, finish))
			if record[finish] == `\r` {
				if finish + 1 >= record.len || record[finish + 1] != `\n` { return CalendarEvents{}, 'calendar.ics.invalid' }
				finish++
			}
			at = finish + 1
			if at < record.len && (record[at] == ` ` || record[at] == `\t`) { at++ } else { break }
		}
		text := editor_bytes_text(line)
		if text.len == 0 || !calendar_ics_utf8(text) { return CalendarEvents{}, 'calendar.ics.invalid' }
		colon := text.index_u8(`:`)
		if colon <= 0 { return CalendarEvents{}, 'calendar.ics.invalid' }
		name := calendar_borrow(text, 0, colon)
		value := calendar_borrow(text, colon + 1, text.len)
		if stage == 0 {
			if !calendar_ics_name(name, 'BEGIN') || !calendar_ics_name(value, 'VCALENDAR') { return CalendarEvents{}, 'calendar.ics.invalid' }
			stage = 1
			continue
		}
		if stage == 3 { return CalendarEvents{}, 'calendar.ics.invalid' }
		if calendar_ics_name(name, 'BEGIN') {
			if stage != 1 || !calendar_ics_name(value, 'VEVENT') { return CalendarEvents{}, 'calendar.ics.unsupported' }
			if headers & 3 != 3 { return CalendarEvents{}, 'calendar.ics.invalid' }
			event_count++
			if event_count > calendar_events_limit { return CalendarEvents{}, 'calendar.ics.limit' }
			stage = 2
			properties = 0
			end_date = CalendarEvent{}
			continue
		}
		if calendar_ics_name(name, 'END') {
			if stage == 1 && calendar_ics_name(value, 'VCALENDAR') {
				if headers & 3 != 3 { return CalendarEvents{}, 'calendar.ics.invalid' }
				stage = 3
				continue
			}
			if stage != 2 || !calendar_ics_name(value, 'VEVENT') || properties & 15 != 15 {
				return CalendarEvents{}, 'calendar.ics.invalid'
			}
			if properties & 32 != 0 && !calendar_ics_next_day(current, end_date) {
				return CalendarEvents{}, 'calendar.ics.unsupported'
			}
			mut duplicate := false
			for index in 0 .. model.count {
				if uids[index] == uid {
					if !calendar_ics_equal(model.items[index], current) { return CalendarEvents{}, 'calendar.ics.duplicate' }
					duplicate = true
					break
				}
			}
			if duplicate {
				unsafe { current.title.free() current.location.free() uid.free() }
			} else {
				model.items[model.count] = current
				uids[model.count] = uid
				model.count++
			}
			current = CalendarEvent{}
			uid = ''
			stage = 1
			continue
		}
		if stage == 1 {
			mut bit := u32(0)
			if calendar_ics_name(name, 'VERSION') && value == '2.0' { bit = 1 }
			else if calendar_ics_name(name, 'PRODID') && value.len > 0 {
				decoded, status := calendar_ics_text(value, calendar_ics_line_limit)
				if status.len > 0 { return CalendarEvents{}, status }
				unsafe { decoded.free() }
				bit = 2
			}
			else if calendar_ics_name(name, 'CALSCALE') && calendar_ics_name(value, 'GREGORIAN') { bit = 4 }
			else { return CalendarEvents{}, 'calendar.ics.unsupported' }
			if headers & bit != 0 || event_count > 0 { return CalendarEvents{}, 'calendar.ics.invalid' }
			headers |= bit
			continue
		}
		mut bit := u32(0)
		if calendar_ics_name(name, 'UID') { bit = 1 }
		else if calendar_ics_name(name, 'DTSTAMP') { bit = 2 }
		else if calendar_ics_name(name, 'DTSTART') || calendar_ics_name(name, 'DTSTART;VALUE=DATE') || calendar_ics_name(name, 'DTSTART;VALUE=DATE-TIME') { bit = 4 }
		else if calendar_ics_name(name, 'SUMMARY') { bit = 8 }
		else if calendar_ics_name(name, 'LOCATION') { bit = 16 }
		else if calendar_ics_name(name, 'DTEND;VALUE=DATE') { bit = 32 }
		else { return CalendarEvents{}, 'calendar.ics.unsupported' }
		if properties & bit != 0 { return CalendarEvents{}, 'calendar.ics.invalid' }
		properties |= bit
		match bit {
			1 {
				decoded, status := calendar_ics_text(value, 256)
				if status.len > 0 { return CalendarEvents{}, status }
				uid = decoded
				if uid.len == 0 { return CalendarEvents{}, 'calendar.ics.invalid' }
			}
			2 { calendar_ics_date(value, false, true) or { return CalendarEvents{}, 'calendar.ics.invalid' } }
			4 {
				all_day := calendar_ics_name(name, 'DTSTART;VALUE=DATE')
				if !all_day && (value.len == 16 || (value.len == 15 && !value.ends_with('00'))) {
					return CalendarEvents{}, 'calendar.ics.unsupported'
				}
				date := calendar_ics_date(value, all_day, false) or { return CalendarEvents{}, 'calendar.ics.invalid' }
				current.year = date.year current.month = date.month current.day = date.day current.minutes = date.minutes
			}
			8, 16 {
				decoded, status := calendar_ics_text(value, if bit == 8 { calendar_event_title_limit } else { calendar_event_location_limit })
				if status.len > 0 { return CalendarEvents{}, status }
				if bit == 8 {
					current.title = decoded
					if decoded.len == 0 { return CalendarEvents{}, 'calendar.ics.invalid' }
				} else { current.location = decoded }
			}
			32 { end_date = calendar_ics_date(value, true, false) or { return CalendarEvents{}, 'calendar.ics.invalid' } }
			else {}
		}
	}
	if stage != 3 { return CalendarEvents{}, 'calendar.ics.invalid' }
	success = true
	return model, ''
}

// Append one escaped UTF-8 logical line, folding before character boundaries.
fn calendar_ics_line(mut bytes []u8, prefix string, text string, escape bool) {
	editor_append(mut bytes, prefix)
	mut column := prefix.len
	mut at := 0
	for at < text.len {
		length := editor_utf8_length(text[at])
		extra := if escape && text[at] in [`\\`, `,`, `;`]! { 1 } else { 0 }
		if column + length + extra > 75 {
			editor_append(mut bytes, '\r\n ')
			column = 1
		}
		if extra > 0 { bytes << `\\` }
		editor_append(mut bytes, calendar_borrow(text, at, at + length))
		column += length + extra
		at += length
	}
	editor_append(mut bytes, '\r\n')
}

fn calendar_ics_date_text(event CalendarEvent, seconds int, utc bool) string {
	mut buffer := [32]u8{}
	length := unsafe {
		if event.minutes < 0 {
			C.snprintf(&char(&buffer[0]), 32, c'%04d%02d%02d', event.year, event.month, event.day)
		} else {
			C.snprintf(&char(&buffer[0]), 32, c'%04d%02d%02dT%02d%02d%02d%s', event.year, event.month,
				event.day, event.minutes / 60, event.minutes % 60, seconds, if utc { c'Z' } else { c'' })
		}
	}
	return unsafe { tos(&buffer[0], length).clone() }
}

fn calendar_ics_uid(random_fd int) ?string {
	mut random := [16]u8{}
	mut offset := 0
	for offset < 16 {
		read := desktop_read(random_fd, unsafe { &random[offset] }, u64(16 - offset))
		if read <= 0 { return none }
		offset += int(read)
	}
	random[6] = (random[6] & 15) | 64
	random[8] = (random[8] & 63) | 128
	mut text := [44]u8{}
	const_hex := '0123456789abcdef'
	mut at := 0
	for index, byte in random {
		if index in [4, 6, 8, 10]! { text[at] = `-` at++ }
		text[at] = const_hex[int(byte >> 4)] text[at + 1] = const_hex[int(byte & 15)] at += 2
	}
	return unsafe { tos(&text[0], at).clone() }
}

fn calendar_ics_encode(model &CalendarEvents) ([]u8, string) {
	if model.count < 0 || model.count > calendar_events_limit { return []u8{}, 'calendar.ics.limit' }
	mut bytes := []u8{cap: 65536}
	unsafe { bytes.flags |= .noslices }
	mut success := false
	defer { if !success { unsafe { bytes.free() } } }
	seconds, _ := desktop_realtime()
	if seconds < 0 { return []u8{}, 'calendar.ics.export_failed' }
	civil := civil_from_epoch(seconds)
	if civil.year < 1 || civil.year > 9999 { return []u8{}, 'calendar.ics.export_failed' }
	stamp := calendar_ics_date_text(CalendarEvent{ year: civil.year, month: civil.month, day: civil.day,
		minutes: civil.hour * 60 + civil.minute }, civil.second, true)
	defer { unsafe { stamp.free() } }
	fd := C.open(c'/dev/urandom', C.O_RDONLY | C.O_CLOEXEC | C.O_NONBLOCK, 0)
	if fd < 0 { return []u8{}, 'calendar.ics.export_failed' }
	defer { desktop_close(fd) }
	editor_append(mut bytes, 'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Vinix//Calendar 1.0//EN\r\nCALSCALE:GREGORIAN\r\n')
	for index in 0 .. model.count {
		event := model.items[index]
		if event.year < 1 || event.year > 9999 || event.month < 1 || event.month > 12
			|| event.day < 1 || event.day > calendar_days_in_month(event.year, event.month)
			|| event.minutes < -1 || event.minutes >= 1440
			|| event.title.len == 0 || event.title.len > calendar_event_title_limit || event.location.len > calendar_event_location_limit
			|| !calendar_ics_utf8(event.title) || !calendar_ics_utf8(event.location) {
			return []u8{}, 'calendar.ics.invalid'
		}
		uid := calendar_ics_uid(fd) or { return []u8{}, 'calendar.ics.export_failed' }
		start := calendar_ics_date_text(event, 0, false)
		editor_append(mut bytes, 'BEGIN:VEVENT\r\n')
		calendar_ics_line(mut bytes, 'UID:', uid, false)
		calendar_ics_line(mut bytes, 'DTSTAMP:', stamp, false)
		calendar_ics_line(mut bytes, if event.minutes < 0 { 'DTSTART;VALUE=DATE:' } else { 'DTSTART:' }, start, false)
		calendar_ics_line(mut bytes, 'SUMMARY:', event.title, true)
		if event.location.len > 0 { calendar_ics_line(mut bytes, 'LOCATION:', event.location, true) }
		editor_append(mut bytes, 'END:VEVENT\r\n')
		unsafe { uid.free() start.free() }
	}
	editor_append(mut bytes, 'END:VCALENDAR\r\n')
	success = true
	return bytes, ''
}
