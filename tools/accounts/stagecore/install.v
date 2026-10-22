// SPDX-License-Identifier: GPL-2.0-or-later
module stagecore

import crypto.rand
import os

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

fn C.fstat(int, &C.stat) int
fn C.openat(int, &char, int, ...int) int
fn C.fstatat(int, &char, &C.stat, int) int
fn C.mkdirat(int, &char, u32) int
fn C.renameat(int, &char, int, &char) int
fn C.unlinkat(int, &char, int) int
fn C.fchmod(int, u32) int
fn C.fsync(int) int

pub struct Installer {
mut:
	root int = -1
	path string
	device u64
	inode u64
}

fn controlled(info &C.stat) bool {
	return info.st_mode & 0o170000 == 0o040000 && info.st_mode & 0o022 == 0
		&& (info.st_uid == 0 || info.st_uid == u32(C.geteuid()))
}

// Bind all later publications to this image, rather than resolving destination
// paths again. A replacement image or an alias below it is never adopted.
pub fn open(path string) !Installer {
	if !path.starts_with('/') || path == '/' { return error('account staging requires an absolute image root') }
	fd := C.open(path.str, C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
	if fd < 0 { return error('cannot capture account staging root') }
	mut info := C.stat{}
	mut named := C.stat{}
	if C.fstat(fd, &info) != 0 || C.fstatat(C.AT_FDCWD, path.str, &named, C.AT_SYMLINK_NOFOLLOW) != 0
		|| !controlled(&info) || info.st_dev != named.st_dev || info.st_ino != named.st_ino {
		C.close(fd)
		return error('account staging root must be an owned controlled directory')
	}
	return Installer{ root: fd, path: path.clone(), device: u64(info.st_dev), inode: u64(info.st_ino) }
}

pub fn (installer &Installer) check() ! {
	mut held := C.stat{}
	mut named := C.stat{}
	if installer.root < 0 || C.fstat(installer.root, &held) != 0
		|| C.fstatat(C.AT_FDCWD, installer.path.str, &named, C.AT_SYMLINK_NOFOLLOW) != 0
		|| !controlled(&held) || !controlled(&named)
		|| u64(held.st_dev) != installer.device || u64(held.st_ino) != installer.inode
		|| held.st_dev != named.st_dev || held.st_ino != named.st_ino {
		return error('account staging root changed; restore the captured image and retry')
	}
}

fn no_checkpoint(_ string) ! {}
fn write_bytes(fd int, data voidptr, size usize) isize { return C.write(fd, data, size) }
fn flush(fd int) int { return C.fsync(fd) }

struct InstallOptions {
	checkpoint fn (string) ! = no_checkpoint
	write fn (int, voidptr, usize) isize = write_bytes
	flush fn (int) int = flush
}

fn check_parents(descriptors &[32]int, names []string, device u64) ! {
	for index in 0 .. names.len - 1 {
		mut held := C.stat{}
		mut named := C.stat{}
		if C.fstat(descriptors[index + 1], &held) != 0
			|| C.fstatat(descriptors[index], names[index].str, &named, C.AT_SYMLINK_NOFOLLOW) != 0
			|| !controlled(&held) || !controlled(&named) || u64(held.st_dev) != device
			|| held.st_dev != named.st_dev || held.st_ino != named.st_ino {
			return error('account tool destination parent changed; restore it and retry')
		}
	}
}

fn check_leaf(parent int, name string) ! {
	mut info := C.stat{}
	if C.fstatat(parent, name.str, &info, C.AT_SYMLINK_NOFOLLOW) != 0 {
		if C.errno == C.ENOENT { return }
		return error('cannot inspect staged account tool')
	}
	if info.st_mode & 0o170000 != 0o100000 || info.st_nlink != 1 || info.st_mode & 0o022 != 0
		|| (info.st_uid != 0 && info.st_uid != u32(C.geteuid())) {
		return error('refusing an aliased or uncontrolled account tool destination')
	}
}

pub fn (installer &Installer) put(source string, relative string, mode u32) ! {
	installer.put_with(source, relative, mode, InstallOptions{})!
}

fn (installer &Installer) put_with(source string, relative string, mode u32, options InstallOptions) ! {
	installer.check()!
	names := relative.split('/')
	defer { unsafe { names.free() } }
	if names.len < 2 || names.len > 32 || mode !in [u32(0o644), u32(0o755)] {
		return error('invalid relative account tool destination')
	}
	for name in names {
		if name.len == 0 || name.len > 128 || name in ['.', '..'] { return error('invalid relative account tool destination') }
		for byte in name {
			if !((byte >= `a` && byte <= `z`) || (byte >= `A` && byte <= `Z`)
				|| (byte >= `0` && byte <= `9`) || byte in [u8(`-`), `_`, `.`]!) {
				return error('invalid relative account tool destination')
			}
		}
	}
	mut descriptors := [32]int{init: -1}
	descriptors[0] = installer.root
	defer { for index in 1 .. 32 { if descriptors[index] >= 0 { C.close(descriptors[index]) } } }
	for index in 0 .. names.len - 1 {
		parent := descriptors[index]
		if C.mkdirat(parent, names[index].str, 0o755) != 0 && C.errno != C.EEXIST {
			return error('cannot create account tool destination parent')
		}
		next := C.openat(parent, names[index].str, C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
		if next < 0 { return error('account tool destination parents cannot be aliases') }
		descriptors[index + 1] = next
		mut info := C.stat{}
		if C.fstat(next, &info) != 0 || !controlled(&info) || u64(info.st_dev) != installer.device {
			return error('account tool destination parent must be owned and controlled')
		}
	}
	parent := descriptors[names.len - 1]
	leaf := names[names.len - 1]
	options.checkpoint('captured')!
	installer.check()!
	check_parents(&descriptors, names, installer.device)!
	check_leaf(parent, leaf)!
	mut random := []u8{len: 16}
	defer { unsafe { random.free() } }
	rand.read(mut random)!
	nonce := random.hex()
	temporary := '.account-tool-' + nonce
	defer { unsafe { nonce.free(); temporary.free() } }
	fd := C.openat(parent, temporary.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC, 0o600)
	if fd < 0 { return error('cannot create private account tool destination') }
	mut opened := true
	mut published := false
	defer {
		if opened { C.close(fd) }
		if !published { C.unlinkat(parent, temporary.str, 0) }
	}
	data := os.read_bytes(source)!
	defer { unsafe { data.free() } }
	mut sent := 0
	for sent < data.len {
		written := options.write(fd, unsafe { &data[sent] }, usize(data.len - sent))
		if written < 0 && C.errno == C.EINTR { continue }
		if written <= 0 || written > data.len - sent { return error('cannot write staged account tool') }
		sent += int(written)
	}
	if C.fchmod(fd, mode) != 0 || options.flush(fd) != 0 { return error('cannot flush staged account tool') }
	mut captured := C.stat{}
	if C.fstat(fd, &captured) != 0 || captured.st_mode & 0o170000 != 0o100000
		|| captured.st_nlink != 1 || captured.st_uid != u32(C.geteuid())
		|| captured.st_size != data.len || captured.st_mode & 0o777 != mode {
		return error('private staged account tool changed during writing')
	}
	opened = false
	if C.close(fd) != 0 { return error('cannot close staged account tool') }
	options.checkpoint('written')!
	installer.check()!
	check_parents(&descriptors, names, installer.device)!
	check_leaf(parent, leaf)!
	mut temporary_info := C.stat{}
	if C.fstatat(parent, temporary.str, &temporary_info, C.AT_SYMLINK_NOFOLLOW) != 0
		|| temporary_info.st_dev != captured.st_dev || temporary_info.st_ino != captured.st_ino
		|| temporary_info.st_mode != captured.st_mode || temporary_info.st_size != captured.st_size
		|| temporary_info.st_nlink != 1 || temporary_info.st_uid != captured.st_uid {
		return error('private staged account tool was replaced before publication')
	}
	if C.renameat(parent, temporary.str, parent, leaf.str) != 0 { return error('cannot publish staged account tool') }
	published = true
	if options.flush(parent) != 0 { return error('account tool was published but its directory flush failed; retry image staging') }
	installer.check()!
	check_parents(&descriptors, names, installer.device)!
}

pub fn (mut installer Installer) close() {
	if installer.root >= 0 { C.close(installer.root) }
	unsafe { installer.path.free() }
	installer = Installer{}
}
