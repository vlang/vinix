// SPDX-License-Identifier: GPL-2.0-or-later
// A native TAR utility. Payload work is limited to one 64 KiB chunk per poll.
module main

enum ArchiveOperation {
	idle
	loading
	extracting
	creating
}

struct ArchiveApp {
mut:
	archive_input       []u8
	extract_input       []u8
	source_input        []u8
	output_input        []u8
	data                []u8
	entries             []ArchiveEntry
	loaded_path         string
	status_key          string = 'archive.hint'
	progress_text       string
	operation           ArchiveOperation
	read_fd             int = -1
	root_fd             int = -1
	write_fd            int = -1
	output_parent       int = -1
	output_leaf         string
	output_inode        u64
	output_device       u64
	operation_path      string
	buffer              []u8
	index               int
	entry_written       u64
	done                u64
	goal                u64
	data_size           u64
	snapshot_inode      u64
	snapshot_device     u64
	snapshot_mtime      i64
	snapshot_mtime_nsec i64
	focus               int = -1
	select_all          bool
	pending             [4]u8
	pending_len         int
	scroll              int
	page_rows           int = 10
}

fn archive_size_text(size u64) string {
	number := size.str()
	result := '${number} B'
	unsafe { number.free() }
	return result
}

fn new_archive_app() ArchiveApp {
	mut app := ArchiveApp{
		archive_input: []u8{cap: archive_path_limit}
		extract_input: []u8{cap: archive_path_limit}
		source_input:  []u8{cap: archive_path_limit}
		output_input:  []u8{cap: archive_path_limit}
		entries:       []ArchiveEntry{cap: 128}
		buffer:        []u8{len: archive_chunk}
	}
	unsafe {
		app.archive_input.flags |= .noslices
		app.extract_input.flags |= .noslices
		app.source_input.flags |= .noslices
		app.output_input.flags |= .noslices
		app.entries.flags |= .noslices
	}
	return app
}

fn open_archive_app(mut desktop Desktop) !NativeApp {
	_ = desktop.tz_offset_seconds
	app := new_archive_app()
	return &app
}

fn (mut a ArchiveApp) set_progress() {
	done := (a.done / 1024).str()
	goal := (a.goal / 1024).str()
	unsafe { a.progress_text.free() }
	a.progress_text = '${done} / ${goal} KiB'
	unsafe {
		done.free()
		goal.free()
	}
}

fn (mut a ArchiveApp) release_operation() {
	if a.read_fd >= 0 { desktop_close(a.read_fd) }
	if a.root_fd >= 0 { desktop_close(a.root_fd) }
	if a.write_fd >= 0 { desktop_close(a.write_fd) }
	if a.output_parent >= 0 { desktop_close(a.output_parent) }
	a.read_fd = -1
	a.root_fd = -1
	a.write_fd = -1
	a.output_parent = -1
	a.output_inode = 0
	a.output_device = 0
	unsafe {
		a.output_leaf.free()
		a.operation_path.free()
	}
	a.output_leaf = ''
	a.operation_path = ''
	a.operation = .idle
	a.entry_written = 0
	a.focus = -1
}

fn (mut a ArchiveApp) remove_partial_tar() {
	if a.output_parent < 0 || a.output_leaf.len == 0 { return }
	mut named := C.stat{}
	if unsafe { C.fstatat(a.output_parent, &char(a.output_leaf.str), &named, C.AT_SYMLINK_NOFOLLOW) } == 0
		&& u64(named.st_ino) == a.output_inode && u64(named.st_dev) == a.output_device {
		C.unlinkat(a.output_parent, &char(a.output_leaf.str), 0)
	}
}

fn (mut a ArchiveApp) fail_operation(key string) {
	if a.operation == .creating { a.remove_partial_tar() }
	if a.operation == .loading {
		unsafe { a.data.free() }
		a.data = []u8{}
		archive_free_entries(mut a.entries)
	}
	a.release_operation()
	a.status_key = key
}

