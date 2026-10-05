// SPDX-License-Identifier: GPL-2.0-or-later
// Anchored ordinary records, stable advisory lock, and atomic publication.
module main

#include <sys/file.h>

fn C.flock(fd int, operation int) int
fn C.renameat(old_directory int, old_path &char, new_directory int, new_path &char) int

$if macos {
	#define vinix_reminders_mtime_nsec(info) ((info)->st_mtimespec.tv_nsec)
} $else {
	#define vinix_reminders_mtime_nsec(info) ((info)->st_mtim.tv_nsec)
}
fn C.vinix_reminders_mtime_nsec(info &C.stat) i64

enum RemindersRecordState { loaded missing invalid }

// vlib real_path currently heap-promotes its 4096-byte temporary under V3.
// Keep this buffer explicitly on the stack and own only the returned text.
fn reminders_canonical_home(home string) string {
	if home.len == 0 || home.len > 4096 || home.index_u8(0) >= 0 { return '' }
	terminated := home.clone()
	defer { unsafe { terminated.free() } }
	mut bytes := [4096]u8{}
	if unsafe { C.realpath(&char(terminated.str), &char(&bytes[0])) } == unsafe { nil } { return '' }
	mut length := 0
	for length < bytes.len && bytes[length] != 0 { length++ }
	if length == bytes.len { return '' }
	return unsafe { tos(&bytes[0], length) }.clone()
}

fn reminders_read_record(directory int) (string, RemindersRecordState) {
	if directory < 0 { return '', .invalid }
	fd := C.openat(directory, c'.vinix-reminders', C.O_RDONLY | C.O_NONBLOCK | C.O_CLOEXEC | C.O_NOFOLLOW, 0)
	if fd < 0 { return '', if C.errno == C.ENOENT { RemindersRecordState.missing } else { RemindersRecordState.invalid } }
	defer { desktop_close(fd) }
	mut info := C.stat{}
	if unsafe { C.fstat(fd, &info) } != 0 || u32(info.st_mode) & u32(C.S_IFMT) != u32(C.S_IFREG)
		|| info.st_size <= 0 || info.st_size > reminders_record_limit { return '', .invalid }
	mut bytes := []u8{len: int(info.st_size)}
	defer { unsafe { bytes.free() } }
	mut at := 0
	mut interrupts := 0
	for at < bytes.len {
		n := desktop_read(fd, unsafe { &u8(bytes.data) + at }, u64(bytes.len - at))
		if n < 0 && C.errno == C.EINTR && interrupts < 8 { interrupts++ continue }
		if n <= 0 { return '', .invalid }
		at += int(n)
	}
	mut after := C.stat{}
	if unsafe { C.fstat(fd, &after) } != 0 || after.st_size != info.st_size || after.st_mtime != info.st_mtime
		|| unsafe { C.vinix_reminders_mtime_nsec(&after) } != unsafe { C.vinix_reminders_mtime_nsec(&info) } { return '', .invalid }
	return editor_bytes_text(bytes).clone(), .loaded
}

// Lock a stable sibling inode: renaming the record must not release its lock.
// flock is nonblocking and the descriptor's close releases it after a crash.
fn reminders_lock(directory int) int {
	fd := C.openat(directory, c'.vinix-reminders.lock', C.O_CREAT | C.O_RDWR | C.O_NONBLOCK | C.O_CLOEXEC | C.O_NOFOLLOW, 0o600)
	if fd < 0 { return -1 }
	mut info := C.stat{}
	if unsafe { C.fstat(fd, &info) } != 0 || u32(info.st_mode) & u32(C.S_IFMT) != u32(C.S_IFREG) {
		desktop_close(fd)
		return -1
	}
	if C.flock(fd, C.LOCK_EX | C.LOCK_NB) != 0 { desktop_close(fd) return -2 }
	return fd
}

