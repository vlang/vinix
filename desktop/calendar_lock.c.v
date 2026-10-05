// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <sys/file.h>

fn C.flock(fd int, operation int) int

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
