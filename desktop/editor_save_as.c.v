// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Exclusive creation never truncates an existing regular file or follows an
// existing final symlink. On failed writes remove only this new file's inode.
fn editor_create_file(path string, data []u8) string {
	fd := C.open(&char(path.str), C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_NONBLOCK | C.O_CLOEXEC, u32(0o600))
	if fd < 0 { return if C.errno == C.EEXIST { 'editor.workflow.exists' } else { 'editor.status.cannot_save' } }
	mut own := C.stat{}
	if unsafe { C.fstat(fd, &own) } != 0 { desktop_close(fd) return 'editor.status.cannot_save' }
	written := desktop_write_all(fd, data.data, u64(data.len)) && desktop_preferences_fsync(fd)
	closed := desktop_close(fd) == 0
	if written && closed { return '' }
	mut current := C.stat{}
	if unsafe { C.lstat(&char(path.str), &current) } == 0 && current.st_dev == own.st_dev && current.st_ino == own.st_ino {
		C.unlink(&char(path.str))
	}
	return 'editor.status.cannot_save'
}
