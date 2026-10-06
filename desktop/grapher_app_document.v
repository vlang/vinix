// SPDX-License-Identifier: GPL-2.0-or-later
// Versioned graph records contain only the five validated editable fields.
module main

const grapher_document_header = 'VINIX-GRAPH 1\n'
const grapher_document_keys = ['expression=', 'xmin=', 'xmax=', 'ymin=', 'ymax=']!
const grapher_document_limit = 1024

struct GrapherDocument {
	// Borrowed from the read buffer until open_graph_document finishes copying.
	fields [5]string
}

fn grapher_document_field_valid(index int, text string) bool {
	limit := if index == 0 { grapher_expression_limit } else { 64 }
	if text.len == 0 || text.len > limit { return false }
	for ch in text { if ch < 32 || ch >= 127 { return false } }
	return true
}

fn grapher_document_values_valid(fields [5]string) bool {
	for index, text in fields {
		if !grapher_document_field_valid(index, text) { return false }
	}
	grapher_parse(fields[0]) or { return false }
	mut range := [4]f64{}
	for index in 0 .. 4 {
		range[index] = grapher_constant(fields[index + 1]) or { return false }
	}
	return grapher_range_valid(range[0], range[1]) && grapher_range_valid(range[2], range[3])
}

fn grapher_document_parse(data string) ?GrapherDocument {
	if data.len > grapher_document_limit || !data.starts_with(grapher_document_header) { return none }
	mut fields := [5]string{}
	mut at := grapher_document_header.len
	for index, key in grapher_document_keys {
		if data.len - at < key.len { return none }
		for offset, ch in key { if data[at + offset] != ch { return none } }
		at += key.len
		start := at
		for at < data.len && data[at] != `\n` { at++ }
		if at == data.len { return none }
		fields[index] = unsafe { tos(data.str + start, at - start) }
		if !grapher_document_field_valid(index, fields[index]) { return none }
		at++
	}
	if at != data.len || !grapher_document_values_valid(fields) { return none }
	return GrapherDocument{ fields: fields }
}

fn (app &GrapherApp) graph_document_values() [5]string {
	mut fields := [5]string{}
	for index in 0 .. fields.len { fields[index] = app.field_text(index) }
	return fields
}

fn grapher_document_bytes(fields [5]string) []u8 {
	mut bytes := []u8{cap: grapher_document_limit}
	unsafe { bytes.flags |= .noslices }
	disk_usage_append(mut bytes, grapher_document_header)
	for index, key in grapher_document_keys {
		disk_usage_append(mut bytes, key)
		disk_usage_append(mut bytes, fields[index])
		bytes << `\n`
	}
	return bytes
}

fn grapher_document_path_valid(path string) bool {
	return path.len <= grapher_field_limit && grapher_valid_utf8(path) && archive_absolute_valid(path)
}

fn (mut app GrapherApp) open_graph_document() {
	app.export_status = ''
	path := app.field_text(6)
	if !grapher_document_path_valid(path) {
		app.document_status = 'grapher.document_invalid_path'
		return
	}
	fd := archive_open_source(path)
	if fd < 0 {
		app.document_status = 'grapher.document_open_failed'
		return
	}
	defer { desktop_close(fd) }
	mut info := C.stat{}
	if unsafe { C.fstat(fd, &info) } != 0 || u32(info.st_mode) & u32(C.S_IFMT) != u32(C.S_IFREG) {
		app.document_status = 'grapher.document_open_failed'
		return
	}
	app.document_status = 'grapher.document_invalid'
	if info.st_size <= 0 || info.st_size > grapher_document_limit { return }
	mut bytes := []u8{len: int(info.st_size)}
	defer { unsafe { bytes.free() } }
	mut at := 0
	mut interruptions := 0
	for at < bytes.len {
		n := desktop_read(fd, unsafe { &u8(bytes.data) + at }, u64(bytes.len - at))
		if n < 0 && C.errno == C.EINTR && interruptions < 8 {
			interruptions++
			continue
		}
		if n <= 0 { return }
		at += int(n)
	}
	mut extra := u8(0)
	if desktop_read(fd, unsafe { &extra }, 1) != 0 { return }
	mut after := C.stat{}
	if unsafe { C.fstat(fd, &after) } != 0 || after.st_size != info.st_size || after.st_mtime != info.st_mtime
		|| unsafe { C.vinix_archive_mtime_nsec(&after) } != unsafe { C.vinix_archive_mtime_nsec(&info) } { return }
	document := grapher_document_parse(editor_bytes_text(bytes)) or { return }
	// No model state changes until every record and all math fields validate.
	for index, text in document.fields { app.set_field(index, text) }
	app.plot()
	app.document_status = 'grapher.document_opened'
	app.pending_length = 0
}

fn (mut app GrapherApp) save_graph_document() {
	app.export_status = ''
	path := app.field_text(6)
	if !grapher_document_path_valid(path) {
		app.document_status = 'grapher.document_invalid_path'
		return
	}
	fields := app.graph_document_values()
	if !grapher_document_values_valid(fields) {
		app.document_status = 'grapher.document_invalid'
		return
	}
	parent, leaf := archive_parent(path)
	if parent < 0 {
		app.document_status = 'grapher.document_save_failed'
		return
	}
	defer {
		desktop_close(parent)
		unsafe { leaf.free() }
	}
	fd := C.openat(parent, &char(leaf.str), C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC | C.O_NONBLOCK, 0o600)
	if fd < 0 {
		app.document_status = if C.errno == C.EEXIST {
			'grapher.document_exists'
		} else {
			'grapher.document_save_failed'
		}
		return
	}
	mut identity := C.stat{}
	identified := unsafe { C.fstat(fd, &identity) } == 0
	bytes := grapher_document_bytes(fields)
	written := identified && desktop_write_all(fd, bytes.data, u64(bytes.len)) && desktop_preferences_fsync(fd) && archive_sync_parent(parent, fd)
	unsafe { bytes.free() }
	closed := desktop_close(fd) == 0
	if !written || !closed {
		mut current := C.stat{}
		// Preserve a concurrently replaced name; remove only our failed creation.
		if identified && unsafe { C.fstatat(parent, &char(leaf.str), &current, C.AT_SYMLINK_NOFOLLOW) } == 0
			&& current.st_dev == identity.st_dev && current.st_ino == identity.st_ino {
			C.unlinkat(parent, &char(leaf.str), 0)
		}
		app.document_status = 'grapher.document_save_failed'
		return
	}
	app.document_status = 'grapher.document_saved'
}
