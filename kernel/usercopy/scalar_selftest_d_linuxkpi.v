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

#include "linuxkpi_scalar_uaccess_v_contract.h"

fn C.vinix_linuxkpi_test_thread_reap_ready(voidptr) bool
fn C.vinix_linuxkpi_test_reap_quiescent() bool
fn C.vinix_linuxkpi_cpu_id() u32
fn C.vinix_linuxkpi_percpu_count() u32
fn C.vinix_linuxkpi_worker_bind(u32) int
fn C.vinix_linuxkpi_irq_save() u64
fn C.vinix_linuxkpi_irq_restore(u64)

const scalar_test_base = u64(0x24000000)
const scalar_test_lazy_base = u64(0x48000000)
const scalar_test_timeout_ns = u64(10000000000)
const scalar_test_pattern = u64(0x8877665544332211)
const scalar_test_pattern_a = u64(0x55aa55aa55aa55aa)
const scalar_test_pattern_b = u64(0xaa55aa55aa55aa55)

struct ScalarSnapshot {
mut:
	free_bytes u64
	count      int
	sizes      [64]u64
	live       [64]u64
}

// The controller is borrowed from the caller's stack until its writer has
// joined. Fields describing a job are published by request and remain fixed
// until completed acknowledges the writer's last physical-page access.
struct ScalarWriter {
mut:
	wake      eventstruct.Event
	ready     bool
	quit      bool
	stop      bool
	request   u64
	completed u64
	writes    u64
	address   voidptr
	width     u64
	warm_cpu  u32
	bind_error int
}

fn scalar_test_require(ok bool, message &char) bool {
	if !ok {
		C.kprintf(c'usercopy: scalar self-test failed: %s\n', message)
	}
	return ok
}

fn scalar_test_snapshot(_snapshot &ScalarSnapshot) bool {
	mut snapshot := unsafe { _snapshot }
	mut classes := [64]memory.HeapClass{}
	count := memory.heap_classes_into(unsafe { &classes[0] }, classes.len)
	if count < 0 || count > snapshot.live.len {
		return scalar_test_require(false, c'heap snapshot capacity')
	}
	snapshot.count = count
	for i in 0 .. count {
		class := classes[i]
		snapshot.sizes[i] = class.size
		snapshot.live[i] = class.live
	}
	return true
}

fn scalar_test_same_heap(before &ScalarSnapshot, after &ScalarSnapshot, scope &char) bool {
	if before.count != after.count {
		C.kprintf(c'usercopy: scalar %s heap class count before=%d after=%d\n',
			scope, before.count, after.count)
		return false
	}
	mut equal := true
	for i := 0; i < before.count; i++ {
		if before.sizes[i] != after.sizes[i] || before.live[i] != after.live[i] {
			C.kprintf(c'usercopy: scalar %s heap class before=%llu after=%llu live before=%llu after=%llu\n',
				scope, before.sizes[i], after.sizes[i], before.live[i], after.live[i])
			equal = false
		}
	}
	return equal
}

fn scalar_test_same_memory(before &ScalarSnapshot, after &ScalarSnapshot, scope &char) bool {
	// Always inspect the live heap, including when physical pages differ.
	heap_equal := scalar_test_same_heap(before, after, scope)
	C.kprintf(c'usercopy: scalar %s free-byte baseline=%llu after=%llu heap_equal=%d\n',
		scope, before.free_bytes, after.free_bytes, int(heap_equal))
	return before.free_bytes == after.free_bytes && heap_equal
}

// These maps are never installed on any CPU. The fixture owns all mappings,
// and a writer job's completion precedes deletion of its physical backing.
fn scalar_test_physical(_pagemap &memory.Pagemap, address u64) ?voidptr {
	mut pagemap := unsafe { _pagemap }
	pagemap.l.acquire()
	physical := pagemap.virt2phys(address) or {
		pagemap.l.release()
		return none
	}
	pagemap.l.release()
	return voidptr(physical + (address & (page_size - 1)) + memory.get_hhdm_offset())
}

