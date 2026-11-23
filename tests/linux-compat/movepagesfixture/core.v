// SPDX-License-Identifier: GPL-2.0-or-later
module movepagesfixture

#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.__errno_location() &i32
fn C._exit(i32)
fn C.close(i32) i32
fn C.fflush(voidptr) i32
fn C.fork() i32
fn C.getpid() i32
fn C.getppid() i32
fn C.mincore(voidptr, u64, &u8) i32
fn C.mmap(voidptr, u64, i32, i32, i32, i64) voidptr
fn C.mprotect(voidptr, u64, i32) i32
fn C.munmap(voidptr, u64) i32
fn C.pause() i32
fn C.pipe(&i32) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.read(i32, voidptr, u64) i64
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.strcmp(&char, &char) i32
fn C.syscall(i64, ...) i64
fn C.sysconf(i32) i64
fn C.waitpid(i32, &i32, i32) i32
fn C.write(i32, voidptr, u64) i64

const canary = i32(0x5a5a5a5a)

fn need(ok bool, label &char) {
	if ok { return }
	unsafe {
		C.printf(c'LINUX MOVEPAGES FAIL: %s errno=%d\n', label, *C.__errno_location())
		C.fflush(nil)
		C._exit(1)
	}
}

fn move_pages(pid i32, count u64, addresses voidptr, nodes voidptr, statuses voidptr, flags u64) i64 {
	unsafe {
		ret := C.syscall(i64(C.SYS_move_pages), i64(pid), count, addresses, nodes, statuses, flags)
		return if ret < 0 { -i64(*C.__errno_location()) } else { ret }
	}
}