fn (mut a ArchiveApp) cancel() {
	if a.operation == .idle { return }
	key := if a.operation == .extracting {
		'archive.cancelled_partial'
	} else {
		'archive.cancelled'
	}
	a.fail_operation(key)
}

fn (mut a ArchiveApp) browse_archive() bool {
	if a.operation != .idle { return false }
	path := editor_bytes_text(a.archive_input).clone()
	defer { unsafe { path.free() } }
	if !archive_absolute_valid(path) {
		a.status_key = 'archive.invalid_path'
		return false
	}
	fd := archive_open_source(path)
	if fd < 0 {
		a.status_key = 'archive.read_failed'
		return false
	}
	mut info := C.stat{}
	if unsafe { C.fstat(fd, &info) } != 0 || u32(info.st_mode) & u32(C.S_IFMT) != u32(C.S_IFREG) {
		desktop_close(fd)
		a.status_key = 'archive.not_regular'
		return false
	}
	if u64(info.st_size) > u64(archive_max_bytes) {
		desktop_close(fd)
		a.status_key = 'archive.source_limit'
		return false
	}
	archive_free_entries(mut a.entries)
	unsafe {
		a.data.free()
		a.loaded_path.free()
	}
	a.loaded_path = ''
	a.data = []u8{len: int(info.st_size)}
	a.read_fd = fd
	a.snapshot_inode = u64(info.st_ino)
	a.snapshot_device = u64(info.st_dev)
	a.snapshot_mtime = info.st_mtime
	a.snapshot_mtime_nsec = unsafe { C.vinix_archive_mtime_nsec(&info) }
	a.operation_path = path.clone()
	a.operation = .loading
	a.status_key = 'archive.loading'
	a.done = 0
	a.goal = u64(info.st_size)
	a.index = 0
	a.scroll = 0
	a.focus = -1
	a.set_progress()
	return true
}

fn (mut a ArchiveApp) extract_archive() bool {
	if a.operation != .idle || a.loaded_path.len == 0 { return false }
	path := editor_bytes_text(a.extract_input).clone()
	defer { unsafe { path.free() } }
	root, status := archive_new_directory(path)
	if root < 0 {
		a.status_key = status
		return false
	}
	a.root_fd = root
	a.operation = .extracting
	a.operation_path = path.clone()
	a.status_key = 'archive.extracting'
	a.index = 0
	a.entry_written = 0
	a.done = 0
	a.goal = a.data_size
	a.focus = -1
	a.set_progress()
	return true
}

