// SPDX-License-Identifier: GPL-2.0-or-later
@[manualfree]
module usercopy

import lib
import memory
import memory.mmap

#include "linuxkpi_pagefault_v_contract.h"

const nocache_test_base = u64(0x68000000)
const nocache_test_lazy_base = u64(0x74000000)
const nocache_test_cow_base = u64(0x7c000000)
const nocache_test_buffer_size = u64(2 * 4096 + 32)

fn nocache_test_pattern(offset u64) u8 {
	return u8(offset * 3 + 17)
}

fn nocache_test_source_unchanged(alias voidptr, start u64) bool {
	unsafe {
		bytes := &u8(alias)
		for offset := u64(0); offset < page_size; offset++ {
			if bytes[offset] != nocache_test_pattern(start + offset) {
				return scalar_test_require(false, c'nocache source bytes remain unchanged')
			}
		}
	}
	return true
}

// Storage is borrowed from this call's stack. Every byte outside the committed
// prefix remains a sentinel, including both destination alignment guards.
fn nocache_test_case(pagemap &memory.Pagemap, source u64, length u64,
	alignment u64, prefix u64, pattern_offset u64) bool {
	buffer := C.vinix_stack_alloc(usize(nocache_test_buffer_size))
	unsafe { C.memset(buffer, 0xcc, nocache_test_buffer_size) }
	displacement := u64(16) + alignment
	if length > nocache_test_buffer_size - displacement { return false }
	destination := voidptr(u64(buffer) + displacement)
	if !scalar_test_require(copy_nocache_pagemap_remaining(pagemap, destination,
		source, length) == length - prefix, c'nocache exact resident remainder') { return false }
	unsafe {
		bytes := &u8(buffer)
		for offset := u64(0); offset < nocache_test_buffer_size; offset++ {
			expected := if offset >= displacement && offset - displacement < prefix {
				nocache_test_pattern(pattern_offset + offset - displacement)
			} else { u8(0xcc) }
			if bytes[offset] != expected {
				return scalar_test_require(false, c'nocache bytes, guards and untouched suffix')
			}
		}
	}
	return true
}

fn nocache_test_context(pagemap &memory.Pagemap, source u64, length u64,
	prefix u64, pattern_offset u64, mode int) bool {
	flags := C.vinix_linuxkpi_irq_save()
	if mode & 1 == 0 { C.vinix_linuxkpi_irq_restore(flags) }
	if mode & 2 != 0 { C.vinix_linuxkpi_preempt_disable() }
	if mode & 4 != 0 { C.pagefault_disable(); C.pagefault_disable() }
	defer {
		if mode & 4 != 0 { C.pagefault_enable(); C.pagefault_enable() }
		if mode & 2 != 0 { C.vinix_linuxkpi_preempt_enable() }
		if mode & 1 != 0 { C.vinix_linuxkpi_irq_restore(flags) }
	}
	depth := if mode & 4 != 0 { u32(2) } else { u32(0) }
	preempt := C.vinix_linuxkpi_preempt_count()
	irq_enabled := mode & 1 == 0
	return fault_test_depth(depth) && fault_test_irq_state(irq_enabled)
		&& nocache_test_case(pagemap, source, length, 3, prefix, pattern_offset)
		&& fault_test_depth(depth) && fault_test_irq_state(irq_enabled)
		&& scalar_test_require(C.vinix_linuxkpi_preempt_count() == preempt,
			c'nocache preserves the actual native preemption count')
}

fn nocache_test_separated_pages() bool {
	mut pagemap := memory.new_pagemap() @[freed]
	defer { mmap.delete_pagemap(mut pagemap) or { panic('nocache map cleanup failed') } }
	backing := memory.pmm_alloc_fallible(3) @[freed]
	if backing == unsafe { nil } { return false }
	mut handed_off := false
	defer {
		if handed_off {
			// Only the endpoints belong to the two ranges. Never free them here.
			memory.pmm_free(voidptr(u64(backing) + page_size), 1)
		} else { memory.pmm_free(backing, 3) }
	}
	// The existing mapper can partially publish on OOM. A fixture construction
	// failure is fatal, rather than attempting an unproven physical rollback.
	mmap.map_range(mut pagemap, nocache_test_base, u64(backing), page_size,
		mmap.prot_read | mmap.prot_write, mmap.map_private) or {
		lib.kpanic(unsafe { nil }, c'nocache first physical map construction failed')
	}
	mmap.map_range(mut pagemap, nocache_test_base + page_size,
		u64(backing) + 2 * page_size, page_size,
		mmap.prot_read | mmap.prot_write, mmap.map_private) or {
		lib.kpanic(unsafe { nil }, c'nocache second physical map construction failed')
	}
	handed_off = true
	first := scalar_test_physical(pagemap, nocache_test_base) or { return false }
	second := scalar_test_physical(pagemap, nocache_test_base + page_size) or { return false }
	if !scalar_test_require(u64(second) == u64(first) + 2 * page_size,
		c'nocache actually separated physical source pages') { return false }
	unsafe {
		for offset := u64(0); offset < page_size; offset++ {
			(&u8(first))[offset] = nocache_test_pattern(offset)
			(&u8(second))[offset] = nocache_test_pattern(page_size + offset)
		}
	}
	for source_alignment := u64(0); source_alignment < 8; source_alignment++ {
		for destination_alignment := u64(0); destination_alignment < 8; destination_alignment++ {
			for length in [u64(0), 1, 2, 3, 4, 7, 8, 9, 31, 32, 33, 63, 64, 65]! {
				if !nocache_test_case(pagemap, nocache_test_base + 32 + source_alignment,
					length, destination_alignment, length, 32 + source_alignment) { return false }
			}
		}
	}
	for alignment := u64(0); alignment < 8; alignment++ {
		for length in [u64(8), 9, 31, 32, 33, 63, 64, 65, 4095, 4096, 4097]! {
			if !nocache_test_case(pagemap, nocache_test_base + page_size - 7,
				length, alignment, length, page_size - 7) { return false }
		}
	}
	mmap.mprotect(mut pagemap, voidptr(nocache_test_base), page_size,
		mmap.prot_read) or { return false }
	for mode in 0 .. 8 {
		if !nocache_test_context(pagemap, nocache_test_base + 35, 65, 65, 35, mode) {
			return false
		}
	}
	mmap.mprotect(mut pagemap, voidptr(nocache_test_base + page_size), page_size,
		mmap.prot_none) or { return false }
	for alignment := u64(0); alignment < 8; alignment++ {
		for prefix in [u64(1), 2, 3, 4, 7, 8, 9, 15, 16, 31]! {
			if !nocache_test_case(pagemap, nocache_test_base + page_size - prefix,
				prefix + 19, alignment, prefix, page_size - prefix) { return false }
		}
	}
	for mode in 0 .. 8 {
		if !nocache_test_context(pagemap, nocache_test_base + page_size - 9,
			32, 9, page_size - 9, mode) { return false }
	}
	return nocache_test_source_unchanged(first, 0)
		&& nocache_test_source_unchanged(second, page_size)
}

