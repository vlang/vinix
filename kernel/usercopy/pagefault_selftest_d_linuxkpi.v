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

#include "linuxkpi_pagefault_v_contract.h"

fn C.vinix_linuxkpi_fault_depth() &u32
fn C.pagefault_disable()
fn C.pagefault_enable()
fn C.pagefault_disabled() bool
fn C.faulthandler_disabled() bool
fn C.vinix_linuxkpi_cpu_id() u32
fn C.vinix_linuxkpi_percpu_count() u32
fn C.vinix_linuxkpi_worker_bind(u32) int
fn C.vinix_linuxkpi_preempt_count() u32
fn C.vinix_linuxkpi_preempt_disable()
fn C.vinix_linuxkpi_preempt_enable()
fn C.vinix_linuxkpi_irq_save() u64
fn C.vinix_linuxkpi_irq_restore(u64)

const fault_test_base = u64(0x64000000)
const fault_test_cow_base = u64(0x78000000)

// Borrowed from the caller's stack until the actor has exited and joined.
// Event wakes accompany flags; no job contains a borrowed mapping pointer.
struct PagefaultActor {
mut:
	wake     eventstruct.Event
	ready    bool
	release  bool
	migrated bool
	finish   bool
	done     bool
	failed   bool
	quit     bool
}

fn fault_test_depth(expected u32) bool {
	depth := C.vinix_linuxkpi_fault_depth()
	return scalar_test_require(depth != unsafe { nil } && katomic.load(depth) == expected
		&& C.pagefault_disabled() == (expected != 0)
		&& C.faulthandler_disabled() == (expected != 0 || C.vinix_linuxkpi_preempt_count() != 0),
		c'fault depth and handler queries follow the current task')
}

fn fault_test_absent(pagemap &memory.Pagemap, address u64) bool {
	if _ := scalar_test_physical(pagemap, address) { return false }
	return true
}

fn fault_test_irq_state(enabled bool) bool {
	flags := C.vinix_linuxkpi_irq_save()
	C.vinix_linuxkpi_irq_restore(flags)
	return scalar_test_require((flags & u64(1 << 9) != 0) == enabled,
		c'fault nesting and checked page locks preserve the caller interrupt state')
}

fn fault_test_missing_checks(pagemap &memory.Pagemap, allow_faults bool) bool {
	address := fault_test_base + 4 * page_size + 3
	mut bytes := [u8(0xcc), 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc]!
	buffer := unsafe { voidptr(&bytes[0]) }
	result := unsafe { &u64(C.vinix_stack_alloc(sizeof(u64))) }
	unsafe { *result = ~u64(0) }
	if allow_faults {
		if !scalar_test_require(!read_scalar_pagemap(pagemap, address, 8, result)
			&& unsafe { *result } == 0 && !write_scalar_pagemap(pagemap, address, 8,
				scalar_test_pattern), c'disabled missing scalar read clears all bits and store fails') {
			return false
		}
	}
	if !scalar_test_require(copy_pagemap_policy_remaining(pagemap, buffer, address,
		8, false, allow_faults, allow_faults) == 8
		&& copy_pagemap_policy_remaining(pagemap, buffer, address,
			8, true, allow_faults, allow_faults) == 8,
		c'blocked missing raw copy returns its complete remainder') { return false }
	for byte in bytes {
		if byte != 0xcc { return scalar_test_require(false, c'blocked raw read leaves suffix untouched') }
	}
	return scalar_test_require(fault_test_absent(pagemap, address)
		&& pagemap.resident_bytes == page_size, c'blocked missing access does not instantiate a page')
}

