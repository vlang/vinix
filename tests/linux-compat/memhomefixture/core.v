// SPDX-License-Identifier: GPL-2.0-or-later
module memhomefixture

#include <errno.h>
#include <sched.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.__errno_location() &i32
fn C._exit(i32)
fn C.dprintf(i32, &char, ...) i32
fn C.fflush(voidptr) i32
fn C.fork() i32
fn C.madvise(voidptr, u64, i32) i32
fn C.mincore(voidptr, u64, &u8) i32
fn C.mmap(voidptr, u64, i32, i32, i32, i64) voidptr
fn C.munmap(voidptr, u64) i32
fn C.pause() i32
fn C.puts(&char) i32
fn C.sched_yield() i32
fn C.strcmp(&char, &char) i32
fn C.syscall(i64, ...) i64
fn C.sysconf(i32) i64
fn C.waitpid(i32, &i32, i32) i32

// Native syscall number on both qualified architectures.
const home_syscall = i64(450)
const preferred = i64(1)
const bind_mode = i64(2)
const interleave = i64(3)
const preferred_many = i64(5)
const addr_flag = u64(2)
const node_addr_flags = u64(3)
const allowed_flag = u64(4)

fn need(ok bool, label &char) {
	if ok { return }
	unsafe {
		C.dprintf(2, c'LINUX MEMHOME FAIL: %s errno=%d\n', label, *C.__errno_location())
		C._exit(1)
	}
}

fn result(ret i64) i64 {
	unsafe { return if ret < 0 { -i64(*C.__errno_location()) } else { ret } }
}

fn home(base u64, length u64, node u64, flags u64) i64 {
	return result(C.syscall(home_syscall, base, length, node, flags))
}

fn bind_policy(base u64, length u64, mode i64, mask u64) {
	need(C.syscall(i64(C.SYS_mbind), base, length, mode, unsafe { &mask }, u64(64), u64(0)) == 0,
		c'install range policy')
}

fn get_policy(address u64, flags u64) (i32, u64) {
	mut mode := i32(-1)
	mut mask := ~u64(0)
	need(C.syscall(i64(C.SYS_get_mempolicy), unsafe { &mode }, unsafe { &mask }, u64(64),
		address, flags) == 0, c'read policy')
	return mode, mask
}

fn has_policy(address u64, flags u64, want_mode i64, want_mask u64) bool {
	mode, mask := get_policy(address, flags)
	return mode == i32(want_mode) && mask == want_mask
}

fn page_node(address u64) i32 {
	node, _ := get_policy(address, node_addr_flags)
	return node
}

fn discard(base u64, length u64) {
	need(C.madvise(voidptr(base), length, C.MADV_DONTNEED) == 0, c'discard eager pages')
}

