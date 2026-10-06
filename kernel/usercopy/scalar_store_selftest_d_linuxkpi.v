// SPDX-License-Identifier: GPL-2.0-or-later
@[manualfree]
module usercopy

import event
import event.eventstruct
import katomic
import lib
import memory
import memory.mmap
import proc
import sched
import time

const scalar_store_test_base = u64(0x28000000)
const scalar_store_test_lazy_base = u64(0x50000000)

// The actor only borrows this caller-stack controller. Its page/width job
// stays fixed until completed acknowledges the last physical-page load.
struct ScalarStoreReader {
mut:
	wake      eventstruct.Event
	ready     bool
	quit      bool
	stop      bool
	request   u64
	completed u64
	reads     u64
	saw_a     bool
	saw_b     bool
	invalid   bool
	address   voidptr
	width     u64
}

fn scalar_store_test_bytes(pagemap &memory.Pagemap, address u64, width u64, value u64) bool {
	for i := u64(0); i < width; i++ {
		physical := scalar_test_physical(pagemap, address + i) or { return false }
		if unsafe { *(&u8(physical)) } != u8(value >> u32(8 * i)) { return false }
	}
	return true
}

fn scalar_store_test_fill(pagemap &memory.Pagemap, address u64, length u64, value u8) bool {
	for i := u64(0); i < length; i++ {
		physical := scalar_test_physical(pagemap, address + i) or { return false }
		unsafe { *(&u8(physical)) = value }
	}
	return true
}

fn scalar_store_test_window(pagemap &memory.Pagemap, address u64, width u64, value u64) bool {
	if !scalar_store_test_fill(pagemap, address - 1, width + 2, 0xcc) { return false }
	return scalar_test_require(write_scalar_pagemap(pagemap, address, width, value)
		&& scalar_store_test_bytes(pagemap, address, width, value)
		&& scalar_store_test_bytes(pagemap, address - 1, 1, 0xcc)
		&& scalar_store_test_bytes(pagemap, address + width, 1, 0xcc),
		c'scalar store width, little-endian bytes and adjacent sentinels')
}

fn scalar_store_test_same_page() bool {
	mut pagemap := memory.new_pagemap() @[freed]
	defer {
		mmap.delete_pagemap(mut pagemap) or { panic('usercopy: scalar store page cleanup failed') }
	}
	if !scalar_test_require(scalar_test_map(pagemap, scalar_store_test_base,
		page_size, true), c'scalar store page creation') { return false }
	for width in [u64(1), 2, 4, 8]! {
		for offset in [u64(32), 49]! {
			for value in [scalar_test_pattern, ~u64(0), u64(-3), u64(0)]! {
				if !scalar_store_test_window(pagemap, scalar_store_test_base + offset,
					width, value) { return false }
			}
		}
	}
	return true
}

fn scalar_store_test_cross_layout(separated bool) bool {
	mut pagemap := memory.new_pagemap() @[freed]
	defer {
		mmap.delete_pagemap(mut pagemap) or { panic('usercopy: scalar store layout cleanup failed') }
	}
	count := if separated { u64(3) } else { u64(2) }
	backing := memory.pmm_alloc_fallible(count) @[freed]
	if backing == unsafe { nil } {
		return scalar_test_require(false, c'scalar store physical layout allocation')
	}
	mut handed_off := false
	defer {
		if !handed_off {
			memory.pmm_free(backing, count)
		} else if separated {
			// The middle page was never handed to a range. The two endpoints
			// remain range-owned until delete_pagemap runs below this defer.
			memory.pmm_free(voidptr(u64(backing) + page_size), 1)
		}
	}
	if separated {
		mmap.map_range(mut pagemap, scalar_store_test_base, u64(backing), page_size,
			mmap.prot_read | mmap.prot_write, mmap.map_private) or {
			lib.kpanic(unsafe { nil }, c'usercopy: scalar store first physical map failed')
		}
		mmap.map_range(mut pagemap, scalar_store_test_base + page_size,
			u64(backing) + 2 * page_size, page_size,
			mmap.prot_read | mmap.prot_write, mmap.map_private) or {
			lib.kpanic(unsafe { nil }, c'usercopy: scalar store second physical map failed')
		}
	} else {
		mmap.map_range(mut pagemap, scalar_store_test_base, u64(backing), 2 * page_size,
			mmap.prot_read | mmap.prot_write, mmap.map_private) or {
			lib.kpanic(unsafe { nil }, c'usercopy: scalar store contiguous physical map failed')
		}
	}
	handed_off = true
	first := scalar_test_physical(pagemap, scalar_store_test_base) or { return false }
	second := scalar_test_physical(pagemap, scalar_store_test_base + page_size) or { return false }
	expected := u64(first) + if separated { 2 * page_size } else { page_size }
	if !scalar_test_require(u64(second) == expected,
		c'scalar store actual contiguous or separated physical layout') { return false }
	for width in [u64(2), 4, 8]! {
		for prefix := u64(1); prefix < width; prefix++ {
			address := scalar_store_test_base + page_size - prefix
			if !scalar_store_test_window(pagemap, address, width, scalar_test_pattern)
				|| !scalar_store_test_window(pagemap, address, width, ~u64(0)) {
				return false
			}
		}
	}
	return true
}

