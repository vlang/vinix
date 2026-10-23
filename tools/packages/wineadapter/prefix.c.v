// SPDX-License-Identifier: GPL-2.0-or-later
module wineadapter

import os

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
fn C.open(&char, int, ...int) int
fn C.openat(int, &char, int, ...int) int
fn C.mkdirat(int, &char, u32) int
fn C.fstat(int, &C.stat) int
fn C.close(int) int
fn C.symlinkat(&char, int, &char) int
fn C.readlinkat(int, &char, &char, usize) isize
fn C.write(int, voidptr, usize) isize
fn C.geteuid() u32

pub struct Prefix {
pub:
	path string
mut:
	data int = -1
	directory int = -1
	device u64
	inode u64
}

pub fn (mut prefix Prefix) close() {
	if prefix.directory >= 0 { C.close(prefix.directory) }
	if prefix.data >= 0 { C.close(prefix.data) }
	unsafe { prefix.path.free() }
	prefix = Prefix{}
}

fn component(name string) bool {
	if name.len == 0 || name == '.' || name == '..' { return false }
	for byte in name { if byte == `/` || byte == 0 || byte < 32 { return false } }
	return true
}

fn directory(fd int, uid u32, private bool) !C.stat {
	mut info := C.stat{}
	if C.fstat(fd, unsafe { &info }) != 0 || u32(info.st_mode) & 0o170000 != 0o040000 {
		return error('Wine prefix needs ordinary directories')
	}
	if private && (u32(info.st_uid) != uid || u32(info.st_gid) != os.getegid() || u32(info.st_mode) & 0o777 != 0o700) {
		return error('Wine prefix directory must belong to the effective account and be mode 0700')
	}
	return info
}

fn absolute_directory(path string) !int {
	if path.len < 2 || path[0] != `/` || path.len > 4096 { return error('Wine prefix needs a canonical absolute data path') }
	// Ancestors are inspected, never read. In the package sandbox O_PATH
	// preserves that distinction while still capturing an openat parent.
	mut flags := C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC
	$if linux { flags = C.O_PATH | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC }
	mut fd := C.open(c'/', flags)
	if fd < 0 { return error('cannot capture Wine data root') }
	mut accepted := false
	defer { if !accepted { C.close(fd) } }
	mut start := 1
	for index in 1 .. path.len + 1 {
		if index < path.len && path[index] != `/` { continue }
		name := unsafe { tos(path.str + start, index - start) }
		if !component(name) { return error('Wine data path contains an unsafe component') }
		owned := name.clone()
		next := C.openat(fd, owned.str, flags)
		unsafe { owned.free() }
		if next < 0 { return error('Wine data path contains a missing or linked directory') }
		C.close(fd); fd = next; start = index + 1
	}
	accepted = true
	return fd
}

