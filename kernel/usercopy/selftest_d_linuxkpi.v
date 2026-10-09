// SPDX-License-Identifier: GPL-2.0-or-later
@[manualfree]
module usercopy

import memory
import memory.mmap

const remaining_test_base = u64(0x20000000)
const remaining_test_lazy_base = u64(0x40000000)
const remaining_test_prefix = u64(7)
const remaining_test_length = u64(19)
const remaining_test_guard = u64(5)

struct RemainingSnapshot {
mut:
	free_bytes u64
	count      int
	sizes      [64]u64
	live       [64]u64
}

fn remaining_test_require(ok bool, message &char) bool {
	if !ok {
		C.kprintf(c'usercopy: remaining-byte self-test failed: %s\n', message)
	}
	return ok
}

fn remaining_test_snapshot(_snapshot &RemainingSnapshot) bool {
	mut snapshot := unsafe { _snapshot }
	mut classes := memory.heap_classes() @[freed]
	defer { unsafe { classes.free() } }
	if classes.len > snapshot.live.len {
		return remaining_test_require(false, c'heap snapshot capacity')
	}
	snapshot.count = classes.len
	for i, class in classes {
		snapshot.sizes[i] = class.size
		snapshot.live[i] = class.live
	}
	// Both snapshots observe the same allocated observer array. Its owner
	// frees it before returning, and free-page sampling happens afterwards.
	return true
}

fn remaining_test_same_heap(before &RemainingSnapshot, after &RemainingSnapshot) bool {
	if !remaining_test_require(before.count == after.count, c'heap class count') {
		return false
	}
	for i := 0; i < before.count; i++ {
		if before.sizes[i] != after.sizes[i] || before.live[i] != after.live[i] {
			C.kprintf(c'usercopy: heap class %llu live before=%llu after=%llu\n',
				before.sizes[i], before.live[i], after.live[i])
			return false
		}
	}
	return true
}

// These address spaces are never installed on a CPU or published to another
// task. The fixture owns their mappings until delete_pagemap reclaims them.
fn remaining_test_physical(_pagemap &memory.Pagemap, address u64) ?voidptr {
	mut pagemap := unsafe { _pagemap }
	pagemap.l.acquire()
	physical := pagemap.virt2phys(address) or {
		pagemap.l.release()
		return none
	}
	pagemap.l.release()
	return voidptr(physical + (address & (page_size - 1)) + memory.get_hhdm_offset())
}

fn remaining_test_bytes(ptr voidptr, length u64, value u8) bool {
	unsafe {
		bytes := &u8(ptr)
		for i := u64(0); i < length; i++ {
			if bytes[i] != value { return false }
		}
	}
	return true
}

fn remaining_test_pattern(ptr voidptr, length u64, first u8) {
	unsafe {
		mut bytes := &u8(ptr)
		for i := u64(0); i < length; i++ {
			bytes[i] = first + u8(i)
		}
	}
}

fn remaining_test_expected(ptr voidptr, length u64, first u8) bool {
	unsafe {
		bytes := &u8(ptr)
		for i := u64(0); i < length; i++ {
			if bytes[i] != first + u8(i) { return false }
		}
	}
	return true
}

fn remaining_test_map(pagemap &memory.Pagemap, base u64, length u64, populate bool) bool {
	flags := mmap.map_private | mmap.map_anonymous | mmap.map_fixed |
		if populate { mmap.map_populate } else { 0 }
	address := mmap.mmap(pagemap, voidptr(base), length, mmap.prot_read | mmap.prot_write,
		flags, unsafe { nil }, 0, unsafe { nil }, unsafe { nil }, unsafe { nil }) or {
		return false
	}
	return u64(address) == base
}

// Seed both sides independently through their owned physical pages, so the
// checked copy under test never prepares its own expected result.
fn remaining_test_seed(pagemap &memory.Pagemap) bool {
	first := remaining_test_physical(pagemap, remaining_test_base) or { return false }
	second := remaining_test_physical(pagemap, remaining_test_base + page_size) or { return false }
	unsafe {
		C.memset(first, 0x99, page_size)
		C.memset(second, 0x99, page_size)
	}
	remaining_test_pattern(voidptr(u64(first) + page_size - remaining_test_prefix),
		remaining_test_prefix, 0x40)
	remaining_test_pattern(second, remaining_test_length - remaining_test_prefix,
		0x40 + u8(remaining_test_prefix))
	return true
}

