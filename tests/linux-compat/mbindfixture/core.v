// SPDX-License-Identifier: GPL-2.0-or-later
module mbindfixture

#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.__errno_location() &i32
fn C._exit(i32)
fn C.fflush(voidptr) i32
fn C.fork() i32
fn C.madvise(voidptr, u64, i32) i32
fn C.mincore(voidptr, u64, &u8) i32
fn C.mmap(voidptr, u64, i32, i32, i32, i64) voidptr
fn C.mprotect(voidptr, u64, i32) i32
fn C.munmap(voidptr, u64) i32
fn C.pause() i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.strcmp(&char, &char) i32
fn C.syscall(i64, ...) i64
fn C.sysconf(i32) i64
fn C.waitpid(i32, &i32, i32) i32

const default_mode = i32(0)
const preferred = i32(1)
const bind_mode = i32(2)
const interleave = i32(3)
const local_mode = i32(4)
const address_flag = u64(2)
const strict_flag = u64(1)
const sparse_length = u64(64 * 1024 * 1024)

fn need(ok bool, label &char) {
	if ok { return }
	unsafe {
		C.printf(c'LINUX MBIND FAIL: %s errno=%d\n', label, *C.__errno_location())
		C.fflush(nil)
		C._exit(1)
	}
}

fn result(ret i64) i64 {
	unsafe { return if ret < 0 { -i64(*C.__errno_location()) } else { ret } }
}

fn bind_range(base u64, bytes u64, mode i32, mask voidptr, maxnode u64, flags u64) i64 {
	return result(C.syscall(i64(C.SYS_mbind), base, bytes, i64(mode), mask, maxnode, flags))
}

fn bind_mask(base u64, bytes u64, mode i32, mask u64, flags u64) i64 {
	return bind_range(base, bytes, mode, unsafe { &mask }, 64, flags)
}

fn get_policy(address u64, flags u64) (i32, u64) {
	unsafe {
		mut mode := i32(-1)
		mut mask := ~u64(0)
		need(C.syscall(i64(C.SYS_get_mempolicy), &mode, &mask, u64(64), address, flags) == 0,
			c'read policy')
		return mode, mask
	}
}

fn policy_is(address u64, flags u64, want_mode i32, want_mask u64) bool {
	mode, mask := get_policy(address, flags)
	return mode == want_mode && mask == want_mask
}

