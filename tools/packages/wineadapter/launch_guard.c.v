// SPDX-License-Identifier: GPL-2.0-or-later
module wineadapter

import os

#include <sys/file.h>
#define vinix_wine_guard_flock flock
#define vinix_wine_guard_fcntl fcntl
fn C.vinix_wine_guard_flock(i32, i32) i32
fn C.vinix_wine_guard_fcntl(i32, i32, ...i32) i32

// Owned coordination for cooperating managed launches, not server admission.
// Keep the file in place after close; unlinking a flock file splits ownership.
// A guard has one owner: do not copy it or close it while another call uses it.
pub struct LaunchGuard {
mut:
	data i32 = -1
	directory i32 = -1
	lock i32 = -1
	device u64
	inode u64
}

pub fn (mut guard LaunchGuard) close() {
	if guard.lock >= 0 { C.close(guard.lock) }
	if guard.directory >= 0 { C.close(guard.directory) }
	if guard.data >= 0 { C.close(guard.data) }
	guard = LaunchGuard{}
}

fn guard_file(fd i32) !C.stat {
	mut info := C.stat{}
	if C.fstat(fd, unsafe { &info }) != 0 || u32(info.st_mode) & 0o170000 != 0o100000
		|| u32(info.st_uid) != u32(C.geteuid()) || u32(info.st_gid) != u32(os.getegid())
		|| u32(info.st_mode) & 0o7777 != 0o600 || info.st_nlink != 1 || info.st_size != 0 {
		return error('Wine launch guard must be an account-owned empty ordinary file with mode 0600 and one link')
	}
	flags := C.vinix_wine_guard_fcntl(fd, C.F_GETFD)
	if flags < 0 || flags & C.FD_CLOEXEC == 0 { return error('Wine launch guard must be close-on-exec') }
	return info
}

pub fn (prefix &Prefix) acquire_launch(data string) !LaunchGuard {
	prefix.recheck(data)!
	mut guard := LaunchGuard{}
	mut accepted := false
	defer { if !accepted { guard.close() } }
	guard.data = C.vinix_wine_guard_fcntl(i32(prefix.data), C.F_DUPFD_CLOEXEC, 3)
	if guard.data < 0 { return error('cannot retain Wine launch data directory') }
	guard.directory = C.vinix_wine_guard_fcntl(i32(prefix.directory), C.F_DUPFD_CLOEXEC, 3)
	if guard.directory < 0 { return error('cannot retain Wine launch prefix directory') }
	guard.lock = i32(C.openat(guard.directory, c'.vinix-managed-launch', C.O_RDWR | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC | C.O_NONBLOCK, 0o600))
	if guard.lock < 0 && C.errno == C.EEXIST {
		guard.lock = i32(C.openat(guard.directory, c'.vinix-managed-launch', C.O_RDWR | C.O_NOFOLLOW | C.O_CLOEXEC | C.O_NONBLOCK))
	}
	if guard.lock < 0 { return error('cannot capture Wine launch guard without following links') }
	info := guard_file(guard.lock)!
	guard.device = u64(info.st_dev); guard.inode = u64(info.st_ino)
	if C.vinix_wine_guard_flock(guard.lock, C.LOCK_EX | C.LOCK_NB) != 0 {
		if C.errno == C.EAGAIN || C.errno == C.EWOULDBLOCK { return error('Wine prefix already has a managed launch') }
		return error('cannot acquire Wine launch guard')
	}
	guard.recheck(data)!
	accepted = true
	return guard
}

// Reopen through the canonical data path and compare all captured identities.
// The guard owns its directory references independently of the Prefix object.
pub fn (guard &LaunchGuard) recheck(data string) ! {
	uid := u32(C.geteuid())
	current := absolute_directory(data)!
	defer { C.close(current) }
	held_data := directory(guard.data, uid, true)!
	current_data := directory(current, uid, true)!
	if held_data.st_dev != current_data.st_dev || held_data.st_ino != current_data.st_ino { return error('Wine launch data directory was replaced') }
	prefix := C.openat(current, c'wine', C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
	if prefix < 0 { return error('Wine launch prefix was replaced') }
	defer { C.close(prefix) }
	held_prefix := directory(guard.directory, uid, true)!
	current_prefix := directory(prefix, uid, true)!
	if held_prefix.st_dev != current_prefix.st_dev || held_prefix.st_ino != current_prefix.st_ino { return error('Wine launch prefix identity changed') }
	held_lock := guard_file(guard.lock)!
	if u64(held_lock.st_dev) != guard.device || u64(held_lock.st_ino) != guard.inode { return error('Wine held launch guard identity changed') }
	check := i32(C.openat(prefix, c'.vinix-managed-launch', C.O_RDONLY | C.O_NOFOLLOW | C.O_CLOEXEC | C.O_NONBLOCK))
	if check < 0 { return error('Wine launch guard path was replaced') }
	defer { C.close(check) }
	info := guard_file(check)!
	if u64(info.st_dev) != guard.device || u64(info.st_ino) != guard.inode { return error('Wine launch guard identity changed') }
}
