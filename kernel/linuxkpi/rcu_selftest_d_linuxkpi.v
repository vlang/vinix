// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module linuxkpi

import event
import katomic
import lib
import proc
import sched
import x86.cpu
import x86.cpu.local as cpulocal
import x86.hpet as rcu_test_clock

#include "linuxkpi_rcu_fixture_v_primitives.h"
#include "linuxkpi_smp_fixture_v_primitives.h"

struct C.vinix_rcu_fixture_head {}
struct C.callback_head {}
fn C.vinix_linuxkpi_rcu_fixture_head_bytes() u32
fn C.vinix_linuxkpi_rcu_fixture_read_lock()
fn C.vinix_linuxkpi_rcu_fixture_read_unlock()
fn C.vinix_linuxkpi_rcu_fixture_get_state() u64
fn C.vinix_linuxkpi_rcu_fixture_start_poll() u64
fn C.vinix_linuxkpi_rcu_fixture_poll(u64) bool
fn C.vinix_linuxkpi_rcu_fixture_synchronize(bool)
fn C.vinix_linuxkpi_rcu_fixture_barrier()
fn C.vinix_linuxkpi_rcu_fixture_call(voidptr, fn (&C.callback_head))
fn C.vinix_linuxkpi_rcu_test_force_count() u64
fn C.vinix_linuxkpi_rcu_test_irq_off_probe() i32
fn C.vinix_linuxkpi_rcu_fixture_task_sleeping(voidptr) bool

const rcu_test_timeout_ns = u64(10000000000)
const rcu_test_dynamic_count = 25

struct RcuNativeNode {
mut:
	head C.vinix_rcu_fixture_head
	remaining u32
	dynamic bool
	held bool
}

// All cross-actor observations have boot lifetime. Reset only after every
// callback returns and both retained actors have exited, joined and reaped.
struct RcuNativeLedger {
mut:
	reader_owner voidptr
	aux_owner voidptr
	reader_ready bool
	aux_ready bool
	quit bool
	command u32
	phase u32
	release_inner bool
	release_scope bool
	allow_irqs bool
	irq_eligible bool
	irq_terminal bool
	nested_entries u32
	aux_command u32
	aux_started bool
	aux_done bool
	callbacks u32
	freed u32
	callback_cookie u64
	failures u32
}
__global rcu_native_ledger RcuNativeLedger

fn rcu_test_fail(bit u32) {
	for {
		old := katomic.load(&rcu_native_ledger.failures)
		if katomic.cas(mut &rcu_native_ledger.failures, old, old | bit) { return }
	}
}

fn rcu_test_task(target u32) bool {
	ints := cpu.interrupt_toggle(false)
	local := cpulocal.current()
	ok := ints && local.cpu_number == u64(target) && local.maskable_irq_depth == 0
		&& preempt_depth[local.cpu_number] == 0 && proc.current_thread() != unsafe { nil }
	cpu.interrupt_toggle(ints)
	return ok
}

fn rcu_test_spin_release(inner bool) {
	started := rcu_test_clock.nanoseconds()
	for !katomic.load(&rcu_native_ledger.quit) {
		released := if inner { katomic.load(&rcu_native_ledger.release_inner) }
			else { katomic.load(&rcu_native_ledger.release_scope) }
		if released { return }
		spin_wait()
		if rcu_test_clock.nanoseconds() - started >= rcu_test_timeout_ns {
			lib.kpanic(unsafe { nil }, c'linuxkpi: held ordinary RCU scope deadline')
		}
	}
}

fn rcu_test_irq_hold(_argument voidptr) {
	local := cpulocal.current()
	// A higher-priority native timer may have switched the target before this
	// IPI. Retry until the real interrupted task is our pin-zero actor.
	eligible := local.cpu_number == 1 && local.maskable_irq_depth != 0
		&& preempt_depth[1] == 0
		&& voidptr(proc.current_thread()) == rcu_native_ledger.reader_owner
	katomic.store(mut &rcu_native_ledger.irq_eligible, eligible)
	if eligible {
		if cpu.interrupt_state() { rcu_test_fail(1) }
		cpu.interrupt_toggle(true)
		katomic.store(mut &rcu_native_ledger.phase, u32(2))
		rcu_test_spin_release(false)
		ints := cpu.interrupt_toggle(false)
		if !ints || local.maskable_irq_depth != 1 || preempt_depth[1] != 0
			|| voidptr(proc.current_thread()) != rcu_native_ledger.reader_owner { rcu_test_fail(2) }
	}
	// No argument borrow survives this publication. The reader TASK supplies
	// the separate phase3 witness only after the matching actual IRET.
	katomic.store(mut &rcu_native_ledger.irq_terminal, true)
}