fn scalar_store_test_suffix(protection int, hole bool) bool {
	mut pagemap := memory.new_pagemap() @[freed]
	defer {
		mmap.delete_pagemap(mut pagemap) or { panic('usercopy: scalar store suffix cleanup failed') }
	}
	if !scalar_test_require(scalar_test_map(pagemap, scalar_store_test_base,
		2 * page_size, true), c'scalar store suffix map creation') { return false }
	second_address := scalar_store_test_base + page_size
	mut second := scalar_test_physical(pagemap, second_address) or { return false }
	if hole {
		mmap.munmap(mut pagemap, voidptr(second_address), page_size) or {
			return scalar_test_require(false, c'scalar store hole creation')
		}
		// munmap released the old physical page: retain no pointer to it.
		second = unsafe { nil }
	} else {
		mmap.mprotect(mut pagemap, voidptr(second_address), page_size, protection) or {
			return scalar_test_require(false, c'scalar store suffix protection')
		}
		// mprotect changes the local PTE, while the range's shadow continues
		// to own this physical page until the unpublished map is deleted.
		if !scalar_test_require(memory.pmm_refcount(voidptr(u64(second)
			- memory.get_hhdm_offset())) == 1, c'protected store suffix backing remains owned') {
			return false
		}
	}
	for width in [u64(2), 4, 8]! {
		prefix := width - 1
		address := second_address - prefix
		if !scalar_store_test_fill(pagemap, address - 1, prefix + 1, 0xcc) { return false }
		if !hole { unsafe { C.memset(second, 0xcc, page_size) } }
		// This native split-page contract commits a protected first-page
		// prefix before the inaccessible suffix fails. It supplies no rollback
		// or atomicity promise and does not establish pinned Linux MOV effects.
		if !scalar_test_require(!write_scalar_pagemap(pagemap, address, width,
			scalar_test_pattern), c'inaccessible scalar store suffix fails')
			|| !scalar_store_test_bytes(pagemap, address, prefix, scalar_test_pattern)
			|| !scalar_store_test_bytes(pagemap, address - 1, 1, 0xcc) {
			return false
		}
		if hole {
			if _ := scalar_test_physical(pagemap, second_address) {
				return scalar_test_require(false, c'scalar store hole remains absent')
			}
		} else {
			for i := u64(0); i < page_size; i++ {
				if unsafe { (&u8(second))[i] } != 0xcc {
					return scalar_test_require(false, c'inaccessible scalar store suffix unchanged')
				}
			}
			for same_width in [u64(1), 2, 4, 8]! {
				if write_scalar_pagemap(pagemap, second_address + 32, same_width, ~u64(0)) {
					return scalar_test_require(false, c'protected same-page scalar store denied')
				}
				for i in 0 .. 8 {
					if unsafe { (&u8(second))[32 + i] } != 0xcc {
						return scalar_test_require(false, c'failed protected scalar store changes no bytes')
					}
				}
			}
		}
	}
	return true
}