fn (mut a ArchiveApp) create_archive() bool {
	if a.operation != .idle { return false }
	source := editor_bytes_text(a.source_input).clone()
	output := editor_bytes_text(a.output_input).clone()
	defer {
		unsafe {
			source.free()
			output.free()
		}
	}
	if !archive_absolute_valid(source) || !archive_absolute_valid(output) {
		a.status_key = 'archive.invalid_path'
		return false
	}
	root := archive_open_source(source)
	if root < 0 {
		a.status_key = 'archive.read_failed'
		return false
	}
	mut info := C.stat{}
	if unsafe { C.fstat(root, &info) } != 0 {
		desktop_close(root)
		a.status_key = 'archive.read_failed'
		return false
	}
	mut basename_start := 0
	for at, byte in source { if byte == `/` { basename_start = at + 1 } }
	basename := unsafe { tos(source.str + basename_start, source.len - basename_start) }
	archive_free_entries(mut a.entries)
	unsafe {
		a.data.free()
		a.loaded_path.free()
	}
	a.data = []u8{}
	a.loaded_path = ''
	mut budget := ArchiveBudget{}
	mut status := archive_collect_entry(mut a.entries, basename, '', info, mut budget)
	if status.len == 0 && u32(info.st_mode) & u32(C.S_IFMT) == u32(C.S_IFDIR) {
		status = archive_collect_directory(root, basename, '', 0, mut a.entries, mut budget)
	}
	if status.len > 0 {
		desktop_close(root)
		archive_free_entries(mut a.entries)
		a.status_key = status
		return false
	}
	parent, leaf := archive_parent(output)
	if parent < 0 {
		desktop_close(root)
		a.status_key = 'archive.invalid_path'
		return false
	}
	fd := C.openat(parent, &char(leaf.str), C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC | C.O_NONBLOCK, 0o600)
	if fd < 0 {
		a.status_key = if C.errno == C.EEXIST { 'archive.exists' } else { 'archive.write_failed' }
		desktop_close(root)
		desktop_close(parent)
		unsafe { leaf.free() }
		return false
	}
	mut output_info := C.stat{}
	if unsafe { C.fstat(fd, &output_info) } != 0 {
		// With no captured identity, a concurrent replacement cannot be
		// distinguished from our output. Preserve the named file on failure.
		desktop_close(fd)
		desktop_close(parent)
		desktop_close(root)
		unsafe { leaf.free() }
		a.status_key = 'archive.write_failed'
		return false
	}
	a.output_inode = u64(output_info.st_ino)
	a.output_device = u64(output_info.st_dev)
	a.root_fd = root
	a.write_fd = fd
	a.output_parent = parent
	a.output_leaf = leaf
	a.operation_path = output.clone()
	a.operation = .creating
	a.index = 0
	a.entry_written = 0
	a.done = 0
	a.goal = budget.used + 1024
	a.status_key = 'archive.creating'
	a.focus = -1
	a.scroll = 0
	a.set_progress()
	return true
}

fn (mut a ArchiveApp) poll() bool {
	if a.operation == .idle { return false }
	match a.operation {
		.loading { a.poll_loading() }
		.extracting { a.poll_extracting() }
		.creating { a.poll_creating() }
		.idle {}
	}
	a.set_progress()
	return true
}

fn (a &ArchiveApp) next_poll_ms() u64 {
	return if a.operation == .idle { u64(2000) } else { u64(16) }
}

fn (mut a ArchiveApp) poll_loading() {
	if a.done < a.goal {
		remaining := a.goal - a.done
		count := if remaining > u64(archive_chunk) { archive_chunk } else { int(remaining) }
		n := desktop_read(a.read_fd, unsafe { &u8(a.data.data) + int(a.done) }, u64(count))
		if n < 0 && C.errno == C.EINTR { return }
		if n <= 0 {
			a.fail_operation('archive.read_failed')
			return
		}
		a.done += u64(n)
		return
	}
	mut captured := C.stat{}
	if unsafe { C.fstat(a.read_fd, &captured) } != 0
		|| u64(captured.st_size) != a.goal || u64(captured.st_ino) != a.snapshot_inode
		|| u64(captured.st_dev) != a.snapshot_device || captured.st_mtime != a.snapshot_mtime
		|| unsafe { C.vinix_archive_mtime_nsec(&captured) } != a.snapshot_mtime_nsec {
		a.fail_operation('archive.source_unstable')
		return
	}
	// The captured bytes become the sole source for browsing and extraction.
	// Header validation covers the complete capture before any output exists.
	total, status := archive_parse_tar(a.data, mut a.entries)
	if status.len > 0 {
		a.fail_operation(status)
		return
	}
	a.data_size = total
	a.loaded_path = a.operation_path.clone()
	a.release_operation()
	a.status_key = 'archive.loaded'
	record_recent_item('vinix-archive', a.loaded_path)
}

