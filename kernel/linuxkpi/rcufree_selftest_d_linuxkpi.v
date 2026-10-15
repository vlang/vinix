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
import x86.hpet as rcufree_clock

#include "linuxkpi_rcufree_fixture_v_primitives.h"

fn C.vinix_linuxkpi_rcufree_fixture_new(u32) voidptr
fn C.vinix_linuxkpi_rcufree_fixture_check(u32, voidptr) bool
fn C.vinix_linuxkpi_rcufree_fixture_enqueue(u32, voidptr)
fn C.vinix_linuxkpi_rcufree_fixture_headless(voidptr)
fn C.vinix_linuxkpi_rcufree_fixture_immediate(voidptr)
fn C.vinix_linuxkpi_rcufree_fixture_head_offset(u32) u32

const rcufree_timeout_ns = u64(10000000000)
const rcufree_object_count = 15
const rcufree_callback_count = 9

struct RcuFreeCallback {
mut:
	head C.vinix_rcu_fixture_head
	remaining u32
}

// Cross-actor state has boot lifetime. It is reset only after every submitted
// callback and both retained native actors have actually left their stacks.
struct RcuFreeLedger {
mut:
	reader_ready bool
	aux_ready bool
	quit bool
	command u32
	phase u32
	release_inner bool
	release_scope bool
	aux_owner voidptr
	aux_command u32
	aux_started bool
	aux_done bool
	headless_payload voidptr
	callbacks u32
	freed_callbacks u32
	failures u32
}
__global rcufree_ledger RcuFreeLedger

fn rcufree_fail(bit u32) {
	for {
		old := katomic.load(&rcufree_ledger.failures)
		if katomic.cas(mut &rcufree_ledger.failures, old, old | bit) { return }
	}
}

fn rcufree_task(target u32) bool {
	ints := cpu.interrupt_toggle(false)
	local := cpulocal.current()
	ok := ints && local.cpu_number == u64(target) && local.maskable_irq_depth == 0
		&& preempt_depth[local.cpu_number] == 0 && proc.current_thread() != unsafe { nil }
	cpu.interrupt_toggle(ints)
	return ok
}

fn rcufree_spin_release(inner bool) {
	started := rcufree_clock.nanoseconds()
	for !katomic.load(&rcufree_ledger.quit) {
		released := if inner { katomic.load(&rcufree_ledger.release_inner) }
			else { katomic.load(&rcufree_ledger.release_scope) }
		if released { return }
		spin_wait()
		if rcufree_clock.nanoseconds() - started >= rcufree_timeout_ns {
			lib.kpanic(unsafe { nil }, c'linuxkpi: deferred-free held reader deadline')
		}
	}
}

fn rcufree_reader(_argument voidptr) {
	if worker_bind(1) != 0 || !rcufree_task(1) { rcufree_fail(1) }
	katomic.store(mut &rcufree_ledger.reader_ready, true)
	for !katomic.load(&rcufree_ledger.quit) {
		mode := katomic.load(&rcufree_ledger.command)
		if mode == 0 { sched.reschedule(); continue }
		if mode == 1 {
			preempt_disable()
			preempt_disable()
			katomic.store(mut &rcufree_ledger.phase, u32(1))
			rcufree_spin_release(true)
			preempt_enable()
			katomic.store(mut &rcufree_ledger.phase, u32(2))
			rcufree_spin_release(false)
			preempt_enable()
		} else {
			ints := cpu.interrupt_toggle(false)
			if !ints || cpulocal.current().cpu_number != 1 || preempt_depth[1] != 0 { rcufree_fail(2) }
			katomic.store(mut &rcufree_ledger.phase, u32(1))
			rcufree_spin_release(false)
			cpu.interrupt_toggle(ints)
		}
		if !rcufree_task(1) { rcufree_fail(4) }
		katomic.store(mut &rcufree_ledger.command, u32(0))
		katomic.store(mut &rcufree_ledger.phase, u32(3))
	}
	event.pthread_exit(unsafe { nil })
}

fn rcufree_aux(_argument voidptr) {
	if worker_bind(2) != 0 || !rcufree_task(2) { rcufree_fail(8) }
	katomic.store(mut &rcufree_ledger.aux_ready, true)
	for !katomic.load(&rcufree_ledger.quit) {
		command := katomic.load(&rcufree_ledger.aux_command)
		if command == 0 { sched.reschedule(); continue }
		katomic.store(mut &rcufree_ledger.aux_started, true)
		if command == 1 { C.vinix_linuxkpi_rcufree_fixture_headless(rcufree_ledger.headless_payload) }
		else { C.vinix_linuxkpi_rcu_fixture_barrier() }
		// The synchronous headless call owns and has already freed the payload;
		// no object read or other use of that pointer follows its return.
		if !rcufree_task(2) { rcufree_fail(16) }
		katomic.store(mut &rcufree_ledger.aux_command, u32(0))
		katomic.store(mut &rcufree_ledger.aux_done, true)
	}
	event.pthread_exit(unsafe { nil })
}