fn scalar_store_test_invalid() bool {
	mut pagemap := memory.new_pagemap() @[freed]
	defer {
		mmap.delete_pagemap(mut pagemap) or { panic('usercopy: scalar store invalid cleanup failed') }
	}
	limit := memory.user_address_limit()
	if !scalar_test_require(scalar_test_map(pagemap, scalar_store_test_base, page_size, true)
		&& scalar_test_map(pagemap, limit - page_size, page_size, true),
		c'scalar store invalid-range control maps') { return false }
	if !scalar_store_test_fill(pagemap, scalar_store_test_base + 32, 16, 0xcc)
		|| !scalar_store_test_fill(pagemap, limit - 8, 8, 0xcc) { return false }
	resident := pagemap.resident_bytes
	for width in [u64(0), 3, 16]! {
		if write_scalar_pagemap(pagemap, scalar_store_test_base + 32, width, ~u64(0)) {
			return scalar_test_require(false, c'invalid scalar store width')
		}
	}
	if write_scalar_pagemap(pagemap, 0, 1, ~u64(0))
		|| write_scalar_pagemap(pagemap, limit, 1, ~u64(0))
		|| write_scalar_pagemap(pagemap, limit - 1, 2, ~u64(0))
		|| write_scalar_pagemap(pagemap, u64(-2), 4, ~u64(0))
		|| write_scalar_pagemap(unsafe { nil }, scalar_store_test_base, 8, ~u64(0)) {
		return scalar_test_require(false, c'invalid whole scalar store range')
	}
	return scalar_test_require(pagemap.resident_bytes == resident
		&& scalar_store_test_bytes(pagemap, scalar_store_test_base + 32, 8, 0xcccccccccccccccc)
		&& scalar_store_test_bytes(pagemap, scalar_store_test_base + 40, 8, 0xcccccccccccccccc)
		&& scalar_store_test_bytes(pagemap, limit - 8, 8, 0xcccccccccccccccc),
		c'invalid whole scalar store range commits no prefix or allocation')
}

fn scalar_store_test_lazy_and_cow() bool {
	mut pagemap := memory.new_pagemap() @[freed]
	defer {
		mmap.delete_pagemap(mut pagemap) or { panic('usercopy: scalar store lazy cleanup failed') }
	}
	if !scalar_test_require(scalar_test_map(pagemap, scalar_store_test_lazy_base,
		64 * 1024 * 1024, false) && pagemap.resident_bytes == 0,
		c'scalar store sparse anonymous reservation absent') { return false }
	mut touched := u64(0)
	for width in [u64(1), 2, 4, 8]! {
		address := scalar_store_test_lazy_base + (16 + 16 * touched) * page_size + 3
		if !scalar_test_require(write_scalar_pagemap(pagemap, address, width, scalar_test_pattern)
			&& scalar_store_test_bytes(pagemap, address, width, scalar_test_pattern),
			c'actual scalar store missing-page fault') { return false }
		touched++
		if !scalar_test_require(pagemap.resident_bytes == touched * page_size,
			c'scalar store faults only its touched page') { return false }
	}
	cross_address := scalar_store_test_lazy_base + 80 * page_size - 3
	if !scalar_test_require(write_scalar_pagemap(pagemap, cross_address, 8, scalar_test_pattern)
		&& scalar_store_test_bytes(pagemap, cross_address, 8, scalar_test_pattern)
		&& pagemap.resident_bytes == 6 * page_size,
		c'actual cross-page scalar store faults exactly two sparse pages') { return false }
	address := scalar_store_test_lazy_base + 64 * page_size + 3
	mut child := mmap.fork_pagemap(pagemap) or {
		return scalar_test_require(false, c'actual scalar store COW fork')
	}
	defer {
		mmap.delete_pagemap(mut child) or { panic('usercopy: scalar store child cleanup failed') }
	}
	shared := scalar_test_physical(pagemap, address) or { return false }
	shared_physical := u64(shared) - memory.get_hhdm_offset() - (address & (page_size - 1))
	if !scalar_test_require(memory.pmm_refcount(voidptr(shared_physical)) == 2,
		c'scalar store native COW starts with two page references') { return false }
	if !scalar_test_require(write_scalar_pagemap(pagemap, address, 8, scalar_test_pattern_b)
		&& scalar_store_test_bytes(pagemap, address, 8, scalar_test_pattern_b)
		&& scalar_store_test_bytes(child, address, 8, scalar_test_pattern),
		c'actual scalar store COW preserves child original bytes') { return false }
	parent_page := scalar_test_physical(pagemap, address) or { return false }
	parent_physical := u64(parent_page) - memory.get_hhdm_offset() - (address & (page_size - 1))
	return scalar_test_require(parent_page != shared
		&& memory.pmm_refcount(voidptr(shared_physical)) == 1
		&& memory.pmm_refcount(voidptr(parent_physical)) == 1,
		c'scalar store COW separates physical pages and reference counts')
}

fn scalar_store_test_load(address voidptr, width u64) u64 {
	if width == 2 { return u64(katomic.load(unsafe { &u16(address) })) }
	if width == 4 { return u64(katomic.load(unsafe { &u32(address) })) }
	return katomic.load(unsafe { &u64(address) })
}

