// SPDX-License-Identifier: GPL-2.0-or-later
module budgetfixture

#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <stdio.h>
#include <sys/mman.h>
#include <unistd.h>

fn C.open(&char, i32, ...) i32
fn C.pread(i32, voidptr, usize, i64) isize
fn C.close(i32) i32
fn C.sysconf(i32) isize
fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr
fn C.munmap(voidptr, usize) i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.__errno_location() &i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

struct Counters {
	limit u64
	owner_limit u64
	charged u64
	denied u64
	reasons [6]u64
	requested u64
	global_bytes u64
	owner_bytes u64
	owner_mapping bool
}

// Parsing and reading use fixed storage: a rejected mmap must not prevent
// its own diagnostic by allocating another mapping or opening a descriptor.
fn line_at(buffer &u8, length int, position int, prefix string) bool {
	if position + prefix.len > length { return false }
	unsafe {
		for i in 0 .. prefix.len {
			if buffer[position + i] != prefix[i] { return false }
		}
	}
	return true
}

fn field(buffer &u8, length int, prefix string) ?u64 {
	unsafe {
		for position in 0 .. length {
			if position != 0 && buffer[position - 1] != `\n` { continue }
			if !line_at(buffer, length, position, prefix) { continue }
			mut index := position + prefix.len
			mut value := u64(0)
			mut digits := 0
			for index < length && buffer[index] >= `0` && buffer[index] <= `9` {
				value = value * 10 + u64(buffer[index] - `0`)
				index++; digits++
			}
			if digits == 0 || index >= length || buffer[index] != `\n` { return none }
			return value
		}
	}
	return none
}

fn has_line(buffer &u8, length int, text string) bool {
	unsafe {
		for i in 0 .. length {
			if (i == 0 || buffer[i - 1] == `\n`) && line_at(buffer, length, i, text) { return true }
		}
	}
	return false
}

fn counters(fd i32, evidence bool) ?Counters {
	unsafe {
	mut buffer := [4096]u8{}
	length := int(C.pread(fd, &buffer[0], 4096, 0))
	if length <= 0 || length >= buffer.len { return none }
	mut reasons := [6]u64{}
	for i, name in ['Denied.invalid: ', 'Denied.accounts: ', 'Denied.objects: ',
		'Denied.global: ', 'Denied.owner: ', 'Denied.cgroup: ']! {
		reasons[i] = field(&buffer[0], length, name)?
	}
	return Counters{
		limit: field(&buffer[0], length, 'Limit: ')?
		owner_limit: field(&buffer[0], length, 'OwnerLimit: ')?
		charged: field(&buffer[0], length, 'Charged: ')?
		denied: field(&buffer[0], length, 'Denied: ')?
		reasons: reasons
		requested: if evidence { field(&buffer[0], length, 'LastDeniedRequested: ')? } else { 0 }
		global_bytes: if evidence { field(&buffer[0], length, 'LastDeniedGlobalBytes: ')? } else { 0 }
		owner_bytes: if evidence { field(&buffer[0], length, 'LastDeniedOwnerBytes: ')? } else { 0 }
		owner_mapping: has_line(&buffer[0], length, 'LastDenied: owner\n')
			&& has_line(&buffer[0], length, 'LastDeniedKind: mapping\n')
	}
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		if C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 { return 1 }
		mut maps := [16384]voidptr{}
		length := usize(C.sysconf(C._SC_PAGESIZE)) * 4
		C.puts(c'LINUX BUDGET: ordinary-user mapping pressure and recovery')
		fd := C.open(c'/proc/kernel-resources', C.O_RDONLY, 0)
		if fd < 0 { return 1 }
		initial := counters(fd, false) or {
			C.puts(c'LINUX BUDGET FAIL: missing denial reason counters')
			return 1
		}
		mut count := 0
		mut failure := i32(0)
		for count < maps.len {
			ptr := C.mmap(nil, length, C.PROT_READ | C.PROT_WRITE,
				C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
			if ptr == voidptr(-1) { failure = *C.__errno_location(); break }
			maps[count] = ptr
			count++
		}
		if failure != C.ENOMEM || count == 0 { return 1 }
		allocated := count
		// pread itself reserves kernel scratch space. Release one mapping
		// first; the rejected reservation must retain its pre-rollback usage.
		count--
		if C.munmap(maps[count], length) != 0 { return 1 }
		pressure := counters(fd, true) or { C.puts(c'LINUX BUDGET FAIL: rejected reservation evidence'); return 1 }
		if !pressure.owner_mapping
			|| pressure.denied != initial.denied + 1 || pressure.reasons[4] != initial.reasons[4] + 1
			|| pressure.requested == 0 || pressure.owner_bytes + pressure.requested <= pressure.owner_limit
			|| pressure.global_bytes < pressure.owner_bytes || pressure.global_bytes > pressure.limit {
			C.puts(c'LINUX BUDGET FAIL: exact owner-limit refusal')
			return 1
		}
		for i in 0 .. 6 {
			if i != 4 && pressure.reasons[i] != initial.reasons[i] { return 1 }
		}
		for i in 0 .. count { if C.munmap(maps[i], length) != 0 { return 1 } }
		retired := counters(fd, true) or { return 1 }
		if retired.charged > initial.charged + 65536 || retired.owner_bytes != pressure.owner_bytes
			|| retired.global_bytes != pressure.global_bytes || retired.denied != pressure.denied { return 1 }
		ptr := C.mmap(nil, length, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if ptr == voidptr(-1) || C.munmap(ptr, length) != 0 { return 1 }
		C.printf(c'LINUX BUDGET: mappings=%d request=%lu owner=%lu limit=%lu global=%lu recovered=%lu\n',
			allocated, pressure.requested, pressure.owner_bytes, pressure.owner_limit, pressure.global_bytes, retired.charged)
		C.close(fd)
		C.puts(c'LINUX BUDGET: PASS')
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
