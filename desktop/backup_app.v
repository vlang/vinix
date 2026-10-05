// SPDX-License-Identifier: GPL-2.0-or-later
// Versioned local folder copies. Incomplete destinations are never removed.
module main

import time

struct BackupFrame {
mut:
	directory voidptr
	destination int = -1
	relative string
	modified i64
	modified_nanos i64
}

struct BackupApp {
mut:
	source_input []u8
	store_input []u8
	restore_input []u8
	versions []string
	version_ids []string
	versions_store string
	selected int = -1
	scroll int
	page_rows int = 8
	focus int = -1
	select_all bool
	pending [4]u8
	pending_len int
	status string = 'backup.ready'
	progress string
	output_path string
	frames []BackupFrame
	buffer []u8
	name_buffer []u8
	root_fd int = -1
	store_fd int = -1
	manifest_fd int = -1
	input_fd int = -1
	output_fd int = -1
	input_info C.stat
	file_size u64
	file_copied u64
	files u64
	bytes u64
	entries u64
	active bool
	restoring bool
	scan_directory voidptr
	version_limit bool
	sequence u64
}

fn new_backup_app(source string, store string, restore string) BackupApp {
	mut app := BackupApp{
		source_input: []u8{cap: backup_path_limit}
		store_input: []u8{cap: backup_path_limit}
		restore_input: []u8{cap: backup_path_limit}
		versions: []string{cap: 128}
		version_ids: []string{cap: 128}
		frames: []BackupFrame{cap: backup_depth_limit}
		buffer: []u8{len: backup_chunk_bytes}
		name_buffer: []u8{len: 256}
	}
	unsafe {
		app.source_input.flags |= .noslices
		app.store_input.flags |= .noslices
		app.restore_input.flags |= .noslices
		app.versions.flags |= .noslices
		app.version_ids.flags |= .noslices
		app.frames.flags |= .noslices
	}
	if backup_valid_path(source) { editor_append(mut app.source_input, source) }
	if backup_valid_path(store) { editor_append(mut app.store_input, store) }
	if backup_valid_path(restore) { editor_append(mut app.restore_input, restore) }
	app.update_progress()
	return app
}

fn open_backup_app(mut desktop Desktop) !NativeApp {
	_ = desktop.tz_offset_seconds
	home := if desktop_user_home.len > 0 { desktop_user_home } else { desktop_home }
	app := new_backup_app(home, '', '')
	return &app
}

fn (mut a BackupApp) update_progress() {
	file_text := a.files.str()
	byte_text := a.bytes.str()
	next := '${file_text} / ${byte_text}'
	unsafe { file_text.free() byte_text.free() a.progress.free() }
	a.progress = next
}

fn (mut a BackupApp) stop_scan() {
	desktop_closedir(a.scan_directory)
	a.scan_directory = unsafe { nil }
}

fn (mut a BackupApp) release_job() {
	if a.input_fd >= 0 { desktop_close(a.input_fd) }
	if a.output_fd >= 0 { desktop_close(a.output_fd) }
	if a.manifest_fd >= 0 { desktop_close(a.manifest_fd) }
	if a.root_fd >= 0 { desktop_close(a.root_fd) }
	if a.store_fd >= 0 { desktop_close(a.store_fd) }
	a.input_fd = -1
	a.output_fd = -1
	a.manifest_fd = -1
	a.root_fd = -1
	a.store_fd = -1
	for frame in a.frames {
		desktop_closedir(frame.directory)
		if frame.destination >= 0 { desktop_close(frame.destination) }
		unsafe { frame.relative.free() }
	}
	a.frames.clear()
	a.active = false
}

fn (mut a BackupApp) fail(key string) {
	a.release_job()
	a.status = key
}

fn (mut a BackupApp) refresh_versions() {
	if a.active { return }
	a.stop_scan()
	for version in a.versions { unsafe { version.free() } }
	for id in a.version_ids { unsafe { id.free() } }
	a.versions.clear()
	a.version_ids.clear()
	a.selected = -1
	a.scroll = 0
	a.version_limit = false
	path := editor_bytes_text(a.store_input).clone()
	defer { unsafe { path.free() } }
	if !backup_valid_path(path) { a.status = 'backup.invalid_path' return }
	fd := backup_open_directory(path)
	if fd < 0 { a.status = 'backup.store_failed' return }
	a.scan_directory = C.fdopendir(fd)
	if a.scan_directory == unsafe { nil } {
		desktop_close(fd)
		a.status = 'backup.store_failed'
		return
	}
	unsafe { a.versions_store.free() }
	a.versions_store = path.clone()
	a.status = 'backup.no_versions'
}

