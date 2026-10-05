// SPDX-License-Identifier: GPL-2.0-or-later
// Saves compare the complete last snapshot under a separate stable lock.
module main

fn C.renameat(old_directory int, old_path &char, new_directory int, new_path &char) int

fn notes_lock(directory int) int {
	if directory < 0 { return -1 }
	fd := C.openat(directory, c'.vinix-notes-lock', C.O_RDWR | C.O_CREAT | C.O_NOFOLLOW |
		C.O_NONBLOCK | C.O_CLOEXEC, u32(0o600))
	if fd < 0 { return -1 }
	mut info := C.stat{}
	if unsafe { C.fstat(fd, &info) } != 0 || u32(info.st_mode) & u32(C.S_IFMT) != u32(C.S_IFREG)
		|| C.flock(fd, C.LOCK_EX | C.LOCK_NB) != 0 {
		desktop_close(fd)
		return -1
	}
	return fd
}

// Return 0 for absence, 1 for a bounded ordinary snapshot, -1 for any failure.
fn notes_read(directory int) (string, int) {
	fd := C.openat(directory, c'.vinix-notes', C.O_RDONLY | C.O_NOFOLLOW | C.O_NONBLOCK | C.O_CLOEXEC, 0)
	if fd < 0 { return '', if C.errno == C.ENOENT { 0 } else { -1 } }
	defer { desktop_close(fd) }
	mut info := C.stat{}
	if unsafe { C.fstat(fd, &info) } != 0 || u32(info.st_mode) & u32(C.S_IFMT) != u32(C.S_IFREG)
		|| info.st_size <= 0 || info.st_size > notes_record_limit {
		return '', -1
	}
	mut bytes := []u8{len: int(info.st_size)}
	defer { unsafe { bytes.free() } }
	mut read := 0
	mut attempts := 0
	for read < bytes.len {
		n := desktop_read(fd, unsafe { &u8(bytes.data) + read }, u64(bytes.len - read))
		if n <= 0 {
			if n < 0 && C.errno == C.EINTR && attempts < 8 {
				attempts++
				continue
			}
			return '', -1
		}
		read += int(n)
	}
	mut extra := u8(0)
	if desktop_read(fd, unsafe { &extra }, 1) != 0 { return '', -1 }
	return editor_bytes_text(bytes).clone(), 1
}

fn notes_unlink_own(directory int, name string, device u64, inode u64) {
	mut current := C.stat{}
	if unsafe { C.fstatat(directory, &char(name.str), &current, C.AT_SYMLINK_NOFOLLOW) } == 0
		&& u64(current.st_dev) == device && u64(current.st_ino) == inode {
		C.unlinkat(directory, &char(name.str), 0)
	}
}

// -2 means a newer snapshot; -1 means no publication; 1 means publication
// succeeded but final directory synchronization or close reported an error.
fn notes_publish(directory int, expected string, data string) int {
	if data.len > notes_record_limit { return -1 }
	lock_fd := notes_lock(directory)
	if lock_fd < 0 { return -1 }
	defer { desktop_close(lock_fd) }
	current, state := notes_read(directory)
	defer { unsafe { current.free() } }
	if state < 0 { return -1 }
	if current != expected || (state == 0 && expected.len > 0) { return -2 }
	pid := C.getpid().str()
	defer { unsafe { pid.free() } }
	mut fd := -1
	mut temporary := ''
	for attempt in 0 .. 16 {
		serial := attempt.str()
		name := '.vinix-notes.tmp-${pid}-${serial}'
		unsafe { serial.free() }
		fd = C.openat(directory, &char(name.str), C.O_WRONLY | C.O_CREAT | C.O_EXCL |
			C.O_NOFOLLOW | C.O_NONBLOCK | C.O_CLOEXEC, u32(0o600))
		if fd >= 0 {
			temporary = name
			break
		}
		unsafe { name.free() }
		if C.errno != C.EEXIST { return -1 }
	}
	if fd < 0 { return -1 }
	defer { unsafe { temporary.free() } }
	mut own := C.stat{}
	if unsafe { C.fstat(fd, &own) } != 0 {
		desktop_close(fd)
		return -1
	}
	if !desktop_write_all(fd, data.str, u64(data.len)) || !desktop_preferences_fsync(fd) {
		desktop_close(fd)
		notes_unlink_own(directory, temporary, u64(own.st_dev), u64(own.st_ino))
		return -1
	}
	if C.renameat(directory, &char(temporary.str), directory, c'.vinix-notes') != 0 {
		desktop_close(fd)
		notes_unlink_own(directory, temporary, u64(own.st_dev), u64(own.st_ino))
		return -1
	}
	mut synced := desktop_preferences_fsync(directory)
	if !synced && C.errno == C.EINVAL { synced = desktop_preferences_fsync(fd) }
	closed := desktop_close(fd) == 0
	return if synced && closed { 0 } else { 1 }
}

fn notes_export(path string, title string, body string) string {
	if path.len > 512 || !backup_valid_path(path) { return 'notes.export_invalid' }
	mut separator := path.len - 1
	for separator > 0 && path[separator] != `/` { separator-- }
	parent := if separator == 0 { '/' } else { console_borrow(path, 0, separator) }
	directory := if parent == '/' {
		C.open(c'/', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW, 0)
	} else {
		backup_open_directory(parent)
	}
	if directory < 0 { return 'notes.export_failed' }
	defer { desktop_close(directory) }
	name := console_borrow(path, separator + 1, path.len).clone()
	defer { unsafe { name.free() } }
	return notes_export_at(directory, name, title, body)
}

// The default personal export uses the already anchored HOME descriptor even
// when HOME is the registration symlink. Other entered paths walk no links.
fn notes_export_at(directory int, name string, title string, body string) string {
	if directory < 0 || !backup_safe_name(name) { return 'notes.export_invalid' }
	fd := C.openat(directory, &char(name.str), C.O_WRONLY | C.O_CREAT | C.O_EXCL |
		C.O_NOFOLLOW | C.O_NONBLOCK | C.O_CLOEXEC, u32(0o600))
	if fd < 0 {
		return if C.errno == C.EEXIST { 'notes.export_exists' } else { 'notes.export_failed' }
	}
	mut own := C.stat{}
	if unsafe { C.fstat(fd, &own) } != 0 {
		desktop_close(fd)
		return 'notes.export_failed'
	}
	written := desktop_write_all(fd, title.str, u64(title.len))
		&& desktop_write_all(fd, c'\n\n', 2)
		&& desktop_write_all(fd, body.str, u64(body.len)) && desktop_preferences_fsync(fd)
	closed := desktop_close(fd) == 0
	if !written || !closed {
		notes_unlink_own(directory, name, u64(own.st_dev), u64(own.st_ino))
		return 'notes.export_failed'
	}
	if !desktop_preferences_fsync(directory) && C.errno != C.EINVAL {
		return 'notes.export_durability'
	}
	return 'notes.export_saved'
}
