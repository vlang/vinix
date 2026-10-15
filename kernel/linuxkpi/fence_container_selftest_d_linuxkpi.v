// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module linuxkpi

import event
import katomic
import lib
import memory
import proc
import sched
import x86.cpu
import x86.cpu.local as cpulocal
import x86.hpet as fct_clock

#include "linuxkpi_fence_container_fixture_v_primitives.h"

fn C.vinix_linuxkpi_fct_bytes(u32) u32
fn C.vinix_linuxkpi_fct_array(i32, voidptr, u64, u32, bool) voidptr
fn C.vinix_linuxkpi_fct_chain_alloc() voidptr
fn C.vinix_linuxkpi_fct_chain_free(voidptr)
fn C.vinix_linuxkpi_fct_chain_init(voidptr, voidptr, voidptr, u64)
fn C.vinix_linuxkpi_fct_walk(voidptr) voidptr
fn C.vinix_linuxkpi_fct_find(&voidptr, u64) i32
fn C.vinix_linuxkpi_fct_first(voidptr) voidptr
fn C.vinix_linuxkpi_fct_next(voidptr, u32) voidptr
fn C.vinix_linuxkpi_fct_match(voidptr, u64) bool
fn C.vinix_linuxkpi_fct_kind(voidptr) u32
fn C.vinix_linuxkpi_fct_refs(voidptr) u32
fn C.vinix_linuxkpi_fct_value(voidptr, u32) u64
fn C.vinix_linuxkpi_fct_pending(voidptr) i32

// All pointers published to another task, IRQ or an API output slot live in
// this boot-lifetime ledger. Reset only after joins, IRQ return and RCU barrier.
struct FenceContainerLedger {
mut:
	ready [3]bool
	commands [3]u32
	started [3]bool
	done [3]bool
	owners [3]voidptr
	quit bool
	reader_held bool
	reader_release bool
	target_held bool
	irq_done bool
	irq C.vinix_irqwork_fixture
	irq_fence voidptr
	leaves [128]voidptr
	count u32
	head voidptr
	out voidptr
	failures u32
}
__global fence_container_ledger FenceContainerLedger