fn (mut a BackupApp) scan_step() {
	for _ in 0 .. 16 {
		C.errno = 0
		if !desktop_readdir(a.scan_directory, mut a.name_buffer) {
			failed := C.errno != 0
			a.stop_scan()
			if failed { a.status = 'backup.store_failed' }
			return
		}
		name := unsafe { tos(a.name_buffer.data, int(C.strlen(&char(a.name_buffer.data)))) }
		if !name.starts_with('snapshot-') || !backup_safe_name(name) { continue }
		fd := C.openat(C.dirfd(a.scan_directory), &char(a.name_buffer.data),
			C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC, 0)
		if fd < 0 { continue }
		complete := backup_read_marker(fd)
		desktop_close(fd)
		if !complete { continue }
		if a.versions.len == 128 {
			a.version_limit = true
			a.stop_scan()
			return
		}
		index_text := a.versions.len.str()
		a.version_ids << 'backup.version.${index_text}'
		unsafe { index_text.free() }
		a.versions << name.clone()
		a.selected = a.versions.len - 1
		a.status = 'backup.ready'
	}
}

fn (mut a BackupApp) start_backup() {
	if a.active { return }
	a.stop_scan()
	source := editor_bytes_text(a.source_input).clone()
	store := editor_bytes_text(a.store_input).clone()
	defer { unsafe { source.free() store.free() } }
	if !backup_valid_path(source) || !backup_valid_path(store) {
		a.status = 'backup.invalid_path' return
	}
	if backup_overlaps(source, store) { a.status = 'backup.overlap' return }
	source_fd := backup_open_directory(source)
	if source_fd < 0 { a.status = 'backup.source_failed' return }
	store_fd := backup_open_directory_avoiding(store, source_fd)
	if store_fd < 0 { desktop_close(source_fd) a.status = 'backup.store_failed' return }
	if backup_same_directory(source_fd, store_fd) {
		desktop_close(source_fd) desktop_close(store_fd) a.status = 'backup.overlap' return
	}
	a.store_fd = store_fd
	mut created := false
	mut snapshot := ''
	stamp := time.now().unix().str()
	defer { unsafe { stamp.free() } }
	for _ in 0 .. 128 {
		a.sequence++
		sequence := a.sequence.str()
		candidate := 'snapshot-${stamp}-${sequence}'
		unsafe { sequence.free() }
		if C.mkdirat(store_fd, &char(candidate.str), 0o700) == 0 {
			snapshot = candidate
			created = true
			break
		}
		unsafe { candidate.free() }
		if C.errno != C.EEXIST { break }
	}
	if !created { desktop_close(source_fd) a.fail('backup.store_failed') return }
	root := C.openat(store_fd, &char(snapshot.str), C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC, 0)
	next_output := backup_join(store, snapshot)
	unsafe { snapshot.free() a.output_path.free() }
	a.output_path = next_output
	a.root_fd = root
	if root < 0 || !desktop_preferences_fsync(store_fd) {
		desktop_close(source_fd) a.fail('backup.copy_failed') return
	}
	a.manifest_fd = backup_new_file(root, 'manifest.txt')
	if a.manifest_fd < 0 || !desktop_write_all(a.manifest_fd, c'VINIX BACKUP 1\n', 15)
		|| !backup_manifest_row(a.manifest_fd, 'SOURCE', source, 0)
		|| C.mkdirat(root, c'data', 0o700) != 0 {
		desktop_close(source_fd) a.fail('backup.manifest_failed') return
	}
	destination := C.openat(root, c'data', C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC, 0)
	a.begin_copy(source_fd, destination, false)
}

