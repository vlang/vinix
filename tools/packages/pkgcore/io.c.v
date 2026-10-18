// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import tools.packages.pkgprotocol

#include <sys/file.h>
#include <sys/statvfs.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdio.h>
$if linux {
	#include <sys/syscall.h>
}

struct C.statvfs {
	f_bsize  usize
	f_frsize usize
	f_bavail usize
}

fn C.statvfs(&char, &C.statvfs) int
fn C.flock(int, int) int
fn C.fsync(int) int
fn C.geteuid() i32
fn C.getegid() i32
fn C.execv(&char, &&char) int
fn C.chown(&char, i32, i32) int
fn C.rename(&char, &char) int
fn C.fchmod(int, u32) int
fn C.write(int, voidptr, usize) isize
fn C.syscall(i64, ...voidptr) i64
fn C.renamex_np(&char, &char, u32) int

fn publish_new_directory(source string, destination string, kind string) ! {
	// Refuse a destination created during acquisition, including an empty
	// directory or dangling symlink. Plain rename can replace those names.
	mut code := -1
	$if macos {
		code = C.renamex_np(source.str, destination.str, C.RENAME_EXCL)
	} $else $if linux {
		code = int(C.syscall(i64(C.SYS_renameat2), int(-100), source.str,
			int(-100), destination.str, u32(1)))
	} $else {
		return error('atomic ${kind} publication is unsupported on this platform')
	}
	if code != 0 {
		return error('cannot publish ${kind} without replacing ${destination}: ${os.last_error()}; destination must be new and the filesystem must support exclusive atomic rename')
	}
}

pub fn replace_path(source string, destination string) ! {
	// os.rename treats a directory symlink as a destination directory. POSIX
	// rename replaces the symlink itself, which activation requires.
	if C.rename(source.str, destination.str) != 0 {
		return error('cannot atomically replace ${destination}')
	}
}

fn ordinary_file(path string) bool {
	// This compiler's os.is_file only excludes directories, so it accepts
	// FIFOs/devices. Inspect the file type before any potentially blocking read.
	info := os.lstat(path) or { return false }
	return info.mode & 0o170000 == 0o100000
}

pub fn copy_file(source string, target string, offset u64, maximum u64) ! {
	copy_file_progress(source, target, offset, maximum, pkgprotocol.Progress{}, no_progress)!
}

pub fn fetch(url string, destination string, maximum u64, resume bool, offline bool) ! {
	fetch_progress(url, destination, maximum, resume, offline, pkgprotocol.Progress{}, no_progress)!
}

// Return whether the completed bytes actually used the retained prefix. A
// server can refuse ranges, requiring a bounded fresh transfer instead.
fn fetch_progress(url string, destination string, maximum u64, resume bool, offline bool, event pkgprotocol.Progress, report fn (pkgprotocol.Progress)) !bool {
	if url.starts_with('file:///') {
		source := url[7..]
		defer { unsafe { source.free() } }
		return fetch_file_progress(source, destination, maximum, resume, event, report)
	}
	return fetch_https_with(url, destination, maximum, resume, offline, event, report, HttpsOutputOptions{})
}

pub fn free_bytes(path string) !u64 {
	// Read statvfs directly: this V's os.disk_usage frees its borrowed path,
	// which corrupts the transaction's state-directory string with -gc none.
	mut usage := C.statvfs{}
	if C.statvfs(path.str, unsafe { &usage }) != 0 {
		return error('cannot determine available disk space: ${path}')
	}
	// Block counts use fundamental allocation units, not the preferred I/O
	// transfer size. Those sizes can differ on the same mounted filesystem.
	block := u64(usage.f_frsize)
	available := u64(usage.f_bavail)
	if block == 0 { return error('filesystem reports an invalid allocation unit: ${path}') }
	if available > ~u64(0) / block {
		return error('available disk space overflow: ${path}')
	}
	return block * available
}

pub fn disk_check(available u64, needed u64, reserve u64) ! {
	if !pkgprotocol.disk_budget(available, needed, reserve).fits() {
		free_text := available.str(); needed_text := needed.str(); reserve_text := reserve.str()
		defer { unsafe { free_text.free(); needed_text.free(); reserve_text.free() } }
		return error('insufficient disk space: ' + free_text + ' bytes free, ' + needed_text + ' needed plus ' + reserve_text + ' reserved; remove unused generations or use a larger disk')
	}
}

pub struct Lock {
	fd int
}