fn fault_test_prefix_checks(pagemap &memory.Pagemap, allow_faults bool) bool {
	address := fault_test_base + page_size - 4
	if !scalar_test_seed(pagemap, address, 4, 0x44332211) { return false }
	mut bytes := [u8(0xcc), 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc]!
	buffer := unsafe { voidptr(&bytes[0]) }
	if !scalar_test_require(copy_pagemap_policy_remaining(pagemap, buffer, address, 8,
		false, allow_faults, allow_faults) == 4,
		c'blocked raw read preserves its resident prefix and exact remainder') { return false }
	for i in 0 .. 8 {
		expected := if i < 4 { u8(u64(0x44332211) >> u32(8 * i)) } else { u8(0xcc) }
		if bytes[i] != expected { return scalar_test_require(false, c'raw resident prefix and untouched tail') }
	}
	for i in 0 .. 8 { bytes[i] = u8(scalar_test_pattern >> u32(8 * i)) }
	if !scalar_test_require(copy_pagemap_policy_remaining(pagemap, buffer, address, 8,
		true, allow_faults, allow_faults) == 4
		&& scalar_store_test_bytes(pagemap, address, 4, scalar_test_pattern),
		c'blocked raw store commits only the resident prefix') { return false }
	if allow_faults {
		result := unsafe { &u64(C.vinix_stack_alloc(sizeof(u64))) }
		unsafe { *result = ~u64(0) }
		// Native checked split-page accesses may commit a writable prefix.
		// They promise neither rollback nor Linux exception-table recovery.
		if !scalar_test_require(!read_scalar_pagemap(pagemap, address, 8, result)
			&& unsafe { *result } == 0 && !write_scalar_pagemap(pagemap, address, 8,
				~scalar_test_pattern)
			&& scalar_store_test_bytes(pagemap, address, 4, ~scalar_test_pattern),
			c'disabled cross-page scalar clears output and preserves permitted store prefix') {
			return false
		}
	}
	return scalar_test_require(fault_test_absent(pagemap, fault_test_base + page_size)
		&& pagemap.resident_bytes == page_size, c'blocked suffix remains absent')
}

fn fault_test_resident_checks(pagemap &memory.Pagemap, allow_faults bool) bool {
	address := fault_test_base + 32
	mut bytes := [u8(0x11), 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88]!
	buffer := unsafe { voidptr(&bytes[0]) }
	if !scalar_test_require(copy_pagemap_policy_remaining(pagemap, buffer, address, 8,
		true, allow_faults, allow_faults) == 0, c'resident raw store in restricted scope') { return false }
	unsafe { C.memset(buffer, 0, 8) }
	if !scalar_test_require(copy_pagemap_policy_remaining(pagemap, buffer, address, 8,
		false, allow_faults, allow_faults) == 0, c'resident raw read in restricted scope') { return false }
	for i in 0 .. 8 {
		if bytes[i] != u8(scalar_test_pattern >> u32(8 * i)) {
			return scalar_test_require(false, c'resident raw bytes preserved')
		}
	}
	for width in [u64(1), 2, 4, 8]! {
		if !scalar_test_require(write_scalar_pagemap(pagemap, address, width, scalar_test_pattern)
			&& scalar_test_value(pagemap, address, width,
				scalar_test_pattern & scalar_test_mask(width)),
			c'resident scalar works without resolving a fault') { return false }
	}
	return true
}

fn fault_test_disabled_missing(pagemap &memory.Pagemap) bool {
	C.pagefault_disable()
	C.pagefault_disable()
	defer { C.pagefault_enable(); C.pagefault_enable() }
	return fault_test_depth(2) && fault_test_resident_checks(pagemap, true)
		&& fault_test_missing_checks(pagemap, true) && fault_test_prefix_checks(pagemap, true)
}

fn fault_test_preempt_missing(pagemap &memory.Pagemap) bool {
	C.vinix_linuxkpi_preempt_disable()
	defer { C.vinix_linuxkpi_preempt_enable() }
	return scalar_test_require(C.vinix_linuxkpi_preempt_count() != 0,
		c'actual preemption pin is visible') && fault_test_depth(0)
		&& fault_test_resident_checks(pagemap, true)
		&& fault_test_missing_checks(pagemap, true) && fault_test_prefix_checks(pagemap, true)
}