fn scalar_test_map(pagemap &memory.Pagemap, base u64, length u64, populate bool) bool {
	flags := mmap.map_private | mmap.map_anonymous | mmap.map_fixed |
		if populate { mmap.map_populate } else { 0 }
	address := mmap.mmap(pagemap, voidptr(base), length, mmap.prot_read | mmap.prot_write,
		flags, unsafe { nil }, 0, unsafe { nil }, unsafe { nil }, unsafe { nil }) or {
		return false
	}
	return u64(address) == base
}

fn scalar_test_mask(width u64) u64 {
	return if width == 8 { ~u64(0) } else { (u64(1) << u32(8 * width)) - 1 }
}

// Seed byte order independently from the reader under test, including when
// adjacent virtual pages have different physical backing.
fn scalar_test_seed(pagemap &memory.Pagemap, address u64, width u64, value u64) bool {
	for i := u64(0); i < width; i++ {
		physical := scalar_test_physical(pagemap, address + i) or { return false }
		unsafe { *(&u8(physical)) = u8(value >> u32(8 * i)) }
	}
	return true
}

fn scalar_test_value(pagemap &memory.Pagemap, address u64, width u64, expected u64) bool {
	result := unsafe { &u64(C.vinix_stack_alloc(sizeof(u64))) }
	unsafe { *result = ~u64(0) }
	return scalar_test_require(read_scalar_pagemap(pagemap, address, width, result)
		&& unsafe { *result } == expected, c'scalar width and little-endian value')
}

fn scalar_test_failure(pagemap &memory.Pagemap, address u64, width u64) bool {
	result := unsafe { &u64(C.vinix_stack_alloc(sizeof(u64))) }
	unsafe { *result = ~u64(0) }
	return scalar_test_require(!read_scalar_pagemap(pagemap, address, width, result)
		&& unsafe { *result } == 0, c'inaccessible scalar clears the whole result')
}

fn scalar_test_boundaries() bool {
	mut pagemap := memory.new_pagemap() @[freed]
	defer {
		mmap.delete_pagemap(mut pagemap) or { panic('usercopy: scalar boundary cleanup failed') }
	}
	if !scalar_test_require(scalar_test_map(pagemap, scalar_test_base, 2 * page_size, true),
		c'boundary map creation') {
		return false
	}
	for width in [u64(1), 2, 4, 8]! {
		for offset in [u64(32), 49]! {
			address := scalar_test_base + offset
			if !scalar_test_seed(pagemap, address, width, scalar_test_pattern)
				|| !scalar_test_value(pagemap, address, width,
					scalar_test_pattern & scalar_test_mask(width)) {
				return false
			}
		}
		// The native result is an unsigned bit pattern; the caller's scalar
		// type supplies signed interpretation without losing its high bit.
		negative := scalar_test_mask(width)
		if !scalar_test_seed(pagemap, scalar_test_base + 80, width, negative)
			|| !scalar_test_value(pagemap, scalar_test_base + 80, width, negative) {
			return false
		}
	}
	for width in [u64(2), 4, 8]! {
		address := scalar_test_base + page_size - (width - 1)
		if !scalar_test_seed(pagemap, address, width, scalar_test_pattern)
			|| !scalar_test_value(pagemap, address, width,
				scalar_test_pattern & scalar_test_mask(width)) {
			return false
		}
	}
	mmap.mprotect(mut pagemap, voidptr(scalar_test_base), 2 * page_size, mmap.prot_read) or {
		return scalar_test_require(false, c'read-only map protection')
	}
	if !scalar_test_seed(pagemap, scalar_test_base + 32, 8, scalar_test_pattern)
		|| !scalar_test_value(pagemap, scalar_test_base + 32, 8, scalar_test_pattern) {
		return false
	}
	mmap.munmap(mut pagemap, voidptr(scalar_test_base + page_size), page_size) or {
		return scalar_test_require(false, c'boundary hole creation')
	}
	for width in [u64(2), 4, 8]! {
		if !scalar_test_failure(pagemap, scalar_test_base + page_size - (width - 1), width) {
			return false
		}
	}
	if !scalar_test_require(scalar_test_map(pagemap, scalar_test_base + page_size,
		page_size, true), c'boundary hole replacement') {
		return false
	}
	mmap.mprotect(mut pagemap, voidptr(scalar_test_base + page_size), page_size,
		mmap.prot_none) or { return scalar_test_require(false, c'PROT_NONE map protection') }
	for width in [u64(1), 2, 4, 8]! {
		if !scalar_test_failure(pagemap, scalar_test_base + page_size + 32, width) {
			return false
		}
		if width != 1 && !scalar_test_failure(pagemap,
			scalar_test_base + page_size - (width - 1), width) {
			return false
		}
	}
	return scalar_test_value(pagemap, scalar_test_base + 32, 8, scalar_test_pattern)
}

