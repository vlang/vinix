// SPDX-License-Identifier: GPL-2.0-or-later
// Shared by the libc-only display host and the signed package launcher. The
// caller owns every descriptor and buffer; these routines allocate no storage.
@[translated]
module x11auth

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

$if x11_host_libc ? {
	pub struct C.stat { pub: st_mode u32 st_uid u32 st_nlink u64 st_dev u64 st_ino u64 st_size i64 }
}
fn C.open(&char, int, ...int) int
fn C.openat(int, &char, int, ...int) int
fn C.mkdirat(int, &char, u32) int
fn C.fchmod(int, u32) int
fn C.geteuid() i32
fn C.fstat(int, &C.stat) int
fn C.fstatat(int, &char, &C.stat, int) int
fn C.close(int) int
fn C.read(int, voidptr, usize) isize
fn C.write(int, voidptr, usize) isize
fn C.unlinkat(int, &char, int) int
fn C.strlen(&char) usize
fn C.strcmp(&char, &char) int
fn C.strncmp(&char, &char, usize) int
fn C.snprintf(&char, usize, &char, ...) int

// Only canonical local display names are admitted. Hostnames, screen suffixes,
// alternate transports and leading zeroes cannot select a different socket.
pub fn display_number(display &char) int {
	unsafe {
		if display == nil || display[0] != `:` || display[1] < `0` || display[1] > `9` { return -1 }
		if display[1] == `0` && display[2] != 0 { return -1 }
		mut number := 0
		for i := 1; i <= 6; i++ {
			if display[i] == 0 { return number }
			if display[i] < `0` || display[i] > `9` { return -1 }
			number = number * 10 + int(display[i] - `0`)
			if number > 65535 { return -1 }
		}
		return -1
	}
}

fn directory_matches(parent int, name &char, fd int, owner u32, private bool) bool {
	mut opened := C.stat{}
	mut named := C.stat{}
	return C.fstat(fd, unsafe { &opened }) == 0
		&& C.fstatat(parent, name, unsafe { &named }, C.AT_SYMLINK_NOFOLLOW) == 0
		&& opened.st_dev == named.st_dev && opened.st_ino == named.st_ino
		&& opened.st_mode & 0o170000 == 0o040000 && opened.st_uid == owner
		&& (if private { opened.st_mode & 0o777 == 0o700 } else { opened.st_mode & 0o022 == 0 })
}