fn fault_test_irq_missing(pagemap &memory.Pagemap) bool {
	flags := C.vinix_linuxkpi_irq_save()
	defer { C.vinix_linuxkpi_irq_restore(flags) }
	return fault_test_irq_state(false) && fault_test_disabled_missing(pagemap)
		&& fault_test_depth(0) && fault_test_irq_state(false)
}

fn fault_test_missing() bool {
	mut pagemap := memory.new_pagemap() @[freed]
	defer {
		mmap.delete_pagemap(mut pagemap) or { panic('usercopy: fault test lazy cleanup failed') }
	}
	if !scalar_test_require(scalar_test_map(pagemap, fault_test_base,
		64 * 1024 * 1024, false) && pagemap.resident_bytes == 0,
		c'fault test owns an unpublished sparse map') { return false }
	if !scalar_test_require(write_scalar_pagemap(pagemap, fault_test_base + page_size - 4,
		4, scalar_test_pattern) && pagemap.resident_bytes == page_size,
		c'ordinary access resolves the first sparse page') { return false }
	if !fault_test_irq_state(true) || !fault_test_irq_missing(pagemap)
		|| !fault_test_irq_state(true) || !fault_test_disabled_missing(pagemap) || !fault_test_depth(0)
		|| !fault_test_preempt_missing(pagemap) || !fault_test_depth(0) { return false }
	// Explicit inatomic policy remains resident-only even at task depth zero.
	if !fault_test_resident_checks(pagemap, false) || !fault_test_missing_checks(pagemap, false)
		|| !fault_test_prefix_checks(pagemap, false) || !fault_test_depth(0) { return false }
	mut bytes := [u8(0), 0, 0, 0, 0, 0, 0, 0]!
	buffer := unsafe { voidptr(&bytes[0]) }
	if !scalar_test_require(copy_pagemap_policy_remaining(pagemap, buffer,
		fault_test_base + page_size - 4, 8, false, true, true) == 0
		&& pagemap.resident_bytes == 2 * page_size,
		c'enabled ordinary copy resolves the formerly blocked suffix') { return false }
	for i in 4 .. 8 {
		if bytes[i] != 0 { return scalar_test_require(false, c'new anonymous suffix is zero') }
	}
	return scalar_test_require(write_scalar_pagemap(pagemap,
		fault_test_base + 4 * page_size + 3, 8, scalar_test_pattern)
		&& scalar_store_test_bytes(pagemap, fault_test_base + 4 * page_size + 3,
			8, scalar_test_pattern) && pagemap.resident_bytes == 3 * page_size,
		c'enabled ordinary scalar store resolves the blocked missing page')
}

fn fault_test_cow_blocked(pagemap &memory.Pagemap, child &memory.Pagemap,
	shared_alias voidptr, physical u64, allow_faults bool) bool {
	address := fault_test_cow_base + 64
	mut bytes := [u8(0xaa), 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa]!
	buffer := unsafe { voidptr(&bytes[0]) }
	if allow_faults && write_scalar_pagemap(pagemap, address, 8, ~scalar_test_pattern) {
		return scalar_test_require(false, c'disabled COW scalar store fails')
	}
	if !scalar_test_require(copy_pagemap_policy_remaining(pagemap, buffer, address,
		8, true, allow_faults, allow_faults) == 8
		&& copy_pagemap_policy_remaining(pagemap, buffer, address,
			8, false, allow_faults, allow_faults) == 0,
		c'COW raw write fails while its resident read succeeds') { return false }
	for i in 0 .. 8 {
		if bytes[i] != u8(scalar_test_pattern >> u32(8 * i)) {
			return scalar_test_require(false, c'resident COW raw read returns original bytes')
		}
	}
	parent_alias := scalar_test_physical(pagemap, address) or { return false }
	child_alias := scalar_test_physical(child, address) or { return false }
	return scalar_test_require(parent_alias == shared_alias && child_alias == shared_alias
		&& memory.pmm_refcount(voidptr(physical)) == 2
		&& scalar_store_test_bytes(pagemap, address, 8, scalar_test_pattern)
		&& scalar_store_test_bytes(child, address, 8, scalar_test_pattern)
		&& scalar_test_value(pagemap, address, 8, scalar_test_pattern),
		c'blocked COW preserves both bytes and shared physical references')
}