fn scalar_store_test_reader(argument voidptr) {
	mut reader := unsafe { &ScalarStoreReader(argument) }
	katomic.store(mut &reader.ready, true)
	for !katomic.load(&reader.quit) {
		request := katomic.load(&reader.request)
		if request == katomic.load(&reader.completed) {
			event.await_one(mut reader.wake, true) or { sched.reschedule() }
			continue
		}
		address := reader.address
		width := reader.width
		mask := scalar_test_mask(width)
		a := scalar_test_pattern_a & mask
		b := scalar_test_pattern_b & mask
		mut count := u64(0)
		for !katomic.load(&reader.stop) && !katomic.load(&reader.quit) {
			value := scalar_store_test_load(address, width)
			if value == a { katomic.store(mut &reader.saw_a, true) }
			if value == b { katomic.store(mut &reader.saw_b, true) }
			if value != a && value != b { katomic.store(mut &reader.invalid, true) }
			katomic.inc(mut &reader.reads)
			count++
			if count & 255 == 0 { sched.reschedule() }
		}
		// Parent mapping teardown is safe only after this publication.
		katomic.store(mut &reader.completed, request)
	}
	// Join preserves the controller frame through the last actor access.
	event.pthread_exit(unsafe { nil })
}

fn scalar_store_test_wait_ready(reader &ScalarStoreReader) bool {
	started := time.monotonic_ns()
	for !katomic.load(&reader.ready) {
		if time.monotonic_ns() - started >= scalar_test_timeout_ns {
			return scalar_test_require(false, c'scalar store reader readiness deadline')
		}
		sched.reschedule()
	}
	return true
}

fn scalar_store_test_stop(_reader &ScalarStoreReader, request u64) {
	mut reader := unsafe { _reader }
	katomic.store(mut &reader.stop, true)
	event.trigger(mut reader.wake, false)
	started := time.monotonic_ns()
	for katomic.load(&reader.completed) != request {
		if time.monotonic_ns() - started >= scalar_test_timeout_ns {
			lib.kpanic(unsafe { nil }, c'usercopy: scalar store reader did not release its page')
		}
		sched.reschedule()
	}
}

fn scalar_store_test_coherent(_reader &ScalarStoreReader, width u64) bool {
	mut reader := unsafe { _reader }
	mut pagemap := memory.new_pagemap() @[freed]
	defer {
		mmap.delete_pagemap(mut pagemap) or { panic('usercopy: scalar store coherence cleanup failed') }
	}
	if !scalar_test_require(scalar_test_map(pagemap, scalar_store_test_base, page_size,
		true), c'scalar store coherence map creation') { return false }
	address := scalar_store_test_base + 64
	physical := scalar_test_physical(pagemap, address) or { return false }
	if !scalar_test_require(u64(physical) & (width - 1) == 0,
		c'naturally aligned scalar store coherence operand') { return false }
	if !write_scalar_pagemap(pagemap, address, width, scalar_test_pattern_a) { return false }
	reader.address = physical
	reader.width = width
	katomic.store(mut &reader.reads, u64(0))
	katomic.store(mut &reader.saw_a, false)
	katomic.store(mut &reader.saw_b, false)
	katomic.store(mut &reader.invalid, false)
	katomic.store(mut &reader.stop, false)
	request := katomic.load(&reader.request) + 1
	katomic.store(mut &reader.request, request)
	event.trigger(mut reader.wake, false)
	defer { scalar_store_test_stop(reader, request) }
	started := time.monotonic_ns()
	mut writes := u64(0)
	mut value := scalar_test_pattern_b
	for writes < 4096 || katomic.load(&reader.reads) < 4096
		|| !katomic.load(&reader.saw_a) || !katomic.load(&reader.saw_b) {
		if time.monotonic_ns() - started >= scalar_test_timeout_ns {
			return scalar_test_require(false, c'aligned scalar store coherence progress deadline')
		}
		if !scalar_test_require(!katomic.load(&reader.invalid)
			&& write_scalar_pagemap(pagemap, address, width, value),
			c'aligned scalar store and independent reader see complete values') { return false }
		value = if value == scalar_test_pattern_a { scalar_test_pattern_b } else { scalar_test_pattern_a }
		writes++
		if writes & 255 == 0 { sched.reschedule() }
	}
	scalar_store_test_stop(reader, request)
	return scalar_test_require(!katomic.load(&reader.invalid),
		c'scalar store reader final acknowledgment preserves complete values')
}

fn scalar_store_test_batch(reader &ScalarStoreReader) bool {
	return scalar_store_test_same_page() && scalar_store_test_cross_layout(false)
		&& scalar_store_test_cross_layout(true) && scalar_store_test_suffix(mmap.prot_read, false)
		&& scalar_store_test_suffix(mmap.prot_none, false) && scalar_store_test_suffix(0, true)
		&& scalar_store_test_invalid() && scalar_store_test_lazy_and_cow()
		&& scalar_store_test_coherent(reader, 2) && scalar_store_test_coherent(reader, 4)
		&& scalar_store_test_coherent(reader, 8)
}

