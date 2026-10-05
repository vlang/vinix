// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <sys/file.h>

fn C.flock(fd int, operation int) int
fn C.mkstemp(template &u8) i32

fn calendar_temporary_matches(fd int, path string) bool {
	mut original := C.stat{}
	mut current := C.stat{}
	return unsafe { C.fstat(fd, &original) } == 0 && unsafe { C.lstat(&char(path.str), &current) } == 0
		&& u32(current.st_mode) & u32(C.S_IFMT) == u32(C.S_IFREG)
		&& original.st_dev == current.st_dev && original.st_ino == current.st_ino
}

fn calendar_remove_temporary(fd int, path string) bool {
	if !calendar_temporary_matches(fd, path) { return false }
	return C.unlink(&char(path.str)) == 0
}

// io.util.temp_file retains its intermediate strings under manualfree.
// mkstemp exclusively creates a private 0600 sibling and mutates only this
// owned template. The caller closes the descriptor and removes failed writes.
fn calendar_temporary_file(home string) (int, string) {
	template := '${home}/.vinix-calendar.XXXXXX'
	fd := int(C.mkstemp(template.str))
	if fd < 0 { unsafe { template.free() } return -1, '' }
	if !desktop_set_cloexec(fd, true) {
		calendar_remove_temporary(fd, template)
		desktop_close(fd)
		unsafe { template.free() }
		return -1, ''
	}
	return fd, template
}

// Lock a stable sibling rather than the event record: publishing replaces the
// record's inode. The kernel releases flock when this descriptor closes, even
// if the application crashes, so the lockfile must never be unlinked.
fn calendar_lock_acquire(home string) int {
	path := '${home}/.vinix-calendar-events.lock'
	defer { unsafe { path.free() } }
	fd := C.open(&char(path.str), C.O_CREAT | C.O_RDWR | C.O_NONBLOCK | C.O_CLOEXEC | C.O_NOFOLLOW, 0o600)
	if fd < 0 { return -1 }
	mut stat := C.stat{}
	if unsafe { C.fstat(fd, &stat) } != 0 || u32(stat.st_mode) & u32(C.S_IFMT) != u32(C.S_IFREG)
		|| C.flock(fd, C.LOCK_EX | C.LOCK_NB) != 0 {
		desktop_close(fd)
		return -1
	}
	return fd
}
