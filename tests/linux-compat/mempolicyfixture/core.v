// SPDX-License-Identifier: GPL-2.0-or-later
module mempolicyfixture

#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <unistd.h>

fn C.__errno_location() &i32
fn C._exit(i32)
fn C.fflush(voidptr) i32
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

const mpol_default = i32(0)
const mpol_bind = i32(2)
const node_flag = u64(1)
const address_flag = u64(2)
const allowed_flag = u64(4)
const canary = u64(0x6a6a6a6a6a6a6a6a)

fn need(ok bool, label &char) {
	if ok { return }
	unsafe {
		C.printf(c'LINUX MEMPOLICY FAIL: %s errno=%d\n', label, *C.__errno_location())
		C.fflush(nil)
		C._exit(1)
	}
}

fn get_policy(mode voidptr, mask voidptr, maxnode u64, address u64, flags u64) i64 {
	unsafe {
		ret := C.syscall(i64(C.SYS_get_mempolicy), mode, mask, maxnode, address, flags)
		return if ret < 0 { -i64(*C.__errno_location()) } else { ret }
	}
}

fn bind(node i32) {
	unsafe {
		mut mask := u64(1) << node
		need(C.syscall(i64(C.SYS_set_mempolicy), i64(mpol_bind), &mask, u64(64)) == 0, c'bind task policy')
	}
}

fn region(length u64) u64 {
	base := C.mmap(unsafe { nil }, length, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	need(base != voidptr(-1), c'allocate test mapping')
	return u64(base)
}

fn check_address(page u64, mapped_node i32) {
	unsafe {
		bind(mapped_node)
		base := region(page)
		*(&u8(base)) = 1
		bind(0)

		mut mode := i32(-1)
		mut mask := canary
		need(get_policy(&mode, &mask, 64, 0, 0) == 0 && mode == mpol_bind && mask == 1,
			c'task query reports the current bind policy')
		need(get_policy(&mode, &mask, 64, base + 1, address_flag) == 0 && mode == mpol_default
			&& mask == 0, c'mapped address has default range policy under a task binding')
		need(get_policy(&mode, &mask, 64, base + 1, address_flag | node_flag) == 0 && mode == mapped_node
			&& mask == 0, c'address node comes from the resident page')
		if mapped_node == 1 {
			C.puts(c'LINUX MEMPOLICY NUMA: PASS')
		}
		need(C.mprotect(voidptr(base), page, C.PROT_NONE) == 0, c'protect resident mapping')
		need(get_policy(&mode, nil, 0, base, address_flag) == 0 && mode == mpol_default,
			c'protected mapping still has a policy')
		mode = -1
		mask = canary
		need(get_policy(&mode, &mask, 64, base, address_flag | node_flag) == -C.EFAULT
			&& mode == -1 && mask == canary, c'node query needs readable mapping')
		need(C.munmap(voidptr(base), page) == 0, c'unmap test page')
		need(get_policy(&mode, &mask, 64, base, address_flag) == -C.EFAULT
			&& mode == -1 && mask == canary, c'unmapped address leaves outputs untouched')
		need(get_policy(nil, nil, 0, ~u64(0), address_flag) == -C.EFAULT, c'no policy beyond userspace')
		need(get_policy(nil, nil, 0, 0, address_flag) == -C.EFAULT, c'null address has no mapping')
		need(get_policy(nil, nil, 0, base, 0) == -C.EINVAL, c'nonzero address needs address flag')
		need(get_policy(nil, nil, 0, base, address_flag | allowed_flag) == -C.EINVAL,
			c'allowed nodes cannot be combined with address query')
		need(get_policy(nil, nil, 0, base, address_flag | (u64(1) << 32)) == -C.EINVAL,
			c'flags validate the upper word')
	}
}

fn check_page_in(page u64) {
	unsafe {
		length := u64(64 * 1024 * 1024)
		base := region(length)
		mut resident := u8(255)
		need(C.mincore(voidptr(base), page, &resident) == 0 && resident & 1 == 0,
			c'start with an absent page')
		mut mode := i32(-1)
		need(get_policy(&mode, nil, 0, base, address_flag) == 0 && mode == mpol_default,
			c'query policy on an absent page')
		need(C.mincore(voidptr(base), page, &resident) == 0 && resident & 1 == 0,
			c'policy-only query keeps the page absent')
		need(get_policy(&mode, nil, 0, base, address_flag | node_flag) == 0 && mode >= 0,
			c'query node of the demand-backed page')
		need(C.mincore(voidptr(base), page, &resident) == 0 && resident & 1 != 0,
			c'node query populated the readable page')
		need(C.munmap(voidptr(base), length) == 0, c'release demand-backed mapping')
	}
}

fn check_mask(page u64, allowed u64) {
	unsafe {
		mut mode := i32(-1)
		mut words := [3]u64{init: canary}
		need(get_policy(&mode, &words[0], 65, 17, allowed_flag) == 0 && mode == 0
			&& words[0] == allowed && words[1] == canary, c'65 means exactly one output word')
		need(get_policy(&mode, &words[0], 66, 0, allowed_flag) == 0 && words[0] == allowed
			&& words[1] == 0 && words[2] == canary, c'66 means two output words')
		mode = -1
		need(get_policy(&mode, &words[0], 0, 0, address_flag) == -C.EINVAL && mode == -1,
			c'short mask precedes bad address and leaves mode untouched')
		need(get_policy(&mode, &words[0], 1 << 30, 0, allowed_flag) == -C.EINVAL && mode == 0,
			c'oversized mask is rejected after mode copy')
		if allowed == 1 {
			need(get_policy(nil, voidptr(1), 1, 0, allowed_flag) == 0, c'zero output words skip bad mask pointer')
		}
		base := region(2 * page)
		first := &u64(base + page - sizeof(u64))
		*first = canary
		need(C.mprotect(voidptr(base + page), page, C.PROT_NONE) == 0, c'guard the second word')
		mode = -1
		need(get_policy(&mode, first, 66, 0, allowed_flag) == -C.EFAULT && mode == 0 && *first == canary,
			c'zero-fill fault leaves the first word untouched after mode copy')
		need(C.munmap(voidptr(base), 2 * page) == 0, c'release guarded mask')
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		reference := argc > 1 && C.strcmp(argv[1], c'--reference') == 0
		page_size := C.sysconf(C._SC_PAGESIZE)
		need(page_size >= 4096, c'determine page size')
		page := u64(page_size)
		mut allowed := u64(0)
		need(get_policy(nil, &allowed, 64, 0, allowed_flag) == 0 && allowed & 1 != 0,
			c'read available NUMA nodes')
		check_address(page, if allowed & 2 == 0 { i32(0) } else { i32(1) })
		check_page_in(page)
		check_mask(page, allowed)
		need(C.syscall(i64(C.SYS_set_mempolicy), i64(mpol_default), nil, u64(0)) == 0,
			c'restore default task policy')
		C.puts(c'LINUX MEMPOLICY SUMMARY: address=checked demand=checked bitmap=checked')
		C.puts(if reference { c'LINUX MEMPOLICY REFERENCE: PASS' } else { c'LINUX MEMPOLICY: PASS' })
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
