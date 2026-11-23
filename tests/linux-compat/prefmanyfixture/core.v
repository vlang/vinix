// SPDX-License-Identifier: GPL-2.0-or-later
module prefmanyfixture

#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <unistd.h>

fn C.__errno_location() &i32
fn C._exit(i32)
fn C.dprintf(i32, &char, ...) i32
fn C.fflush(voidptr) i32
fn C.madvise(voidptr, u64, i32) i32
fn C.mincore(voidptr, u64, &u8) i32
fn C.mmap(voidptr, u64, i32, i32, i32, i64) voidptr
fn C.munmap(voidptr, u64) i32
fn C.pause() i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.strcmp(&char, &char) i32
fn C.syscall(i64, ...) i64
fn C.sysconf(i32) i64

const preferred_many = i64(5)
const address_flag = u64(2)
const node_address_flags = u64(3)
const allowed_flag = u64(4)
const mib = u64(1024 * 1024)

fn need(ok bool, label &char) {
	if ok { return }
	unsafe {
		C.dprintf(2, c'LINUX PREFMANY FAIL: %s errno=%d\n', label, *C.__errno_location())
		C._exit(1)
	}
}

fn result(value i64) i64 {
	unsafe { return if value < 0 { -i64(*C.__errno_location()) } else { value } }
}

fn set_policy(mask u64) i64 {
	return result(C.syscall(i64(C.SYS_set_mempolicy), preferred_many, unsafe { &mask }, u64(64)))
}

fn bind_policy(address u64, length u64, mask u64) i64 {
	return result(C.syscall(i64(C.SYS_mbind), address, length, preferred_many, unsafe { &mask },
		u64(64), u64(0)))
}

fn get_policy(address u64, flags u64) (i32, u64) {
	mut mode := i32(-1)
	mut mask := ~u64(0)
	need(C.syscall(i64(C.SYS_get_mempolicy), unsafe { &mode }, unsafe { &mask }, u64(64),
		address, flags) == 0, c'read policy')
	return mode, mask
}

fn policy_is(address u64, flags u64, want_mask u64) bool {
	mode, mask := get_policy(address, flags)
	return mode == i32(preferred_many) && mask == want_mask
}

fn page_node(address u64) i32 {
	node, _ := get_policy(address, node_address_flags)
	return node
}

fn empty_region(length u64, page u64) u64 {
	base := C.mmap(unsafe { nil }, length, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	need(base != voidptr(-1), c'map pages')
	need(C.madvise(base, length, C.MADV_DONTNEED) == 0, c'discard eagerly populated pages')
	mut resident := u8(255)
	need(C.mincore(base, page, unsafe { &resident }) == 0 && resident & 1 == 0,
		c'pages start unpopulated')
	return u64(base)
}

fn check_policies(page u64, allowed u64) {
	// Use a low absent node so reference kernels with smaller configured
	// nodemasks can also distinguish unsupported IDs from unavailable nodes.
	unavailable := ~allowed & (allowed + 1)
	need(set_policy(allowed) == 0 && policy_is(0, 0, allowed), c'task policy retains every preferred node')
	need(set_policy(0) == -C.EINVAL, c'task rejects an empty mask')
	if unavailable != 0 { need(set_policy(unavailable) == -C.EINVAL, c'task rejects unavailable nodes') }
	need(policy_is(0, 0, allowed), c'failed request keeps the task policy')
	// The mixed-mask check uses IDs supported by both Linux references.
	if unavailable > 0 && unavailable <= 8 {
		need(set_policy(allowed | unavailable) == 0 && policy_is(0, 0, allowed),
			c'task policy keeps only available nodes')
	}
	base := empty_region(2 * page, page)
	second := base + page
	need(bind_policy(second, page, allowed) == 0 && policy_is(second, address_flag, allowed),
		c'range policy retains every preferred node')
	need(bind_policy(second, page, 0) == -C.EINVAL, c'range rejects an empty mask')
	if unavailable != 0 {
		need(bind_policy(second, page, unavailable) == -C.EINVAL, c'range rejects unavailable nodes')
	}
	need(policy_is(second, address_flag, allowed), c'failed request keeps the range policy')
	mut task_node := i32(0)
	if allowed & 2 != 0 { task_node = 1 }
	need(set_policy(u64(1) << task_node) == 0, c'prefer task node')
	mixed := if unavailable <= 8 { u64(1) | unavailable } else { u64(1) }
	need(bind_policy(second, page, mixed) == 0 && policy_is(second, address_flag, 1),
		c'range prefers node zero')
	unsafe {
		*(&u8(base)) = 17
		*(&u8(second)) = 21
	}
	need(page_node(base) == task_node && page_node(second) == 0,
		c'range policy overrides task placement')
	need(C.munmap(voidptr(base), 2 * page) == 0, c'release placement pages')
}

fn check_pressure(page u64, allowed u64) {
	// With two or three nodes, qualify a fixed allocation against the
	// hardware presented to the guest. The pressure run uses 128 MiB per
	// preferred node and checks the reported samples for every node.
	preferred := allowed & ~u64(1)
	length := 320 * mib
	need(set_policy(preferred) == 0, c'prefer the nonzero nodes')
	base := empty_region(length, page)
	mut samples := [3]u32{}
	for offset := u64(0); offset < length; offset += page {
		address := base + offset
		unsafe { *(&u8(address)) = 84 }
		if offset % mib == 0 {
			node := page_node(address)
			need(node >= 0 && node < samples.len && allowed & (u64(1) << node) != 0,
				c'pressure sample is on an available node')
			if offset == 0 { need(node != 0, c'first allocation uses a preferred node') }
			unsafe { (&samples[0])[node]++ }
		}
	}
	need(policy_is(0, 0, preferred), c'fallback preserves the policy')
	need(C.munmap(voidptr(base), length) == 0, c'release pressure pages')
	C.printf(c'LINUX PREFMANY PRESSURE: node0=%u node1=%u node2=%u\n', samples[0], samples[1], samples[2])
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		_, allowed := get_policy(0, allowed_flag)
		need(allowed & 1 != 0, c'node zero is available')
		page := C.sysconf(C._SC_PAGESIZE)
		need(page >= 4096, c'valid page size')
		check_policies(u64(page), allowed)
		if allowed == 3 || allowed == 7 { check_pressure(u64(page), allowed) }
		C.puts(c'LINUX PREFMANY SUMMARY: mask=checked placement=checked')
		reference := argc > 1 && C.strcmp(argv[1], c'--reference') == 0
		C.puts(if reference { c'LINUX PREFMANY REFERENCE: PASS' } else { c'LINUX PREFMANY: PASS' })
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