// Exercise the real locked walk without fault resolution. A failed page must
// preserve exactly the committed prefix and both surrounding guard regions.
fn remaining_test_boundary_copy(pagemap &memory.Pagemap, to_user bool, expected_remaining u64) bool {
	mut buffer := [32]u8{}
	unsafe { C.memset(voidptr(&buffer[0]), 0xcc, buffer.len) }
	buffer_address := unsafe { voidptr(&buffer[0]) }
	data := voidptr(u64(buffer_address) + remaining_test_guard)
	start := remaining_test_base + page_size - remaining_test_prefix
	if to_user {
		remaining_test_pattern(data, remaining_test_length, 0x20)
	}
	remaining := copy_pagemap_policy_remaining(pagemap, data, start, remaining_test_length,
		to_user, false, false)
	if !remaining_test_require(remaining == expected_remaining, c'cross-page remaining count') {
		return false
	}
	copied := remaining_test_length - expected_remaining
	if !remaining_test_require(remaining_test_bytes(buffer_address, remaining_test_guard, 0xcc)
		&& remaining_test_bytes(voidptr(u64(data) + remaining_test_length),
			u64(buffer.len) - remaining_test_guard - remaining_test_length, 0xcc),
		c'kernel buffer guards') {
		return false
	}
	if to_user {
		if !remaining_test_require(remaining_test_expected(data, remaining_test_length, 0x20),
			c'to-user source unchanged') {
			return false
		}
		first := remaining_test_physical(pagemap, remaining_test_base) or { return false }
		if !remaining_test_require(remaining_test_bytes(first, page_size - remaining_test_prefix,
			0x99) && remaining_test_expected(voidptr(u64(first) + page_size - remaining_test_prefix),
			remaining_test_prefix, 0x20), c'to-user committed prefix and preceding guard') {
			return false
		}
		if second := remaining_test_physical(pagemap, remaining_test_base + page_size) {
			second_copied := if copied > remaining_test_prefix {
				copied - remaining_test_prefix
			} else {
				0
			}
			if !remaining_test_require(remaining_test_expected(second, second_copied,
				0x20 + u8(remaining_test_prefix)), c'to-user second-page prefix') {
				return false
			}
			if expected_remaining != 0
				&& !remaining_test_require(remaining_test_expected(second,
					remaining_test_length - remaining_test_prefix, 0x40 + u8(remaining_test_prefix)),
					c'to-user inaccessible suffix unchanged') {
				return false
			}
			if !remaining_test_require(remaining_test_bytes(voidptr(u64(second) +
				remaining_test_length - remaining_test_prefix),
				page_size - (remaining_test_length - remaining_test_prefix), 0x99),
				c'to-user trailing guard') {
				return false
			}
		}
	} else {
		if !remaining_test_require(remaining_test_expected(data, copied, 0x40),
			c'from-user copied prefix') {
			return false
		}
		if !remaining_test_require(remaining_test_bytes(voidptr(u64(data) + copied),
			expected_remaining, 0xcc), c'raw from-user suffix unchanged') {
			return false
		}
	}
	return true
}

