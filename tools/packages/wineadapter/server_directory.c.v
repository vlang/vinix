// SPDX-License-Identifier: GPL-2.0-or-later
module wineadapter

import os

#include <fcntl.h>
#include <sys/stat.h>
#define vinix_wine_directory_fcntl fcntl
#define vinix_wine_directory_fstatat fstatat
#define vinix_wine_directory_lock flock
fn C.vinix_wine_directory_fcntl(i32, i32, ...voidptr) i32
fn C.vinix_wine_directory_fstatat(i32, &char, &C.stat, i32) i32
struct C.vinix_wine_directory_lock { mut: l_type i16 l_whence i16 l_start i64 l_len i64 l_pid i32 }

// One owner; do not copy or concurrently close this value. Keep the borrowed
// LaunchGuard live and exclusively owned throughout preparation and rechecks.
// Closing never removes Wine's files or directories and does not stop a server.
pub struct ServerDirectory {
pub:
	path string
mut:
	base i32 = -1
	directory i32 = -1
	lock_fd i32 = -1
	base_name string
	name string
}

pub fn (mut server ServerDirectory) close() {
	if server.lock_fd >= 0 { C.close(server.lock_fd) }
	if server.directory >= 0 { C.close(server.directory) }
	if server.base >= 0 { C.close(server.base) }
	unsafe { server.path.free(); server.base_name.free(); server.name.free() }
	server = ServerDirectory{}
}

fn server_directory_info(fd i32) !C.stat {
	info := directory(fd, u32(C.geteuid()), true)!
	if u32(info.st_mode) & 0o7777 != 0o700 { return error('Wine server directory must have mode 0700') }
	return info
}

fn server_account() ! {
	uid := u32(C.geteuid())
	if uid == 0 || os.getegid() == 0 || u32(os.getuid()) != uid || os.getgid() != os.getegid() {
		return error('Wine server directory requires matching ordinary real and effective account identities')
	}
}

fn server_unlocked(fd i32) ! {
	mut owner := C.vinix_wine_directory_lock{l_type: i16(C.F_WRLCK), l_whence: i16(C.SEEK_SET), l_len: 1}
	if C.vinix_wine_directory_fcntl(fd, C.F_GETLK, unsafe { &owner }) != 0 {
		return error('cannot inspect Wine server lock ownership')
	}
	if owner.l_type != C.F_UNLCK { return error('Wine server lock already has an owner') }
}

fn absent_server_socket(fd i32) ! {
	mut info := C.stat{}
	if C.vinix_wine_directory_fstatat(fd, c'socket', unsafe { &info }, C.AT_SYMLINK_NOFOLLOW) == 0 {
		return error('Wine server socket entry already exists')
	}
	if C.errno != C.ENOENT { return error('cannot inspect Wine server socket entry') }
}

// Before spawning: capture the pinned private Wine 9.17 namespace and refuse
// existing endpoints or record-lock owners. The caller must hold no POSIX
// record locks on this file: F_GETLK does not report the caller's own locks.
// This neither starts a server nor authenticates a socket or executable.
pub fn (guard &LaunchGuard) prepare_server_directory(data string) !ServerDirectory {
	guard.recheck(data)!
	server_account()!
	uid := u32(C.geteuid())
	info := server_directory_info(guard.directory)!
	uid_text := uid.str(); device := u64(info.st_dev).hex(); inode := u64(info.st_ino).hex()
	defer { unsafe { uid_text.free(); device.free(); inode.free() } }
	base_name := '.wine-${uid_text}'
	name := 'server-${device}-${inode}'
	mut server := ServerDirectory{base_name: base_name, name: name, path: '${data}/wine/${base_name}/${name}'}
	mut accepted := false
	defer { if !accepted { server.close() } }
	server.base = i32(child(guard.directory, base_name, uid)!)
	server_directory_info(server.base)!
	server.directory = i32(child(server.base, name, uid)!)
	server_directory_info(server.directory)!
	server.lock_fd = i32(C.openat(server.directory, c'lock', C.O_RDONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC | C.O_NONBLOCK, 0o600))
	if server.lock_fd < 0 && C.errno == C.EEXIST {
		server.lock_fd = i32(C.openat(server.directory, c'lock', C.O_RDONLY | C.O_NOFOLLOW | C.O_CLOEXEC | C.O_NONBLOCK))
	}
	if server.lock_fd < 0 { return error('cannot capture Wine server lock without following links') }
	guard_file(server.lock_fd)!
	server.require_idle(guard, data)!
	accepted = true
	return server
}

// Namespace continuity only: a running server may legitimately own the lock
// and have a socket. Call require_idle separately immediately before startup.
pub fn (server &ServerDirectory) recheck(guard &LaunchGuard, data string) ! {
	guard.recheck(data)!
	server_account()!
	if !component(server.base_name) || !component(server.name) { return error('Wine server directory capture is closed') }
	held_base := server_directory_info(server.base)!
	base := i32(C.openat(guard.directory, server.base_name.str, C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC))
	if base < 0 { return error('Wine server base directory was replaced') }
	defer { C.close(base) }
	current_base := server_directory_info(base)!
	if held_base.st_dev != current_base.st_dev || held_base.st_ino != current_base.st_ino { return error('Wine server base identity changed') }
	held_directory := server_directory_info(server.directory)!
	dir := i32(C.openat(base, server.name.str, C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC))
	if dir < 0 { return error('Wine server directory was replaced') }
	defer { C.close(dir) }
	current_directory := server_directory_info(dir)!
	if held_directory.st_dev != current_directory.st_dev || held_directory.st_ino != current_directory.st_ino { return error('Wine server directory identity changed') }
	held_lock := guard_file(server.lock_fd)!
	fd := i32(C.openat(dir, c'lock', C.O_RDONLY | C.O_NOFOLLOW | C.O_CLOEXEC | C.O_NONBLOCK))
	if fd < 0 { return error('Wine server lock path was replaced') }
	defer { C.close(fd) }
	current_lock := guard_file(fd)!
	if held_lock.st_dev != current_lock.st_dev || held_lock.st_ino != current_lock.st_ino { return error('Wine server lock identity changed') }
	guard.recheck(data)!
}

pub fn (server &ServerDirectory) require_idle(guard &LaunchGuard, data string) ! {
	server.recheck(guard, data)!
	server_unlocked(server.lock_fd)!
	absent_server_socket(server.directory)!
	server.recheck(guard, data)!
}