fn (mut a BackupApp) start_restore() {
	if a.active { return }
	a.stop_scan()
	if a.selected < 0 || a.selected >= a.versions.len { a.status = 'backup.select_version' return }
	store := editor_bytes_text(a.store_input).clone()
	target := editor_bytes_text(a.restore_input).clone()
	source := editor_bytes_text(a.source_input).clone()
	defer { unsafe { store.free() target.free() source.free() } }
	if !backup_valid_path(store) || !backup_valid_path(target) { a.status = 'backup.invalid_path' return }
	if backup_overlaps(store, target) || (backup_valid_path(source) && backup_overlaps(source, target)) {
		a.status = 'backup.overlap' return
	}
	if store != a.versions_store { a.status = 'backup.select_version' return }
	store_fd := backup_open_directory(store)
	if store_fd < 0 { a.status = 'backup.store_failed' return }
	defer { desktop_close(store_fd) }
	version := a.versions[a.selected]
	root := C.openat(store_fd, &char(version.str), C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC, 0)
	if root < 0 { a.status = 'backup.source_failed' return }
	defer { desktop_close(root) }
	if !backup_read_marker(root) { a.status = 'backup.select_version' return }
	source_fd := C.openat(root, c'data', C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC, 0)
	if source_fd < 0 { a.status = 'backup.source_failed' return }
	original_fd := if backup_valid_path(source) { backup_open_directory(source) } else { -1 }
	defer { if original_fd >= 0 { desktop_close(original_fd) } }
	mut split := target.len - 1
	for split > 0 && target[split] != `/` { split-- }
	parent := if split == 0 { '/' } else { unsafe { tos(target.str, split) } }
	// The root parent is the only valid '/' directory accepted here.
	parent_fd := if parent == '/' {
		C.open(c'/', C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC, 0)
	} else { backup_open_directory_avoiding_roots(parent, [source_fd, store_fd, root, original_fd]!) }
	if parent_fd < 0 { desktop_close(source_fd) a.status = 'backup.store_failed' return }
	for forbidden in [source_fd, store_fd, root, original_fd]! {
		if forbidden >= 0 && backup_same_directory(parent_fd, forbidden) {
			desktop_close(source_fd) desktop_close(parent_fd) a.status = 'backup.overlap' return
		}
	}
	name := unsafe { tos(target.str + split + 1, target.len - split - 1) }.clone()
	defer { unsafe { name.free() } }
	if C.mkdirat(parent_fd, &char(name.str), 0o700) != 0 {
		key := if C.errno == C.EEXIST { 'backup.exists' } else { 'backup.store_failed' }
		desktop_close(source_fd) desktop_close(parent_fd) a.status = key return
	}
	destination := C.openat(parent_fd, &char(name.str), C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC, 0)
	a.store_fd = parent_fd
	unsafe { a.output_path.free() }
	a.output_path = target.clone()
	if !desktop_preferences_fsync(parent_fd) {
		desktop_close(source_fd)
		if destination >= 0 { desktop_close(destination) }
		a.fail('backup.copy_failed') return
	}
	a.root_fd = C.dup(destination)
	if a.root_fd < 0 {
		desktop_close(source_fd)
		if destination >= 0 { desktop_close(destination) }
		a.fail('backup.copy_failed') return
	}
	a.begin_copy(source_fd, destination, true)
}

fn (mut a BackupApp) begin_copy(source int, destination int, restoring bool) {
	if destination < 0 { desktop_close(source) a.fail('backup.copy_failed') return }
	directory := C.fdopendir(source)
	if directory == unsafe { nil } {
		desktop_close(source) desktop_close(destination) a.fail('backup.copy_failed') return
	}
	mut source_info := C.stat{}
	if unsafe { C.fstat(source, &source_info) } != 0 {
		desktop_closedir(directory) desktop_close(destination) a.fail('backup.source_failed') return
	}
	a.frames << BackupFrame{directory: directory, destination: destination, modified: i64(source_info.st_mtime),
		modified_nanos: unsafe { C.vinix_backup_mtime_nsec(&source_info) }}
	a.files = 0
	a.bytes = 0
	a.entries = 0
	a.file_size = 0
	a.file_copied = 0
	a.restoring = restoring
	a.active = true
	a.status = 'backup.running'
	a.update_progress()
}

