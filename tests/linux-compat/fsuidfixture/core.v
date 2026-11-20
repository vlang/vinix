// SPDX-License-Identifier: GPL-2.0-or-later
// setfsuid(2)/setfsgid(2): queries and results, permitted ids, argument
// words, /proc status columns, filesystem capabilities leaving and returning
// with uid 0, file access and new files' owners, dumpability, and ids
// following the effective ones through the setuid family.
// The same ELF runs as Vinix's init and, given --reference, under Linux.
module fsuidfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/prctl.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.read(i32, voidptr, usize) isize
struct C.stat {}

fn C.fstat(i32, &C.stat) i32
fn C.mkdir(&char, u32) i32
fn C.chown(&char, u32, u32) i32
fn C.unlink(&char) i32
fn C.alloca(usize) voidptr
fn C.strcmp(&char, &char) i32
fn C.strncmp(&char, &char, usize) i32
fn C.strchr(&char, i32) &char
fn C.strlen(&char) usize
fn C.strtoull(&char, &&char, i32) u64
fn C.setgroups(usize, voidptr) i32
fn C.prctl(i32, ...) i32
fn C.mount(&char, &char, &char, u64, voidptr) i32

// CAP_CHOWN, DAC_OVERRIDE, DAC_READ_SEARCH, FOWNER, FSETID, LINUX_IMMUTABLE,
// MKNOD and MAC_OVERRIDE.
const fs_caps = u64(0x1f) | (u64(1) << 9) | (u64(1) << 27) | (u64(1) << 32)
const cap_kill = u64(1) << 5

struct State {
mut:
	checks   int
	failures int
}

fn check(mut s State, label &char, ok bool, got i64) {
	s.checks++
	if !ok {
		s.failures++
		C.printf(c'LINUX FSUID FAIL: %s value=%ld\n', label, got)
	}
}

fn fsuid(value u64) i64 {
	return i64(C.syscall(isize(C.SYS_setfsuid), value))
}

fn fsgid(value u64) i64 {
	return i64(C.syscall(isize(C.SYS_setfsgid), value))
}

// Copy the /proc/self/status line starting with `key` into `out`.
fn status_line(key &char, out &u8) bool {
	unsafe {
		buf := &u8(C.alloca(8192))
		fd := C.open(c'/proc/self/status', C.O_RDONLY)
		if fd < 0 { return false }
		mut total := isize(0)
		for total < 8191 {
			n := C.read(fd, voidptr(u64(buf) + u64(total)), usize(8191 - total))
			if n <= 0 { break }
			total += n
		}
		C.close(fd)
		buf[total] = 0
		mut line := &char(buf)
		key_len := usize(C.strlen(key))
		for *line != 0 {
			next := C.strchr(line, `\n`)
			length := if next == nil { C.strlen(line) } else { usize(u64(next) - u64(line)) }
			if C.strncmp(line, key, key_len) == 0 && length < 128 {
				for i in 0 .. int(length) { out[i] = u8(*&char(u64(line) + u64(i))) }
				out[length] = 0
				return true
			}
			if next == nil { break }
			line = &char(u64(next) + 1)
		}
		return false
	}
}

fn status_is(key &char, wanted &char) bool {
	line := unsafe { &u8(C.alloca(128)) }
	return status_line(key, line) && C.strcmp(&char(line), wanted) == 0
}

fn effective_caps() u64 {
	line := unsafe { &u8(C.alloca(128)) }
	if !status_line(c'CapEff:', line) { return 0 }
	return C.strtoull(unsafe { &char(u64(line) + 7) }, unsafe { nil }, 16)
}

// The new file's owner, or -1 with errno when it cannot be created.
fn create_owner(path &char, uid &u32, gid &u32) int {
	unsafe {
		C.unlink(path)
		errno_ptr := C.__errno_location()
		*errno_ptr = 0
		fd := C.open(path, C.O_CREAT | C.O_RDWR, 0o600)
		if fd < 0 { return -*errno_ptr }
		st := &u8(C.alloca(256))
		C.fstat(fd, &C.stat(st))
		$if arm64 {
			*uid = *&u32(u64(st) + 24)
			*gid = *&u32(u64(st) + 28)
		} $else {
			*uid = *&u32(u64(st) + 28)
			*gid = *&u32(u64(st) + 32)
		}
		C.close(fd)
		return 0
	}
}