fn scalar_test_invalid() bool {
	mut pagemap := memory.new_pagemap() @[freed]
	defer {
		mmap.delete_pagemap(mut pagemap) or { panic('usercopy: scalar invalid cleanup failed') }
	}
	for width in [u64(0), 3, 16]! {
		if !scalar_test_failure(pagemap, scalar_test_base, width) { return false }
	}
	limit := memory.user_address_limit()
	return scalar_test_failure(pagemap, 0, 1)
		&& scalar_test_failure(pagemap, limit, 1)
		&& scalar_test_failure(pagemap, limit - 1, 2)
		&& scalar_test_failure(pagemap, u64(-2), 4)
		&& scalar_test_failure(unsafe { nil }, scalar_test_base, 8)
}

fn scalar_test_lazy() bool {
	mut pagemap := memory.new_pagemap() @[freed]
	defer {
		mmap.delete_pagemap(mut pagemap) or { panic('usercopy: scalar lazy cleanup failed') }
	}
	if !scalar_test_require(scalar_test_map(pagemap, scalar_test_lazy_base,
		64 * 1024 * 1024, false) && pagemap.resident_bytes == 0,
		c'sparse anonymous reservation starts absent') {
		return false
	}
	source := unsafe { &u8(C.vinix_stack_alloc(8)) }
	for i in 0 .. 8 { unsafe { source[i] = u8(scalar_test_pattern >> u32(8 * i)) } }
	address := scalar_test_lazy_base + 16 * page_size + 3
	if !scalar_test_require(copy_pagemap_policy_remaining(pagemap, source, address, 8,
		true, true, true) == 0 && pagemap.resident_bytes == page_size,
		c'actual anonymous first write faults only its page') {
		return false
	}
	for width in [u64(1), 2, 4, 8]! {
		if !scalar_test_value(pagemap, address, width,
			scalar_test_pattern & scalar_test_mask(width)) {
			return false
		}
	}
	// A different absent page exercises the getter's real read-fault path.
	return scalar_test_value(pagemap, scalar_test_lazy_base + 32 * page_size + 8, 8, 0)
		&& scalar_test_require(pagemap.resident_bytes == 2 * page_size,
			c'actual anonymous scalar read faults only its page')
}

fn scalar_test_store(address voidptr, width u64, value u64) {
	if width == 2 {
		mut target := unsafe { &u16(address) }
		katomic.store(mut target, u16(value))
	} else if width == 4 {
		mut target := unsafe { &u32(address) }
		katomic.store(mut target, u32(value))
	} else {
		mut target := unsafe { &u64(address) }
		katomic.store(mut target, value)
	}
}