fn fct_fail(bit u32) {
	for {
		old := katomic.load(&fence_container_ledger.failures)
		if katomic.cas(mut &fence_container_ledger.failures, old, old | bit) { return }
	}
}
fn fct_wait(flag &bool) bool {
	start := fct_clock.nanoseconds()
	for !katomic.load(flag) {
		if fct_clock.nanoseconds() - start >= dmafence_test_timeout_ns { return false }
		sched.reschedule()
	}
	return katomic.load(&fence_container_ledger.failures) == 0
}
fn fct_actor(argument voidptr) {
	index := u32(usize(argument))
	if worker_bind(index + 1) != 0 || !dma_fence_test_task(index + 1) { fct_fail(1) }
	katomic.store(mut &fence_container_ledger.ready[index], true)
	for !katomic.load(&fence_container_ledger.quit) {
		command := katomic.load(&fence_container_ledger.commands[index])
		if command == 0 { sched.reschedule(); continue }
		katomic.store(mut &fence_container_ledger.started[index], true)
		if command == 1 || command == 2 {
			preempt_disable()
			if command == 1 { preempt_disable(); katomic.store(mut &fence_container_ledger.reader_held, true) }
			else { katomic.store(mut &fence_container_ledger.target_held, true) }
			start := fct_clock.nanoseconds()
			for {
				if (command == 1 && katomic.load(&fence_container_ledger.reader_release))
					|| (command == 2 && katomic.load(&fence_container_ledger.irq_done)) { break }
				if fct_clock.nanoseconds() - start >= dmafence_test_timeout_ns {
					lib.kpanic(unsafe { nil }, c'linuxkpi: fence container pinned actor deadline')
				}
				spin_wait()
			}
			if command == 1 { preempt_enable() }
			preempt_enable()
		} else { C.vinix_linuxkpi_rcu_fixture_barrier() }
		if !dma_fence_test_task(index + 1) { fct_fail(2) }
		katomic.store(mut &fence_container_ledger.commands[index], u32(0))
		katomic.store(mut &fence_container_ledger.done[index], true)
	}
	event.pthread_exit(unsafe { nil })
}
fn fct_start(index u32, command u32) {
	katomic.store(mut &fence_container_ledger.done[index], false)
	katomic.store(mut &fence_container_ledger.started[index], false)
	katomic.store(mut &fence_container_ledger.commands[index], command)
}
fn fct_finish(index u32) {
	if !fct_wait(&fence_container_ledger.done[index]) {
		lib.kpanic(unsafe { nil }, c'linuxkpi: fence container actor cleanup deadline')
	}
}
fn fct_irq(_work &C.irq_work) {
	local := cpulocal.current()
	if cpu.interrupt_state() || local.maskable_irq_depth == 0 || local.cpu_number != 1 { fct_fail(4) }
	test_alloc_oom(0)
	result := C.vinix_linuxkpi_dmafence_fixture_signal(fence_container_ledger.irq_fence, 0, 0)
	valid := proc.current_thread().linuxkpi_alloc_fail_after == 0 && !cpu.interrupt_state()
	test_alloc_oom(-1)
	if result != 0 || !valid { fct_fail(8) }
	katomic.store(mut &fence_container_ledger.irq_done, true)
}
fn fct_signal_irq(fence voidptr) bool {
	fence_container_ledger.irq_fence = fence
	katomic.store(mut &fence_container_ledger.irq_done, false)
	katomic.store(mut &fence_container_ledger.target_held, false)
	fct_start(0, 2)
	mut queued := false
	defer {
		if queued { C.vinix_linuxkpi_irqwork_fixture_sync(unsafe { &fence_container_ledger.irq }) }
		katomic.store(mut &fence_container_ledger.irq_done, true)
		fct_finish(0)
		fence_container_ledger.irq_fence = unsafe { nil }
	}
	if !fct_wait(&fence_container_ledger.target_held) { return false }
	if C.vinix_linuxkpi_irqwork_fixture_init(unsafe { &fence_container_ledger.irq }, fct_irq, 0) != 0 { return false }
	queued = C.vinix_linuxkpi_irqwork_fixture_queue(unsafe { &fence_container_ledger.irq }, 1)
	return queued && fct_wait(&fence_container_ledger.irq_done)
}
fn fct_signaled(fence voidptr) bool {
	start := fct_clock.nanoseconds()
	// Raw bit observation deliberately avoids ops.signaled's synchronous poll.
	for C.vinix_linuxkpi_fct_value(fence, 0) & 1 == 0 {
		if fct_clock.nanoseconds() - start >= dmafence_test_timeout_ns { return false }
		sched.reschedule()
	}
	return true
}
fn fct_clear() {
	for i in 0 .. fence_container_ledger.count {
		C.vinix_linuxkpi_dmafence_fixture_signal(fence_container_ledger.leaves[i], 0, 0)
	}
	C.vinix_linuxkpi_dmafence_fixture_put(fence_container_ledger.out)
	fence_container_ledger.out = unsafe { nil }
	if fence_container_ledger.head != unsafe { nil } {
		// All producers have stopped and every child has signaled. Let queued
		// container IRQ callbacks relinquish their references before the final
		// external put, so the following barrier includes every owner free.
		start := fct_clock.nanoseconds()
		for C.vinix_linuxkpi_fct_refs(fence_container_ledger.head) != 1 {
			if fct_clock.nanoseconds() - start >= dmafence_test_timeout_ns {
				lib.kpanic(unsafe { nil }, c'linuxkpi: fence container callback retirement deadline')
			}
			sched.reschedule()
		}
	}
	C.vinix_linuxkpi_dmafence_fixture_put(fence_container_ledger.head)
	fence_container_ledger.head = unsafe { nil }
	for i in 0 .. fence_container_ledger.count {
		C.vinix_linuxkpi_dmafence_fixture_put(fence_container_ledger.leaves[i])
		fence_container_ledger.leaves[i] = unsafe { nil }
	}
	fence_container_ledger.count = 0
	C.vinix_linuxkpi_rcu_fixture_barrier()
}
fn fct_leaves(count u32, kind u32, context u64) bool {
	for i in 0 .. count {
		leaf := dma_fence_test_new(kind, 0, context, u64(i + 1))
		if leaf == unsafe { nil } { return false }
		fence_container_ledger.leaves[i] = leaf
		fence_container_ledger.count++
	}
	return true
}
fn fct_array_new(any bool) voidptr {
	count := fence_container_ledger.count
	unsafe {
		vector := &voidptr(C.kmalloc(usize(count) * sizeof(voidptr), 3264))
		if vector == nil { return nil }
		for i in 0 .. count { vector[i] = C.vinix_linuxkpi_dmafence_fixture_get(fence_container_ledger.leaves[i], 0) }
		head := C.vinix_linuxkpi_fct_array(i32(count), vector, C.vinix_linuxkpi_dmafence_fixture_context(1), 7, any)
		if head == nil {
			for i in 0 .. count { C.vinix_linuxkpi_dmafence_fixture_put(vector[i]) }
			C.kfree(vector)
		}
		return head
	}
}
fn fct_arrays(any bool) bool {
	defer { fct_clear() }
	context := C.vinix_linuxkpi_dmafence_fixture_context(1)
	if !fct_leaves(3, 1, context) { return false }
	fence_container_ledger.head = fct_array_new(any)
	head := fence_container_ledger.head
	if head == unsafe { nil } { return false }
	if C.vinix_linuxkpi_fct_kind(head) != 1 || C.vinix_linuxkpi_fct_kind(fence_container_ledger.leaves[0]) != 0
		|| !C.vinix_linuxkpi_fct_match(head, context) || C.vinix_linuxkpi_fct_match(head, context + 1)
		|| C.vinix_linuxkpi_fct_first(head) != fence_container_ledger.leaves[0]
		|| C.vinix_linuxkpi_fct_next(head, 2) != fence_container_ledger.leaves[2]
		|| C.vinix_linuxkpi_fct_next(head, 3) != unsafe { nil } { return false }
	C.vinix_linuxkpi_dmafence_fixture_deadline(head, 987654321)
	if dmafence_test_ledger.deadline != 987654321 { return false }
	C.vinix_linuxkpi_dmafence_fixture_enable(head)
	if C.vinix_linuxkpi_fct_refs(head) != 4 { return false }
	C.vinix_linuxkpi_dmafence_fixture_error(fence_container_ledger.leaves[0], -5)
	if !fct_signal_irq(fence_container_ledger.leaves[0]) { return false }
	if any {
		if !fct_signaled(head) || C.vinix_linuxkpi_dmafence_fixture_status(head) != -5
			|| C.vinix_linuxkpi_fct_pending(head) != 0 { return false }
	} else if C.vinix_linuxkpi_fct_value(head, 0) & 1 != 0 { return false }
	C.vinix_linuxkpi_dmafence_fixture_error(fence_container_ledger.leaves[1], -6)
	for i in 1 .. 3 { if !fct_signal_irq(fence_container_ledger.leaves[i]) { return false } }
	return fct_signaled(head) && C.vinix_linuxkpi_dmafence_fixture_status(head) == -5
		&& C.vinix_linuxkpi_fct_pending(head) == if any { -2 } else { 0 }
}
fn fct_oom_and_poll() bool {
	defer { fct_clear() }
	if !fct_leaves(1, 0, C.vinix_linuxkpi_dmafence_fixture_context(1)) { return false }
	vector := C.kmalloc(sizeof(voidptr), 3264)
	if vector == unsafe { nil } { return false }
	unsafe { (&voidptr(vector))[0] = C.vinix_linuxkpi_dmafence_fixture_get(fence_container_ledger.leaves[0], 0) }
	test_alloc_oom(0)
	missing := C.vinix_linuxkpi_fct_array(1, vector, 1, 0, false)
	test_alloc_oom(-1)
	if missing != unsafe { nil } {
		C.vinix_linuxkpi_dmafence_fixture_put(missing)
		return false
	}
	// Failed construction leaves both the vector and its child reference owned.
	valid := C.vinix_linuxkpi_fct_refs(fence_container_ledger.leaves[0]) == 2
	C.vinix_linuxkpi_dmafence_fixture_put(fence_container_ledger.leaves[0])
	C.kfree(vector)
	if !valid { return false }
	test_alloc_oom(0)
	missing_chain := C.vinix_linuxkpi_fct_chain_alloc()
	test_alloc_oom(-1)
	if missing_chain != unsafe { nil } { C.vinix_linuxkpi_fct_chain_free(missing_chain); return false }
	unpublished := C.vinix_linuxkpi_fct_chain_alloc()
	if unpublished == unsafe { nil } { return false }
	C.vinix_linuxkpi_fct_chain_free(unpublished)
	C.vinix_linuxkpi_dmafence_fixture_signal(fence_container_ledger.leaves[0], 0, 0)
	fence_container_ledger.head = fct_array_new(false)
	if fence_container_ledger.head == unsafe { nil } { return false }
	return C.vinix_linuxkpi_dmafence_fixture_signaled(fence_container_ledger.head, false)
		&& C.vinix_linuxkpi_dmafence_fixture_status(fence_container_ledger.head) == 1
		&& C.vinix_linuxkpi_fct_refs(fence_container_ledger.head) == 1
}
fn fct_chain_append(leaf voidptr, seqno u64) bool {
	node := C.vinix_linuxkpi_fct_chain_alloc()
	if node == unsafe { nil } { return false }
	child := C.vinix_linuxkpi_dmafence_fixture_get(leaf, 0)
	C.vinix_linuxkpi_fct_chain_init(node, fence_container_ledger.head, child, seqno)
	// Successful init transfers the old head and child references to this node.
	fence_container_ledger.head = node
	return true
}
fn fct_chain_basics() bool {
	defer { fct_clear() }
	if !fct_leaves(3, 1, C.vinix_linuxkpi_dmafence_fixture_context(1)) { return false }
	if !fct_chain_append(fence_container_ledger.leaves[0], 10) { return false }
	context := C.vinix_linuxkpi_fct_value(fence_container_ledger.head, 1)
	if C.vinix_linuxkpi_fct_value(fence_container_ledger.head, 3) != 0 { return false }
	if !fct_chain_append(fence_container_ledger.leaves[1], 20)
		|| !fct_chain_append(fence_container_ledger.leaves[2], 30) { return false }
	head := fence_container_ledger.head
	if C.vinix_linuxkpi_fct_kind(head) != 2 || C.vinix_linuxkpi_fct_value(head, 1) != context
		|| C.vinix_linuxkpi_fct_value(head, 3) != 20 { return false }
	C.vinix_linuxkpi_dmafence_fixture_deadline(head, 112233)
	if dmafence_test_ledger.deadline != 112233 { return false }
	fence_container_ledger.out = C.vinix_linuxkpi_dmafence_fixture_get(head, 0)
	if C.vinix_linuxkpi_fct_find(unsafe { &fence_container_ledger.out }, 31) != -22
		|| fence_container_ledger.out != head
		|| C.vinix_linuxkpi_fct_find(unsafe { &fence_container_ledger.out }, 20) != 0
		|| C.vinix_linuxkpi_fct_value(fence_container_ledger.out, 2) != 20 { return false }
	C.vinix_linuxkpi_dmafence_fixture_put(fence_container_ledger.out)
	fence_container_ledger.out = unsafe { nil }
	C.vinix_linuxkpi_dmafence_fixture_enable(head)
	// The head's same callback/IRQ union repeatedly changes representation.
	for i := 3; i > 0; {
		i--
		if !fct_signal_irq(fence_container_ledger.leaves[i]) { return false }
		if i != 0 {
			start := fct_clock.nanoseconds()
			for C.vinix_linuxkpi_dmafence_fixture_callbacks(fence_container_ledger.leaves[i - 1]) != 1 {
				if fct_clock.nanoseconds() - start >= dmafence_test_timeout_ns { return false }
				sched.reschedule()
			}
		}
	}
	if !fct_signaled(head) { return false }
	fence_container_ledger.out = C.vinix_linuxkpi_fct_walk(C.vinix_linuxkpi_dmafence_fixture_get(head, 0))
	return fence_container_ledger.out == unsafe { nil } && C.vinix_linuxkpi_dmafence_fixture_status(head) == 1
}
fn fct_chain_release() bool {
	defer { fct_clear() }
	if !fct_leaves(128, 0, C.vinix_linuxkpi_dmafence_fixture_context(1)) { return false }
	for i in 0 .. 128 {
		if !fct_chain_append(fence_container_ledger.leaves[i], u64(i + 1)) { return false }
	}
	context := C.vinix_linuxkpi_fct_value(fence_container_ledger.head, 1)
	// A non-increasing sequence gets a fresh context and clamps its seqno.
	if !fct_chain_append(fence_container_ledger.leaves[0], 1) { return false }
	return C.vinix_linuxkpi_fct_value(fence_container_ledger.head, 1) != context
		&& C.vinix_linuxkpi_fct_value(fence_container_ledger.head, 2) == 128
		&& C.vinix_linuxkpi_fct_value(fence_container_ledger.head, 3) == 0
}
fn fct_deferred() bool {
	mut reader := false
	mut barrier := false
	defer {
		katomic.store(mut &fence_container_ledger.reader_release, true)
		if reader { fct_finish(2) }
		if barrier { fct_finish(1) }
		fct_clear()
	}
	if !fct_leaves(1, 0, C.vinix_linuxkpi_dmafence_fixture_context(1)) { return false }
	fence_container_ledger.head = fct_array_new(false)
	head := fence_container_ledger.head
	if head == unsafe { nil } { return false }
	if !fct_chain_append(head, 1) { return false }
	// append consumed the previous head as prev and took a separate contained
	// reference. This deliberately exercises an array as an ordinary prev.
	head_chain := fence_container_ledger.head
	C.vinix_linuxkpi_dmafence_fixture_enable(head_chain)
	katomic.store(mut &fence_container_ledger.reader_held, false)
	katomic.store(mut &fence_container_ledger.reader_release, false)
	fct_start(2, 1)
	reader = true
	if !fct_wait(&fence_container_ledger.reader_held) { return false }
	C.vinix_linuxkpi_dmafence_fixture_put(head_chain)
	fence_container_ledger.head = unsafe { nil }
	if !fct_signal_irq(fence_container_ledger.leaves[0]) { return false }
	start := fct_clock.nanoseconds()
	for {
		preempt_disable()
		dead := C.vinix_linuxkpi_fct_refs(head_chain) == 0
		preempt_enable()
		if dead { break }
		if fct_clock.nanoseconds() - start >= dmafence_test_timeout_ns { return false }
		sched.reschedule()
	}
	for C.vkiw_running_count(voidptr(usize(head_chain) + 88)) != 0 {
		if fct_clock.nanoseconds() - start >= dmafence_test_timeout_ns { return false }
		sched.reschedule()
	}
	// Do not reinterpret the chain union as irq_work here. The original IRQ
	// dispatcher retains only a pointer record after its callback's final put.
	force := C.vinix_linuxkpi_rcu_test_force_count()
	held := memory.free_bytes()
	fct_start(1, 3)
	barrier = true
	for C.vinix_linuxkpi_rcu_test_force_count() == force {
		if fct_clock.nanoseconds() - start >= dmafence_test_timeout_ns { return false }
		sched.reschedule()
	}
	if katomic.load(&fence_container_ledger.done[1]) || memory.free_bytes() != held { return false }
	katomic.store(mut &fence_container_ledger.reader_release, true)
	return fct_wait(&fence_container_ledger.done[2]) && fct_wait(&fence_container_ledger.done[1])
}
fn fct_lifecycle() bool {
	ints := cpu.interrupt_toggle(false)
	mut controller := proc.current_thread()
	affinity := katomic.load(&controller.affinity_mask)
	numa := katomic.load(&controller.numa_node)
	gate := controller.linuxkpi_alloc_fail_after
	cpu.interrupt_toggle(ints)
	mut owners := unsafe { [3]&proc.Thread{} }
	mut created := 0
	defer {
		katomic.store(mut &fence_container_ledger.reader_release, true)
		katomic.store(mut &fence_container_ledger.irq_done, true)
		katomic.store(mut &fence_container_ledger.quit, true)
		for i in 0 .. created { irq_test_join(owners[i]) }
		C.vinix_linuxkpi_rcu_fixture_barrier()
		selftest_free_baseline()
		restore := cpu.interrupt_toggle(false)
		controller.linuxkpi_alloc_fail_after = gate
		katomic.store(mut &controller.numa_node, numa)
		katomic.store(mut &controller.affinity_mask, affinity)
		cpu.interrupt_toggle(restore)
	}
	if !ints || worker_bind(0) != 0 { return false }
	fence_container_ledger = FenceContainerLedger{}
	for i in 0 .. 3 {
		mut actor := sched.try_new_kernel_thread(voidptr(fct_actor), voidptr(i)) or { return false }
		proc.pin_thread(actor)
		proc.pin_thread(actor)
		actor.pthread_joinable = 1
		if !sched.enqueue_thread(actor, false) {
			proc.unpin_thread(actor)
			proc.unpin_thread(actor)
			sched.discard_unstarted_thread(actor)
			return false
		}
		owners[i] = actor
		fence_container_ledger.owners[i] = actor
		created++
	}
	for i in 0 .. 3 { if !fct_wait(&fence_container_ledger.ready[i]) { return false } }
	return fct_oom_and_poll() && fct_arrays(false) && fct_arrays(true)
		&& fct_chain_basics() && fct_chain_release() && fct_deferred()
}
fn fence_containers_native_selftest() bool {
	if cpu_locals.len < 4 || cpu_locals.len > 64 || C.vinix_linuxkpi_fct_bytes(0) != 120
		|| C.vinix_linuxkpi_fct_bytes(1) != 128 || C.vinix_linuxkpi_fct_bytes(2) != 32 { return false }
	for round in 0 .. 3 {
		before := selftest_free_baseline()
		if !fct_lifecycle() { return false }
		C.kprintf(c'linuxkpi: fence container lifecycle warmup %d free-byte baseline=%llu after=%llu\n', round + 1, before, selftest_free_baseline())
	}
	mut before := CPUFeatureHeapSnapshot{}
	mut after := CPUFeatureHeapSnapshot{}
	free_before := selftest_free_baseline()
	if !cpu_feature_test_heap(unsafe { &before }) || !fct_lifecycle() { return false }
	free_after := selftest_free_baseline()
	if !cpu_feature_test_heap(unsafe { &after }) { return false }
	mut equal := before.count == after.count
	for i in 0 .. before.count {
		if before.sizes[i] != after.sizes[i] || before.live[i] != after.live[i] { equal = false }
	}
	C.kprintf(c'linuxkpi: fence container fourth lifecycle free-byte baseline=%llu after=%llu heap_equal=%d\n', free_before, free_after, int(equal))
	return free_before == free_after && equal && katomic.load(&fence_container_ledger.failures) == 0
}
