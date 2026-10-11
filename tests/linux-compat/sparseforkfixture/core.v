// SPDX-License-Identifier: GPL-2.0-or-later
module sparseforkfixture

#include <errno.h>
#include <stdio.h>
#include <sys/mman.h>
#include <sys/sysinfo.h>
#include <sys/wait.h>
#include <unistd.h>

struct C.sysinfo {
	freeram usize
	mem_unit u32
}

fn C.sysinfo(&C.sysinfo) i32
fn C.sysconf(i32) isize
fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr
fn C.munmap(voidptr, usize) i32
fn C.madvise(voidptr, usize, i32) i32
fn C.pipe(&i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) bool
fn C.WEXITSTATUS(i32) i32
fn C._exit(i32)
fn C.__errno_location() &i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

fn free_bytes() u64 {
	mut info := C.sysinfo{}
	if C.sysinfo(&info) != 0 { return 0 }
	return u64(info.freeram) * u64(info.mem_unit)
}

fn child_work(maps &voidptr, wipe &u8, length usize) i32 {
	unsafe {
		if wipe[0] != 0 { return 1 }
		wipe[0] = 77
		for i in 0 .. 512 {
			mut data := &u8(maps[i])
			if i % 16 == 0 {
				if data[0] != 42 { return 2 }
				data[0] = 19
			} else if i % 32 == 1 {
				// First access after fork must fault in zero pages independently.
				if data[0] != 0 { return 3 }
				data[0] = 23
			}
			if C.munmap(maps[i], length) != 0 { return 4 }
		}
		return 0
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		page := usize(C.sysconf(C._SC_PAGESIZE))
		if page !in [usize(4096), 16384]! { return 1 }
		length := usize(64 * 1024 * 1024)
		mut maps := [512]voidptr{}
		for i in 0 .. maps.len {
			maps[i] = C.mmap(nil, length, C.PROT_READ | C.PROT_WRITE,
				C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
			if maps[i] == voidptr(-1) { C.puts(c'LINUX SPARSEFORK FAIL: reserve mappings'); return 1 }
			if i % 16 == 0 { (&u8(maps[i]))[0] = 42 }
		}
		mut wipe := &u8(C.mmap(nil, length, C.PROT_READ | C.PROT_WRITE,
			C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
		if voidptr(wipe) == voidptr(-1) { return 1 }
		wipe[0] = 99
		if C.madvise(wipe, length, 18) != 0 { return 1 } // MADV_WIPEONFORK
		mut ready := [2]i32{}
		mut resume := [2]i32{}
		if C.pipe(&ready[0]) != 0 || C.pipe(&resume[0]) != 0 { return 1 }
		before := free_bytes()
		child := C.fork()
		if child < 0 {
			C.printf(c'LINUX SPARSEFORK FAIL: fork errno=%d\n', *C.__errno_location())
			return 1
		}
		if child == 0 {
			C.close(ready[0]); C.close(resume[1])
			mut token := u8(0)
			if C.write(ready[1], c'x', 1) != 1 || C.read(resume[0], &token, 1) != 1 { C._exit(5) }
			C._exit(child_work(&maps[0], wipe, length))
		}
		C.close(ready[1]); C.close(resume[0])
		mut token := u8(0)
		if C.read(ready[0], &token, 1) != 1 { return 1 }
		after := free_bytes()
		kept := if before > after { before - after } else { 0 }
		// An isolated guest must not allocate a page-table root for each empty
		// private reservation. Allow metadata, resident COW tables and stacks.
		limit := u64(maps.len) * u64(page) / 2 + 2 * 1024 * 1024
		C.printf(c'LINUX SPARSEFORK: page=%lu ranges=%d before=%lu after=%lu fork_bytes=%lu limit=%lu\n',
			page, i32(maps.len), before, after, kept, limit)
		if C.write(resume[1], c'x', 1) != 1 { return 1 }
		C.close(ready[0]); C.close(resume[1])
		mut status := i32(0)
		if C.waitpid(child, &status, 0) != child || !C.WIFEXITED(status)
			|| C.WEXITSTATUS(status) != 0 { C.puts(c'LINUX SPARSEFORK FAIL: child zero/COW/unmap'); return 1 }
		if before == 0 || after == 0 || kept > limit {
			C.puts(c'LINUX SPARSEFORK FAIL: untouched reservations allocate page roots')
			return 1
		}
		if wipe[0] != 99 { return 1 }
		for i in 0 .. maps.len {
			if i % 16 == 0 && (&u8(maps[i]))[0] != 42 { return 1 }
			if i % 32 == 1 && (&u8(maps[i]))[0] != 0 { return 1 }
			if C.munmap(maps[i], length) != 0 { return 1 }
		}
		if C.munmap(wipe, length) != 0 { return 1 }
		C.puts(c'LINUX SPARSEFORK: PASS')
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