fn new_region(length u64, page u64) u64 {
	base := C.mmap(unsafe { nil }, length, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	need(base != voidptr(-1), c'map anonymous pages')
	discard(u64(base), length)
	mut resident := u8(255)
	need(C.mincore(base, page, unsafe { &resident }) == 0 && resident & 1 == 0,
		c'pages start unpopulated')
	return u64(base)
}

fn fault(address u64) i32 {
	unsafe { *(&u8(address)) = 19 }
	return page_node(address)
}

fn pin_node_zero() {
	mut affinity := [16]u64{}
	affinity[0] = 1
	need(C.syscall(i64(C.SYS_sched_setaffinity), i64(0), u64(sizeof(affinity)),
		unsafe { &affinity[0] }) == 0, c'pin the faulting thread to CPU zero')
	for _ in 0 .. 128 {
		mut cpu := u32(255)
		mut node := u32(255)
		need(C.syscall(i64(C.SYS_getcpu), unsafe { &cpu }, unsafe { &node }, voidptr(0)) == 0,
			c'read faulting CPU and node')
		if cpu == 0 && node == 0 { return }
		need(C.sched_yield() == 0, c'yield to the selected CPU')
	}
	need(false, c'wait for migration to CPU zero on node zero')
}

fn check_validation(page u64) {
	base := new_region(2 * page, page)
	need(home(base + 1, 0, 0, 0) == -C.EINVAL, c'reject misalignment before zero-length shortcut')
	need(home(base, 0, 0, u64(1) << 32) == -C.EINVAL, c'reject nonzero flags at native width')
	need(home(base, 0, u64(1) << 32, 0) == -C.EINVAL, c'reject oversized node before zero length')
	need(home(base, 0, 0, 0) == 0, c'zero-length update succeeds')
	need(home(base, ~u64(0), 0, 0) == 0, c'length that rounds to zero succeeds')
	need(home(base, ~u64(0) - base + 1 + page, 0, 0) == -C.EINVAL, c'wrapped end is invalid')
	need(home(base, page, 0, 0) == -C.ENOENT, c'no explicit policy returns ENOENT')
	bind_policy(base, page, preferred, 1)
	need(home(base, page, 0, 0) == -C.EOPNOTSUPP && has_policy(base, addr_flag, preferred, 1),
		c'unsupported modes keep their policy')
	need(C.munmap(voidptr(base), 2 * page) == 0, c'release validation mapping')
}

fn check_partial(page u64, other bool) {
	base := new_region(6 * page, page)
	mask := if other { u64(3) } else { u64(1) }
	node := if other { u64(1) } else { u64(0) }
	bind_policy(base, page, bind_mode, mask)
	need(C.munmap(voidptr(base + page), page) == 0, c'create a hole between policy ranges')
	need(home(base + page, page, node, 0) == -C.ENOENT, c'a hole alone has no policy')
	bind_policy(base + 3 * page, page, preferred_many, mask)
	bind_policy(base + 4 * page, page, interleave, 1)
	bind_policy(base + 5 * page, page, bind_mode, mask)
	need(home(base, 6 * page, node, 0) == -C.EOPNOTSUPP, c'stop at first unsupported policy')
	need(has_policy(base, addr_flag, bind_mode, mask)
		&& has_policy(base + 3 * page, addr_flag, preferred_many, mask), c'home updates preserve mode and mask')
	need(fault(base) == i32(node) && fault(base + 3 * page) == i32(node),
		c'earlier updates survive the error across a hole and an unbound range')
	need(fault(base + 2 * page) == 0 && fault(base + 5 * page) == 0,
		c'unbound and later ranges keep CPU-local placement')
	need(home(base, 4 * page, node, 0) == 0, c'holes and unbound ranges do not block success')
	need(C.munmap(voidptr(base), 6 * page) == 0, c'release split ranges and hole')
}

fn check_placement(page u64) {
	base := new_region(5 * page, page)
	bind_policy(base, 5 * page, bind_mode, 3)
	first := base + page
	second := first + page
	need(fault(first) == 0, c'no home override uses the CPU node')
	need(home(first, 2 * page - 1, 1, 0) == 0, c'round length and split interior range')
	need(page_node(first) == 0, c'update preserves existing page placement')
	need(fault(base) == 0 && fault(base + 3 * page) == 0, c'pages outside the update keep the old policy')
	child := C.fork()
	need(child >= 0, c'fork with home override')
	if child == 0 {
		need(fault(first) == 1, c'child copy-on-write follows the home override')
		need(fault(second) == 1, c'child inherits the home override')
		C._exit(0)
	}
	mut status := i32(-1)
	need(C.waitpid(child, unsafe { &status }, 0) == child && status == 0, c'child placement passes')
	need(page_node(first) == 0, c'child copy-on-write preserves parent placement')
	need(fault(second) == 1, c'rounded end includes the second page')
	discard(first, page)
	need(fault(first) == 1, c'future faults use the home override')
	bind_policy(first, page, bind_mode, 3)
	discard(first, page)
	need(fault(first) == 0, c'replacing a range policy clears the override')
	bind_policy(first, page, bind_mode, 1)
	need(home(first, page, 1, 0) == 0, c'home node can be outside the mask')
	discard(first, page)
	need(fault(first) == 0, c'bind continues to enforce the mask')
	need(has_policy(0, 0, 0, 0), c'range override leaves the task policy alone')
	need(C.munmap(voidptr(base), 5 * page) == 0, c'release placement range')
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		page := C.sysconf(C._SC_PAGESIZE)
		need(page >= 4096, c'valid native page size')
		_, allowed := get_policy(0, allowed_flag)
		need(allowed & 1 != 0, c'node zero is available')
		pin_node_zero()
		check_validation(u64(page))
		other := allowed & 2 != 0
		check_partial(u64(page), other)
		if other {
			check_placement(u64(page))
			C.puts(c'LINUX MEMHOME NUMA: PASS')
		}
		C.puts(c'LINUX MEMHOME SUMMARY: ranges=checked placement=checked')
		reference := argc > 1 && C.strcmp(argv[1], c'--reference') == 0
		C.puts(if reference { c'LINUX MEMHOME REFERENCE: PASS' } else { c'LINUX MEMHOME: PASS' })
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