fn rcu_test_nested_irq(_argument voidptr) {
	local := cpulocal.current()
	if cpu.interrupt_state() || local.cpu_number != 1 || local.maskable_irq_depth != 2
		|| preempt_depth[1] != 0
		|| voidptr(proc.current_thread()) != rcu_native_ledger.reader_owner { rcu_test_fail(4) }
	katomic.store(mut &rcu_native_ledger.nested_entries,
		katomic.load(&rcu_native_ledger.nested_entries) + 1)
}

fn rcu_test_reader(_argument voidptr) {
	if worker_bind(1) != 0 || !rcu_test_task(1) { rcu_test_fail(8) }
	katomic.store(mut &rcu_native_ledger.reader_ready, true)
	for !katomic.load(&rcu_native_ledger.quit) {
		mode := katomic.load(&rcu_native_ledger.command)
		if mode == 0 { sched.reschedule(); continue }
		if mode == 1 || mode == 5 {
			if mode == 1 {
				C.vinix_linuxkpi_rcu_fixture_read_lock()
				C.vinix_linuxkpi_rcu_fixture_read_lock()
			} else { preempt_disable(); preempt_disable() }
			katomic.store(mut &rcu_native_ledger.phase, u32(1))
			rcu_test_spin_release(true)
			if mode == 1 { C.vinix_linuxkpi_rcu_fixture_read_unlock() } else { preempt_enable() }
			katomic.store(mut &rcu_native_ledger.phase, u32(2))
			rcu_test_spin_release(false)
			if mode == 1 { C.vinix_linuxkpi_rcu_fixture_read_unlock() } else { preempt_enable() }
		} else {
			if mode == 2 { preempt_disable(); preempt_disable() }
			ints := cpu.interrupt_toggle(false)
			local := cpulocal.current()
			if !ints || local.cpu_number != 1 || local.maskable_irq_depth != 0 { rcu_test_fail(16) }
			expected_pins := if mode == 2 { u32(2) } else { u32(0) }
			if preempt_depth[1] != expected_pins || cpu.interrupt_state() { rcu_test_fail(32) }
			katomic.store(mut &rcu_native_ledger.phase, u32(1))
			if mode == 2 {
				// The existing GP has already requested this held CPU. Dropping
				// both pins while CLI remains active cannot acknowledge its old
				// implicit IRQ-disabled read region.
				rcu_test_spin_release(true)
				release_preemption(false)
				release_preemption(false)
				if preempt_depth[1] != 0 || cpu.interrupt_state() { rcu_test_fail(32) }
				katomic.store(mut &rcu_native_ledger.phase, u32(2))
			}
			if mode == 3 {
				// A real software INT entered while raw CLI is active must not
				// report quiescence on its return to the original saved IF0.
				rcu_test_spin_release(true)
				if C.vinix_linuxkpi_rcu_test_irq_off_probe() != 0 || cpu.interrupt_state()
					|| local.maskable_irq_depth != 0 || preempt_depth[1] != 0 { rcu_test_fail(32) }
				katomic.store(mut &rcu_native_ledger.phase, u32(2))
			}
			if mode == 4 {
				started := rcu_test_clock.nanoseconds()
				for !katomic.load(&rcu_native_ledger.allow_irqs) && !katomic.load(&rcu_native_ledger.quit) {
					spin_wait()
					if rcu_test_clock.nanoseconds() - started >= rcu_test_timeout_ns {
						lib.kpanic(unsafe { nil }, c'linuxkpi: ordinary RCU IRQ-entry deadline')
					}
				}
				cpu.interrupt_toggle(ints)
				started_return := rcu_test_clock.nanoseconds()
				for !katomic.load(&rcu_native_ledger.irq_terminal) && !katomic.load(&rcu_native_ledger.quit) {
					spin_wait()
					if rcu_test_clock.nanoseconds() - started_return >= rcu_test_timeout_ns {
						lib.kpanic(unsafe { nil }, c'linuxkpi: ordinary RCU IRQ-return deadline')
					}
				}
			} else {
				rcu_test_spin_release(false)
				cpu.interrupt_toggle(ints)
			}
		}
		if !rcu_test_task(1) { rcu_test_fail(64) }
		katomic.store(mut &rcu_native_ledger.command, u32(0))
		katomic.store(mut &rcu_native_ledger.phase, u32(3))
	}
	event.pthread_exit(unsafe { nil })
}

