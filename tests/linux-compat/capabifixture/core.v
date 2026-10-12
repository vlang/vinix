// SPDX-License-Identifier: GPL-2.0-or-later
module capabifixture

#define __EXPORTED_HEADERS__
#include <errno.h>
#include <grp.h>
#include <linux/capability.h>
#include <stdio.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct C.__user_cap_header_struct { mut: version u32 pid i32 }
struct C.__user_cap_data_struct { mut: effective u32 permitted u32 inheritable u32 }
fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.mmap(voidptr, usize, i32, i32, i32, isize) voidptr
fn C.mprotect(voidptr, usize, i32) i32
fn C.munmap(voidptr, usize) i32
fn C.sysconf(i32) isize
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

const v1 = u32(0x19980330)
const v2 = u32(0x20071026)
const v3 = u32(0x20080522)

fn call(set bool, header voidptr, data voidptr, expected_errno i32) bool {
	unsafe {
		errno_ptr := C.__errno_location()
		*errno_ptr = 0
		result := C.syscall(if set { isize(C.SYS_capset) } else { isize(C.SYS_capget) }, header, data)
		expected := if expected_errno == 0 { isize(0) } else { isize(-1) }
		if result != expected || *errno_ptr != expected_errno {
			C.printf(c'LINUX CAPABI FAIL: set=%d actual=%ld/%d expected=%ld/%d\n', i32(set), result, *errno_ptr, expected, expected_errno)
			return false
		}
		return true
	}
}
fn unchanged(wanted [2]C.__user_cap_data_struct) bool {
	unsafe {
		mut header := C.__user_cap_header_struct{ version: v3 }
		mut data := [2]C.__user_cap_data_struct{}
		if !call(false, &header, &data[0], 0) { return false }
		for i in 0 .. 2 {
			if data[i].effective != wanted[i].effective || data[i].permitted != wanted[i].permitted
				|| data[i].inheritable != wanted[i].inheritable { return false }
		}
		return true
	}
}
fn probes() bool {
	unsafe {
		for version in [u32(0), 1, u32(-1), v3 + 1]! {
			for pid in [i32(0), -1, 2147483647]! {
				mut header := C.__user_cap_header_struct{ version: version pid: pid }
				if !call(false, &header, nil, 0) || header.version != v3 || header.pid != pid { return false }
				for set in [false, true]! {
					for pointer in [voidptr(nil), voidptr(1)]! {
						if !set && pointer == nil { continue }
						header.version = version
						if !call(set, &header, pointer, C.EINVAL) || header.version != v3 || header.pid != pid { return false }
					}
				}
			}
		}
		for version in [v1, v2, v3]! {
			for pid in [i32(0), -1, 2147483647]! {
				mut header := C.__user_cap_header_struct{ version: version pid: pid }
				if !call(false, &header, nil, 0) || header.version != version || header.pid != pid { return false }
			}
		}
		return true
	}
}
fn boundaries(page usize) bool {
	unsafe {
		base := C.mmap(nil, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if base == voidptr(C.MAP_FAILED) { return false }
		defer { C.munmap(base, page * 2) }
		if C.mprotect(voidptr(usize(base) + page), page, C.PROT_NONE) != 0 { return false }
		mut word := &u32(voidptr(usize(base) + page - 4))
		for version in [v1, v2, v3]! {
			*word = version
			if !call(false, word, nil, 0) || *word != version || !call(false, word, voidptr(1), C.EFAULT)
				|| !call(true, word, nil, C.EFAULT) { return false }
		}
		for version in [u32(0), 1, u32(-1), v3 + 1]! {
			for set in [false, true]! {
				for pointer in [voidptr(nil), voidptr(1)]! {
					*word = version
					if !call(set, word, pointer, if !set && pointer == nil { 0 } else { C.EINVAL }) || *word != v3 { return false }
				}
			}
		}
		for version in [u32(0), v3]! {
			*word = version
			if C.mprotect(base, page, C.PROT_READ) != 0 { return false }
			if !call(false, word, nil, if version == 0 { C.EFAULT } else { 0 }) || *word != version
				|| !call(false, word, voidptr(1), C.EFAULT) || !call(true, word, nil, C.EFAULT) { return false }
			if C.mprotect(base, page, C.PROT_READ | C.PROT_WRITE) != 0 { return false }
		}
		partial := voidptr(usize(base) + page - 2)
		return call(false, partial, nil, C.EFAULT) && call(true, partial, nil, C.EFAULT)
	}
}
fn sized_child(version u32, page usize, original [2]C.__user_cap_data_struct) bool {
	unsafe {
		C.fflush(nil)
		pid := C.fork()
		if pid < 0 { return false }
		if pid == 0 {
			base := C.mmap(nil, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
			if base == voidptr(C.MAP_FAILED) || C.mprotect(voidptr(usize(base) + page), page, C.PROT_NONE) != 0 { C._exit(1) }
			entries := if version == v1 { 1 } else { 2 }
			data := &C.__user_cap_data_struct(voidptr(usize(base) + page - usize(entries) * 12))
			mut header := C.__user_cap_header_struct{ version: version }
			if !call(false, &header, data, 0) { C._exit(2) }
			for i in 0 .. entries {
				if data[i].effective != original[i].effective || data[i].permitted != original[i].permitted
					|| data[i].inheritable != original[i].inheritable { C._exit(3) }
			}
			if !call(true, &header, data, 0) { C._exit(4) }
			mut expected := [original[0], original[1]]!
			if version == v1 { expected[1] = C.__user_cap_data_struct{} }
			if !unchanged(expected) { C._exit(5) }
			if version != v1 {
				short := voidptr(usize(base) + page - 12)
				if !call(false, &header, short, C.EFAULT) || !call(true, &header, short, C.EFAULT) || !unchanged(expected) { C._exit(6) }
			}
			if C.munmap(base, page * 2) != 0 { C._exit(7) }
			C.printf(c'LINUX CAPABI CHILD: version=%u exact data size and capability state\n', version)
			C.fflush(nil)
			C._exit(0)
		}
		mut status := i32(-1)
		return C.waitpid(pid, &status, 0) == pid && status == 0 && unchanged(original)
	}
}
fn masks(original [2]C.__user_cap_data_struct) bool {
	unsafe {
		mut data := [original[0], original[1]]!
		data[1].effective |= u32(0xfffffe00)
		data[1].permitted |= u32(0xfffffe00)
		data[1].inheritable |= u32(0xfffffe00)
		for version in [v2, v3]! {
			mut header := C.__user_cap_header_struct{ version: version }
			if !call(true, &header, &data[0], 0) || !unchanged(original) { return false }
		}
		return true
	}
}
@[export: 'main']
pub fn run() i32 {
	unsafe {
		page := usize(C.sysconf(C._SC_PAGESIZE))
		if page < 4096 { return 1 }
		for level in 0 .. 2 {
			if level == 1 && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { return 1 }
			mut header := C.__user_cap_header_struct{ version: v3 }
			mut data := [2]C.__user_cap_data_struct{}
			if !call(false, &header, &data[0], 0) || !probes() || !boundaries(page) || !masks(data) { return 1 }
			for version in [v1, v2, v3]! { if !sized_child(version, page, data) { return 1 } }
			C.printf(c'LINUX CAPABI PASS: level=%ld discovery, protected words, data sizes and reserved masks\n', isize(level))
		}
		C.printf(c'LINUX CAPABI PASS: page=%lu version-only probes and legacy high-word truncation\n', page)
		C.puts(c'LINUX CAPABI: PASS')
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