fn nocache_test_missing() bool {
	mut pagemap := memory.new_pagemap() @[freed]
	defer { mmap.delete_pagemap(mut pagemap) or { panic('nocache lazy cleanup failed') } }
	if !scalar_test_map(pagemap, nocache_test_lazy_base, 64 * 1024 * 1024, false) { return false }
	for mode in 0 .. 8 {
		if !nocache_test_context(pagemap, nocache_test_lazy_base + 8, 65, 0, 8, mode)
			|| !scalar_test_require(pagemap.resident_bytes == 0
				&& fault_test_absent(pagemap, nocache_test_lazy_base),
				c'nocache missing source never instantiates a page') { return false }
	}
	if !write_scalar_pagemap(pagemap, nocache_test_lazy_base, 1, 0) { return false }
	first := scalar_test_physical(pagemap, nocache_test_lazy_base) or { return false }
	unsafe {
		for offset := u64(0); offset < page_size; offset++ {
			(&u8(first))[offset] = nocache_test_pattern(offset)
		}
	}
	for mode in 0 .. 8 {
		if !nocache_test_context(pagemap, nocache_test_lazy_base + page_size - 9,
			32, 9, page_size - 9, mode) { return false }
	}
	return scalar_test_require(pagemap.resident_bytes == page_size
		&& fault_test_absent(pagemap, nocache_test_lazy_base + page_size),
		c'nocache resident prefix leaves the demand suffix absent')
		&& nocache_test_source_unchanged(first, 0)
}

fn nocache_test_cow() bool {
	mut pagemap := memory.new_pagemap() @[freed]
	defer { mmap.delete_pagemap(mut pagemap) or { panic('nocache COW parent cleanup failed') } }
	if !scalar_test_map(pagemap, nocache_test_cow_base, page_size, true) { return false }
	first := scalar_test_physical(pagemap, nocache_test_cow_base) or { return false }
	unsafe {
		for offset := u64(0); offset < page_size; offset++ {
			(&u8(first))[offset] = nocache_test_pattern(offset)
		}
	}
	mut child := mmap.fork_pagemap(pagemap, pagemap.kernel_owner) or { return false }
	defer { mmap.delete_pagemap(mut child) or { panic('nocache COW child cleanup failed') } }
	physical := u64(first) - memory.get_hhdm_offset()
	for mode in 0 .. 8 {
		if !nocache_test_context(pagemap, nocache_test_cow_base + 35, 65, 65, 35, mode) {
			return false
		}
	}
	parent_alias := scalar_test_physical(pagemap, nocache_test_cow_base) or { return false }
	child_alias := scalar_test_physical(child, nocache_test_cow_base) or { return false }
	return scalar_test_require(parent_alias == first && child_alias == first
		&& memory.pmm_refcount(voidptr(physical)) == 2,
		c'nocache resident COW source preserves both physical shares')
		&& nocache_test_source_unchanged(parent_alias, 0)
		&& nocache_test_source_unchanged(child_alias, 0)
}

fn nocache_test_batch() bool {
	return fault_test_depth(0) && nocache_test_separated_pages()
		&& nocache_test_missing() && nocache_test_cow() && fault_test_depth(0)
}

pub fn nocache_selftest() bool {
	if copy_nocache_pagemap_remaining(unsafe { nil }, unsafe { nil }, u64(-1), 0) != 0
		|| raw_copy_from_user_nocache(unsafe { nil }, u64(-1), 0) != 0 { return false }
	for _ in 0 .. 3 { if !nocache_test_batch() { return false } }
	mut before := ScalarSnapshot{}
	mut after := ScalarSnapshot{}
	if !scalar_test_snapshot(unsafe { &before }) { return false }
	before.free_bytes = memory.free_bytes()
	if !nocache_test_batch() { return false }
	if !scalar_test_snapshot(unsafe { &after }) { return false }
	after.free_bytes = memory.free_bytes()
	if !scalar_test_same_memory(unsafe { &before }, unsafe { &after },
		c'nocache complete fourth map lifecycle') { return false }
	C.kprintf(c'usercopy: resident non-temporal copies, alignment, page prefixes, COW sources and fences passed; no pages or heap objects retained\n')
	return true
}
