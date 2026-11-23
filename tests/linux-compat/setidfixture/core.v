// SPDX-License-Identifier: GPL-2.0-or-later
module setidfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <stdio.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

struct C.stat {
	st_mode u32
	st_size i64
}

fn C.alloca(usize) voidptr
fn C.chdir(&char) int
fn C.close(int) int
fn C.fallocate(int, int, i64, i64) int
fn C.fchmod(int, u32) int
fn C.fchown(int, u32, u32) int
fn C.fflush(voidptr) int
fn C.fork() int
fn C.ftruncate(int, i64) int
fn C.mkdir(&char, u32) int
fn C.mount(&char, &char, &char, usize, voidptr) int
fn C.umount(&char) int
fn C.open(&char, int, ...) int
fn C.pause() int
fn C.printf(&char, ...) int
fn C.puts(&char) int
fn C.pwrite(int, voidptr, usize, i64) isize
fn C.setgid(u32) int
fn C.setgroups(usize, voidptr) int
fn C.setuid(u32) int
fn C.snprintf(&char, usize, &char, ...) int
fn C.stat(&char, &C.stat) int
fn C.strcmp(&char, &char) int
fn C.truncate(&char, i64) int
fn C.waitpid(int, &int, int) int
fn C.write(int, voidptr, usize) isize
fn C._exit(int)
fn C.__errno_location() &int

const operations = [c'write', c'pwrite', c'append', c'shrink', c'grow', c'same-size',
	c'truncate', c'open-trunc', c'zero-write', c'fallocate']!
const modes = [u32(0o6777), u32(0o6666), u32(0o6666)]!

fn check(ok bool, stage &char, path &char, mode u32, size i64) bool {
	if !ok {
		unsafe {
			C.printf(c'LINUX SETID FAIL: %s %s mode=%o size=%ld errno=%d\n', stage, path,
				mode, size, *C.__errno_location())
		}
		C.fflush(unsafe { nil })
	}
	return ok
}

fn path_for(path &char, operation int, group int) {
	C.snprintf(path, 40, c'%s-%d', unsafe { operations[operation] }, group)
}

fn inspect(path &char, stage &char, mode u32, size i64) bool {
	unsafe {
		st := &C.stat(C.alloca(sizeof(C.stat)))
		if C.stat(path, st) != 0 { return check(false, stage, path, 0, -1) }
		actual_mode := st.st_mode & 0o7777
		return check(actual_mode == mode && st.st_size == size, stage, path, actual_mode, st.st_size)
	}
}

fn mutate(path &char, operation int) bool {
	if operation == 6 { return C.truncate(path, 2) == 0 }
	flags := if operation == 2 { C.O_APPEND } else if operation == 7 { C.O_TRUNC } else { 0 }
	fd := C.open(path, C.O_WRONLY | flags)
	if fd < 0 { return false }
	ok := match operation {
		0, 2 { C.write(fd, c'X', 1) == 1 }
		1 { C.pwrite(fd, c'X', 1, 0) == 1 }
		3 { C.ftruncate(fd, 2) == 0 }
		4 { C.ftruncate(fd, 6) == 0 }
		5 { C.ftruncate(fd, 4) == 0 }
		7 { true }
		8 { C.write(fd, c'X', 0) == 0 }
		else { C.fallocate(fd, 0, 0, 6) == 0 }
	}
	return C.close(fd) == 0 && ok
}

fn reset(path &char, mode u32, group u32) bool {
	fd := C.open(path, C.O_CREAT | C.O_WRONLY | C.O_TRUNC, 0o666)
	if fd < 0 { return false }
	ok := C.write(fd, c'base', 4) == 4 && C.fchown(fd, 0, group) == 0 && C.fchmod(fd, mode) == 0
	return C.close(fd) == 0 && ok
}