fn rcu_test_aux(_argument voidptr) {
	if worker_bind(2) != 0 || !rcu_test_task(2) { rcu_test_fail(128) }
	katomic.store(mut &rcu_native_ledger.aux_ready, true)
	for !katomic.load(&rcu_native_ledger.quit) {
		command := katomic.load(&rcu_native_ledger.aux_command)
		if command == 0 { sched.reschedule(); continue }
		katomic.store(mut &rcu_native_ledger.aux_started, true)
		if command == 2 { C.vinix_linuxkpi_rcu_fixture_barrier() }
		else { C.vinix_linuxkpi_rcu_fixture_synchronize(command == 3) }
		if !rcu_test_task(2) { rcu_test_fail(256) }
		katomic.store(mut &rcu_native_ledger.aux_command, u32(0))
		katomic.store(mut &rcu_native_ledger.aux_done, true)
	}
	event.pthread_exit(unsafe { nil })
}

fn rcu_test_wait(flag &bool) bool {
	started := rcu_test_clock.nanoseconds()
	for !katomic.load(flag) {
		if katomic.load(&rcu_native_ledger.failures) != 0
			|| rcu_test_clock.nanoseconds() - started >= rcu_test_timeout_ns { return false }
		sched.reschedule()
	}
	return katomic.load(&rcu_native_ledger.failures) == 0
}

fn rcu_test_wait_phase(phase u32) bool {
	started := rcu_test_clock.nanoseconds()
	for katomic.load(&rcu_native_ledger.phase) < phase {
		if katomic.load(&rcu_native_ledger.failures) != 0
			|| rcu_test_clock.nanoseconds() - started >= rcu_test_timeout_ns { return false }
		sched.reschedule()
	}
	return katomic.load(&rcu_native_ledger.failures) == 0
}

fn rcu_test_wait_aux_parked() bool {
	// Both native observer pins remain held until final join/off-stack teardown.
	// A real sleep proves the actor entered the synchronous API, rather than
	// merely publishing aux_started immediately before its barrier snapshot.
	owner := unsafe { &proc.Thread(rcu_native_ledger.aux_owner) }
	started := rcu_test_clock.nanoseconds()
	for !(katomic.load(&rcu_native_ledger.aux_started)
		&& C.vinix_linuxkpi_rcu_fixture_task_sleeping(unsafe { &owner.linuxkpi_task[0] })
		&& !katomic.load(&owner.is_in_queue) && katomic.load(&owner.running_on) == u64(-1)
		&& !katomic.load(&owner.is_in_queue)) {
		if katomic.load(&rcu_native_ledger.failures) != 0
			|| rcu_test_clock.nanoseconds() - started >= rcu_test_timeout_ns { return false }
		sched.reschedule()
	}
	return true
}

fn rcu_test_wait_force(previous u64) bool {
	started := rcu_test_clock.nanoseconds()
	for C.vinix_linuxkpi_rcu_test_force_count() == previous {
		if katomic.load(&rcu_native_ledger.failures) != 0
			|| rcu_test_clock.nanoseconds() - started >= rcu_test_timeout_ns { return false }
		sched.reschedule()
	}
	return true
}

fn rcu_test_wait_cookie(cookie u64) bool {
	started := rcu_test_clock.nanoseconds()
	for !C.vinix_linuxkpi_rcu_fixture_poll(cookie) {
		if katomic.load(&rcu_native_ledger.failures) != 0
			|| rcu_test_clock.nanoseconds() - started >= rcu_test_timeout_ns { return false }
		sched.reschedule()
	}
	return true
}

