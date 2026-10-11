// SPDX-License-Identifier: GPL-2.0-or-later
module mapstoragefixture

#include <fcntl.h>
#include <grp.h>
#include <stdio.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.open(&char, i32, ...) i32
fn C.pread(i32, voidptr, usize, i64) isize
fn C.close(i32) i32
fn C.sysconf(i32) isize
fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr
fn C.munmap(voidptr, usize) i32
fn C.mprotect(voidptr, usize, i32) i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) bool
fn C.WEXITSTATUS(i32) i32
fn C._exit(i32)
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

fn charged(fd i32) ?u64 {
	unsafe {
		mut buffer := [4096]u8{}
		length := int(C.pread(fd, &buffer[0], buffer.len, 0))
		prefix := 'Charged: '
		if length <= prefix.len || length >= buffer.len { return none }
		for i in 0 .. length - prefix.len {
			if i != 0 && buffer[i - 1] != `\n` { continue }
			mut matches := true
			for j in 0 .. prefix.len {
				if buffer[i + j] != prefix[j] {
					matches = false
					break
				}
			}
			if !matches { continue }
			mut index := i + prefix.len
			mut value := u64(0)
			mut digits := 0
			for index < length && buffer[index] >= `0` && buffer[index] <= `9` {
				value = value * 10 + u64(buffer[index] - `0`)
				index++
				digits++
			}
			if digits > 0 && index < length && buffer[index] == `\n` { return value }
			return none
		}
	}
	return none
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		if C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 { return 1 }
		page := usize(C.sysconf(C._SC_PAGESIZE))
		if page !in [usize(4096), 16384]! { return 1 }
		fd := C.open(c'/proc/kernel-resources', C.O_RDONLY, 0)
		if fd < 0 { return 1 }
		initial := charged(fd) or { return 1 }
		length := usize(64 * 1024 * 1024)
		mut maps := [1024]voidptr{}
		mut retained := initial
		for cycle in 0 .. 2 {
			before := charged(fd) or { return 1 }
			for i in 0 .. maps.len {
				maps[i] = C.mmap(nil, length, C.PROT_READ | C.PROT_WRITE,
					C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
				if maps[i] == voidptr(-1) {
					C.puts(c'LINUX MAPSTORAGE FAIL: sparse reservation')
					return 1
				}
			}
			after := charged(fd) or { return 1 }
			limit := u64(maps.len) * 2048 + 131072
			C.printf(c'LINUX MAPSTORAGE: cycle=%d page=%lu maps=%d mapping_bytes=%lu limit=%lu\n',
				i32(cycle), page, i32(maps.len), after - before, limit)
			if after < before || after - before > limit {
				C.puts(c'LINUX MAPSTORAGE FAIL: fixed metadata overreservation')
				return 1
			}
			for i in 0 .. maps.len / 2 {
				if C.mprotect(voidptr(usize(maps[i]) + page), page, C.PROT_NONE) != 0 { return 1 }
			}
			split := charged(fd) or { return 1 }
			C.printf(c'LINUX MAPSTORAGE: cycle=%d split_bytes=%lu\n', i32(cycle), split - after)
			if split < after || split - after > u64(maps.len) * 1024 + 131072 {
				C.puts(c'LINUX MAPSTORAGE FAIL: split metadata bound')
				return 1
			}
			// Fork must preserve split aliases and independently fault sparse
			// pages. Changing the child's middle range must not alter the parent.
			child := C.fork()
			if child < 0 {
				C.puts(c'LINUX MAPSTORAGE FAIL: split fork')
				return 1
			}
			if child == 0 {
				mut data := &u8(maps[0])
				if data[0] != 0 || data[length - 1] != 0 { C._exit(2) }
				if C.mprotect(voidptr(usize(maps[0]) + page), page, C.PROT_READ | C.PROT_WRITE) != 0 {
					C._exit(3)
				}
				if data[page] != 0 { C._exit(5) }
				data[0] = 41
				data[page] = 42
				data[length - 1] = 43
				for i in 0 .. maps.len { if C.munmap(maps[i], length) != 0 { C._exit(4) } }
				C._exit(0)
			}
			mut status := i32(0)
			if C.waitpid(child, &status, 0) != child || !C.WIFEXITED(status) || C.WEXITSTATUS(status) != 0 {
				C.puts(c'LINUX MAPSTORAGE FAIL: child split/zero/unmap')
				return 1
			}
			mut data := &u8(maps[0])
			if C.mprotect(voidptr(usize(maps[0]) + page), page, C.PROT_READ) != 0 { return 1 }
			if data[0] != 0 || data[page] != 0 || data[length - 1] != 0 { return 1 }
			for i in 0 .. maps.len { if C.munmap(maps[i], length) != 0 { return 1 } }
			retired := charged(fd) or { return 1 }
			// Retained page-map vector capacity and empty resident tables stay
			// charged. A second cycle reuses them instead of accumulating storage.
			if retired > initial + 1048576 || (cycle != 0 && retired > retained + 65536) {
				C.puts(c'LINUX MAPSTORAGE FAIL: retained storage grows')
				return 1
			}
			retained = retired
			C.printf(c'LINUX MAPSTORAGE: cycle=%d split_bytes=%lu retained_bytes=%lu\n',
				i32(cycle), split - after, retired - initial)
		}
		C.close(fd)
		C.puts(c'LINUX MAPSTORAGE: PASS')
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