fn check_modes(stage &char, may_keep bool) bool {
	sizes := [i64(4), 4, 5, 2, 6, 4, 2, 0, 4, 6]!
	path := unsafe { &char(C.alloca(40)) }
	for operation in 0 .. operations.len {
		for group in 0 .. modes.len {
			path_for(path, operation, group)
			original := unsafe { modes[group] }
			size := unsafe { sizes[operation] }
			mode := if may_keep || operation == 8 { original } else if group == 1 {
				u32(0o2666)
			} else {
				original & 0o777
			}
			if !inspect(path, stage, mode, size) { return false }
		}
	}
	return true
}

fn mutate_all(stage &char, prepare bool) bool {
	path := unsafe { &char(C.alloca(40)) }
	for operation in 0 .. operations.len {
		for group in 0 .. modes.len {
			path_for(path, operation, group)
			if prepare && !check(reset(path, unsafe { modes[group] }, if group == 2 { u32(1001) } else { u32(1000) }),
				stage, path, 0, -1) { return false }
			if !check(mutate(path, operation), stage, path, 0, -1) { return false }
		}
	}
	return true
}

fn exercise() bool {
	if !mutate_all(c'privileged mutation', true) || !check_modes(c'CAP_FSETID preserved', true) { return false }
	path := unsafe { &char(C.alloca(40)) }
	for operation in 0 .. operations.len {
		for group in 0 .. modes.len {
			path_for(path, operation, group)
			if !check(reset(path, unsafe { modes[group] }, if group == 2 { u32(1001) } else { u32(1000) }),
				c'reset', path, 0, -1) { return false }
		}
	}
	pid := C.fork()
	if pid == 0 {
		ok := C.setgroups(0, unsafe { nil }) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0
			&& mutate_all(c'UID 1000 mutation', false)
		C._exit(if ok { 0 } else { 1 })
	}
	mut status := 0
	return check(pid > 0 && C.waitpid(pid, &status, 0) == pid && status == 0, c'UID 1000 child',
		c'.', 0, i64(status)) && check_modes(c'UID 1000 mode', false)
}

@[export: 'main']
pub fn run(argc int, argv &&char) int {
	unsafe {
		reference := argc == 2 && C.strcmp(argv[1], c'--reference') == 0
		dir := &char(c'/setid')
		if !check(C.mkdir(dir, 0o755) == 0 && C.mount(c'none', dir, c'tmpfs', 0, nil) == 0
			&& C.chdir(dir) == 0, c'mount tmpfs', dir, 0, -1) || !exercise() { return 1 }
		C.puts(c'LINUX SETID TMPFS: 30 privileged and 30 unprivileged operations passed')
		if !check(C.chdir(c'/') == 0 && C.umount(dir) == 0, c'unmount tmpfs', dir, 0, -1) { return 1 }
		if reference {
			C.puts(c'LINUX SETID SUMMARY: tmpfs=30 privileged + 30 unprivileged')
			C.puts(c'LINUX SETID REFERENCE: PASS')
			C.fflush(nil)
			for { C.pause() }
		}
		device := $if arm64 { &char(c'/dev/vda') } $else { &char(c'/dev/sd0') }
		if !check(C.mount(device, dir, c'ext2', 0, nil) == 0 && C.chdir(dir) == 0,
			c'mount ext2', device, 0, -1) || !exercise() { return 1 }
		if !check(C.chdir(c'/') == 0 && C.umount(dir) == 0 && C.mount(device, dir, c'ext2', 0, nil) == 0
			&& C.chdir(dir) == 0, c'remount ext2', device, 0, -1)
			|| !check_modes(c'ext2 after remount', false) { return 1 }
		if !check(C.chdir(c'/') == 0 && C.umount(dir) == 0, c'unmount ext2', dir, 0, -1) { return 1 }
		C.puts(c'LINUX SETID DISK: 30 privileged and 30 unprivileged operations and remount passed')
		C.puts(c'LINUX SETID: PASS')
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