fn rcu_test_start_scope(mode u32) bool {
	for attempt in 0 .. 32 {
		katomic.store(mut &rcu_native_ledger.release_inner, false)
		katomic.store(mut &rcu_native_ledger.release_scope, false)
		katomic.store(mut &rcu_native_ledger.allow_irqs, false)
		katomic.store(mut &rcu_native_ledger.irq_eligible, false)
		katomic.store(mut &rcu_native_ledger.irq_terminal, false)
		katomic.store(mut &rcu_native_ledger.phase, u32(0))
		katomic.store(mut &rcu_native_ledger.command, mode)
		if !rcu_test_wait_phase(1) { return false }
		if mode != 4 { return true }
		if C.vinix_linuxkpi_smp_fixture_single(1, rcu_test_irq_hold, unsafe { nil }, 0) != 0 { return false }
		katomic.store(mut &rcu_native_ledger.allow_irqs, true)
		if !rcu_test_wait_phase(2) { return false }
		if katomic.load(&rcu_native_ledger.irq_eligible) { return true }
		if !rcu_test_wait_phase(3) { return false }
		if attempt == 31 { return false }
	}
	return false
}

fn rcu_test_begin_aux(command u32) {
	katomic.store(mut &rcu_native_ledger.aux_started, false)
	katomic.store(mut &rcu_native_ledger.aux_done, false)
	katomic.store(mut &rcu_native_ledger.aux_command, command)
}

fn rcu_test_callback(argument &C.callback_head) {
	mut node := unsafe { &RcuNativeNode(argument) }
	remaining := node.remaining
	dynamic := node.dynamic
	held := node.held
	node.held = false
	ints := cpu.interrupt_toggle(false)
	local := cpulocal.current()
	valid := ints && local.maskable_irq_depth == 0 && preempt_depth[local.cpu_number] == 1
	cpu.interrupt_toggle(ints)
	if !valid || may_sleep() { rcu_test_fail(512) }
	if held {
		force := C.vinix_linuxkpi_rcu_test_force_count()
		cookie := C.vinix_linuxkpi_rcu_fixture_start_poll()
		started := rcu_test_clock.nanoseconds()
		for C.vinix_linuxkpi_rcu_test_force_count() == force {
			spin_wait()
			if rcu_test_clock.nanoseconds() - started >= rcu_test_timeout_ns {
				lib.kpanic(unsafe { nil }, c'linuxkpi: held ordinary RCU callback force deadline')
			}
		}
		observe := rcu_test_clock.nanoseconds()
		for rcu_test_clock.nanoseconds() - observe < 2000000 {
			if C.vinix_linuxkpi_rcu_fixture_poll(cookie) || katomic.load(&rcu_native_ledger.aux_done) {
				rcu_test_fail(1024)
			}
			spin_wait()
		}
		katomic.store(mut &rcu_native_ledger.callback_cookie, cookie)
	}
	katomic.store(mut &rcu_native_ledger.callbacks, katomic.load(&rcu_native_ledger.callbacks) + 1)
	if remaining > 1 {
		node.remaining = remaining - 1
		C.vinix_linuxkpi_rcu_fixture_call(node, rcu_test_callback)
		// Self requeue may already have published this detached head. No object
		// read follows the original call_rcu invocation.
	} else if dynamic {
		C.kfree(node)
		katomic.store(mut &rcu_native_ledger.freed, katomic.load(&rcu_native_ledger.freed) + 1)
	}
}