fn fault_test_disabled_cow(pagemap &memory.Pagemap, child &memory.Pagemap,
	shared_alias voidptr, physical u64) bool {
	C.pagefault_disable()
	defer { C.pagefault_enable() }
	return fault_test_depth(1) && fault_test_cow_blocked(pagemap, child, shared_alias, physical, true)
}

fn fault_test_preempt_cow(pagemap &memory.Pagemap, child &memory.Pagemap,
	shared_alias voidptr, physical u64) bool {
	C.vinix_linuxkpi_preempt_disable()
	defer { C.vinix_linuxkpi_preempt_enable() }
	return fault_test_depth(0) && fault_test_cow_blocked(pagemap, child, shared_alias, physical, true)
}

fn fault_test_irq_cow(pagemap &memory.Pagemap, child &memory.Pagemap,
	shared_alias voidptr, physical u64) bool {
	flags := C.vinix_linuxkpi_irq_save()
	defer { C.vinix_linuxkpi_irq_restore(flags) }
	return fault_test_irq_state(false)
		&& fault_test_disabled_cow(pagemap, child, shared_alias, physical)
		&& fault_test_depth(0) && fault_test_irq_state(false)
}

fn fault_test_cow() bool {
	mut pagemap := memory.new_pagemap() @[freed]
	defer {
		mmap.delete_pagemap(mut pagemap) or { panic('usercopy: fault test COW parent cleanup failed') }
	}
	address := fault_test_cow_base + 64
	if !scalar_test_require(scalar_test_map(pagemap, fault_test_cow_base, page_size, false)
		&& write_scalar_pagemap(pagemap, address, 8, scalar_test_pattern),
		c'fault COW original page') { return false }
	mut child := mmap.fork_pagemap(pagemap, pagemap.kernel_owner) or {
		return scalar_test_require(false, c'fault test actual COW fork')
	}
	defer {
		mmap.delete_pagemap(mut child) or { panic('usercopy: fault test COW child cleanup failed') }
	}
	shared_alias := scalar_test_physical(pagemap, address) or { return false }
	physical := u64(shared_alias) - memory.get_hhdm_offset() - (address & (page_size - 1))
	if !fault_test_irq_state(true) || !fault_test_irq_cow(pagemap, child, shared_alias, physical)
		|| !fault_test_irq_state(true)
		|| !fault_test_disabled_cow(pagemap, child, shared_alias, physical) || !fault_test_depth(0)
		|| !fault_test_preempt_cow(pagemap, child, shared_alias, physical) || !fault_test_depth(0)
		|| !fault_test_cow_blocked(pagemap, child, shared_alias, physical, false) { return false }
	if !scalar_test_require(write_scalar_pagemap(pagemap, address, 8, ~scalar_test_pattern),
		c'enabled scalar store resolves genuine COW') { return false }
	parent := scalar_test_physical(pagemap, address) or { return false }
	parent_physical := u64(parent) - memory.get_hhdm_offset() - (address & (page_size - 1))
	return scalar_test_require(parent != shared_alias && memory.pmm_refcount(voidptr(physical)) == 1
		&& memory.pmm_refcount(voidptr(parent_physical)) == 1
		&& scalar_store_test_bytes(pagemap, address, 8, ~scalar_test_pattern)
		&& scalar_store_test_bytes(child, address, 8, scalar_test_pattern),
		c'enabled COW writes only parent and releases exactly its shared reference')
}

fn fault_test_batch() bool {
	return fault_test_depth(0) && fault_test_missing() && fault_test_cow() && fault_test_depth(0)
}

fn fault_test_actor_wait(_controller &PagefaultActor, finish bool) bool {
	mut controller := unsafe { _controller }
	for {
		if katomic.load(&controller.quit) { return false }
		ready := if finish { katomic.load(&controller.finish) } else { katomic.load(&controller.release) }
		if ready { return true }
		event.await_one(mut controller.wake, true)
	}
	return false
}