fn rcufree_wait(flag &bool) bool {
	started := rcufree_clock.nanoseconds()
	for !katomic.load(flag) {
		if katomic.load(&rcufree_ledger.failures) != 0
			|| rcufree_clock.nanoseconds() - started >= rcufree_timeout_ns { return false }
		sched.reschedule()
	}
	return katomic.load(&rcufree_ledger.failures) == 0
}

fn rcufree_wait_phase(phase u32) bool {
	started := rcufree_clock.nanoseconds()
	for katomic.load(&rcufree_ledger.phase) < phase {
		if katomic.load(&rcufree_ledger.failures) != 0
			|| rcufree_clock.nanoseconds() - started >= rcufree_timeout_ns { return false }
		sched.reschedule()
	}
	return katomic.load(&rcufree_ledger.failures) == 0
}

fn rcufree_scope_start(mode u32) bool {
	katomic.store(mut &rcufree_ledger.release_inner, false)
	katomic.store(mut &rcufree_ledger.release_scope, false)
	katomic.store(mut &rcufree_ledger.phase, u32(0))
	katomic.store(mut &rcufree_ledger.command, mode)
	return rcufree_wait_phase(1)
}

fn rcufree_aux_start(command u32) {
	katomic.store(mut &rcufree_ledger.aux_started, false)
	katomic.store(mut &rcufree_ledger.aux_done, false)
	katomic.store(mut &rcufree_ledger.aux_command, command)
}

fn rcufree_aux_parked() bool {
	owner := unsafe { &proc.Thread(rcufree_ledger.aux_owner) }
	started := rcufree_clock.nanoseconds()
	for !(katomic.load(&rcufree_ledger.aux_started)
		&& C.vinix_linuxkpi_rcu_fixture_task_sleeping(unsafe { &owner.linuxkpi_task[0] })
		&& !katomic.load(&owner.is_in_queue) && katomic.load(&owner.running_on) == u64(-1)
		&& !katomic.load(&owner.is_in_queue)) {
		if katomic.load(&rcufree_ledger.failures) != 0
			|| rcufree_clock.nanoseconds() - started >= rcufree_timeout_ns { return false }
		sched.reschedule()
	}
	return true
}

fn rcufree_wait_force(previous u64) bool {
	started := rcufree_clock.nanoseconds()
	for C.vinix_linuxkpi_rcu_test_force_count() == previous {
		if katomic.load(&rcufree_ledger.failures) != 0
			|| rcufree_clock.nanoseconds() - started >= rcufree_timeout_ns { return false }
		sched.reschedule()
	}
	return true
}

fn rcufree_callback(argument &C.callback_head) {
	mut node := unsafe { &RcuFreeCallback(argument) }
	remaining := node.remaining
	ints := cpu.interrupt_toggle(false)
	local := cpulocal.current()
	valid := ints && local.maskable_irq_depth == 0 && preempt_depth[local.cpu_number] == 1
	cpu.interrupt_toggle(ints)
	if !valid || may_sleep() { rcufree_fail(32) }
	katomic.store(mut &rcufree_ledger.callbacks, katomic.load(&rcufree_ledger.callbacks) + 1)
	if remaining > 1 {
		node.remaining = remaining - 1
		C.vinix_linuxkpi_rcu_fixture_call(node, rcufree_callback)
		// The callback owns only its saved scalar values after re-publication.
	} else {
		C.vinix_linuxkpi_rcufree_fixture_immediate(node)
		katomic.store(mut &rcufree_ledger.freed_callbacks,
			katomic.load(&rcufree_ledger.freed_callbacks) + 1)
	}
}