fn child(parent int, name string, uid u32) !int {
	if !component(name) { return error('invalid Wine prefix component') }
	if C.mkdirat(parent, name.str, 0o700) != 0 && C.errno != C.EEXIST { return error('cannot create private Wine directory') }
	fd := C.openat(parent, name.str, C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
	if fd < 0 { return error('Wine prefix directory is linked or unavailable') }
	directory(fd, uid, true) or { C.close(fd); return err }
	return fd
}

fn link(parent int, name string, target string) ! {
	if !component(name) || target.contains('\x00') { return error('invalid Wine prefix link') }
	if C.symlinkat(target.str, parent, name.str) != 0 && C.errno != C.EEXIST { return error('cannot create Wine prefix link') }
	mut buffer := [4097]u8{}
	length := C.readlinkat(parent, name.str, &char(&buffer[0]), 4096)
	if length < 0 || length >= 4096 || unsafe { tos(&buffer[0], int(length)) } != target {
		return error('Wine prefix link target differs')
	}
}

fn disable_update(parent int, uid u32) ! {
	mut fd := C.openat(parent, c'.update-timestamp', C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC, 0o600)
	if fd >= 0 {
		if C.write(fd, c'disable\n', 8) != 8 { C.close(fd); return error('cannot disable Wine automatic prefix updates') }
		C.close(fd)
	} else if C.errno != C.EEXIST { return error('cannot capture Wine update policy') }
	fd = C.openat(parent, c'.update-timestamp', C.O_RDONLY | C.O_NOFOLLOW | C.O_CLOEXEC | C.O_NONBLOCK)
	if fd < 0 { return error('Wine update policy must be an ordinary file') }
	defer { C.close(fd) }
	mut info := C.stat{}
	mut buffer := [9]u8{}
	if C.fstat(fd, unsafe { &info }) != 0 || u32(info.st_mode) & 0o170000 != 0o100000 || u32(info.st_uid) != uid
		|| info.st_nlink != 1 || info.st_size != 8 || u32(info.st_mode) & 0o077 != 0
		|| C.read(fd, &buffer[0], 9) != 8 || unsafe { tos(&buffer[0], 8) } != 'disable\n' {
		return error('Wine update policy differs from the private disabled policy')
	}
}

// All mutation uses captured descriptors. Links to signed builtins are created
// only within the private prefix; a pre-existing different target is refused.
pub fn prepare_prefix(data string, builtins string) !Prefix {
	uid := C.geteuid()
	if uid == 0 || os.getegid() == 0 { return error('packaged Wine requires an ordinary account') }
	data_fd := absolute_directory(data)!
	mut prefix := Prefix{path: data + '/wine', data: data_fd}
	mut accepted := false
	defer { if !accepted { prefix.close() } }
	directory(data_fd, uid, true)!
	prefix.directory = child(data_fd, 'wine', uid)!
	info := directory(prefix.directory, uid, true)!
	prefix.device = u64(info.st_dev); prefix.inode = u64(info.st_ino)
	if !os.is_abs_path(builtins) || builtins.contains('\x00') { return error('Wine builtins must use an absolute packaged directory') }
	builtins_fd := absolute_directory(builtins)!
	defer { C.close(builtins_fd) }
	mut names := os.ls(builtins)!
	defer { unsafe { names.free() } }
	names.sort()
	if names.len < 1 || names.len > 900 { return error('Wine builtin inventory is empty or too large') }
	drive := child(prefix.directory, 'drive_c', uid)!
	defer { C.close(drive) }
	windows := child(drive, 'windows', uid)!
	defer { C.close(windows) }
	system := child(windows, 'system32', uid)!
	defer { C.close(system) }
	users := child(drive, 'users', uid)!
	defer { C.close(users) }
	user := child(users, 'vinix', uid)!
	defer { C.close(user) }
	temporary := child(user, 'Temp', uid)!
	C.close(temporary)
	devices := child(prefix.directory, 'dosdevices', uid)!
	defer { C.close(devices) }
	link(devices, 'c:', '../drive_c')!
	link(devices, 'z:', '/')!
	for name in names {
		// Wine's signed Windows inventory also contains drivers, control-panel
		// modules, type libraries and its theme. Keep the pinned format bounded.
		if !component(name) || !(name.ends_with('.dll') || name.ends_with('.exe')
			|| name.ends_with('.sys') || name.ends_with('.cpl') || name.ends_with('.drv')
			|| name.ends_with('.ocx') || name.ends_with('.ax') || name.ends_with('.tlb')
			|| name.ends_with('.ds') || name.ends_with('.com') || name.ends_with('.acm')
			|| name.ends_with('.msstyles')) { return error('unexpected Wine builtin name') }
		fd := C.openat(builtins_fd, name.str, C.O_RDONLY | C.O_NOFOLLOW | C.O_CLOEXEC | C.O_NONBLOCK)
		if fd < 0 { return error('Wine builtin is linked or unavailable') }
		mut source := C.stat{}
		ok := C.fstat(fd, unsafe { &source }) == 0 && u32(source.st_mode) & 0o170000 == 0o100000
		C.close(fd)
		if !ok { return error('Wine builtin is not an ordinary file') }
		target := builtins + '/' + name
		link(system, name, target) or { unsafe { target.free() }; return err }
		unsafe { target.free() }
	}
	disable_update(prefix.directory, uid)!
	prefix.recheck(data)!
	accepted = true
	return prefix
}

pub fn (prefix &Prefix) recheck(data string) ! {
	fd := absolute_directory(data)!
	defer { C.close(fd) }
	original := directory(prefix.data, C.geteuid(), true)!
	current := directory(fd, C.geteuid(), true)!
	if original.st_dev != current.st_dev || original.st_ino != current.st_ino { return error('Wine data directory was replaced') }
	check := C.openat(fd, c'wine', C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
	if check < 0 { return error('Wine prefix was replaced') }
	defer { C.close(check) }
	info := directory(check, C.geteuid(), true)!
	if u64(info.st_dev) != prefix.device || u64(info.st_ino) != prefix.inode { return error('Wine prefix identity changed') }
}