fn (mut a ArchiveApp) poll_extracting() {
	if a.index >= a.entries.len {
		a.release_operation()
		a.status_key = 'archive.extracted'
		return
	}
	entry := a.entries[a.index]
	if a.write_fd < 0 {
		a.write_fd = archive_extract_entry(a.root_fd, entry)
		if a.write_fd < 0 {
			a.fail_operation('archive.extract_failed')
			return
		}
		if entry.directory {
			desktop_close(a.write_fd)
			a.write_fd = -1
			a.index++
			return
		}
	}
	if a.entry_written < entry.size {
		remaining := entry.size - a.entry_written
		count := if remaining > u64(archive_chunk) { archive_chunk } else { int(remaining) }
		pointer := unsafe { &u8(a.data.data) + entry.offset + int(a.entry_written) }
		if !desktop_write_all(a.write_fd, pointer, u64(count)) {
			a.fail_operation('archive.extract_failed')
			return
		}
		a.entry_written += u64(count)
		a.done += u64(count)
		return
	}
	if !desktop_preferences_fsync(a.write_fd) {
		a.fail_operation('archive.extract_failed')
		return
	}
	closed := desktop_close(a.write_fd) == 0
	a.write_fd = -1
	if !closed {
		a.fail_operation('archive.extract_failed')
		return
	}
	a.entry_written = 0
	a.index++
}

fn (mut a ArchiveApp) poll_creating() {
	if a.index >= a.entries.len {
		zeros := [1024]u8{}
		if !desktop_write_all(a.write_fd, &zeros[0], 1024) || !desktop_preferences_fsync(a.write_fd) {
			a.fail_operation('archive.write_failed')
			return
		}
		if !archive_sync_parent(a.output_parent, a.write_fd) {
			a.fail_operation('archive.write_failed')
			return
		}
		closed := desktop_close(a.write_fd) == 0
		a.write_fd = -1
		if !closed {
			a.fail_operation('archive.write_failed')
			return
		}
		a.done += 1024
		a.release_operation()
		a.status_key = 'archive.created'
		return
	}
	entry := a.entries[a.index]
	if a.read_fd < 0 && a.entry_written == 0 {
		if !entry.directory {
			a.read_fd = archive_relative_source(a.root_fd, entry.source_path)
			if a.read_fd < 0 || !archive_source_matches(a.read_fd, entry) {
				a.fail_operation('archive.source_changed')
				return
			}
		}
		header := archive_tar_header(entry)
		if !desktop_write_all(a.write_fd, &header[0], 512) {
			a.fail_operation('archive.write_failed')
			return
		}
		a.done += 512
		if entry.directory {
			a.index++
			return
		}
	}
	if a.entry_written < entry.size {
		remaining := entry.size - a.entry_written
		count := if remaining > u64(archive_chunk) { archive_chunk } else { int(remaining) }
		n := desktop_read(a.read_fd, a.buffer.data, u64(count))
		if n < 0 && C.errno == C.EINTR { return }
		if n <= 0 {
			a.fail_operation('archive.source_changed')
			return
		}
		if !desktop_write_all(a.write_fd, a.buffer.data, u64(n)) {
			a.fail_operation('archive.write_failed')
			return
		}
		a.entry_written += u64(n)
		a.done += u64(n)
		return
	}
	if !archive_source_matches(a.read_fd, entry) {
		a.fail_operation('archive.source_changed')
		return
	}
	padding := (512 - int(entry.size % 512)) % 512
	zeros := [512]u8{}
	if padding > 0 && !desktop_write_all(a.write_fd, &zeros[0], u64(padding)) {
		a.fail_operation('archive.write_failed')
		return
	}
	a.done += u64(padding)
	desktop_close(a.read_fd)
	a.read_fd = -1
	a.entry_written = 0
	a.index++
}

fn (mut a ArchiveApp) close_app() {
	a.cancel()
	a.release_operation()
	archive_free_entries(mut a.entries)
	unsafe {
		a.archive_input.free()
		a.extract_input.free()
		a.source_input.free()
		a.output_input.free()
		a.entries.free()
		a.data.free()
		a.loaded_path.free()
		a.progress_text.free()
		a.buffer.free()
	}
	a = ArchiveApp{}
}