fn rcufree_mixed(controller &proc.Thread) bool {
	mut objects := unsafe { [rcufree_object_count]voidptr{} }
	mut callbacks := unsafe { [rcufree_callback_count]&RcuFreeCallback{} }
	mut allocated := 0
	mut submitted := 0
	mut callback_allocated := 0
	mut callback_submitted := 0
	defer {
		katomic.store(mut &rcufree_ledger.release_inner, true)
		katomic.store(mut &rcufree_ledger.release_scope, true)
		for index in submitted .. allocated { C.vinix_linuxkpi_rcufree_fixture_immediate(objects[index]) }
		for index in callback_submitted .. callback_allocated { C.vinix_linuxkpi_rcufree_fixture_immediate(callbacks[index]) }
		if submitted != 0 || callback_submitted != 0 {
			started := rcufree_clock.nanoseconds()
			for katomic.load(&rcufree_ledger.freed_callbacks) < u32(callback_submitted) {
				if rcufree_clock.nanoseconds() - started >= rcufree_timeout_ns {
					lib.kpanic(unsafe { nil }, c'linuxkpi: deferred-free callback cleanup deadline')
				}
				sched.reschedule()
			}
			C.vinix_linuxkpi_rcu_fixture_barrier()
		}
	}
	for index in 0 .. rcufree_object_count {
		objects[index] = C.vinix_linuxkpi_rcufree_fixture_new(u32(index % 3))
		if objects[index] == unsafe { nil } { return false }
		allocated++
	}
	for index in 0 .. rcufree_callback_count {
		mut node := unsafe { &RcuFreeCallback(C.kzalloc(sizeof(RcuFreeCallback), 3264)) }
		if node == unsafe { nil } { return false }
		node.remaining = if index == 0 { u32(3) } else { u32(1) }
		callbacks[index] = node
		callback_allocated++
	}
	if !rcufree_scope_start(1) { return false }
	held_pages := memory.free_bytes()
	force := C.vinix_linuxkpi_rcu_test_force_count()
	test_alloc_oom(0)
	preempt_disable()
	ints := cpu.interrupt_toggle(false)
	for index in 0 .. allocated {
		C.vinix_linuxkpi_rcufree_fixture_enqueue(u32(index % 3), objects[index])
		submitted++
		if index < callback_allocated {
			C.vinix_linuxkpi_rcu_fixture_call(callbacks[index], rcufree_callback)
			callback_submitted++
		}
	}
	allocation_free := controller.linuxkpi_alloc_fail_after == 0 && !cpu.interrupt_state()
		&& cpulocal.current().cpu_number == 0 && preempt_depth[0] == 1
	cpu.interrupt_toggle(ints)
	preempt_enable()
	test_alloc_oom(-1)
	if !allocation_free { return false }
	rcufree_aux_start(2)
	if !rcufree_aux_parked() || !rcufree_wait_force(force)
		|| katomic.load(&rcufree_ledger.aux_done) || memory.free_bytes() != held_pages
		|| katomic.load(&rcufree_ledger.callbacks) != 0 { return false }
	for index in 0 .. allocated {
		if !C.vinix_linuxkpi_rcufree_fixture_check(u32(index % 3), objects[index]) { return false }
	}
	katomic.store(mut &rcufree_ledger.release_inner, true)
	if !rcufree_wait_phase(2) { return false }
	inner_force := C.vinix_linuxkpi_rcu_test_force_count()
	if !rcufree_wait_force(inner_force) || memory.free_bytes() != held_pages
		|| katomic.load(&rcufree_ledger.aux_done) || katomic.load(&rcufree_ledger.callbacks) != 0 { return false }
	katomic.store(mut &rcufree_ledger.release_scope, true)
	// Ownership of every embedded object ends here. No pointer dereference in
	// this function follows the release; barrier covers actual deferred frees.
	if !rcufree_wait_phase(3) || !rcufree_wait(&rcufree_ledger.aux_done) { return false }
	started := rcufree_clock.nanoseconds()
	for katomic.load(&rcufree_ledger.freed_callbacks) != rcufree_callback_count {
		if katomic.load(&rcufree_ledger.failures) != 0
			|| rcufree_clock.nanoseconds() - started >= rcufree_timeout_ns { return false }
		sched.reschedule()
	}
	C.vinix_linuxkpi_rcu_fixture_barrier()
	return katomic.load(&rcufree_ledger.callbacks) == rcufree_callback_count + 2
		&& katomic.load(&rcufree_ledger.failures) == 0
}

fn rcufree_headless() bool {
	payload := C.vinix_linuxkpi_rcufree_fixture_new(1)
	if payload == unsafe { nil } { return false }
	mut submitted := false
	defer {
		katomic.store(mut &rcufree_ledger.release_scope, true)
		if submitted {
			started := rcufree_clock.nanoseconds()
			for !katomic.load(&rcufree_ledger.aux_done) {
				if rcufree_clock.nanoseconds() - started >= rcufree_timeout_ns {
					lib.kpanic(unsafe { nil }, c'linuxkpi: deferred-free headless cleanup deadline')
				}
				sched.reschedule()
			}
		} else { C.vinix_linuxkpi_rcufree_fixture_immediate(payload) }
	}
	if !rcufree_scope_start(2) { return false }
	held_pages := memory.free_bytes()
	force := C.vinix_linuxkpi_rcu_test_force_count()
	rcufree_ledger.headless_payload = payload
	rcufree_aux_start(1)
	submitted = true
	if !rcufree_aux_parked() || !rcufree_wait_force(force)
		|| katomic.load(&rcufree_ledger.aux_done) || memory.free_bytes() != held_pages
		|| !C.vinix_linuxkpi_rcufree_fixture_check(1, payload) { return false }
	katomic.store(mut &rcufree_ledger.release_scope, true)
	return rcufree_wait_phase(3) && rcufree_wait(&rcufree_ledger.aux_done)
}

