// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module seccompinstallfixture

#define __EXPORTED_HEADERS__
#include <errno.h>
#include <grp.h>
#include <linux/capability.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct SockFilter { code u16 jt u8 jf u8 k u32 }
struct SockFprog { len u16 filter voidptr }
struct C.__user_cap_header_struct { mut: version u32 pid i32 }
struct C.__user_cap_data_struct { mut: effective u32 permitted u32 inheritable u32 }
__global ( checks i32 )

fn C.syscall(isize, ...) isize
fn C.prctl(i32, ...) i32
fn C.__errno_location() &i32
fn C.mmap(voidptr, usize, i32, i32, i32, isize) voidptr
fn C.mprotect(voidptr, usize, i32) i32
fn C.munmap(voidptr, usize) i32
fn C.sysconf(i32) isize
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memset(voidptr, i32, usize) voidptr
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

fn mode() i32 { return unsafe { C.prctl(C.PR_GET_SECCOMP, usize(0), usize(0), usize(0), usize(0)) } }
fn nnp() i32 { return unsafe { C.prctl(C.PR_GET_NO_NEW_PRIVS, usize(0), usize(0), usize(0), usize(0)) } }
fn install(method i32, flags u32, program voidptr) isize {
	return unsafe {
		if method == 0 { C.syscall(isize(C.SYS_seccomp), isize(1), usize(flags), program) }
		else { isize(C.prctl(C.PR_SET_SECCOMP, usize(2), program, usize(0), usize(0))) }
	}
}
fn check(method i32, flags u32, program voidptr, wanted i32) bool {
	unsafe {
		old_mode := mode(); old_nnp := nnp()
		e := C.__errno_location(); *e = 0
		result := install(method, flags, program)
		actual := *e
		if result != if wanted == 0 { isize(0) } else { isize(-1) }
			|| actual != wanted || nnp() != old_nnp || mode() != if wanted == 0 { 2 } else { old_mode } {
			C.printf(c'LINUX SECCOMPINSTALL DETAIL: method=%d flags=%u result=%ld/%d expected=%d mode=%d/%d nnp=%d/%d\n',
				method, flags, result, actual, wanted, mode(), old_mode, nnp(), old_nnp)
			C.fflush(nil)
			return false
		}
		checks++
		return true
	}
}
fn privileges(kind i32) bool {
	unsafe {
		mut header := C.__user_cap_header_struct{version: 0x20080522}
		mut data := [2]C.__user_cap_data_struct{}
		if C.syscall(isize(C.SYS_capget), &header, &data[0]) != 0 || data[0].effective & (u32(1) << 21) == 0 { return false }
		if kind in [1, 4]! {
			data[0].effective &= ~(u32(1) << 21)
			data[0].permitted &= ~(u32(1) << 21)
			if C.syscall(isize(C.SYS_capset), &header, &data[0]) != 0 { return false }
		}
		if kind in [2, 3]! && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { return false }
		if kind in [3, 4]! && C.prctl(C.PR_SET_NO_NEW_PRIVS, usize(1), usize(0), usize(0), usize(0)) != 0 { return false }
		return mode() == 0 && nnp() == if kind in [3, 4]! { 1 } else { 0 }
	}
}
fn probes(kind i32, page usize) bool {
	unsafe {
		if !privileges(kind) { return false }
		authorized := kind in [0, 3, 4]!
		base := C.mmap(nil, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if base == voidptr(C.MAP_FAILED) { return false }
		defer { C.munmap(base, page * 2) }
		if C.mprotect(voidptr(usize(base) + page), page, C.PROT_NONE) != 0 { return false }
		mut allow := SockFilter{code: 0x06, k: 0x7fff0000}
		mut malformed := SockFilter{code: 0xffff}
		for method in [i32(0), 1]! {
			for pointer in [voidptr(nil), voidptr(1), voidptr(usize(base) + page), voidptr(usize(base) + page - 8)]! {
				if !check(method, 0, pointer, C.EFAULT) { return false }
			}
			for length in [u16(0), 4097, 65535]! {
				for pointer in [voidptr(nil), voidptr(1), voidptr(&allow)]! {
					program := SockFprog{len: length, filter: pointer}
					if !check(method, 0, &program, C.EINVAL) { return false }
				}
			}
			for pointer in [voidptr(nil), voidptr(1), voidptr(usize(base) + page), voidptr(usize(base) + page - 4)]! {
				program := SockFprog{len: 1, filter: pointer}
				if !check(method, 0, &program, if authorized { C.EFAULT } else { C.EACCES }) { return false }
			}
			program := SockFprog{len: 1, filter: &malformed}
			if !check(method, 0, &program, if authorized { C.EINVAL } else { C.EACCES }) { return false }
			// Readonly sock_fprog is a read-only input, with all 16 bytes required.
			exact := voidptr(usize(base) + page - 16)
			faulting := SockFprog{len: 1, filter: voidptr(1)}
			C.memcpy(exact, &faulting, 16)
			mut saved := [16]u8{}
			C.memcpy(&saved[0], exact, 16)
			if C.mprotect(base, page, C.PROT_READ) != 0 || !check(method, 0, exact, if authorized { C.EFAULT } else { C.EACCES })
				|| C.memcmp(exact, &saved[0], 16) != 0 || C.mprotect(base, page, C.PROT_READ | C.PROT_WRITE) != 0 { return false }
		}
		for flags in [u32(0x80000000), 0x40000000]! {
			for pointer in [voidptr(nil), voidptr(1)]! {
				if !check(0, flags, pointer, C.EINVAL) { return false }
			}
		}
		// Repeated verifier/copy/permission rejection must not install a head.
		for _ in 0 .. 200 {
			for method in [i32(0), 1]! {
				program := SockFprog{len: 1, filter: &malformed}
				if !check(method, 0, &program, if authorized { C.EINVAL } else { C.EACCES }) { return false }
			}
		}
		for method in [i32(0), 1]! {
			// Valid readable programs prove both CAP_SYS_ADMIN and NNP bypasses.
			program := SockFprog{len: 1, filter: &allow}
			if !check(method, 0, &program, if authorized { 0 } else { C.EACCES }) { return false }
			// Exact instruction size at a protected boundary, readonly and unaligned
			// headers, and nonzero sock_fprog padding are accepted by Linux.
			instruction := voidptr(usize(base) + page - 8)
			C.memcpy(instruction, &allow, 8)
			mut bytes := [32]u8{}
			C.memset(&bytes[0], 0xa5, 32)
			packed := SockFprog{len: 1, filter: instruction}
			C.memcpy(&bytes[1], &packed.len, 2)
			C.memcpy(&bytes[9], &packed.filter, 8)
			if C.mprotect(base, page, C.PROT_READ) != 0 || !check(method, 0, &bytes[1], if authorized { 0 } else { C.EACCES })
				|| C.mprotect(base, page, C.PROT_READ | C.PROT_WRITE) != 0 { return false }
		}
		return true
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		page := C.sysconf(C._SC_PAGESIZE)
		if page <= 0 { return 1 }
		C.printf(c'LINUX SECCOMPINSTALL PAGE: bytes=%ld\n', page)
		for kind in 0 .. 5 {
			C.fflush(nil)
			pid := C.fork()
			if pid < 0 { return 1 }
			if pid == 0 {
				if !probes(i32(kind), usize(page)) { C._exit(1) }
				C.printf(c'LINUX SECCOMPINSTALL CASE: kind=%d checks=%d PASS\n', i32(kind), checks)
				C.fflush(nil)
				C._exit(0)
			}
			mut outcome := i32(-1)
			if C.waitpid(pid, &outcome, 0) != pid || outcome != 0 {
				C.printf(c'LINUX SECCOMPINSTALL DETAIL: kind=%d outcome=%d\n', i32(kind), outcome)
				C.fflush(nil)
				C.puts(c'LINUX SECCOMPINSTALL FAIL: installation ordering or state')
				C.fflush(nil)
				return 1
			}
		}
		C.puts(c'LINUX SECCOMPINSTALL PASS: header/length before authorization, permission before instruction copy/verifier, syscall/prctl, CAP_SYS_ADMIN/NNP, exact protected boundaries and unchanged rejection state')
		C.puts(c'LINUX SECCOMPINSTALL: PASS')
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