fn remaining_test_boundaries() bool {
	mut pagemap := memory.new_pagemap() @[freed]
	defer {
		mmap.delete_pagemap(mut pagemap) or { panic('usercopy: boundary pagemap cleanup failed') }
	}
	if !remaining_test_require(remaining_test_map(pagemap, remaining_test_base, 2 * page_size,
		true), c'boundary map creation') {
		return false
	}
	if !remaining_test_seed(pagemap)
		|| !remaining_test_boundary_copy(pagemap, false, 0)
		|| !remaining_test_boundary_copy(pagemap, true, 0) {
		return false
	}

	mmap.munmap(mut pagemap, voidptr(remaining_test_base + page_size), page_size) or {
		return remaining_test_require(false, c'missing second page unmap')
	}
	// The first page was modified by the successful to-user copy; reseed it.
	first := remaining_test_physical(pagemap, remaining_test_base) or { return false }
	remaining_test_pattern(voidptr(u64(first) + page_size - remaining_test_prefix),
		remaining_test_prefix, 0x40)
	if !remaining_test_boundary_copy(pagemap, false, remaining_test_length - remaining_test_prefix)
		|| !remaining_test_boundary_copy(pagemap, true, remaining_test_length - remaining_test_prefix) {
		return false
	}
	if !remaining_test_require(remaining_test_map(pagemap, remaining_test_base + page_size,
		page_size, true), c'second page recreation') {
		return false
	}

	mmap.mprotect(mut pagemap, voidptr(remaining_test_base + page_size), page_size,
		mmap.prot_none) or { return remaining_test_require(false, c'PROT_NONE protection') }
	if !remaining_test_seed(pagemap)
		|| !remaining_test_boundary_copy(pagemap, false, remaining_test_length - remaining_test_prefix)
		|| !remaining_test_boundary_copy(pagemap, true, remaining_test_length - remaining_test_prefix) {
		return false
	}
	mmap.mprotect(mut pagemap, voidptr(remaining_test_base + page_size), page_size,
		mmap.prot_read) or { return remaining_test_require(false, c'read-only protection') }
	if !remaining_test_seed(pagemap)
		|| !remaining_test_boundary_copy(pagemap, false, 0)
		|| !remaining_test_boundary_copy(pagemap, true, remaining_test_length - remaining_test_prefix) {
		return false
	}
	mut bytes := [32]u8{}
	unsafe { C.memset(voidptr(&bytes[0]), 0xcc, bytes.len) }
	ptr := unsafe { voidptr(&bytes[0]) }
	start := remaining_test_base + page_size - remaining_test_prefix
	if !remaining_test_require(!copy_pagemap_policy(pagemap, ptr, start, remaining_test_length,
		true, false, false), c'Boolean adapter failure') {
		return false
	}
	return true
}

fn remaining_test_lazy_and_cow() bool {
	mut pagemap := memory.new_pagemap() @[freed]
	defer {
		mmap.delete_pagemap(mut pagemap) or { panic('usercopy: lazy pagemap cleanup failed') }
	}
	// This size has a sparse policy on both architectures. Only the two pages
	// touched by the cross-page copy should become present.
	if !remaining_test_require(remaining_test_map(pagemap, remaining_test_lazy_base,
		64 * 1024 * 1024, false), c'lazy anonymous reservation') {
		return false
	}
	mut source := [32]u8{}
	mut output := [32]u8{}
	source_ptr := unsafe { voidptr(&source[0]) }
	output_ptr := unsafe { voidptr(&output[0]) }
	remaining_test_pattern(source_ptr, u64(source.len), 0x60)
	start := remaining_test_lazy_base + page_size - remaining_test_prefix
	if !remaining_test_require(!copy_pagemap_policy(pagemap, output_ptr, start,
		remaining_test_length, false, false, false), c'lazy pages initially absent') {
		return false
	}
	if !remaining_test_require(copy_pagemap_policy_remaining(pagemap, output_ptr, start,
		remaining_test_length, false, true, true) == 0
		&& remaining_test_bytes(output_ptr, remaining_test_length, 0),
		c'actual anonymous read fault') {
		return false
	}
	if !remaining_test_require(copy_pagemap_policy_remaining(pagemap, source_ptr, start,
		remaining_test_length, true, true, true) == 0, c'actual anonymous write') {
		return false
	}
	if !remaining_test_require(pagemap.resident_bytes == 2 * page_size,
		c'only touched anonymous pages resident') {
		return false
	}
	mut child := mmap.fork_pagemap(pagemap, pagemap.kernel_owner) or {
		return remaining_test_require(false, c'actual native COW fork')
	}
	defer {
		mmap.delete_pagemap(mut child) or { panic('usercopy: COW child cleanup failed') }
	}
	shared_page := remaining_test_physical(pagemap, start) or { return false }
	shared_physical := u64(shared_page) - memory.get_hhdm_offset() - (start & (page_size - 1))
	if !remaining_test_require(memory.pmm_refcount(voidptr(shared_physical)) == 2,
		c'COW page shared before write') {
		return false
	}
	remaining_test_pattern(source_ptr, u64(source.len), 0x80)
	if !remaining_test_require(copy_pagemap_policy_remaining(child, source_ptr, start,
		remaining_test_length, true, true, true) == 0, c'actual native COW write fault') {
		return false
	}
	if !remaining_test_require(copy_pagemap_policy_remaining(pagemap, output_ptr, start,
		remaining_test_length, false, false, false) == 0
		&& remaining_test_expected(output_ptr, remaining_test_length, 0x60),
		c'COW parent unchanged') {
		return false
	}
	if !remaining_test_require(copy_pagemap_policy_remaining(child, output_ptr, start,
		remaining_test_length, false, false, false) == 0
		&& remaining_test_expected(output_ptr, remaining_test_length, 0x80),
		c'COW child copied bytes') {
		return false
	}
	child_page := remaining_test_physical(child, start) or { return false }
	return remaining_test_require(child_page != shared_page
		&& memory.pmm_refcount(voidptr(shared_physical)) == 1, c'COW page reference separation')
}