fn rcufree_lifecycle() bool {
	ints := cpu.interrupt_toggle(false)
	mut controller := proc.current_thread()
	affinity := katomic.load(&controller.affinity_mask)
	node := katomic.load(&controller.numa_node)
	old_failure_gate := controller.linuxkpi_alloc_fail_after
	cpu.interrupt_toggle(ints)
	mut owners := unsafe { [2]&proc.Thread{} }
	mut created := 0
	defer {
		katomic.store(mut &rcufree_ledger.release_inner, true)
		katomic.store(mut &rcufree_ledger.release_scope, true)
		katomic.store(mut &rcufree_ledger.quit, true)
		for index in 0 .. created { irq_test_join(owners[index]) }
		selftest_free_baseline()
		restore_ints := cpu.interrupt_toggle(false)
		controller.linuxkpi_alloc_fail_after = old_failure_gate
		katomic.store(mut &controller.numa_node, node)
		katomic.store(mut &controller.affinity_mask, affinity)
		cpu.interrupt_toggle(restore_ints)
	}
	if !ints || worker_bind(0) != 0 { return false }
	rcufree_ledger = RcuFreeLedger{}
	immediate_baseline := memory.free_bytes()
	for kind in u32(0) .. u32(3) {
		payload := C.vinix_linuxkpi_rcufree_fixture_new(kind)
		if payload == unsafe { nil } { return false }
		valid := C.vinix_linuxkpi_rcufree_fixture_check(kind, payload)
		C.vinix_linuxkpi_rcufree_fixture_immediate(payload)
		if !valid { return false }
	}
	C.vinix_linuxkpi_rcufree_fixture_immediate(unsafe { nil })
	C.vinix_linuxkpi_rcufree_fixture_immediate(voidptr(16))
	if memory.free_bytes() != immediate_baseline { return false }
	for index in 0 .. 2 {
		entry := if index == 0 { voidptr(rcufree_reader) } else { voidptr(rcufree_aux) }
		mut actor := sched.try_new_kernel_thread(entry, unsafe { nil }) or { return false }
		proc.pin_thread(actor)
		proc.pin_thread(actor)
		actor.pthread_joinable = 1
		if index == 1 { rcufree_ledger.aux_owner = actor }
		if !sched.enqueue_thread(actor, false) {
			proc.unpin_thread(actor)
			proc.unpin_thread(actor)
			sched.discard_unstarted_thread(actor)
			return false
		}
		owners[index] = actor
		created++
	}
	if !rcufree_wait(&rcufree_ledger.reader_ready) || !rcufree_wait(&rcufree_ledger.aux_ready) { return false }
	return rcufree_mixed(controller) && rcufree_headless()
}

fn rcufree_native_selftest() bool {
	if cpu_locals.len < 4 || cpu_locals.len > 64
		|| C.vinix_linuxkpi_rcufree_fixture_head_offset(0) != 0
		|| C.vinix_linuxkpi_rcufree_fixture_head_offset(1) != 16
		|| C.vinix_linuxkpi_rcufree_fixture_head_offset(2) != 4088 { return false }
	for round in 0 .. 3 {
		before := selftest_free_baseline()
		if !rcufree_lifecycle() { return false }
		C.kprintf(c'linuxkpi: deferred-free lifecycle warmup %d free-byte baseline=%llu after=%llu\n',
			round + 1, before, selftest_free_baseline())
	}
	mut before := CPUFeatureHeapSnapshot{}
	mut after := CPUFeatureHeapSnapshot{}
	free_before := selftest_free_baseline()
	if !cpu_feature_test_heap(unsafe { &before }) || !rcufree_lifecycle() { return false }
	free_after := selftest_free_baseline()
	if !cpu_feature_test_heap(unsafe { &after }) { return false }
	mut equal := before.count == after.count
	for index in 0 .. before.count {
		if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] { equal = false }
	}
	C.kprintf(c'linuxkpi: deferred-free fourth lifecycle free-byte baseline=%llu after=%llu heap_equal=%d\n',
		free_before, free_after, int(equal))
	return free_before == free_after && equal
}