fn (mut a BackupApp) complete_job() {
	if !a.restoring {
		manifest_synced := desktop_preferences_fsync(a.manifest_fd)
		manifest_closed := desktop_close(a.manifest_fd) == 0
		if !manifest_synced || !manifest_closed {
			a.manifest_fd = -1 a.fail('backup.manifest_failed') return
		}
		a.manifest_fd = -1
		if !desktop_preferences_fsync(a.root_fd) { a.fail('backup.manifest_failed') return }
		marker_fd := backup_new_file(a.root_fd, 'complete')
		if marker_fd < 0 { a.fail('backup.manifest_failed') return }
		written := desktop_write_all(marker_fd, backup_marker.str, u64(backup_marker.len))
		synced := desktop_preferences_fsync(marker_fd)
		closed := desktop_close(marker_fd) == 0
		if !written || !synced || !closed || !desktop_preferences_fsync(a.root_fd) {
			C.unlinkat(a.root_fd, c'complete', 0)
			a.fail('backup.manifest_failed') return
		}
	}
	restoring := a.restoring
	a.release_job()
	a.status = if restoring { 'backup.restored' } else { 'backup.complete' }
}

fn (mut a BackupApp) copy_step() {
	if a.input_fd >= 0 {
		remaining := a.file_size - a.file_copied
		wanted := if remaining > backup_chunk_bytes { backup_chunk_bytes } else { int(remaining) }
		if wanted > 0 {
			n := desktop_read(a.input_fd, a.buffer.data, u64(wanted))
			if n < 0 && C.errno == C.EINTR { return }
			if n <= 0 || !desktop_write_all(a.output_fd, a.buffer.data, u64(n)) {
				a.fail('backup.copy_failed') return
			}
			a.file_copied += u64(n)
			a.bytes += u64(n)
			a.update_progress()
			return
		}
		mut after := C.stat{}
		if unsafe { C.fstat(a.input_fd, &after) } != 0 || after.st_size != a.input_info.st_size
			|| after.st_mtime != a.input_info.st_mtime
			|| unsafe { C.vinix_backup_mtime_nsec(&after) } != unsafe { C.vinix_backup_mtime_nsec(&a.input_info) } {
			a.fail('backup.changed') return
		}
		if !desktop_preferences_fsync(a.output_fd) { a.fail('backup.copy_failed') return }
		closed := desktop_close(a.output_fd) == 0
		a.output_fd = -1
		desktop_close(a.input_fd)
		a.input_fd = -1
		if !closed { a.fail('backup.copy_failed') return }
		a.files++
		a.update_progress()
		return
	}
	if a.frames.len == 0 { a.complete_job() return }
	index := a.frames.len - 1
	C.errno = 0
	if !desktop_readdir(a.frames[index].directory, mut a.name_buffer) {
		if C.errno != 0 { a.fail('backup.copy_failed') return }
		mut directory_after := C.stat{}
		if unsafe { C.fstat(C.dirfd(a.frames[index].directory), &directory_after) } != 0
			|| i64(directory_after.st_mtime) != a.frames[index].modified
			|| unsafe { C.vinix_backup_mtime_nsec(&directory_after) } != a.frames[index].modified_nanos {
			a.fail('backup.changed') return
		}
		if !desktop_preferences_fsync(a.frames[index].destination) {
			a.fail('backup.copy_failed') return
		}
		desktop_closedir(a.frames[index].directory)
		desktop_close(a.frames[index].destination)
		unsafe { a.frames[index].relative.free() }
		a.frames.delete_last()
		return
	}
	name := unsafe { tos(a.name_buffer.data, int(C.strlen(&char(a.name_buffer.data)))) }
	if name == '.' || name == '..' { return }
	if !backup_safe_name(name) { a.fail('backup.special') return }
	a.entries++
	if a.entries > backup_entry_limit { a.fail('backup.limit') return }
	source_fd := C.dirfd(a.frames[index].directory)
	mut info := C.stat{}
	if unsafe { C.fstatat(source_fd, &char(a.name_buffer.data), &info, C.AT_SYMLINK_NOFOLLOW) } != 0 {
		a.fail('backup.copy_failed') return
	}
	kind := u32(info.st_mode) & u32(C.S_IFMT)
	if kind != u32(C.S_IFDIR) && kind != u32(C.S_IFREG) { a.fail('backup.special') return }
	relative := backup_join(a.frames[index].relative, name)
	if relative.len > backup_path_limit { unsafe { relative.free() } a.fail('backup.limit') return }
	if kind == u32(C.S_IFDIR) {
		if a.frames.len >= backup_depth_limit { unsafe { relative.free() } a.fail('backup.limit') return }
		child := C.openat(source_fd, &char(a.name_buffer.data), C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC, 0)
		if child < 0 { unsafe { relative.free() } a.fail('backup.special') return }
		if backup_same_directory(child, a.store_fd) || (a.root_fd >= 0 && backup_same_directory(child, a.root_fd)) {
			desktop_close(child) unsafe { relative.free() } a.fail('backup.overlap') return
		}
		mut child_info := C.stat{}
		if unsafe { C.fstat(child, &child_info) } != 0 || child_info.st_dev != info.st_dev || child_info.st_ino != info.st_ino {
			desktop_close(child) unsafe { relative.free() } a.fail('backup.changed') return
		}
		directory := C.fdopendir(child)
		if directory == unsafe { nil } { desktop_close(child) unsafe { relative.free() } a.fail('backup.copy_failed') return }
		if C.mkdirat(a.frames[index].destination, &char(a.name_buffer.data), 0o700) != 0 {
			desktop_closedir(directory) unsafe { relative.free() } a.fail('backup.copy_failed') return
		}
		destination := C.openat(a.frames[index].destination, &char(a.name_buffer.data), C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC, 0)
		if destination < 0 || (!a.restoring && !backup_manifest_row(a.manifest_fd, 'D', relative, 0)) {
			desktop_closedir(directory)
			if destination >= 0 { desktop_close(destination) }
			unsafe { relative.free() } a.fail('backup.copy_failed') return
		}
		a.frames << BackupFrame{directory: directory, destination: destination, relative: relative,
			modified: i64(child_info.st_mtime), modified_nanos: unsafe { C.vinix_backup_mtime_nsec(&child_info) }}
		return
	}
	defer { unsafe { relative.free() } }
	input := C.openat(source_fd, &char(a.name_buffer.data), C.O_RDONLY | C.O_NONBLOCK | C.O_NOFOLLOW | C.O_CLOEXEC, 0)
	if input < 0 { a.fail('backup.special') return }
	mut actual := C.stat{}
	if unsafe { C.fstat(input, &actual) } != 0 || u32(actual.st_mode) & u32(C.S_IFMT) != u32(C.S_IFREG)
		|| actual.st_dev != info.st_dev || actual.st_ino != info.st_ino || actual.st_size < 0 {
		desktop_close(input) a.fail('backup.changed') return
	}
	if u64(actual.st_size) > backup_file_limit || u64(actual.st_size) > backup_total_limit - a.bytes {
		desktop_close(input) a.fail('backup.limit') return
	}
	output := backup_new_file(a.frames[index].destination, name)
	if output < 0 { desktop_close(input) a.fail('backup.copy_failed') return }
	a.input_fd = input
	a.output_fd = output
	a.input_info = actual
	a.file_size = u64(actual.st_size)
	a.file_copied = 0
	if !a.restoring && !backup_manifest_row(a.manifest_fd, 'F', relative, a.file_size) {
		a.fail('backup.manifest_failed')
	}
}

fn (mut a BackupApp) poll() bool {
	if a.active { a.copy_step() return true }
	if a.scan_directory != unsafe { nil } { a.scan_step() return true }
	return false
}

fn (a &BackupApp) next_poll_ms() u64 {
	return if a.active { u64(1) } else if a.scan_directory != unsafe { nil } { u64(30) } else { u64(2000) }
}

fn (mut a BackupApp) close_app() {
	a.stop_scan()
	a.release_job()
	for version in a.versions { unsafe { version.free() } }
	for id in a.version_ids { unsafe { id.free() } }
	a.versions.clear()
	a.version_ids.clear()
	unsafe {
		a.versions.free() a.version_ids.free() a.frames.free() a.source_input.free() a.store_input.free()
		a.restore_input.free() a.buffer.free() a.name_buffer.free() a.progress.free() a.output_path.free() a.versions_store.free()
	}
	a = BackupApp{}
}
