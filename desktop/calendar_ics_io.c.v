// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn calendar_ics_read(path string) (string, string) {
	if !archive_absolute_valid(path) { return '', 'calendar.ics.path_invalid' }
	parent, leaf := archive_parent(path)
	if parent < 0 { return '', 'calendar.ics.read_failed' }
	defer { desktop_close(parent) unsafe { leaf.free() } }
	fd := C.openat(parent, &char(leaf.str), C.O_RDONLY | C.O_CLOEXEC | C.O_NONBLOCK | C.O_NOFOLLOW, 0)
	if fd < 0 { return '', 'calendar.ics.read_failed' }
	defer { desktop_close(fd) }
	mut info := C.stat{}
	if unsafe { C.fstat(fd, &info) } != 0 || u32(info.st_mode) & u32(C.S_IFMT) != u32(C.S_IFREG) {
		return '', 'calendar.ics.read_failed'
	}
	if info.st_size < 0 || info.st_size > calendar_ics_max_bytes { return '', 'calendar.ics.limit' }
	mut bytes := []u8{cap: int(info.st_size) + 1}
	unsafe { bytes.flags |= .noslices }
	defer { unsafe { bytes.free() } }
	mut buffer := [4096]u8{}
	for {
		read := desktop_read(fd, unsafe { &buffer[0] }, 4096)
		if read < 0 { return '', 'calendar.ics.read_failed' }
		if read == 0 { break }
		if bytes.len + int(read) > calendar_ics_max_bytes { return '', 'calendar.ics.limit' }
		for index in 0 .. int(read) { bytes << buffer[index] }
	}
	return editor_bytes_text(bytes).clone(), ''
}

fn (mut a CalendarApp) import_ics(path string) {
	if a.events.read_failed { a.ics_status = 'calendar.event.read_failed' return }
	record, read_status := calendar_ics_read(path)
	if read_status.len > 0 { a.ics_status = read_status return }
	defer { unsafe { record.free() } }
	mut imported, parse_status := calendar_ics_parse(record)
	if parse_status.len > 0 { a.ics_status = parse_status return }
	defer { imported.free_items() }
	mut accepted := [calendar_events_limit]bool{}
	mut added := 0
	for index in 0 .. imported.count {
		mut duplicate := false
		for previous in 0 .. a.events.count {
			if calendar_ics_equal(imported.items[index], a.events.items[previous]) { duplicate = true break }
		}
		for previous in 0 .. index {
			if accepted[previous] && calendar_ics_equal(imported.items[index], imported.items[previous]) { duplicate = true break }
		}
		if !duplicate { accepted[index] = true added++ }
	}
	if a.events.count + added > calendar_events_limit { a.ics_status = 'calendar.ics.limit' return }
	if added == 0 { a.ics_status = 'calendar.ics.nothing' return }
	previous_count := a.events.count
	for index in 0 .. imported.count {
		if !accepted[index] { continue }
		// Transfer each accepted pair of strings; the temporary model still frees
		// skipped entries, and a failed save releases every transferred row.
		a.events.items[a.events.count] = imported.items[index]
		a.events.count++
		imported.items[index] = CalendarEvent{}
	}
	if !a.events.save() {
		for index in previous_count .. a.events.count {
			unsafe { a.events.items[index].title.free() a.events.items[index].location.free() }
			a.events.items[index] = CalendarEvent{}
		}
		a.events.count = previous_count
		a.ics_status = if a.events.save_conflict { 'calendar.event.changed' } else { 'calendar.event.save_failed' }
		return
	}
	a.ics_status = 'calendar.ics.imported'
	a.agenda_scroll = 0
}

fn (mut a CalendarApp) export_ics(path string) {
	if !archive_absolute_valid(path) { a.ics_status = 'calendar.ics.path_invalid' return }
	if a.events.read_failed { a.ics_status = 'calendar.event.read_failed' return }
	bytes, status := calendar_ics_encode(&a.events)
	if status.len > 0 { a.ics_status = status return }
	defer { unsafe { bytes.free() } }
	parent, leaf := archive_parent(path)
	if parent < 0 { a.ics_status = 'calendar.ics.export_failed' return }
	defer { desktop_close(parent) unsafe { leaf.free() } }
	fd := C.openat(parent, &char(leaf.str), C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_NONBLOCK | C.O_CLOEXEC, 0o600)
	if fd < 0 {
		a.ics_status = if C.errno == C.EEXIST { 'calendar.ics.export_exists' } else { 'calendar.ics.export_failed' }
		return
	}
	mut identity := C.stat{}
	identified := unsafe { C.fstat(fd, &identity) } == 0
	written := identified && desktop_write_all(fd, bytes.data, u64(bytes.len))
		&& desktop_preferences_fsync(fd) && archive_sync_parent(parent, fd)
	closed := desktop_close(fd) == 0
	if !written || !closed {
		mut current := C.stat{}
		if identified && unsafe { C.fstatat(parent, &char(leaf.str), &current, C.AT_SYMLINK_NOFOLLOW) } == 0
			&& current.st_dev == identity.st_dev && current.st_ino == identity.st_ino {
			C.unlinkat(parent, &char(leaf.str), 0)
		}
		a.ics_status = 'calendar.ics.export_failed'
		return
	}
	a.ics_status = 'calendar.ics.exported'
}

fn calendar_ics_home(home string) string {
	if home.len == 0 || home.len >= 4096 || home.index_u8(0) >= 0 { return home.clone() }
	terminated := home.clone()
	defer { unsafe { terminated.free() } }
	mut buffer := [4096]u8{}
	if unsafe { C.realpath(&char(terminated.str), &char(&buffer[0])) } == unsafe { nil } { return home.clone() }
	mut length := 0
	for length < buffer.len && buffer[length] != 0 { length++ }
	if length == buffer.len { return home.clone() }
	return unsafe { tos(&buffer[0], length).clone() }
}