fn scalar_test_writer(argument voidptr) {
	mut writer := unsafe { &ScalarWriter(argument) }
	if writer.warm_cpu != ~u32(0) {
		writer.bind_error = C.vinix_linuxkpi_worker_bind(writer.warm_cpu)
		if writer.bind_error == 0 && C.vinix_linuxkpi_cpu_id() != writer.warm_cpu {
			writer.bind_error = -1
		}
		if writer.bind_error != 0 {
			// Publish failure before readiness, then release the borrowed
			// controller only through the same real join/off-stack path.
			katomic.store(mut &writer.ready, true)
			event.pthread_exit(unsafe { nil })
		}
	}
	katomic.store(mut &writer.ready, true)
	for !katomic.load(&writer.quit) {
		if writer.warm_cpu != ~u32(0) && C.vinix_linuxkpi_cpu_id() != writer.warm_cpu {
			lib.kpanic(unsafe { nil }, c'usercopy: scalar warm writer migrated outside its CPU')
		}
		request := katomic.load(&writer.request)
		if request == katomic.load(&writer.completed) {
			event.await_one(mut writer.wake, true) or { sched.reschedule() }
			continue
		}
		address := writer.address
		width := writer.width
		mut value := scalar_test_pattern_b
		for !katomic.load(&writer.stop) && !katomic.load(&writer.quit) {
			scalar_test_store(address, width, value)
			katomic.inc(mut &writer.writes)
			value = if value == scalar_test_pattern_a {
				scalar_test_pattern_b
			} else {
				scalar_test_pattern_a
			}
		}
		// No physical-page access follows this acknowledgment. The parent can
		// now reclaim that job's map while this actor sleeps for its next job.
		katomic.store(mut &writer.completed, request)
	}
	// There is no controller access after publishing pthread_exited inside
	// this exit helper. Join keeps the parent's borrowed stack frame alive.
	event.pthread_exit(unsafe { nil })
}

fn scalar_test_wait_ready(writer &ScalarWriter) bool {
	started := time.monotonic_ns()
	for !katomic.load(&writer.ready) {
		if time.monotonic_ns() - started >= scalar_test_timeout_ns {
			return scalar_test_require(false, c'writer readiness deadline')
		}
		sched.reschedule()
	}
	return true
}

fn scalar_test_stop(_writer &ScalarWriter, request u64) {
	mut writer := unsafe { _writer }
	katomic.store(mut &writer.stop, true)
	event.trigger(mut writer.wake, false)
	started := time.monotonic_ns()
	for katomic.load(&writer.completed) != request {
		if time.monotonic_ns() - started >= scalar_test_timeout_ns {
			// A failed test must never return borrowed backing to the allocator
			// while its actor can still write it.
			lib.kpanic(unsafe { nil }, c'usercopy: scalar writer did not release its page')
		}
		sched.reschedule()
	}
}

fn scalar_test_coherent(_writer &ScalarWriter, width u64) bool {
	mut writer := unsafe { _writer }
	mut pagemap := memory.new_pagemap() @[freed]
	defer {
		mmap.delete_pagemap(mut pagemap) or { panic('usercopy: scalar coherence cleanup failed') }
	}
	if !scalar_test_require(scalar_test_map(pagemap, scalar_test_base, page_size, true),
		c'coherence map creation') {
		return false
	}
	address := scalar_test_base + 64
	physical := scalar_test_physical(pagemap, address) or { return false }
	if !scalar_test_require(u64(physical) & (width - 1) == 0,
		c'naturally aligned coherence operand') {
		return false
	}
	scalar_test_store(physical, width, scalar_test_pattern_a)
	writer.address = physical
	writer.width = width
	katomic.store(mut &writer.writes, u64(0))
	katomic.store(mut &writer.stop, false)
	request := katomic.load(&writer.request) + 1
	katomic.store(mut &writer.request, request)
	event.trigger(mut writer.wake, false)
	defer { scalar_test_stop(writer, request) }
	result := unsafe { &u64(C.vinix_stack_alloc(sizeof(u64))) }
	mask := scalar_test_mask(width)
	a := scalar_test_pattern_a & mask
	b := scalar_test_pattern_b & mask
	started := time.monotonic_ns()
	mut reads := u64(0)
	mut saw_a := false
	mut saw_b := false
	for reads < 4096 || !saw_a || !saw_b || katomic.load(&writer.writes) < 1024 {
		if time.monotonic_ns() - started >= scalar_test_timeout_ns {
			return scalar_test_require(false, c'aligned coherence progress deadline')
		}
		if !scalar_test_require(read_scalar_pagemap(pagemap, address, width, result),
			c'aligned concurrent read succeeds') {
			return false
		}
		value := unsafe { *result }
		if !scalar_test_require(value == a || value == b, c'aligned read is one complete store') {
			return false
		}
		saw_a = saw_a || value == a
		saw_b = saw_b || value == b
		reads++
		if reads & 255 == 0 { sched.reschedule() }
	}
	return true
}