fn new_region(length u64) u64 {
	base := C.mmap(unsafe { nil }, length, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	need(base != voidptr(-1), c'map anonymous pages')
	return u64(base)
}

fn page_node(address u64) i32 {
	node, _ := get_policy(address, address_flag | 1)
	return node
}

fn discard_pages(base u64, length u64, page u64) {
	unsafe {
		need(C.madvise(voidptr(base), length, C.MADV_DONTNEED) == 0, c'discard prefaulted pages')
		for address := base; address < base + length; address += page {
			mut resident := u8(255)
			need(C.mincore(voidptr(address), page, &resident) == 0 && resident & 1 == 0,
				c'future placement starts with an absent page')
		}
	}
}

fn check_binding(page u64, other i32) {
	unsafe {
		mut node0 := u64(1)
		need(C.syscall(i64(C.SYS_set_mempolicy), i64(bind_mode), &node0, u64(64)) == 0, c'bind task to node 0')
		base := new_region(sparse_length)
		*(&u8(base)) = 7
		mask := u64(1) << other
		target := base + page
		discard_pages(target, 3 * page, page)
		need(bind_mask(target, 3 * page - 1, bind_mode, mask, 0) == 0, c'bind interior pages with rounded length')
		need(policy_is(0, 0, bind_mode, 1), c'address binding leaves task policy alone')
		need(policy_is(base, address_flag, default_mode, 0)
			&& policy_is(target + 3 * page, address_flag, default_mode, 0), c'adjacent pages keep their policies')
		need(policy_is(target + 2 * page, address_flag, bind_mode, mask), c'last rounded page is bound')
		*(&u8(target)) = 11
		need(page_node(base) == 0 && page_node(target) == other, c'faults use task and range policies')
		need(C.mprotect(voidptr(target + page), page, C.PROT_NONE) == 0, c'split bound range with mprotect')
		need(policy_is(target + page, address_flag, bind_mode, mask), c'protection split keeps policy')
		need(C.mprotect(voidptr(target + page), page, C.PROT_READ | C.PROT_WRITE) == 0, c'restore page protections')
		*(&u8(target + page)) = 12
		need(page_node(target + page) == other, c'restored page uses the bound node')

		child := C.fork()
		need(child >= 0, c'fork a bound mapping')
		if child == 0 {
			need(policy_is(target, address_flag, bind_mode, mask), c'child inherits range policy')
			*(&u8(target)) = 19
			need(page_node(target) == other, c'child copy-on-write uses bound node')
			need(bind_mask(target, page, default_mode, 0, 0) == 0
				&& policy_is(target, address_flag, default_mode, 0), c'child clears its policy')
			C._exit(0)
		}
		mut status := i32(-1)
		need(C.waitpid(child, &status, 0) == child && status == 0, c'child checks complete')
		need(*(&u8(target)) == 11 && policy_is(target, address_flag, bind_mode, mask),
			c'child changes do not affect parent')

		need(C.munmap(voidptr(target + page), page) == 0, c'unmap middle page of bound range')
		need(bind_mask(target, 3 * page, preferred, 1, 0) == -C.EFAULT
			&& policy_is(target, address_flag, bind_mode, mask), c'hole rejects nondefault change')
		need(bind_mask(target, 3 * page, default_mode, 0, 0) == 0
			&& policy_is(target, address_flag, default_mode, 0)
			&& policy_is(target + 2 * page, address_flag, default_mode, 0), c'clear policies across a hole')
		need(C.munmap(voidptr(base), sparse_length) == 0, c'release split mapping')
	}
}

fn check_placement(page u64, other i32) {
	unsafe {
		base := new_region(sparse_length)
		*(&u8(base)) = 20
		if other == 1 {
			need(bind_mask(base, page, bind_mode, 2, strict_flag) == -C.EIO
				&& policy_is(base, address_flag, default_mode, 0), c'strict binding rejects a misplaced page')
		}
		mask := u64(1) << other
		need(bind_mask(base, page, bind_mode, mask, 0) == 0 && page_node(base) == 0,
			c'ordinary binding leaves resident page on its original node')
		target := new_region(page)
		moved := C.syscall(i64(C.SYS_mremap), base, page, page, u64(3), target)
		need(moved == i64(target) && *(&u8(target)) == 20
			&& policy_is(target, address_flag, bind_mode, mask), c'moving remap carries data and policy')
		need(C.munmap(voidptr(target), page) == 0, c'release remapped page')

		interleaved := base + 2 * page
		discard_pages(interleaved, 3 * page, page)
		allowed := if other == 0 { u64(1) } else { u64(3) }
		need(bind_mask(interleaved, 3 * page, interleave, allowed, 0) == 0, c'interleave a shifted range')
		for index in [u64(2), u64(0), u64(1)]! {
			address := interleaved + index * page
			*(&u8(address)) = 1
			expected := if other == 0 { i32(0) } else { i32((address / page) & 1) }
			need(page_node(address) == expected, c'interleave placement follows page index')
		}
		need(bind_range(interleaved, page, preferred, nil, 0, 0) == 0
			&& policy_is(interleaved, address_flag, local_mode, 0), c'preferred with empty mask becomes local')
		need(C.munmap(voidptr(base), sparse_length) == 0, c'release interleaved mapping')
		if other == 1 { C.puts(c'LINUX MBIND NUMA: PASS') }
	}
}

fn check_errors(page u64, reference bool) {
	unsafe {
		base := new_region(page)
		need(bind_range(base + 1, page, bind_mode, voidptr(1), 64, 0) == -C.EFAULT,
			c'faulting mask precedes unaligned address')
		need(bind_range(base + 1, page, bind_mode, voidptr(1), 64, 0x80000000) == -C.EFAULT,
			c'faulting mask precedes invalid flags')
		need(bind_mask(base + 1, page, bind_mode, 1, 0) == -C.EINVAL, c'reject unaligned address')
		need(bind_mask(base, page, bind_mode, 1, 8) == -C.EINVAL, c'reject unknown flags')
		need(bind_range(base, 0, bind_mode, nil, 0, 0) == 0, c'empty interval skips policy validation')
		need(bind_mask(base, page, default_mode, 1, 0) == -C.EINVAL, c'default requires empty mask')
		need(bind_range(base, page, bind_mode, voidptr(1), 1, 0) == -C.EINVAL, c'maxnode one names zero bits')
		if !reference {
			need(bind_mask(base, page, bind_mode, 1, 2) == -C.EOPNOTSUPP, c'explicit migration is unavailable')
		}
		need(C.munmap(voidptr(base), page) == 0, c'release error test mapping')
		need(bind_range(base, page, default_mode, nil, 0, 0) == -C.EFAULT, c'entirely unmapped range faults')
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		reference := argc > 1 && C.strcmp(argv[1], c'--reference') == 0
		page_size := C.sysconf(C._SC_PAGESIZE)
		need(page_size >= 4096, c'get native page size')
		page := u64(page_size)
		_, allowed := get_policy(0, 4)
		other := if allowed & 2 != 0 { i32(1) } else { i32(0) }
		check_binding(page, other)
		check_placement(page, other)
		check_errors(page, reference)
		C.puts(c'LINUX MBIND SUMMARY: ranges=checked placement=checked inheritance=checked')
		C.puts(if reference { c'LINUX MBIND REFERENCE: PASS' } else { c'LINUX MBIND: PASS' })
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