fn fault_test_actor_context(_controller &PagefaultActor) bool {
	mut controller := unsafe { _controller }
	// Creation occurred while the parent had depth two. New tasks start zero.
	if !fault_test_depth(0) || C.vinix_linuxkpi_worker_bind(0) != 0
		|| C.vinix_linuxkpi_cpu_id() != 0 { return false }
	C.pagefault_disable()
	C.pagefault_disable()
	mut held := u32(2)
	// This helper returns before pthread_exit, so every abort balances depth.
	defer { for held > 0 { C.pagefault_enable(); held-- } }
	if !fault_test_depth(2) { return false }
	katomic.store(mut &controller.ready, true)
	if !fault_test_actor_wait(controller, false) || !fault_test_depth(2) { return false }
	target := if C.vinix_linuxkpi_percpu_count() > 1 { u32(1) } else { u32(0) }
	if C.vinix_linuxkpi_worker_bind(target) != 0 { return false }
	sched.yield(true)
	if !scalar_test_require(C.vinix_linuxkpi_cpu_id() == target && fault_test_depth(2),
		c'task-local disabled scope survives sleep, yield and CPU migration') { return false }
	katomic.store(mut &controller.migrated, true)
	if !fault_test_actor_wait(controller, true) || !fault_test_depth(2) { return false }
	C.pagefault_enable()
	held--
	if !fault_test_depth(1) { return false }
	C.pagefault_enable()
	held--
	return fault_test_depth(0)
}

fn fault_test_actor(argument voidptr) {
	mut controller := unsafe { &PagefaultActor(argument) }
	ok := fault_test_actor_context(controller)
	katomic.store(mut &controller.failed, !ok)
	katomic.store(mut &controller.ready, true)
	katomic.store(mut &controller.migrated, true)
	katomic.store(mut &controller.done, true)
	for !katomic.load(&controller.quit) { event.await_one(mut controller.wake, true) }
	// No controller access after exiting; the parent's join retains its frame.
	event.pthread_exit(unsafe { nil })
}

fn fault_test_wait(_controller &PagefaultActor, stage int, actor &proc.Thread, parked bool) bool {
	mut controller := unsafe { _controller }
	started := time.monotonic_ns()
	for {
		if katomic.load(&controller.failed) { return false }
		ready := match stage {
			0 { katomic.load(&controller.ready) }
			1 { katomic.load(&controller.migrated) }
			else { katomic.load(&controller.done) }
		}
		if ready && (!parked || (!katomic.load(&actor.is_in_queue)
			&& katomic.load(&actor.running_on) == u64(-1) && !katomic.load(&actor.is_dead))) {
			// In particular, observing done must precede the final failure read:
			// the actor publishes failed before done and may do so mid-poll.
			return scalar_test_require(!katomic.load(&controller.failed),
				c'fault actor completed the observed context stage successfully')
		}
		if time.monotonic_ns() - started >= scalar_test_timeout_ns {
			return scalar_test_require(false, c'fault actor stage or actual sleep deadline')
		}
		sched.reschedule()
	}
	return false
}

fn fault_test_join(_controller &PagefaultActor, actor &proc.Thread) bool {
	mut controller := unsafe { _controller }
	katomic.store(mut &controller.quit, true)
	event.trigger(mut controller.wake, false)
	started := time.monotonic_ns()
	for !katomic.load(&actor.pthread_exited) {
		if time.monotonic_ns() - started >= scalar_test_timeout_ns {
			lib.kpanic(unsafe { nil }, c'usercopy: fault actor exit deadline')
		}
		sched.reschedule()
	}
	mut owner := unsafe { actor }
	if !katomic.cas(mut &owner.pthread_joinable, u32(1), u32(0)) {
		lib.kpanic(unsafe { nil }, c'usercopy: fault actor join owner lost')
	}
	event.pthread_wait(actor)
	// One pin remains after the join pin is released, retaining this observer.
	for !C.vinix_linuxkpi_test_thread_reap_ready(actor) {
		if time.monotonic_ns() - started >= scalar_test_timeout_ns {
			proc.unpin_thread(actor)
			sched.reap_deferred()
			return scalar_test_require(false, c'fault actor off-stack deadline')
		}
		sched.reschedule()
	}
	proc.unpin_thread(actor)
	// The actor pointer is dead after its final pin; never inspect it again.
	sched.reap_deferred()
	for !C.vinix_linuxkpi_test_reap_quiescent() {
		if time.monotonic_ns() - started >= scalar_test_timeout_ns {
			return scalar_test_require(false, c'fault actor final reclamation deadline')
		}
		sched.reap_deferred()
		sched.reschedule()
	}
	return true
}

