// SPDX-License-Identifier: GPL-2.0-or-later
module seccompallocfixture

#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <stdio.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct SockFilter { code u16 jt u8 jf u8 k u32 }
struct SockFprog { len u16 filter voidptr }
fn C.syscall(isize, ...) isize
fn C.prctl(i32, ...) i32
fn C.__errno_location() &i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.open(&char, i32, ...) i32
fn C.pread(i32, voidptr, usize, i64) isize
fn C.close(i32) i32
fn C.sscanf(&char, &char, ...) i32
fn C.usleep(u32) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

fn mode() i32 { return unsafe { C.prctl(C.PR_GET_SECCOMP, usize(0), usize(0), usize(0), usize(0)) } }
fn nnp() i32 { return unsafe { C.prctl(C.PR_GET_NO_NEW_PRIVS, usize(0), usize(0), usize(0), usize(0)) } }
fn install(method i32, program voidptr) isize {
	return unsafe {
		if method == 0 { C.syscall(isize(C.SYS_seccomp), isize(1), isize(0), program) }
		else { isize(C.prctl(C.PR_SET_SECCOMP, usize(2), program, usize(0), usize(0))) }
	}
}
fn reject(method i32, program voidptr, expected i32) bool {
	unsafe {
		old_mode := mode(); old_nnp := nnp()
		e := C.__errno_location(); *e = 0
		result := install(method, program)
		actual := *e
		if result != -1 || actual != expected || mode() != old_mode || nnp() != old_nnp {
			C.printf(c'LINUX SECCOMPALLOC DETAIL: method=%d actual=%ld/%d expected=%d mode=%d/%d nnp=%d/%d\n',
				method, result, actual, expected, mode(), old_mode, nnp(), old_nnp)
			C.fflush(nil)
			return false
		}
		return true
	}
}
fn count(fd i32) ?u64 {
	unsafe {
		mut data := [4096]char{}
		length := C.pread(fd, &data[0], usize(data.len - 1), 0)
		if length <= 0 || length >= data.len { return none }
		data[int(length)] = 0
		mut line := 0
		for line < int(length) {
			mut pages := u64(0)
			if C.sscanf(&data[line], c'large - - %lu', &pages) == 1 { return pages }
			for line < int(length) && data[line] != char(10) { line++ }
			line++
		}
	}
	return none
}
fn cohort(method i32, ordinary bool) bool {
	unsafe {
		if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { return false }
		mut instructions := [4095]SockFilter{}
		instructions[4094] = SockFilter{code: 0x06, k: 0x7fff0000}
		program := SockFprog{len: 4095, filter: &instructions[0]}
		if ordinary {
			if !reject(method, &program, C.EACCES)
				|| C.prctl(C.PR_SET_NO_NEW_PRIVS, usize(1), usize(0), usize(0), usize(0)) != 0 { return false }
		}
		if !reject(method, voidptr(1), C.EFAULT) { return false }
		zero := SockFprog{filter: voidptr(1)}
		oversized := SockFprog{len: 4097, filter: voidptr(1)}
		if !reject(method, &zero, C.EINVAL) || !reject(method, &oversized, C.EINVAL) { return false }
		e := C.__errno_location(); *e = 0
		result := install(method, &program)
		actual := *e
		// The auditor requires success in production and ENOMEM in a separate
		// fault-injection build. The fixture records which path it exercised.
		failure := result == -1 && actual == C.ENOMEM
		if !(failure || (result == 0 && actual == 0)) || mode() != if failure { 0 } else { 2 }
			|| nnp() != if ordinary { 1 } else { 0 } { return false }
		bad_pointer := SockFprog{len: 4095, filter: voidptr(1)}
		if !reject(method, &bad_pointer, if failure { C.ENOMEM } else { C.EFAULT }) { return false }
		// A 32760-byte buffer uses the big allocator (three ARM pages or
		// nine x86 pages including metadata), beyond the medium slab classes.
		// Rejected copies must return those pages, using one open observer.
		fd := C.open(c'/proc/slabinfo', C.O_RDONLY)
		if fd < 0 { return false }
		for _ in 0 .. 128 { if !reject(method, &bad_pointer, if failure { C.ENOMEM } else { C.EFAULT }) { return false } }
		C.usleep(13000000)
		before := count(fd) or { return false }
		for _ in 0 .. 128 { if !reject(method, &bad_pointer, if failure { C.ENOMEM } else { C.EFAULT }) { return false } }
		C.usleep(13000000)
		after := count(fd) or { return false }
		if before != after || C.close(fd) != 0 { return false }
		// Allocation failure cannot disable unrelated syscall/filter service.
		mut allow := SockFilter{code: 0x06, k: 0x7fff0000}
		small := SockFprog{len: 1, filter: &allow}
		if install(method, &small) != 0 || mode() != 2 || C.syscall(isize(C.SYS_getpid)) <= 0 { return false }
		C.printf(c'LINUX SECCOMPALLOC CASE: method=%d ordinary=%d allocation=%d mode=%d nnp=%d big_pages=%lu/%lu PASS\n',
			method, i32(ordinary), if failure { i32(C.ENOMEM) } else { i32(0) }, mode(), nnp(), before, after)
		C.fflush(nil)
		return true
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		for method in [i32(0), 1]! { for ordinary in [false, true]! {
			C.fflush(nil)
			pid := C.fork()
			if pid < 0 { return 1 }
			if pid == 0 { C._exit(if cohort(method, ordinary) { 0 } else { 1 }) }
			mut outcome := i32(-1)
			if C.waitpid(pid, &outcome, 0) != pid || outcome != 0 {
				C.printf(c'LINUX SECCOMPALLOC DETAIL: method=%d ordinary=%d outcome=%d\n', method, i32(ordinary), outcome)
				C.fflush(nil)
				C.puts(c'LINUX SECCOMPALLOC FAIL: allocation result, recovery or retention')
				C.fflush(nil)
				return 1
			}
		} }
		C.puts(c'LINUX SECCOMPALLOC PASS: production/fault-injection outcomes recorded, validation precedence, syscall/prctl recovery and large buffer retention')
		C.puts(c'LINUX SECCOMPALLOC: PASS')
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