fn directory(parent int, name &char, owner u32, private bool, make bool) int {
	if make { C.mkdirat(parent, name, 0o700) }
	fd := C.openat(parent, name, C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
	if fd < 0 { return -1 }
	if !directory_matches(parent, name, fd, owner, private) { C.close(fd); return -1 }
	return fd
}

// root and system_owner are explicit only for isolated filesystem-policy tests.
// Production callers always pass "/" and UID 0. No environment override exists.
// A created surface must be new: the host never adopts another process's files.
pub fn open_surface(root &char, path &char, uid u32, system_owner u32, create bool) int {
	unsafe {
		mut prefix := [4096]char{}
		length := if uid == 0 {
			C.snprintf(&prefix[0], sizeof(prefix), c'%srun/vinix-hosted-x11/', root)
		} else {
			C.snprintf(&prefix[0], sizeof(prefix), c'%srun/user/%u/vinix-hosted-x11/', root, uid)
		}
		if length < 1 || length >= int(sizeof(prefix)) || C.strncmp(path, &prefix[0], usize(length)) != 0 { return -1 }
		leaf := path + length
		leaf_length := C.strlen(leaf)
		if leaf_length == 0 || leaf_length > 96 { return -1 }
		for i := usize(0); i < leaf_length; i++ {
			ch := leaf[i]
			if !((ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`) || (ch >= `0` && ch <= `9`) || ch == `-` || ch == `_`) { return -1 }
		}
		fd := host_root(root, uid, system_owner, create)
		if fd < 0 { return -1 }
		if create && C.mkdirat(fd, leaf, 0o700) != 0 { C.close(fd); return -1 }
		surface := directory(fd, leaf, uid, true, false)
		C.close(fd)
		return surface
	}
}

// A compositor can prepare this parent before opening its private diagnostic
// log; the surface itself is created exclusively by the host after exec.
pub fn host_root(root &char, uid u32, system_owner u32, create bool) int {
	unsafe {
		mut fd := C.open(root, C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
		if fd < 0 { return -1 }
		mut info := C.stat{}
		if C.fstat(fd, &info) != 0 || info.st_uid != system_owner || info.st_mode & 0o022 != 0 { C.close(fd); return -1 }
		next := directory(fd, c'run', system_owner, false, false)
		C.close(fd); fd = next
		if fd < 0 { return -1 }
		if uid != 0 {
			next_user := directory(fd, c'user', system_owner, false, false)
			C.close(fd); fd = next_user
			if fd < 0 { return -1 }
			mut account := [16]char{}
			C.snprintf(&account[0], sizeof(account), c'%u', uid)
			next_account := directory(fd, &account[0], uid, true, false)
			C.close(fd); fd = next_account
			if fd < 0 { return -1 }
		}
		// The legacy root directory may be a root-owned tmpfs mount (0755).
		// Every surface remains exclusive 0700; ordinary account roots are 0700.
		next_host := directory(fd, c'vinix-hosted-x11', uid, uid != 0, create)
		C.close(fd); fd = next_host
		return fd
	}
}

fn record(display &char, cookie &u8, output &u8) int {
	unsafe {
		if display_number(display) < 0 { return -1 }
		n := int(C.strlen(display + 1))
		output[0] = 255; output[1] = 255 // FamilyWild; number still matches exactly.
		output[2] = 0; output[3] = 0
		output[4] = 0; output[5] = u8(n)
		for i in 0 .. n { output[6+i] = u8(display[1+i]) }
		output[6+n] = 0; output[7+n] = 18
		name := &char(c'MIT-MAGIC-COOKIE-1')
		for i in 0 .. 18 { output[8+n+i] = u8(name[i]) }
		output[26+n] = 0; output[27+n] = 16
		for i in 0 .. 16 { output[28+n+i] = cookie[i] }
		return 44+n
	}
}

// Entropy is read directly from the kernel, never a PRNG, PID or clock. The
// authority is exclusive and private even if the caller has a permissive umask.
pub fn create_authority(surface int, display &char) bool {
	unsafe {
		mut cookie := [16]u8{}
		entropy := C.open(c'/dev/urandom', C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW)
		if entropy < 0 { return false }
		mut used := 0
		for used < 16 {
			n := C.read(entropy, &cookie[0] + used, usize(16-used))
			if n <= 0 { C.close(entropy); return false }
			used += int(n)
		}
		C.close(entropy)
		mut bytes := [64]u8{}
		length := record(display, &cookie[0], &bytes[0])
		for i in 0 .. 16 { cookie[i] = 0 }
		if length < 0 { return false }
		fd := C.openat(surface, c'Xauthority', C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC, 0o600)
		if fd < 0 { return false }
		mut written := 0
		for written < length {
			n := C.write(fd, &bytes[0]+written, usize(length-written))
			if n <= 0 { C.close(fd); C.unlinkat(surface, c'Xauthority', 0); return false }
			written += int(n)
		}
		C.close(fd)
		for i in 0 .. 64 { bytes[i] = 0 }
		return true
	}
}

pub fn authority_matches(surface int, display &char, uid u32) bool {
	unsafe {
		fd := C.openat(surface, c'Xauthority', C.O_RDONLY | C.O_NOFOLLOW | C.O_CLOEXEC | C.O_NONBLOCK)
		if fd < 0 { return false }
		mut opened := C.stat{}
		mut named := C.stat{}
		valid := C.fstat(fd, &opened) == 0 && C.fstatat(surface, c'Xauthority', &named, C.AT_SYMLINK_NOFOLLOW) == 0
			&& opened.st_dev == named.st_dev && opened.st_ino == named.st_ino
			&& opened.st_mode & 0o170000 == 0o100000 && opened.st_uid == uid
			&& opened.st_mode & 0o777 == 0o600 && opened.st_nlink == 1 && opened.st_size >= 45 && opened.st_size <= 49
		if !valid { C.close(fd); return false }
		mut bytes := [64]u8{}
		mut used := 0
		for used < 64 {
			n := C.read(fd, &bytes[0]+used, usize(64-used))
			if n < 0 { C.close(fd); return false }
			if n == 0 { break }
			used += int(n)
		}
		C.close(fd)
		mut expected := [64]u8{}
		mut unused := [16]u8{}
		length := record(display, &unused[0], &expected[0])
		if length < 0 || used != length { return false }
		for i in 0 .. length-16 { if bytes[i] != expected[i] { return false } }
		return true
	}
}

pub fn admit(root &char, authority &char, display &char, uid u32, system_owner u32) bool {
	unsafe {
		if authority == nil || display_number(display) < 0 { return false }
		length := C.strlen(authority)
		if length < 12 || length > 4095 || C.strcmp(authority+length-11, c'/Xauthority') != 0 { return false }
		mut path := [4096]char{}
		for i := usize(0); i < length-11; i++ { path[i] = authority[i] }
		surface := open_surface(root, &path[0], uid, system_owner, false)
		if surface < 0 { return false }
		valid := authority_matches(surface, display, uid) && socket_matches(root, display, uid, system_owner)
		C.close(surface)
		return valid
	}
}

// The global socket directory may be sticky and writable, as required by X11.
// Neither a symlink nor a non-sticky writable parent is a trusted transport.
pub fn socket_parent(root &char, system_owner u32) int {
	return socket_directory(root, system_owner, false)
}

// Only the trusted system identity prepares the shared sticky transport. An
// existing node is inspected unchanged; no caller chmods somebody else's node.
pub fn prepare_socket_parent(root &char, system_owner u32) int {
	if u32(C.geteuid()) != system_owner { return -1 }
	return socket_directory(root, system_owner, true)
}

fn socket_directory(root &char, system_owner u32, create bool) int {
	unsafe {
		base := C.open(root, C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
		if base < 0 { return -1 }
		mut info := C.stat{}
		if C.fstat(base, &info) != 0 || info.st_uid != system_owner || info.st_mode & 0o022 != 0 { C.close(base); return -1 }
		tmp := C.openat(base, c'tmp', C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
		if tmp < 0 { C.close(base); return -1 }
		mut named := C.stat{}
		valid_tmp := C.fstat(tmp, &info) == 0 && C.fstatat(base, c'tmp', &named, C.AT_SYMLINK_NOFOLLOW) == 0
			&& info.st_dev == named.st_dev && info.st_ino == named.st_ino && info.st_uid == system_owner
			&& (info.st_mode & 0o022 == 0 || info.st_mode & 0o1000 != 0)
		C.close(base)
		if !valid_tmp { C.close(tmp); return -1 }
		created := create && C.mkdirat(tmp, c'.X11-unix', 0o1777) == 0
		dir := C.openat(tmp, c'.X11-unix', C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
		if dir < 0 { C.close(tmp); return -1 }
		if created && (C.fstat(dir, &info) != 0 || C.fstatat(tmp, c'.X11-unix', &named, C.AT_SYMLINK_NOFOLLOW) != 0
			|| info.st_dev != named.st_dev || info.st_ino != named.st_ino || info.st_uid != system_owner
			|| C.fchmod(dir, 0o1777) != 0) { C.close(dir); C.close(tmp); return -1 }
		valid_dir := C.fstat(dir, &info) == 0 && C.fstatat(tmp, c'.X11-unix', &named, C.AT_SYMLINK_NOFOLLOW) == 0
			&& info.st_dev == named.st_dev && info.st_ino == named.st_ino && info.st_uid == system_owner
			&& (info.st_mode & 0o022 == 0 || info.st_mode & 0o1000 != 0)
		C.close(tmp)
		if !valid_dir { C.close(dir); return -1 }
		return dir
	}
}

pub fn socket_matches(root &char, display &char, uid u32, system_owner u32) bool {
	unsafe {
		number := display_number(display)
		if number < 0 { return false }
		dir := socket_parent(root, system_owner)
		if dir < 0 { return false }
		mut info := C.stat{}
		mut name := [16]char{}
		C.snprintf(&name[0], sizeof(name), c'X%d', number)
		valid := C.fstatat(dir, &name[0], &info, C.AT_SYMLINK_NOFOLLOW) == 0
			&& info.st_mode & 0o170000 == 0o140000 && info.st_uid == uid
		C.close(dir)
		return valid
	}
}