fn fault_test_lifecycle() bool {
	if !fault_test_depth(0) { return false }
	mut controller := unsafe { &PagefaultActor(C.vinix_stack_alloc(sizeof(PagefaultActor))) }
	unsafe { *controller = PagefaultActor{} }
	C.pagefault_disable()
	C.pagefault_disable()
	mut held := u32(2)
	defer { for held > 0 { C.pagefault_enable(); held-- } }
	mut actor := sched.try_new_kernel_thread(voidptr(fault_test_actor), controller) or {
		return scalar_test_require(false, c'fault actor creation')
	}
	proc.pin_thread(actor)
	proc.pin_thread(actor)
	actor.pthread_joinable = 1
	if !sched.enqueue_thread(actor, false) {
		proc.unpin_thread(actor)
		proc.unpin_thread(actor)
		sched.discard_unstarted_thread(actor)
		return scalar_test_require(false, c'fault actor enqueue')
	}
	mut joined := false
	defer { if !joined { fault_test_join(controller, actor) } }
	if !fault_test_wait(controller, 0, actor, true) || !fault_test_depth(2) { return false }
	C.pagefault_enable()
	held--
	if !fault_test_depth(1) { return false }
	C.pagefault_enable()
	held--
	// The other sleeping task remains disabled while this task is enabled.
	if !fault_test_depth(0) { return false }
	katomic.store(mut &controller.release, true)
	event.trigger(mut controller.wake, false)
	if !fault_test_wait(controller, 1, actor, true) || !fault_test_depth(0) { return false }
	katomic.store(mut &controller.finish, true)
	event.trigger(mut controller.wake, false)
	if !fault_test_wait(controller, 2, actor, true) || !fault_test_depth(0) { return false }
	for _ in 0 .. 3 { if !fault_test_batch() { return false } }
	mut before := ScalarSnapshot{}
	mut after := ScalarSnapshot{}
	if !scalar_test_snapshot(unsafe { &before }) { return false }
	before.free_bytes = memory.free_bytes()
	if !fault_test_batch() { return false }
	if !scalar_test_snapshot(unsafe { &after }) { return false }
	after.free_bytes = memory.free_bytes()
	if !scalar_test_same_memory(unsafe { &before }, unsafe { &after },
		c'fault resident fourth batch') { return false }
	join_ok := fault_test_join(controller, actor)
	joined = true
	return join_ok
}

pub fn pagefault_selftest() bool {
	for i in 0 .. 3 {
		before := memory.free_bytes()
		if !fault_test_lifecycle() { return false }
		C.kprintf(c'usercopy: fault complete-lifecycle warmup %d free-byte baseline=%llu after=%llu\n',
			i + 1, before, memory.free_bytes())
	}
	mut before := ScalarSnapshot{}
	mut after := ScalarSnapshot{}
	if !scalar_test_snapshot(unsafe { &before }) { return false }
	before.free_bytes = memory.free_bytes()
	if !fault_test_lifecycle() { return false }
	if !scalar_test_snapshot(unsafe { &after }) { return false }
	after.free_bytes = memory.free_bytes()
	if !scalar_test_same_memory(unsafe { &before }, unsafe { &after },
		c'fault complete fourth actor lifecycle') { return false }
	C.kprintf(c'usercopy: task-local fault scopes, sleep and migration, resident-only copies, demand faults and COW passed; no pages or heap objects retained\n')
	return true
}