fn remaining_test_invalid() bool {
	if !remaining_test_require(raw_copy_from_user(unsafe { nil }, u64(-1), 0) == 0
		&& raw_copy_to_user(u64(-1), unsafe { nil }, 0) == 0
		&& copy_pagemap_policy_remaining(unsafe { nil }, unsafe { nil }, u64(-1), 0,
			false, true, true) == 0
		&& copy_pagemap_policy(unsafe { nil }, unsafe { nil }, u64(-1), 0,
			false, true, true), c'zero length precedes pointer access') {
		return false
	}
	// The public raw-call chain makes V promote an addressed fixed array.
	// This synchronous borrowed scratch must stay on the current stack.
	ptr := C.vinix_stack_alloc(32)
	unsafe { C.memset(ptr, 0xcc, 32) }
	limit := memory.user_address_limit()
	if !remaining_test_require(raw_copy_from_user(ptr, limit - 1, 2) == 2
		&& raw_copy_from_user(ptr, u64(-2), 4) == 4
		&& raw_copy_from_user(ptr, 0, 1) == 1
		&& raw_copy_from_user(unsafe { nil }, remaining_test_base, 1) == 1
		&& raw_copy_to_user(limit - 1, ptr, 2) == 2
		&& raw_copy_to_user(u64(-2), ptr, 4) == 4
		&& raw_copy_to_user(0, ptr, 1) == 1
		&& raw_copy_to_user(remaining_test_base, unsafe { nil }, 1) == 1,
		c'full invalid range rejected') {
		return false
	}
	return remaining_test_require(remaining_test_bytes(ptr, 32, 0xcc),
		c'invalid range buffer unchanged')
}

fn remaining_test_batch() bool {
	return remaining_test_invalid() && remaining_test_boundaries() && remaining_test_lazy_and_cow()
}

pub fn remaining_selftest() bool {
	for _ in 0 .. 3 {
		if !remaining_test_batch() { return false }
	}
	mut before := RemainingSnapshot{}
	mut after := RemainingSnapshot{}
	if !remaining_test_snapshot(unsafe { &before }) { return false }
	before.free_bytes = memory.free_bytes()
	if !remaining_test_batch() { return false }
	if !remaining_test_snapshot(unsafe { &after }) { return false }
	after.free_bytes = memory.free_bytes()
	if before.free_bytes != after.free_bytes {
		C.kprintf(c'usercopy: free-byte baseline=%llu after=%llu\n', before.free_bytes,
			after.free_bytes)
		return false
	}
	if !remaining_test_same_heap(unsafe { &before }, unsafe { &after }) { return false }
	C.kprintf(c'usercopy: exact remaining bytes, unchanged raw suffix, demand faults and COW passed; no pages or heap objects retained\n')
	return true
}