fn rcu_test_scope(mode u32) bool {
	mut node := RcuNativeNode{ remaining: 1 }
	mut submitted := false
	defer {
		katomic.store(mut &rcu_native_ledger.release_inner, true)
		katomic.store(mut &rcu_native_ledger.release_scope, true)
		katomic.store(mut &rcu_native_ledger.allow_irqs, true)
		if submitted { C.vinix_linuxkpi_rcu_fixture_barrier() }
	}
	if !rcu_test_start_scope(mode) { return false }
	before := katomic.load(&rcu_native_ledger.callbacks)
	force := C.vinix_linuxkpi_rcu_test_force_count()
	old_cookie := C.vinix_linuxkpi_rcu_fixture_get_state()
	cookie := C.vinix_linuxkpi_rcu_fixture_start_poll()
	C.vinix_linuxkpi_rcu_fixture_call(unsafe { &node }, rcu_test_callback)
	submitted = true
	rcu_test_begin_aux(if mode == 3 { u32(3) } else { u32(1) })
	if !rcu_test_wait_aux_parked() || !rcu_test_wait_force(force) { return false }
	if mode == 4 {
		if C.vinix_linuxkpi_smp_fixture_single(1, rcu_test_nested_irq, unsafe { nil }, 1) != 0
			|| katomic.load(&rcu_native_ledger.nested_entries) == 0 { return false }
	}
	if C.vinix_linuxkpi_rcu_fixture_poll(cookie) || C.vinix_linuxkpi_rcu_fixture_poll(old_cookie)
		|| katomic.load(&rcu_native_ledger.callbacks) != before || katomic.load(&rcu_native_ledger.aux_done) {
		return false
	}
	if mode == 1 || mode == 2 || mode == 3 || mode == 5 {
		katomic.store(mut &rcu_native_ledger.release_inner, true)
		if !rcu_test_wait_phase(2) { return false }
		inner_force := C.vinix_linuxkpi_rcu_test_force_count()
		if !rcu_test_wait_force(inner_force) || C.vinix_linuxkpi_rcu_fixture_poll(cookie)
			|| katomic.load(&rcu_native_ledger.callbacks) != before
			|| katomic.load(&rcu_native_ledger.aux_done) { return false }
	}
	katomic.store(mut &rcu_native_ledger.release_scope, true)
	if !rcu_test_wait_phase(3) || !rcu_test_wait_cookie(cookie) || !rcu_test_wait_cookie(old_cookie)
		|| !rcu_test_wait(&rcu_native_ledger.aux_done) { return false }
	C.vinix_linuxkpi_rcu_fixture_barrier()
	return katomic.load(&rcu_native_ledger.callbacks) == before + 1
		&& katomic.load(&rcu_native_ledger.failures) == 0
}

fn rcu_test_dynamic(controller &proc.Thread) bool {
	mut nodes := unsafe { [rcu_test_dynamic_count]&RcuNativeNode{} }
	mut allocated := 0
	mut submitted := 0
	defer {
		katomic.store(mut &rcu_native_ledger.release_inner, true)
		katomic.store(mut &rcu_native_ledger.release_scope, true)
		katomic.store(mut &rcu_native_ledger.allow_irqs, true)
		for index in submitted .. allocated { C.kfree(nodes[index]) }
		if submitted != 0 {
			started := rcu_test_clock.nanoseconds()
			for katomic.load(&rcu_native_ledger.freed) < u32(submitted) {
				if rcu_test_clock.nanoseconds() - started >= rcu_test_timeout_ns {
					lib.kpanic(unsafe { nil }, c'linuxkpi: ordinary RCU self-free cleanup deadline')
				}
				sched.reschedule()
			}
			C.vinix_linuxkpi_rcu_fixture_barrier()
		}
	}
	for index in 0 .. rcu_test_dynamic_count {
		mut node := unsafe { &RcuNativeNode(C.kzalloc(sizeof(RcuNativeNode), 3264)) }
		if node == unsafe { nil } { return false }
		node.remaining = if index == 0 { u32(6) } else { u32(1) }
		node.dynamic = true
		node.held = index == 0
		nodes[index] = node
		allocated++
	}
	if !rcu_test_start_scope(1) { return false }
	test_alloc_oom(0)
	ints := cpu.interrupt_toggle(false)
	for index in 0 .. allocated {
		C.vinix_linuxkpi_rcu_fixture_call(nodes[index], rcu_test_callback)
		submitted++
	}
	allocation_free := controller.linuxkpi_alloc_fail_after == 0 && !cpu.interrupt_state()
	cpu.interrupt_toggle(ints)
	test_alloc_oom(-1)
	if !allocation_free { return false }
	rcu_test_begin_aux(2)
	if !rcu_test_wait_aux_parked() || katomic.load(&rcu_native_ledger.aux_done) { return false }
	katomic.store(mut &rcu_native_ledger.release_inner, true)
	katomic.store(mut &rcu_native_ledger.release_scope, true)
	if !rcu_test_wait_phase(3) || !rcu_test_wait(&rcu_native_ledger.aux_done) { return false }
	started := rcu_test_clock.nanoseconds()
	for katomic.load(&rcu_native_ledger.freed) != rcu_test_dynamic_count {
		if katomic.load(&rcu_native_ledger.failures) != 0
			|| rcu_test_clock.nanoseconds() - started >= rcu_test_timeout_ns { return false }
		sched.reschedule()
	}
	C.vinix_linuxkpi_rcu_fixture_barrier()
	return rcu_test_wait_cookie(katomic.load(&rcu_native_ledger.callback_cookie))
		&& katomic.load(&rcu_native_ledger.callbacks) == u32(5 + rcu_test_dynamic_count + 5)
		&& katomic.load(&rcu_native_ledger.failures) == 0
}

