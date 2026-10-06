// SPDX-License-Identifier: GPL-2.0-or-later
// One bounded UTF-8 text file becomes one new note. Source descriptors never
// follow links; publication includes the current draft atomically.
module main

const notes_import_raw_limit = notes_body_limit * 2 + 3

fn notes_import_normalize(raw []u8) (string, string) {
	mut at := if raw.len >= 3 && raw[0] == 0xef && raw[1] == 0xbb && raw[2] == 0xbf { 3 } else { 0 }
	mut text := []u8{cap: if raw.len < notes_body_limit { raw.len } else { notes_body_limit }}
	unsafe { text.flags |= .noslices }
	defer { unsafe { text.free() } }
	for at < raw.len {
		if text.len == notes_body_limit { return '', 'notes.limit' }
		if raw[at] == `\r` {
			text << `\n`
			if at + 1 < raw.len && raw[at + 1] == `\n` { at++ }
		} else {
			text << raw[at]
		}
		at++
	}
	borrowed := editor_bytes_text(text)
	if !notes_valid_text(borrowed, notes_body_limit, true) { return '', 'notes.invalid_text' }
	return borrowed.clone(), ''
}

// The basename is the title; strip a nonempty .txt extension and truncate
// only at a UTF-8 boundary. Empty text files still produce a titled note.
fn notes_import_title(path string) string {
	mut start := path.len
	for start > 0 && path[start - 1] != `/` { start-- }
	mut end := path.len
	if end - start > 4 && path[end - 4] == `.` && (path[end - 3] | 0x20) == `t`
		&& (path[end - 2] | 0x20) == `x` && (path[end - 1] | 0x20) == `t` { end -= 4 }
	mut at := start
	for at < end {
		length := editor_utf8_length(path[at])
		if length == 0 || at + length > end || at + length - start > notes_title_limit { break }
		at += length
	}
	return console_borrow(path, start, at).clone()
}

fn notes_import_read_at(directory int, name string) (string, string) {
	fd := C.openat(directory, &char(name.str), C.O_RDONLY | C.O_NOFOLLOW | C.O_NONBLOCK | C.O_CLOEXEC, 0)
	if fd < 0 { return '', 'notes.import_failed' }
	defer { desktop_close(fd) }
	mut before := C.stat{}
	if unsafe { C.fstat(fd, &before) } != 0 || u32(before.st_mode) & u32(C.S_IFMT) != u32(C.S_IFREG)
		|| before.st_size < 0 { return '', 'notes.import_failed' }
	if before.st_size > notes_import_raw_limit { return '', 'notes.limit' }
	mut raw := []u8{len: int(before.st_size)}
	defer { unsafe { raw.free() } }
	mut read := 0
	mut attempts := 0
	for read < raw.len {
		n := desktop_read(fd, unsafe { &u8(raw.data) + read }, u64(raw.len - read))
		if n <= 0 {
			if n < 0 && C.errno == C.EINTR && attempts < 8 { attempts++ continue }
			return '', 'notes.import_failed'
		}
		read += int(n)
	}
	mut extra := u8(0)
	if desktop_read(fd, unsafe { &extra }, 1) != 0 { return '', 'notes.import_failed' }
	mut after := C.stat{}
	if unsafe { C.fstat(fd, &after) } != 0 || after.st_dev != before.st_dev
		|| after.st_ino != before.st_ino || after.st_size != before.st_size
		|| after.st_mtime != before.st_mtime
		|| unsafe { C.vinix_backup_mtime_nsec(&after) } != unsafe { C.vinix_backup_mtime_nsec(&before) } {
		return '', 'notes.import_failed'
	}
	return notes_import_normalize(raw)
}

fn (a &NotesApp) read_import(path string) (string, string) {
	if path.len > 512 || !backup_valid_path(path) || !notes_valid_text(path, 512, false) {
		return '', 'notes.import_invalid'
	}
	mut separator := path.len - 1
	for separator > 0 && path[separator] != `/` { separator-- }
	parent := if separator == 0 { '/' } else { console_borrow(path, 0, separator) }
	name := console_borrow(path, separator + 1, path.len).clone()
	defer { unsafe { name.free() } }
	mut home_end := a.default_export.len - 1
	for home_end > 0 && a.default_export[home_end] != `/` { home_end-- }
	home_parent := if home_end == 0 { '/' } else { console_borrow(a.default_export, 0, home_end) }
	// Like personal export, files directly in registered HOME use the anchored
	// descriptor. Every other entered path refuses links in all its parents.
	if parent == home_parent && a.home_fd >= 0 { return notes_import_read_at(a.home_fd, name) }
	directory := if parent == '/' {
		C.open(c'/', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW, 0)
	} else { backup_open_directory(parent) }
	if directory < 0 { return '', 'notes.import_failed' }
	defer { desktop_close(directory) }
	return notes_import_read_at(directory, name)
}

fn (mut a NotesApp) open_import() {
	if a.close_requested { return }
	if !a.importing { a.import_focus = a.focus }
	a.importing = true
	a.import_status = ''
	a.focus_field(4)
}

fn (mut a NotesApp) cancel_import() {
	a.importing = false
	a.import_status = ''
	a.focus_field(if a.import_focus >= 0 && a.import_focus <= 3 { a.import_focus } else { 2 })
}

fn (mut a NotesApp) import_note() {
	path := editor_bytes_text(a.import_path)
	body, read_status := a.read_import(path)
	defer { unsafe { body.free() } }
	if read_status.len > 0 { a.import_status = read_status return }
	if a.read_failed { a.import_status = 'notes.corrupt' return }
	if a.count >= notes_limit || a.next_id == ~u64(0) { a.import_status = 'notes.limit' return }
	if a.selected >= 0 && a.title.len == 0 { a.import_status = 'notes.title_required' return }
	title := notes_import_title(path)
	defer { unsafe { title.free() } }
	if title.len == 0 { a.import_status = 'notes.import_invalid' return }
	data := a.encode_added(-1, title, body)
	defer { unsafe { data.free() } }
	if data.len > notes_record_limit { a.import_status = 'notes.limit' return }
	state := notes_publish(a.home_fd, a.record, data)
	if state < 0 {
		a.import_status = if state == -2 { 'notes.conflict' } else { 'notes.save_failed' }
		return
	}
	if a.selected >= 0 {
		unsafe { a.items[a.selected].title.free() a.items[a.selected].body.free() }
		a.items[a.selected].title = editor_bytes_text(a.title).clone()
		a.items[a.selected].body = editor_bytes_text(a.body).clone()
	}
	unsafe { a.record.free() }
	a.record = data.clone()
	a.items[a.count] = NotesEntry{ id: a.next_id, title: title.clone(), body: body.clone() }
	a.next_id++
	a.count++
	a.dirty = false
	a.reset_close_choice()
	a.load_selected(a.count - 1)
	a.query.clear()
	a.list_scroll = 0
	a.refilter()
	a.importing = false
	a.import_status = ''
	a.export_status = ''
	a.focus_field(2)
	a.status = if state == 1 { 'notes.import_durability' } else { 'notes.import_saved' }
}