fn opens(path &char) int {
	unsafe {
		errno_ptr := C.__errno_location()
		*errno_ptr = 0
		fd := C.open(path, C.O_RDONLY)
		if fd < 0 { return -*errno_ptr }
		C.close(fd)
		return 0
	}
}

fn privileged(mut s State) {
	unsafe {
		C.mkdir(c'/tmp', 0o1777)
		C.mkdir(c'/tmp/fsuid-root', 0o700)
		C.close(C.open(c'/tmp/fsuid-root/file', C.O_CREAT | C.O_RDWR, 0o600))
		C.mkdir(c'/tmp/fsuid-1000', 0o700)
		C.chown(c'/tmp/fsuid-1000', 1000, 1000)
		check(mut s, c'query', fsuid(u64(-1)) == 0, fsuid(u64(-1)))
		check(mut s, c'query word', fsuid(0xffffffff) == 0, 0)
		check(mut s, c'set returns old', fsuid(1000) == 0, 0)
		check(mut s, c'set kept', fsuid(u64(-1)) == 1000, fsuid(u64(-1)))
		check(mut s, c'status uid', status_is(c'Uid:', c'Uid:\t0\t0\t0\t1000'), 0)
		caps := effective_caps()
		check(mut s, c'filesystem capabilities dropped', caps & fs_caps == 0 && caps & cap_kill != 0,
			i64(caps))
		check(mut s, c'access as filesystem uid', opens(c'/tmp/fsuid-root/file') == -C.EACCES,
			opens(c'/tmp/fsuid-root/file'))
		mut uid := u32(0)
		mut gid := u32(0)
		created := create_owner(c'/tmp/fsuid-1000/by-fsuid', &uid, &gid)
		check(mut s, c'owner from filesystem uid', created == 0 && uid == 1000 && gid == 0, created)
		check(mut s, c'setfsgid returns old', fsgid(1000) == 0, 0)
		created2 := create_owner(c'/tmp/fsuid-1000/by-fsgid', &uid, &gid)
		check(mut s, c'owner from filesystem gid', created2 == 0 && uid == 1000 && gid == 1000, created2)
		check(mut s, c'status gid', status_is(c'Gid:', c'Gid:\t0\t0\t0\t1000'), 0)
		check(mut s, c'back to root', fsuid(0) == 1000, 0)
		restored := effective_caps()
		check(mut s, c'filesystem capabilities restored', restored & fs_caps == fs_caps, i64(restored))
		check(mut s, c'access as root again', opens(c'/tmp/fsuid-root/file') == 0, 0)
		check(mut s, c'setfsgid back', fsgid(0) == 1000, 0)
		check(mut s, c'uid word', fsuid((u64(1) << 32) | 5) == 0, 0)
		check(mut s, c'uid word kept', fsuid(u64(-1)) == 5, fsuid(u64(-1)))
		check(mut s, c'uid word back', fsuid(0) == 5, 0)
		check(mut s, c'undumpable', C.prctl(C.PR_GET_DUMPABLE, 0, 0, 0, 0) == 0, 0)
	}
}

