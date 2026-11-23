// SPDX-License-Identifier: GPL-2.0-or-later
module memfdpolicyfixture

#include <errno.h>
#include <fcntl.h>
#include <sched.h>
#include <stdio.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct C.stat {
	st_mode u32
}

fn C.__errno_location() &i32
fn C._exit(i32)
fn C.close(i32) i32
fn C.fcntl(i32, i32, ...) i32
fn C.fflush(voidptr) i32
fn C.fork() i32
fn C.fstat(i32, &C.stat) i32
fn C.getpid() i32
fn C.mount(&char, &char, &char, u64, voidptr) i32
fn C.open(&char, i32, ...) i32
fn C.pause() i32
fn C.pipe(&i32) i32
fn C.pread(i32, voidptr, u64, i64) i64
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.pwrite(i32, voidptr, u64, i64) i64
fn C.read(i32, voidptr, u64) i64
fn C.setuid(u32) i32
fn C.strcmp(&char, &char) i32
fn C.strlen(&char) u64
fn C.syscall(i64, ...) i64
fn C.waitpid(i32, &i32, i32) i32
fn C.write(i32, voidptr, u64) i64

const policy_path = c'/proc/sys/vm/memfd_noexec'
const mfd_exec = u64(0x10)
const mfd_noexec_seal = u64(0x08)
const f_get_seals = 1034
const f_seal_exec = 0x20
const f_seal_seal = 1

struct CapHeader {
	version u32 = 0x20080522
	pid     i32
}

struct CapData {
mut:
	effective   u32
	permitted   u32
	inheritable u32
}

fn need(ok bool, label &char) {
	if ok {
		return
	}
	unsafe {
		C.printf(c'LINUX MEMFDPOLICY FAIL: %s errno=%d\n', label, *C.__errno_location())
		C.fflush(nil)
		C._exit(1)
	}
}

fn create(name &char, flags u64) i32 {
	unsafe {
		fd := C.syscall(i64(C.SYS_memfd_create), name, flags)
		return if fd < 0 { -*C.__errno_location() } else { i32(fd) }
	}
}

fn check_memfd(flags u64, mode u32, seals i32, label &char) {
	fd := create(c'policy', flags)
	mut info := C.stat{}
	need(fd >= 0 && C.fstat(fd, &info) == 0 && info.st_mode & 0o777 == mode
		&& C.fcntl(fd, f_get_seals) == seals, label)
	C.close(fd)
}

fn scope(fd i32, expected u8, label &char) {
	mut text := [3]u8{}
	need(C.pread(fd, &text[0], text.len, 0) == 2 && text[0] == expected && text[1] == `\n`, label)
}

fn set_scope(fd i32, value u8) {
	mut text := [value, `\n`]!
	need(C.pwrite(fd, &text[0], text.len, 0) == text.len, c'write policy value')
}

fn malformed(fd i32, text &char) {
	unsafe {
		need(C.pwrite(fd, text, C.strlen(text), 0) == -1 && *C.__errno_location() == C.EINVAL,
			c'invalid value or value below parent floor')
	}
}

fn exchange(fd i32, send bool) {
	mut token := u8(1)
	count := if send { C.write(fd, &token, 1) } else { C.read(fd, &token, 1) }
	need(count == 1 && token == 1, c'parent-child synchronization')
}

fn check_write_permission(fd i32) {
	child := C.fork()
	need(child >= 0, c'fork for capability check')
	if child == 0 {
		unsafe {
			mut header := CapHeader{}
			mut caps := [2]CapData{}
			need(C.syscall(i64(C.SYS_capget), &header, &caps[0]) == 0, c'read current capabilities')
			caps[0].effective &= ~(u32(1) << 21)
			need(C.syscall(i64(C.SYS_capset), &header, &caps[0]) == 0, c'drop effective CAP_SYS_ADMIN')
			need(C.pwrite(fd, c'1', 1, 0) == -1 && *C.__errno_location() == C.EPERM,
				c'uid zero still needs namespace capability')
			need(C.setuid(1000) == 0, c'drop privileges')
			scope(fd, `0`, c'policy remains readable after dropping privileges')
			need(C.pwrite(fd, c'1', 1, 0) == -1 && *C.__errno_location() == C.EPERM,
				c'write checks credentials using inherited descriptor')
			C._exit(0)
		}
	}
	mut status := i32(0)
	need(C.waitpid(child, &status, 0) == child && status == 0, c'capability checks')
}