fn scalar_store_test_join(_reader &ScalarStoreReader, actor &proc.Thread) bool {
	mut reader := unsafe { _reader }
	katomic.store(mut &reader.stop, true)
	katomic.store(mut &reader.quit, true)
	event.trigger(mut reader.wake, false)
	started := time.monotonic_ns()
	for !katomic.load(&actor.pthread_exited) {
		if time.monotonic_ns() - started >= scalar_test_timeout_ns {
			lib.kpanic(unsafe { nil }, c'usercopy: scalar store reader exit deadline')
		}
		sched.reschedule()
	}
	mut owner := unsafe { actor }
	if !katomic.cas(mut &owner.pthread_joinable, u32(1), u32(0)) {
		lib.kpanic(unsafe { nil }, c'usercopy: scalar store reader join owner lost')
	}
	event.pthread_wait(actor)
	// The second retained reference protects this off-stack observer after
	// pthread_wait has released the join reference.
	for !C.vinix_linuxkpi_test_thread_reap_ready(actor) {
		if time.monotonic_ns() - started >= scalar_test_timeout_ns {
			proc.unpin_thread(actor)
			sched.reap_deferred()
			return scalar_test_require(false, c'scalar store reader off-stack deadline')
		}
		sched.reschedule()
	}
	proc.unpin_thread(actor)
	// Never inspect actor after releasing its final retained reference.
	sched.reap_deferred()
	for !C.vinix_linuxkpi_test_reap_quiescent() {
		if time.monotonic_ns() - started >= scalar_test_timeout_ns {
			return scalar_test_require(false, c'scalar store reader final reclamation deadline')
		}
		sched.reap_deferred()
		sched.reschedule()
	}
	return true
}

fn scalar_store_test_lifecycle() bool {
	mut reader := unsafe { &ScalarStoreReader(C.vinix_stack_alloc(sizeof(ScalarStoreReader))) }
	unsafe { *reader = ScalarStoreReader{} }
	mut actor := sched.try_new_kernel_thread(voidptr(scalar_store_test_reader), reader) or {
		return scalar_test_require(false, c'scalar store reader creation')
	}
	proc.pin_thread(actor)
	proc.pin_thread(actor)
	actor.pthread_joinable = 1
	if !sched.enqueue_thread(actor, false) {
		proc.unpin_thread(actor)
		proc.unpin_thread(actor)
		sched.discard_unstarted_thread(actor)
		return scalar_test_require(false, c'scalar store reader enqueue')
	}
	mut joined := false
	defer { if !joined { scalar_store_test_join(reader, actor) } }
	if !scalar_store_test_wait_ready(reader) { return false }
	for _ in 0 .. 3 { if !scalar_store_test_batch(reader) { return false } }
	mut before := ScalarSnapshot{}
	mut after := ScalarSnapshot{}
	if !scalar_test_snapshot(unsafe { &before }) { return false }
	before.free_bytes = memory.free_bytes()
	if !scalar_store_test_batch(reader) { return false }
	if !scalar_test_snapshot(unsafe { &after }) { return false }
	after.free_bytes = memory.free_bytes()
	if !scalar_test_same_memory(unsafe { &before }, unsafe { &after },
		c'store resident fourth batch') { return false }
	join_ok := scalar_store_test_join(reader, actor)
	joined = true
	return join_ok
}

pub fn scalar_store_selftest() bool {
	for i in 0 .. 3 {
		before := memory.free_bytes()
		if !scalar_store_test_lifecycle() { return false }
		C.kprintf(c'usercopy: scalar store complete-lifecycle warmup %d free-byte baseline=%llu after=%llu\n',
			i + 1, before, memory.free_bytes())
	}
	mut before := ScalarSnapshot{}
	mut after := ScalarSnapshot{}
	if !scalar_test_snapshot(unsafe { &before }) { return false }
	before.free_bytes = memory.free_bytes()
	if !scalar_store_test_lifecycle() { return false }
	if !scalar_test_snapshot(unsafe { &after }) { return false }
	after.free_bytes = memory.free_bytes()
	if !scalar_test_same_memory(unsafe { &before }, unsafe { &after },
		c'store complete fourth actor lifecycle') { return false }
	C.kprintf(c'usercopy: scalar stores, page prefixes, demand faults, COW and aligned concurrent reads passed; no pages or heap objects retained\n')
	return true
}