fn scalar_test_batch(writer &ScalarWriter) bool {
	return scalar_test_invalid() && scalar_test_boundaries() && scalar_test_lazy()
		&& scalar_test_coherent(writer, 2) && scalar_test_coherent(writer, 4)
		&& scalar_test_coherent(writer, 8)
}

fn scalar_test_join(_writer &ScalarWriter, actor &proc.Thread) bool {
	mut writer := unsafe { _writer }
	katomic.store(mut &writer.stop, true)
	katomic.store(mut &writer.quit, true)
	event.trigger(mut writer.wake, false)
	started := time.monotonic_ns()
	for !katomic.load(&actor.pthread_exited) {
		if time.monotonic_ns() - started >= scalar_test_timeout_ns {
			lib.kpanic(unsafe { nil }, c'usercopy: scalar writer exit deadline')
		}
		sched.reschedule()
	}
	mut owner := unsafe { actor }
	if !katomic.cas(mut &owner.pthread_joinable, u32(1), u32(0)) {
		lib.kpanic(unsafe { nil }, c'usercopy: scalar writer join owner lost')
	}
	event.pthread_wait(actor)
	// The second, fixture-owned reference lets this observer inspect the
	// off-stack handoff after join released its own reference.
	for !C.vinix_linuxkpi_test_thread_reap_ready(actor) {
		if time.monotonic_ns() - started >= scalar_test_timeout_ns {
			proc.unpin_thread(actor)
			sched.reap_deferred()
			return scalar_test_require(false, c'writer off-stack handoff deadline')
		}
		sched.reschedule()
	}
	proc.unpin_thread(actor)
	// Never inspect actor again after the final reference has been released.
	sched.reap_deferred()
	for !C.vinix_linuxkpi_test_reap_quiescent() {
		if time.monotonic_ns() - started >= scalar_test_timeout_ns {
			return scalar_test_require(false, c'writer final reclamation deadline')
		}
		sched.reap_deferred()
		sched.reschedule()
	}
	return true
}

fn scalar_test_lifecycle_on(warm_cpu u32) bool {
	mut writer := unsafe { &ScalarWriter(C.vinix_stack_alloc(sizeof(ScalarWriter))) }
	unsafe { *writer = ScalarWriter{warm_cpu: warm_cpu} }
	mut actor := sched.try_new_kernel_thread(voidptr(scalar_test_writer), writer) or {
		return scalar_test_require(false, c'writer creation')
	}
	// One pin is the join reference, and one observes the off-stack handoff.
	proc.pin_thread(actor)
	proc.pin_thread(actor)
	actor.pthread_joinable = 1
	if !sched.enqueue_thread(actor, false) {
		proc.unpin_thread(actor)
		proc.unpin_thread(actor)
		sched.discard_unstarted_thread(actor)
		return scalar_test_require(false, c'writer enqueue')
	}
	mut joined := false
	defer {
		if !joined { scalar_test_join(writer, actor) }
	}
	if !scalar_test_wait_ready(writer) { return false }
	if !scalar_test_require(writer.bind_error == 0, c'warm writer CPU binding') { return false }
	for _ in 0 .. 3 {
		if !scalar_test_batch(writer) { return false }
	}
	mut before := ScalarSnapshot{}
	mut after := ScalarSnapshot{}
	if !scalar_test_snapshot(unsafe { &before }) { return false }
	before.free_bytes = memory.free_bytes()
	if !scalar_test_batch(writer) { return false }
	if !scalar_test_snapshot(unsafe { &after }) { return false }
	after.free_bytes = memory.free_bytes()
	if !scalar_test_same_memory(unsafe { &before }, unsafe { &after }, c'resident fourth batch') {
		return false
	}
	join_ok := scalar_test_join(writer, actor)
	joined = true
	return join_ok
}