fn reminders_sync_directory(directory int, file int) bool {
	if desktop_preferences_fsync(directory) { return true }
	// Vinix may reject directory fsync; file fsync drains its device cache.
	return C.errno == C.EINVAL && desktop_preferences_fsync(file)
}

// Cleanup is allowed only while the pathname still identifies our exclusive
// creation. A replaced file or a failed identity read is always preserved.
fn reminders_remove_owned(directory int, name string, info C.stat) {
	mut current := C.stat{}
	if unsafe { C.fstatat(directory, &char(name.str), &current, C.AT_SYMLINK_NOFOLLOW) } == 0
		&& current.st_dev == info.st_dev && current.st_ino == info.st_ino {
		C.unlinkat(directory, &char(name.str), 0)
	}
}

fn (mut app RemindersApp) save_record(record string) string {
	directory := app.home_fd
	previous := app.record
	if directory < 0 || record.len > reminders_record_limit { return 'reminders.save_failed' }
	lock_fd := reminders_lock(directory)
	if lock_fd == -2 { return 'reminders.busy' }
	if lock_fd < 0 { return 'reminders.save_failed' }
	defer { desktop_close(lock_fd) }
	current, state := reminders_read_record(directory)
	defer { unsafe { current.free() } }
	if state == .invalid { return 'reminders.save_failed' }
	if current != previous || (state == .missing && previous.len > 0) { return 'reminders.changed' }
	mut fd := -1
	mut name := ''
	pid := C.getpid().str()
	defer { unsafe { pid.free() name.free() } }
	for _ in 0 .. 32 {
		app.sequence++
		number := app.sequence.str()
		unsafe { name.free() }
		name = '.vinix-reminders.tmp.${pid}.${number}'
		unsafe { number.free() }
		fd = C.openat(directory, &char(name.str), C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NONBLOCK | C.O_CLOEXEC | C.O_NOFOLLOW, 0o600)
		if fd >= 0 { break }
		if C.errno != C.EEXIST { return 'reminders.save_failed' }
	}
	if fd < 0 { return 'reminders.save_failed' }
	mut info := C.stat{}
	known := unsafe { C.fstat(fd, &info) } == 0
	mut published := false
	defer {
		if !published && known { reminders_remove_owned(directory, name, info) }
		if fd >= 0 { desktop_close(fd) }
	}
	if !known || !desktop_write_all(fd, record.str, u64(record.len)) || !desktop_preferences_fsync(fd) { return 'reminders.save_failed' }
	if C.renameat(directory, &char(name.str), directory, c'.vinix-reminders') != 0 { return 'reminders.save_failed' }
	published = true
	synced := reminders_sync_directory(directory, fd)
	closed := desktop_close(fd) == 0
	fd = -1
	return if synced && closed { 'reminders.saved' } else { 'reminders.saved_unsynced' }
}

fn reminders_write_export(path string, data string) string {
	// archive_parent walks every intermediate component with O_NOFOLLOW and
	// clones the final filename before handing it to POSIX.
	parent, leaf := archive_parent(path)
	if parent < 0 { return 'reminders.invalid_path' }
	defer { desktop_close(parent) unsafe { leaf.free() } }
	fd := C.openat(parent, &char(leaf.str), C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_NONBLOCK | C.O_CLOEXEC, 0o600)
	if fd < 0 { return if C.errno == C.EEXIST { 'reminders.export_exists' } else { 'reminders.export_failed' } }
	mut info := C.stat{}
	known := unsafe { C.fstat(fd, &info) } == 0
	written := known && desktop_write_all(fd, data.str, u64(data.len)) && desktop_preferences_fsync(fd)
	synced := written && reminders_sync_directory(parent, fd)
	closed := desktop_close(fd) == 0
	if !written || !closed {
		if known { reminders_remove_owned(parent, leaf, info) }
		return 'reminders.export_failed'
	}
	return if synced { 'reminders.export_saved' } else { 'reminders.export_unsynced' }
}