fn check_namespace(fd i32) {
	root_pidns := C.open(c'/proc/self/ns/pid', C.O_RDONLY)
	need(root_pidns >= 0, c'open ancestor PID namespace')
	mut to_child := [2]i32{}
	mut to_parent := [2]i32{}
	need(C.pipe(&to_child[0]) == 0 && C.pipe(&to_parent[0]) == 0, c'synchronization pipes')
	set_scope(fd, `1`)
	need(C.syscall(i64(C.SYS_unshare), i64(C.CLONE_NEWPID)) == 0, c'create future PID namespace')
	set_scope(fd, `0`)
	scope(fd, `0`, c'unshare leaves caller in active namespace')
	child := C.fork()
	need(child >= 0, c'fork namespace init')
	if child == 0 {
		C.close(to_child[1])
		C.close(to_parent[0])
		need(C.getpid() == 1, c'child is the new namespace init')
		child_pidns := C.open(c'/proc/self/ns/pid', C.O_RDONLY)
		need(child_pidns >= 0, c'open active child PID namespace')
		need(C.syscall(i64(C.SYS_unshare), i64(C.CLONE_NEWPID)) == 0, c'create nested future PID namespace')
		need(C.syscall(i64(C.SYS_setns), i64(child_pidns), i64(C.CLONE_NEWPID)) == 0,
			c'restore active namespace for future children and release nested one')
		C.close(child_pidns)
		unsafe {
			need(C.syscall(i64(C.SYS_setns), i64(root_pidns), i64(C.CLONE_NEWPID)) == -1
				&& *C.__errno_location() == C.EINVAL, c'setns rejects ancestor PID namespace')
		}
		scope(fd, `1`, c'child retained its inherited value and reads it through parent fd')
		check_memfd(0, 0o666, f_seal_exec, c'inherited default disables execution')
		check_memfd(mfd_exec, 0o777, f_seal_seal, c'scope one allows explicit execution')
		set_scope(fd, `0`)
		exchange(to_parent[1], true)
		exchange(to_child[0], false)
		scope(fd, `2`, c'raising ancestor updates existing child')
		malformed(fd, c'1')
		need(create(c'policy', mfd_exec) == -C.EACCES, c'ancestor blocks explicit execution')
		check_memfd(0, 0o666, f_seal_exec, c'ancestor disables implicit execution')
		exchange(to_parent[1], true)
		exchange(to_child[0], false)
		scope(fd, `0`, c'lowering ancestor restores the stored child value')
		check_memfd(0, 0o777, f_seal_seal, c'child returns to executable default')
		set_scope(fd, `2`)
		scope(fd, `2`, c'child sets its own value through parent fd')
		C._exit(0)
	}
	C.close(to_child[0])
	C.close(to_parent[1])
	exchange(to_parent[0], false)
	set_scope(fd, `2`)
	exchange(to_child[1], true)
	exchange(to_parent[0], false)
	set_scope(fd, `0`)
	exchange(to_child[1], true)
	mut status := i32(0)
	need(C.waitpid(child, &status, 0) == child && status == 0, c'child policy checks')
	scope(fd, `0`, c'child write left ancestor unchanged')
	C.close(root_pidns)
	C.close(to_child[1])
	C.close(to_parent[0])
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		C.mount(c'proc', c'/proc', c'proc', 0, nil)
		fd := C.open(policy_path, C.O_RDWR)
		need(fd >= 0, c'open /proc/sys/vm/memfd_noexec')
		mut info := C.stat{}
		need(C.fstat(fd, &info) == 0 && info.st_mode & 0o777 == 0o644, c'policy inode permissions')
		scope(fd, `0`, c'initial policy is zero')
		check_memfd(0, 0o777, f_seal_seal, c'initial memfd default is executable')
		for value in [c'3', c'9', c'-1', c'+1', c'0x', c'1x', c'1\r', c'000000000000000000001', c'  ']! {
			malformed(fd, value)
		}
		need(C.pwrite(fd, c'\t0x1\n', 5, 0) == 5, c'hexadecimal value with whitespace')
		scope(fd, `1`, c'hexadecimal value is stored')
		need(C.pwrite(fd, c'2', 1, 1) == 1, c'nonzero offset write succeeds')
		scope(fd, `1`, c'nonzero offset write is ignored')
		need(C.pwrite(fd, c'2 \t1', 4, 0) == 3, c'write consumes first integer and whitespace')
		scope(fd, `2`, c'scope two is stored')
		truncating := C.open(policy_path, C.O_WRONLY | C.O_TRUNC)
		need(truncating >= 0, c'open for shell redirection')
		C.close(truncating)
		scope(fd, `2`, c'open with truncation preserves policy')
		mut byte := u8(0)
		need(C.read(fd, &byte, 1) == 1 && byte == `2` && C.read(fd, &byte, 1) == 0,
			c'sysctl short read ends at nonzero offset')
		need(create(nil, mfd_exec | mfd_noexec_seal) == -C.EINVAL, c'conflicting flags precede policy')
		need(create(nil, mfd_exec) == -C.EACCES, c'enforcement precedes invalid memfd name')
		need(create(nil, 0) == -C.EFAULT, c'implicit noexec still validates name')
		check_memfd(mfd_noexec_seal, 0o666, f_seal_exec, c'explicit noexec works at scope two')
		need(C.pwrite(fd, c'-0', 2, 0) == 2, c'accept signed zero')
		scope(fd, `0`, c'initial namespace can lower its value')

		check_write_permission(fd)
		check_namespace(fd)
		C.close(fd)
		C.puts(c'LINUX MEMFDPOLICY SUMMARY: scopes=0,1,2 inheritance=live capability=checked')
		C.puts(if argc > 1 && C.strcmp(argv[1], c'--reference') == 0 {
			c'LINUX MEMFDPOLICY REFERENCE: PASS'
		} else {
			c'LINUX MEMFDPOLICY: PASS'
		})
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