fn rcu_test_lifecycle() bool {
	ints := cpu.interrupt_toggle(false)
	mut controller := proc.current_thread()
	affinity := katomic.load(&controller.affinity_mask)
	node := katomic.load(&controller.numa_node)
	old_failure_gate := controller.linuxkpi_alloc_fail_after
	cpu.interrupt_toggle(ints)
	mut owners := unsafe { [2]&proc.Thread{} }
	mut created := 0
	defer {
		katomic.store(mut &rcu_native_ledger.release_inner, true)
		katomic.store(mut &rcu_native_ledger.release_scope, true)
		katomic.store(mut &rcu_native_ledger.allow_irqs, true)
		katomic.store(mut &rcu_native_ledger.quit, true)
		for index in 0 .. created { irq_test_join(owners[index]) }
		selftest_free_baseline()
		restore_ints := cpu.interrupt_toggle(false)
		controller.linuxkpi_alloc_fail_after = old_failure_gate
		katomic.store(mut &controller.numa_node, node)
		katomic.store(mut &controller.affinity_mask, affinity)
		cpu.interrupt_toggle(restore_ints)
	}
	if !ints || worker_bind(0) != 0 { return false }
	rcu_native_ledger = RcuNativeLedger{}
	for index in 0 .. 2 {
		entry := if index == 0 { voidptr(rcu_test_reader) } else { voidptr(rcu_test_aux) }
		mut actor := sched.try_new_kernel_thread(entry, unsafe { nil }) or { return false }
		proc.pin_thread(actor)
		proc.pin_thread(actor)
		actor.pthread_joinable = 1
		if index == 0 { rcu_native_ledger.reader_owner = actor }
		else { rcu_native_ledger.aux_owner = actor }
		if !sched.enqueue_thread(actor, false) {
			proc.unpin_thread(actor)
			proc.unpin_thread(actor)
			sched.discard_unstarted_thread(actor)
			return false
		}
		owners[index] = actor
		created++
	}
	if !rcu_test_wait(&rcu_native_ledger.reader_ready) || !rcu_test_wait(&rcu_native_ledger.aux_ready) { return false }
	for mode in u32(1) .. u32(6) {
		if !rcu_test_scope(mode) { return false }
	}
	return rcu_test_dynamic(controller)
}

fn rcu_native_selftest() bool {
	if cpu_locals.len < 4 || cpu_locals.len > 64 || C.vinix_linuxkpi_rcu_fixture_head_bytes() != 16 { return false }
	for round in 0 .. 3 {
		before := selftest_free_baseline()
		if !rcu_test_lifecycle() { return false }
		C.kprintf(c'linuxkpi: ordinary RCU lifecycle warmup %d free-byte baseline=%llu after=%llu\n',
			round + 1, before, selftest_free_baseline())
	}
	mut before := CPUFeatureHeapSnapshot{}
	mut after := CPUFeatureHeapSnapshot{}
	free_before := selftest_free_baseline()
	if !cpu_feature_test_heap(unsafe { &before }) || !rcu_test_lifecycle() { return false }
	free_after := selftest_free_baseline()
	if !cpu_feature_test_heap(unsafe { &after }) { return false }
	mut equal := before.count == after.count
	for index in 0 .. before.count {
		if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] { equal = false }
	}
	C.kprintf(c'linuxkpi: ordinary RCU fourth lifecycle free-byte baseline=%llu after=%llu heap_equal=%d\n',
		free_before, free_after, int(equal))
	return free_before == free_after && equal
}
