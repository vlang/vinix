// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The files. A store is the directory they are in, so that tests and an
// installer working on another root use the same code as the running system.
//
// Each file is replaced whole: written beside itself, synced, renamed over
// the old one, and the directory synced. Three files cannot change in one
// step, so they are written in the order that keeps every moment in between
// safe: the password file first, then groups, then passwd. An account that
// is in passwd without a password record cannot be logged in to, and a
// password record without an account is not used by anything; add_user
// replaces a record left over under the same name.
module accountcore

import os

#include <fcntl.h>
#include <unistd.h>
#include <sys/file.h>
#include <sys/stat.h>

fn C.flock(fd int, operation int) int
fn C.fsync(fd int) int
fn C.fchmod(fd int, mode u32) int
fn C.fchown(fd int, owner u32, group u32) int
fn C.fstat(fd int, buf &C.stat) int

const lock_exclusive = 2 // LOCK_EX
const lock_shared = 1 // LOCK_SH
const lock_release = 8 // LOCK_UN

pub struct Store {
pub:
	etc string = '/etc'
	// Whether the files are given to root. Off where the store is a test's
	// directory and the test is not root.
	owned bool = true
}

pub fn (s Store) passwd_path() string {
	return s.etc + '/passwd'
}

pub fn (s Store) group_path() string {
	return s.etc + '/group'
}

pub fn (s Store) shadow_path() string {
	return s.etc + '/shadow'
}

fn (s Store) lock_path() string {
	return s.etc + '/.pwd.lock'
}

// A lock held on the store. Readers share it, a writer has it alone, and it
// goes when the descriptor does, so a program that dies leaves nothing
// locked.
pub struct Lock {
	fd int = -1
}

pub fn (s Store) lock(exclusive bool) !Lock {
	path := s.lock_path()
	defer { unsafe { path.free() } }
	fd := C.open(&char(path.str), C.O_RDWR | C.O_CREAT | C.O_CLOEXEC | C.O_NOFOLLOW, 0o600)
	if fd < 0 {
		return error('cannot open ${path}')
	}
	if C.flock(fd, if exclusive { lock_exclusive } else { lock_shared }) != 0 {
		C.close(fd)
		return error('cannot lock ${path}')
	}
	return Lock{
		fd: fd
	}
}

pub fn (l Lock) release() {
	if l.fd >= 0 {
		C.flock(l.fd, lock_release)
		C.close(l.fd)
	}
}

// A file as it must be to be believed: a regular file, not a link, that
// root owns (where `owned` asks for that) and only its owner can write, and
// no larger than max_file.
pub fn read_trusted(path string, private bool, owned bool) !string {
	fd := C.open(&char(path.str), C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW)
	if fd < 0 {
		return error('cannot open ${path}')
	}
	defer { C.close(fd) }
	mut info := C.stat{}
	if C.fstat(fd, unsafe { &info }) != 0 {
		return error('cannot inspect ${path}')
	}
	if u32(info.st_mode) & 0o170000 != 0o100000 {
		return error('${path} is not a regular file')
	}
	if owned && info.st_uid != 0 {
		return error('${path} is not owned by root')
	}
	if u32(info.st_mode) & 0o022 != 0 {
		return error('${path} is writable by others')
	}
	if private && u32(info.st_mode) & 0o077 != 0 {
		return error('${path} is readable by others')
	}
	if u64(info.st_size) > u64(max_file) {
		return error('${path} is too large')
	}
	mut data := []u8{len: int(info.st_size)}
	defer { unsafe { data.free() } }
	mut done := 0
	for done < data.len {
		got := C.read(fd, unsafe { &data[done] }, usize(data.len - done))
		if got < 0 {
			return error('cannot read ${path}')
		}
		if got == 0 {
			break
		}
		done += int(got)
	}
	return data[..done].bytestr()
}

fn sync_directory(path string) {
	fd := C.open(&char(path.str), C.O_RDONLY | C.O_CLOEXEC)
	if fd >= 0 {
		C.fsync(fd)
		C.close(fd)
	}
}

fn (s Store) replace(path string, text string, mode u32) ! {
	temporary := '${path}.new'
	// A leftover from a write that was interrupted is not ours to append to.
	os.rm(temporary) or {}
	fd := C.open(&char(temporary.str), C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_CLOEXEC | C.O_NOFOLLOW,
		0o600)
	if fd < 0 {
		return error('cannot create ${temporary}')
	}
	mut ok := true
	mut done := 0
	for done < text.len {
		put := C.write(fd, unsafe { text.str + done }, usize(text.len - done))
		if put <= 0 {
			ok = false
			break
		}
		done += int(put)
	}
	if ok && s.owned && C.fchown(fd, 0, 0) != 0 {
		ok = false
	}
	if ok && C.fchmod(fd, mode) != 0 {
		ok = false
	}
	if ok && C.fsync(fd) != 0 {
		ok = false
	}
	C.close(fd)
	if !ok {
		os.rm(temporary) or {}
		return error('cannot write ${temporary}')
	}
	os.rename(temporary, path) or {
		os.rm(temporary) or {}
		return error('cannot replace ${path}')
	}
}

// The database as the files have it. A missing shadow file is an empty one:
// every account is then one nobody can log in to.
pub fn (s Store) load() !Database {
	passwd_path := s.passwd_path()
	group_path := s.group_path()
	shadow_path := s.shadow_path()
	defer { unsafe { passwd_path.free(); group_path.free(); shadow_path.free() } }
	passwd := read_trusted(passwd_path, false, s.owned)!
	defer { unsafe { passwd.free() } }
	group := read_trusted(group_path, false, s.owned)!
	defer { unsafe { group.free() } }
	mut shadow := ''
	defer { unsafe { shadow.free() } }
	if os.exists(shadow_path) || os.is_link(shadow_path) {
		shadow = read_trusted(shadow_path, true, s.owned)!
	}
	mut db := Database{}
	mut complete := false
	defer { if !complete { db.close() } }
	db.users = parse_passwd(passwd)!
	db.groups = parse_group(group)!
	db.shadows = parse_shadow(shadow)!
	db.validate()!
	complete = true
	return db
}

// Only what everyone may read: for a program that is not root.
pub fn (s Store) load_public() !Database {
	passwd_path := s.passwd_path()
	group_path := s.group_path()
	defer { unsafe { passwd_path.free(); group_path.free() } }
	passwd := read_trusted(passwd_path, false, s.owned)!
	defer { unsafe { passwd.free() } }
	group := read_trusted(group_path, false, s.owned)!
	defer { unsafe { group.free() } }
	mut db := Database{}
	mut complete := false
	defer { if !complete { db.close() } }
	db.users = parse_passwd(passwd)!
	db.groups = parse_group(group)!
	db.validate()!
	complete = true
	return db
}

pub fn (s Store) save(db Database) ! {
	db.validate()!
	s.replace(s.shadow_path(), format_shadow(db.shadows), 0o600)!
	s.replace(s.group_path(), format_group(db.groups), 0o644)!
	s.replace(s.passwd_path(), format_passwd(db.users), 0o644)!
	sync_directory(s.etc)
}