fn scalar_test_lifecycle() bool {
	return scalar_test_lifecycle_on(~u32(0))
}

fn scalar_test_restore_placement(owner &proc.Thread, mask u64, node int) {
	flags := C.vinix_linuxkpi_irq_save()
	katomic.store(mut unsafe { &owner.affinity_mask }, mask)
	katomic.store(mut unsafe { &owner.numa_node }, node)
	C.vinix_linuxkpi_irq_restore(flags)
}

fn scalar_test_warm_cpus() bool {
	count := C.vinix_linuxkpi_percpu_count()
	flags := C.vinix_linuxkpi_irq_save()
	owner := proc.current_thread()
	if flags & (u64(1) << 9) == 0 || owner == unsafe { nil } || count == 0 || count > 64 {
		C.vinix_linuxkpi_irq_restore(flags)
		return scalar_test_require(false, c'per-CPU warmup task and affinity domain')
	}
	mask := katomic.load(&owner.affinity_mask)
	node := katomic.load(&owner.numa_node)
	C.vinix_linuxkpi_irq_restore(flags)
	// This is the executing controller's borrowed Thread. It cannot exit
	// before this frame returns; all child lifetimes join before restoration.
	defer { scalar_test_restore_placement(owner, mask, node) }
	// A freed mapping can leave one spare per CPU/class. Three migrating
	// batches do not enumerate those caches. Run the real full workload on
	// each boot CPU exactly once, with a genuinely bound neighbor writer.
	for target := u32(0); target < count; target++ {
		if !scalar_test_require(C.vinix_linuxkpi_worker_bind(target) == 0
			&& C.vinix_linuxkpi_cpu_id() == target, c'warm controller CPU binding') { return false }
		before := memory.free_bytes()
		neighbor := if target + 1 < count { target + 1 } else { u32(0) }
		if !scalar_test_lifecycle_on(neighbor) { return false }
		if !scalar_test_require(C.vinix_linuxkpi_cpu_id() == target,
			c'warm controller placement after sleeping lifecycle') { return false }
		C.kprintf(c'usercopy: scalar per-CPU complete-lifecycle warmup CPU=%u writer=%u free-byte baseline=%llu after=%llu\n',
			target, neighbor, before, memory.free_bytes())
	}
	return true
}

pub fn scalar_selftest() bool {
	if !scalar_test_warm_cpus() { return false }
	// First use can populate permanent shared vmap page tables for the two
	// guarded worker stacks. Warm the complete lifetime, including actual
	// off-stack reclamation, before measuring another complete lifetime.
	for i in 0 .. 3 {
		before := memory.free_bytes()
		if !scalar_test_lifecycle() { return false }
		C.kprintf(c'usercopy: scalar complete-lifecycle warmup %d free-byte baseline=%llu after=%llu\n',
			i + 1, before, memory.free_bytes())
	}
	mut before := ScalarSnapshot{}
	mut after := ScalarSnapshot{}
	if !scalar_test_snapshot(unsafe { &before }) { return false }
	before.free_bytes = memory.free_bytes()
	if !scalar_test_lifecycle() { return false }
	if !scalar_test_snapshot(unsafe { &after }) { return false }
	after.free_bytes = memory.free_bytes()
	if !scalar_test_same_memory(unsafe { &before }, unsafe { &after },
		c'complete fourth actor lifecycle') {
		return false
	}
	C.kprintf(c'usercopy: scalar widths, page boundaries, fault zeros and aligned concurrent reads passed; no pages or heap objects retained\n')
	return true
}