fn unprivileged(mut s State) {
	unsafe {
		child := C.fork()
		if child == 0 {
			C.setgroups(0, nil)
			C.syscall(isize(C.SYS_setresgid), 1000, 1001, 1002)
			C.syscall(isize(C.SYS_setresuid), 1000, 1001, 1002)
			C.prctl(C.PR_SET_DUMPABLE, 1, 0, 0, 0)
			mut local := State{}
			check(mut local, c'follows effective', fsuid(u64(-1)) == 1001, fsuid(u64(-1)))
			check(mut local, c'root refused', fsuid(0) == 1001 && fsuid(u64(-1)) == 1001, 0)
			check(mut local, c'still dumpable', C.prctl(C.PR_GET_DUMPABLE, 0, 0, 0, 0) == 1, 0)
			check(mut local, c'real', fsuid(1000) == 1001, 0)
			check(mut local, c'saved', fsuid(1002) == 1000, 0)
			check(mut local, c'effective', fsuid(1001) == 1002, 0)
			check(mut local, c'other refused', fsuid(5) == 1001 && fsuid(u64(-1)) == 1001, 0)
			check(mut local, c'change undumpable', C.prctl(C.PR_GET_DUMPABLE, 0, 0, 0, 0) == 0, 0)
			check(mut local, c'gid follows effective', fsgid(u64(-1)) == 1001, 0)
			check(mut local, c'gid root refused', fsgid(0) == 1001 && fsgid(u64(-1)) == 1001, 0)
			check(mut local, c'gid real', fsgid(1000) == 1001, 0)
			check(mut local, c'gid saved', fsgid(1002) == 1000, 0)
			check(mut local, c'status uid', status_is(c'Uid:', c'Uid:\t1000\t1001\t1002\t1001'), 0)
			check(mut local, c'status gid', status_is(c'Gid:', c'Gid:\t1000\t1001\t1002\t1002'), 0)
			// File access goes by the filesystem uid.
			mut uid := u32(0)
			mut gid := u32(0)
			refused := create_owner(c'/tmp/fsuid-1000/denied', &uid, &gid)
			check(mut local, c'effective uid not used', refused == -C.EACCES, refused)
			fsuid(1000)
			allowed := create_owner(c'/tmp/fsuid-1000/allowed', &uid, &gid)
			check(mut local, c'filesystem uid used', allowed == 0 && uid == 1000 && gid == 1002, allowed)
			// The setuid family puts it back on the effective uid.
			C.syscall(isize(C.SYS_setresuid), -1, 1000, -1)
			check(mut local, c'setresuid follows', status_is(c'Uid:', c'Uid:\t1000\t1000\t1002\t1000'), 0)
			fsuid(1002)
			C.syscall(isize(C.SYS_setreuid), -1, -1)
			check(mut local, c'setreuid resets', fsuid(u64(-1)) == 1000, fsuid(u64(-1)))
			// setresuid and setresgid that change nothing leave it alone; the same
			// effective id with a different filesystem id is a change.
			fsuid(1002)
			C.syscall(isize(C.SYS_setresuid), -1, -1, -1)
			check(mut local, c'setresuid no-op', fsuid(u64(-1)) == 1002, fsuid(u64(-1)))
			C.syscall(isize(C.SYS_setresuid), -1, 1000, -1)
			check(mut local, c'setresuid same euid resets', fsuid(u64(-1)) == 1000, fsuid(u64(-1)))
			C.syscall(isize(C.SYS_setresgid), -1, -1, -1)
			check(mut local, c'setresgid no-op', fsgid(u64(-1)) == 1002, fsgid(u64(-1)))
			C.syscall(isize(C.SYS_setresgid), -1, 1001, -1)
			check(mut local, c'setresgid same egid resets', fsgid(u64(-1)) == 1001, fsgid(u64(-1)))
			C.printf(c'LINUX FSUID CHILD: checks=%d failures=%d\n', local.checks, local.failures)
			C.fflush(nil)
			C._exit(if local.failures == 0 { 0 } else { 1 })
		}
		mut status := i32(0)
		C.waitpid(child, &status, 0)
		check(mut s, c'unprivileged child', status == 0, i64(status))
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		reference := argc > 1 && C.strcmp(argv[1], c'--reference') == 0
		C.mount(c'proc', c'/proc', c'proc', 0, nil)
		mut s := State{}
		privileged(mut s)
		unprivileged(mut s)
		C.printf(c'LINUX FSUID SUMMARY: checks=%d failures=%d\n', s.checks, s.failures)
		if s.failures == 0 {
			C.puts(if reference { c'LINUX FSUID REFERENCE: PASS' } else { c'LINUX FSUID: PASS' })
		}
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