// Only a fresh image may answer read-only requests without a state lock. A
// missing lock beside durable state is corruption, not an empty installation.
fn state_requires_lock(directory string) bool {
	for name in ['lock', 'current', 'catalog.json', 'trust-history.json']! {
		path := directory + '/' + name
		mut info := C.stat{}
		present := C.lstat(path.str, unsafe { &info }) == 0 || C.errno != C.ENOENT
		unsafe { path.free() }
		if present { return true }
	}
	return false
}

// A lock must name the one captured inode, rather than share another lock or
// permit writer chmod to change an external hard-linked file. These stat calls
// consume stack scratch synchronously; repeated admission must not retain it.
fn coordination_entry(fd int, parent int, name &char, kind string) !C.stat {
	mut info := C.stat{}
	if C.fstat(fd, unsafe { &info }) != 0 { return error('cannot inspect ${kind}') }
	if u32(info.st_mode) & 0o170000 != 0o100000 {
		return error('${kind} must be an ordinary regular file; repair package state before retrying')
	}
	if info.st_nlink != 1 { return error('${kind} must be an ordinary regular file without hard links; repair package state before retrying') }
	mut named := C.stat{}
	if C.fstatat(parent, name, unsafe { &named }, C.AT_SYMLINK_NOFOLLOW) != 0
		|| named.st_mode & 0o170000 != 0o100000 || named.st_dev != info.st_dev || named.st_ino != info.st_ino {
		return error('${kind} changed during admission; stop package workers and restore trusted coordination files before retrying')
	}
	return info
}

fn check_coordination_file(fd int, path string, kind string) ! {
	coordination_entry(fd, C.AT_FDCWD, path.str, kind)!
}

fn acquire_reader(directory string) !Lock {
	// A malformed FIFO must not block before its captured type can be checked.
	path := directory + '/lock'
	defer { unsafe { path.free() } }
	fd := C.open(path.str, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if fd < 0 { return error('package state is unavailable; refresh trusted repositories before reviewing changes') }
	check_coordination_file(fd, path, 'package state lock') or { C.close(fd); return err }
	if C.flock(fd, C.LOCK_SH | C.LOCK_NB) != 0 {
		C.close(fd)
		return error('another package transaction is running; review again when it finishes')
	}
	check_coordination_file(fd, path, 'package state lock') or { C.close(fd); return err }
	return Lock{ fd: fd }
}

pub fn owned_directory(path string, mode int) ! {
	mut info := C.stat{}
	if C.lstat(path.str, unsafe { &info }) != 0 {
		if C.errno != C.ENOENT { return error('cannot inspect package state directory: ' + path) }
		make_package_directories(path, u32(mode))!
		if C.lstat(path.str, unsafe { &info }) != 0 { return error('cannot inspect created package state directory: ' + path) }
	}
	if info.st_mode & 0o170000 != 0o040000 {
		return error('package state must use ordinary directories: ${path}')
	}
	if info.st_uid != u32(os.geteuid()) || info.st_mode & 0o022 != 0 {
		return error('package state must be owned by the invoking administrator and not writable by other users: ${path}')
	}
	os.chmod(path, mode)!
}

pub fn acquire(directory string) !Lock {
	owned_directory(directory, 0o755)!
	path := directory + '/lock'
	defer { unsafe { path.free() } }
	fd := C.open(path.str, C.O_RDWR | C.O_CREAT | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK, 0o644)
	if fd < 0 {
		return error('cannot open package lock; package changes require administrator access')
	}
	// Refuse before chmod/flock: neither operation establishes a file's type.
	check_coordination_file(fd, path, 'package state lock') or { C.close(fd); return err }
	if C.flock(fd, C.LOCK_EX | C.LOCK_NB) != 0 {
		C.close(fd)
		return error('another package transaction is running; try again when it finishes')
	}
	check_coordination_file(fd, path, 'package state lock') or { C.close(fd); return err }
	if C.fchmod(fd, 0o644) != 0 {
		C.close(fd)
		return error('cannot set package lock reader permissions')
	}
	for name in ['objects', 'generations']! {
		entry := directory + '/' + name
		owned_directory(entry, 0o755) or {
			unsafe { entry.free() }
			C.close(fd)
			return err
		}
		unsafe { entry.free() }
	}
	check_coordination_file(fd, path, 'package state lock') or { C.close(fd); return err }
	return Lock{ fd: fd }
}

pub fn (l Lock) release() { C.close(l.fd) }