fn region(length u64) u64 {
	base := C.mmap(unsafe { nil }, length, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	need(base != voidptr(-1), c'map anonymous range')
	return u64(base)
}

fn check_locations(page u64) (u64, i32) {
	unsafe {
		base := region(4 * page)
		*(&u8(base)) = 1
		*(&u8(base + 2 * page)) = 2
		// An explicit reservation stays unpopulated even on kernels that
		// commit small writable anonymous mappings eagerly.
		absent := voidptr(base + page)
		need(C.mmap(absent, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS | C.MAP_FIXED,
			-1, 0) == absent, c'reserve unpopulated page')
		need(C.mprotect(voidptr(base + 2 * page), page, C.PROT_NONE) == 0, c'protect resident page')
		need(C.munmap(voidptr(base + 3 * page), page) == 0, c'unmap last page')

		mut addresses := [base, base + 1, base + page, base + 2 * page, base + 3 * page, ~u64(0)]!
		mut statuses := [canary, canary, canary, canary, canary, canary, canary]!
		need(move_pages(0, 6, &addresses[0], nil, &statuses[0], 0) == 0, c'query mixed pages')
		node := statuses[0]
		need(node >= 0 && statuses[1] == node, c'resident page and unaligned address have the same node')
		need(statuses[2] == -C.ENOENT, c'unpopulated mapping returns ENOENT')
		need(statuses[3] >= 0, c'resident PROT_NONE page has a node')
		need(statuses[4] == -C.EFAULT && statuses[5] == -C.EFAULT, c'holes return EFAULT')
		need(statuses[6] == canary, c'copy exactly one status per address')
		mut resident := u8(255)
		need(C.mincore(voidptr(base + page), page, &resident) == 0 && resident & 1 == 0,
			c'query does not populate the absent page')
		need(C.munmap(voidptr(base + page), 2 * page) == 0, c'release adjacent ranges')
		return base, node
	}
}

fn check_chunks(page u64, resident u64, node i32) {
	unsafe {
		input := region(2 * page)
		need(C.mprotect(voidptr(input + page), page, C.PROT_NONE) == 0, c'guard input')
		addresses := &u64(input + page - 16 * sizeof(u64))
		for i in 0 .. 16 {
			addresses[i] = resident
		}
		mut statuses := [17]i32{init: canary}
		need(move_pages(0, 17, addresses, nil, &statuses[0], 0) == -C.EFAULT, c'fault in later input chunk')
		for i in 0 .. 16 {
			need(statuses[i] == node, c'earlier results survive input fault')
		}
		need(statuses[16] == canary, c'faulting input chunk leaves its output unchanged')
		need(C.munmap(voidptr(input), 2 * page) == 0, c'release guarded input')

		output := region(2 * page)
		need(C.mprotect(voidptr(output + page), page, C.PROT_NONE) == 0, c'guard output')
		locations := &i32(output + page - 16 * sizeof(i32))
		mut good := [17]u64{init: resident}
		for i in 0 .. 16 {
			locations[i] = canary
		}
		need(move_pages(0, 17, &good[0], nil, locations, 0) == -C.EFAULT, c'fault in later output chunk')
		for i in 0 .. 16 {
			need(locations[i] == node, c'earlier results survive output fault')
		}
		need(C.munmap(voidptr(output), 2 * page) == 0, c'release guarded output')
	}
}

fn check_processes(resident u64, node i32, reference bool) {
	unsafe {
		need(move_pages(-1, 0, nil, nil, nil, 1) == -C.EINVAL, c'flags precede target lookup')
		need(move_pages(-1, 0, nil, nil, nil, 0) == -C.ESRCH, c'unknown PID')
		need(move_pages(0, 0, voidptr(1), voidptr(1), voidptr(1), u64(1) << 32) == 0,
			c'zero count skips vectors and flags use low word')
		need(move_pages(0, 0, nil, nil, nil, 2) == 0, c'MPOL_MF_MOVE accepted for query')
		if !reference {
			need(move_pages(0, 1, nil, voidptr(1), nil, 0) == -C.EOPNOTSUPP, c'migration unavailable')
		}

		mut gate := [2]i32{}
		need(C.pipe(&gate[0]) == 0, c'open child gate')
		child := C.fork()
		need(child >= 0, c'fork query target')
		if child == 0 {
			C.close(gate[1])
			mut token := u8(0)
			need(C.read(gate[0], &token, 1) == 1, c'receive child gate')
			need(C.setgid(1000) == 0 && C.setuid(1000) == 0, c'drop child credentials')
			need(move_pages(C.getppid(), 0, nil, nil, nil, 0) == -C.EPERM,
				c'unprivileged query of a different UID')
			need(move_pages(-1, 0, nil, nil, nil, 4) == -C.EPERM,
				c'MPOL_MF_MOVE_ALL capability precedes lookup even for empty query')
			need(move_pages(0, 0, nil, nil, nil, 0) == 0, c'unprivileged self query')
			C._exit(0)
		}
		C.close(gate[0])
		mut address := resident
		mut result := canary
		need(move_pages(C.getpid(), 1, &address, nil, &result, 0) == 0 && result == node,
			c'explicit self PID')
		need(move_pages(child, 1, &address, nil, &result, 0) == 0 && result == node,
			c'query a resident page in a live child')
		mut token := u8(1)
		need(C.write(gate[1], &token, 1) == 1, c'release child gate')
		C.close(gate[1])
		mut status := i32(-1)
		need(C.waitpid(child, &status, 0) == child && status == 0, c'child checks passed')
		need(move_pages(child, 0, nil, nil, nil, 0) == -C.ESRCH, c'reaped PID unavailable')
	}
}

fn check_numa(page u64) {
	unsafe {
		mut allowed := [32]u64{}
		need(C.syscall(i64(C.SYS_get_mempolicy), nil, &allowed[0], u64(2048), u64(0), u64(4)) == 0,
			c'read allowed nodes')
		if allowed[0] & 3 != 3 { return }
		mut addresses := [2]u64{}
		for i in 0 .. 2 {
			mut mask := u64(1) << i
			need(C.syscall(i64(C.SYS_set_mempolicy), i64(2), &mask, u64(64)) == 0, c'bind allocations to node')
			addresses[i] = region(page)
			*(&u8(addresses[i])) = 1
		}
		need(C.syscall(i64(C.SYS_set_mempolicy), i64(0), nil, u64(0)) == 0, c'restore default policy')
		mut statuses := [canary, canary]!
		need(move_pages(0, 2, &addresses[0], nil, &statuses[0], 0) == 0
			&& statuses[0] == 0 && statuses[1] == 1, c'query physical pages allocated on distinct nodes')
		need(C.munmap(voidptr(addresses[0]), page) == 0 && C.munmap(voidptr(addresses[1]), page) == 0,
			c'release node-bound pages')
		C.puts(c'LINUX MOVEPAGES NUMA: PASS')
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		reference := argc > 1 && C.strcmp(argv[1], c'--reference') == 0
		page_size := C.sysconf(C._SC_PAGESIZE)
		need(page_size >= 4096, c'get native page size')
		page := u64(page_size)
		resident, node := check_locations(page)
		check_chunks(page, resident, node)
		check_processes(resident, node, reference)
		check_numa(page)
		need(C.munmap(voidptr(resident), page) == 0, c'release resident page')
		C.puts(c'LINUX MOVEPAGES SUMMARY: locations=checked permissions=checked chunks=checked')
		C.puts(if reference { c'LINUX MOVEPAGES REFERENCE: PASS' } else { c'LINUX MOVEPAGES: PASS' })
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
