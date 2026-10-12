// SPDX-License-Identifier: GPL-2.0-or-later
module linuxkpi

import lib
import event
import katomic
import proc
import sched
import x86.cpu
import x86.cpu.local as cpulocal
import x86.hpet as rcu_cold_clock

#include "linuxkpi_rcu_v_primitives.h"

fn C.vkr_rcu_ready() bool
fn C.vkr_rcu_quiescent(u32)
fn C.vkr_rcu_bootstrap(u32) i32

// Normal interrupt return exists before the compatibility module is warmed by
// its sole boot owner. Do not enter a generated lazy module wrapper from an AP.
__global (
	rcu_native_active u32
	rcu_native_force_count u64
	rcu_native_cold_irq_result i32
)

const rcu_cold_timeout_ns = u64(30000000000)

struct RcuColdIrqLedger {
mut:
	owner voidptr
	ready bool
	quit bool
	failed bool
	eligible bool
	sequence u64
	terminal u64
	post_iret u64
}

// Borrowed callbacks and the task-return observer share only this permanent
// ledger. Reset it after the retained actor has joined and left its stack.
__global rcu_cold_irq_ledger RcuColdIrqLedger

// Called only by the real ordinary maskable THUNK after closing its depth,
// while kernel GS and the original saved frame remain installed. In particular,
// enabling IRQs inside a borrowed handler does not make its task quiescent.
// The interrupted scope must have had IF set and no native preemption pins.
// No Linux lock can be used here: its pin/unpin accounting would recurse.
@[export: 'vinix_linuxkpi_rcu_native_irq_exit']
fn rcu_native_irq_exit(saved_flags u64) {
	if katomic.load(&rcu_native_active) == 0 { return }
	if cpu.interrupt_state() {
		lib.kpanic(unsafe { nil }, c'linuxkpi: RCU IRQ return requires IRQs disabled')
	}
	local := cpulocal.current()
	if local.maskable_irq_depth != 0 || preempt_depth[local.cpu_number] != 0
		|| (saved_flags & 512) == 0 || !C.vkr_rcu_ready() {
		return
	}
	C.vkr_rcu_quiescent(u32(local.cpu_number))
}

// A real doorbell forces an outer return on each immutable boot CPU, including
// the calling CPU. IRQ-disabled and pinned scopes defer their acknowledgement
// until a later qualifying return. An empty CSD queue still returns through the
// ordinary THUNK; no callback or synthetic queue record supplies an early QS.
@[export: 'vinix_linuxkpi_rcu_force_quiescence']
fn rcu_force_quiescence() {
	if katomic.load(&rcu_native_active) == 0 || !C.vkr_rcu_ready() || !C.vks_smp_ready() {
		lib.kpanic(unsafe { nil }, c'linuxkpi: RCU force before native SMP readiness')
	}
	for index := 0; index < cpu_locals.len; index++ {
		smp_send_ipi(u32(index))
	}
	katomic.inc(mut &rcu_native_force_count)
}

// Read-only fixture witness: the actual transport has rung every boot CPU.
// This observes no backend cookie/epoch and supplies no quiescent state.
@[export: 'vinix_linuxkpi_rcu_test_force_count']
fn rcu_test_force_count() u64 {
	return katomic.load(&rcu_native_force_count)
}

// The maintained immutable immediate-INT leaves execute the real maskable
// THUNK even with IF clear. Exercise its saved-IF0 return without submitting a
// synthetic RCU callback or manufacturing an epoch acknowledgement.
@[export: 'vinix_linuxkpi_rcu_test_irq_off_probe']
fn rcu_test_irq_off_probe() i32 {
	if cpu.interrupt_state() || katomic.load(&rcu_native_active) == 0 {
		return -22
	}
	local := cpulocal.current()
	if local.maskable_irq_depth != 0 || preempt_depth[local.cpu_number] != 0 {
		return -22
	}
	return C.vinix_linuxkpi_irq_probe(smp_call_vector)
}

fn rcu_cold_irq_actor(_argument voidptr) {
	if worker_bind(1) != 0 {
		katomic.store(mut &rcu_cold_irq_ledger.failed, true)
		katomic.store(mut &rcu_cold_irq_ledger.ready, true)
		event.pthread_exit(unsafe { nil })
		return
	}
	ints := cpu.interrupt_toggle(false)
	mut owner := proc.current_thread()
	local := cpulocal.current()
	if owner == unsafe { nil } {
		katomic.store(mut &rcu_cold_irq_ledger.failed, true)
		katomic.store(mut &rcu_cold_irq_ledger.ready, true)
		cpu.interrupt_toggle(ints)
		event.pthread_exit(unsafe { nil })
		return
	}
	valid := ints && local.cpu_number == 1 && local.maskable_irq_depth == 0
		&& preempt_depth[1] == 0 && voidptr(owner) == rcu_cold_irq_ledger.owner
		&& voidptr(owner.process) == voidptr(kernel_process)
	old_gate := owner.linuxkpi_alloc_fail_after
	owner.linuxkpi_alloc_fail_after = 0
	if !valid { katomic.store(mut &rcu_cold_irq_ledger.failed, true) }
	katomic.store(mut &rcu_cold_irq_ledger.ready, true)
	cpu.interrupt_toggle(ints)
	for valid && !katomic.load(&rcu_cold_irq_ledger.quit) {
		check_ints := cpu.interrupt_toggle(false)
		terminal := katomic.load(&rcu_cold_irq_ledger.terminal)
		if terminal > katomic.load(&rcu_cold_irq_ledger.post_iret) {
			// This is the selected ordinary task, after the actual maskable IRET.
			// CSD completion alone happens earlier inside the interrupt handler.
			if !check_ints || cpulocal.current().cpu_number != 1
				|| cpulocal.current().maskable_irq_depth != 0 || preempt_depth[1] != 0
				|| voidptr(proc.current_thread()) != voidptr(owner)
				|| owner.linuxkpi_alloc_fail_after != 0 {
				katomic.store(mut &rcu_cold_irq_ledger.failed, true)
			}
			katomic.store(mut &rcu_cold_irq_ledger.post_iret, terminal)
		}
		cpu.interrupt_toggle(check_ints)
		// Only the real LAPIC vector delivers the queued original SMP callback.
		spin_wait()
	}
	restore_ints := cpu.interrupt_toggle(false)
	owner.linuxkpi_alloc_fail_after = old_gate
	cpu.interrupt_toggle(restore_ints)
	event.pthread_exit(unsafe { nil })
}

fn rcu_cold_irq_probe(_argument voidptr) {
	local := cpulocal.current()
	mut owner := proc.current_thread()
	sequence := katomic.load(&rcu_cold_irq_ledger.sequence)
	// A timer can switch the destination to idle or another task before the
	// IPI arrives. Such a callback is a retry, never an accepted test context.
	eligible := owner != unsafe { nil } && voidptr(owner) == rcu_cold_irq_ledger.owner
		&& local.cpu_number == 1 && local.maskable_irq_depth != 0 && preempt_depth[1] == 0
	katomic.store(mut &rcu_cold_irq_ledger.eligible, eligible)
	if eligible {
		depth := local.maskable_irq_depth
		mask := katomic.load(&owner.affinity_mask)
		node := katomic.load(&owner.numa_node)
		old_gate := owner.linuxkpi_alloc_fail_after
		entry_valid := !cpu.interrupt_state() && old_gate == 0
			&& voidptr(owner.process) == voidptr(kernel_process) && !C.vkr_rcu_ready()
		cpu.interrupt_toggle(true)
		result := C.vkr_rcu_bootstrap(u32(cpu_locals.len))
		returned_ints := cpu.interrupt_toggle(false)
		valid := entry_valid && result == -1 && returned_ints
			&& voidptr(cpulocal.current()) == voidptr(local)
			&& local.maskable_irq_depth == depth && preempt_depth[1] == 0
			&& voidptr(proc.current_thread()) == voidptr(owner)
			&& katomic.load(&owner.affinity_mask) == mask
			&& katomic.load(&owner.numa_node) == node
			&& owner.linuxkpi_alloc_fail_after == 0 && !C.vkr_rcu_ready()
		// Restore the borrowed actor even when a negative-control constructor
		// changes its state. Its permanent task owns the gate until actual exit.
		katomic.store(mut &owner.affinity_mask, mask)
		katomic.store(mut &owner.numa_node, node)
		owner.linuxkpi_alloc_fail_after = old_gate
		katomic.store(mut &rcu_native_cold_irq_result, if valid { i32(0) } else { i32(-1) })
	}
	// No borrowed-task or callback argument access follows this publication.
	katomic.store(mut &rcu_cold_irq_ledger.terminal, sequence)
}

fn rcu_cold_irq_wait(sequence u64, ready bool) bool {
	started := rcu_cold_clock.nanoseconds()
	for {
		if katomic.load(&rcu_cold_irq_ledger.failed) { return false }
		if ready {
			if katomic.load(&rcu_cold_irq_ledger.ready) { return true }
		} else if katomic.load(&rcu_cold_irq_ledger.post_iret) >= sequence {
			return true
		}
		if rcu_cold_clock.nanoseconds() - started >= rcu_cold_timeout_ns { return false }
		sched.reschedule()
	}
	return false
}

fn rcu_cold_irq_batch() bool {
	ints := cpu.interrupt_toggle(false)
	mut controller := proc.current_thread()
	if !ints || controller == unsafe { nil } {
		cpu.interrupt_toggle(ints)
		return false
	}
	mask := katomic.load(&controller.affinity_mask)
	node := katomic.load(&controller.numa_node)
	old_gate := controller.linuxkpi_alloc_fail_after
	cpu.interrupt_toggle(ints)
	defer {
		restore_ints := cpu.interrupt_toggle(false)
		controller.linuxkpi_alloc_fail_after = old_gate
		katomic.store(mut &controller.affinity_mask, mask)
		katomic.store(mut &controller.numa_node, node)
		cpu.interrupt_toggle(restore_ints)
	}
	if worker_bind(0) != 0 { return false }
	rcu_cold_irq_ledger = RcuColdIrqLedger{}
	mut actor := sched.try_new_kernel_thread(voidptr(rcu_cold_irq_actor), unsafe { nil }) or { return false }
	proc.pin_thread(actor)
	proc.pin_thread(actor)
	actor.pthread_joinable = 1
	rcu_cold_irq_ledger.owner = actor
	if !sched.enqueue_thread(actor, false) {
		rcu_cold_irq_ledger.owner = unsafe { nil }
		proc.unpin_thread(actor)
		proc.unpin_thread(actor)
		sched.discard_unstarted_thread(actor)
		return false
	}
	defer {
		katomic.store(mut &rcu_cold_irq_ledger.quit, true)
		irq_test_join(actor)
		selftest_free_baseline()
		rcu_cold_irq_ledger.owner = unsafe { nil }
	}
	if !rcu_cold_irq_wait(0, true) { return false }
	started := rcu_cold_clock.nanoseconds()
	mut sequence := u64(0)
	for {
		if rcu_cold_clock.nanoseconds() - started >= rcu_cold_timeout_ns { return false }
		sequence++
		katomic.store(mut &rcu_cold_irq_ledger.sequence, sequence)
		katomic.store(mut &rcu_native_cold_irq_result, i32(-2))
		if C.vinix_linuxkpi_smp_fixture_single(1, rcu_cold_irq_probe, unsafe { nil }, 1) != 0
			|| !rcu_cold_irq_wait(sequence, false) { return false }
		if katomic.load(&rcu_cold_irq_ledger.eligible) {
			return katomic.load(&rcu_native_cold_irq_result) == 0
		}
	}
	return false
}

fn rcu_cold_irq_selftest() bool {
	// This remote-IRQ fixture needs two representable native CPUs. The backend
	// itself still accepts a one-CPU domain; this test makes no one-CPU claim.
	if cpu_locals.len < 2 || cpu_locals.len > 64 || !C.vks_smp_ready() || C.vkr_rcu_ready() { return false }
	for round in 0 .. 3 {
		before := selftest_free_baseline()
		if !rcu_cold_irq_batch() { return false }
		C.kprintf(c'linuxkpi: RCU cold IRQ actor warmup %d free-byte baseline=%llu after=%llu\n',
			round + 1, before, selftest_free_baseline())
	}
	mut before := CPUFeatureHeapSnapshot{}
	mut after := CPUFeatureHeapSnapshot{}
	free_before := selftest_free_baseline()
	if !cpu_feature_test_heap(unsafe { &before }) || !rcu_cold_irq_batch() { return false }
	free_after := selftest_free_baseline()
	if !cpu_feature_test_heap(unsafe { &after }) { return false }
	mut equal := before.count == after.count
	for index in 0 .. before.count {
		if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] { equal = false }
	}
	C.kprintf(c'linuxkpi: RCU cold IRQ actor fourth batch free-byte baseline=%llu after=%llu heap_equal=%d\n',
		free_before, free_after, int(equal))
	return free_before == free_after && equal
}

fn initialise_ordinary_rcu() {
	if !smp_boot_context() || katomic.load(&rcu_native_active) != 0 {
		lib.kpanic(unsafe { nil }, c'linuxkpi: invalid RCU boot owner context')
	}
	test_alloc_oom(0)
	ints := cpu.interrupt_toggle(false)
	irq_off_result := C.vkr_rcu_bootstrap(u32(cpu_locals.len))
	irq_off_valid := !cpu.interrupt_state() && proc.current_thread().linuxkpi_alloc_fail_after == 0
	cpu.interrupt_toggle(ints)
	preempt_disable()
	preempt_disable()
	pinned_result := C.vkr_rcu_bootstrap(u32(cpu_locals.len))
	pinned_valid := cpu.interrupt_state() && native_preempt_count() == 2
		&& proc.current_thread().linuxkpi_alloc_fail_after == 0
	release_preemption(false)
	release_preemption(false)
	test_alloc_oom(-1)
	irq_valid := rcu_cold_irq_selftest()
	if irq_off_result != -1 || pinned_result != -1 || !irq_off_valid || !pinned_valid
		|| !irq_valid
		|| katomic.load(&rcu_native_cold_irq_result) != 0 {
		C.kprintf(c'linuxkpi: RCU cold contexts irq_off=%d pinned=%d irq_off_valid=%d pinned_valid=%d actor=%d handler=%d\n',
			irq_off_result, pinned_result, int(irq_off_valid), int(pinned_valid), int(irq_valid),
			katomic.load(&rcu_native_cold_irq_result))
		lib.kpanic(unsafe { nil }, c'linuxkpi: unsafe RCU constructor context was accepted')
	}
	for fail_after in 0 .. 2 {
		before := selftest_free_baseline()
		test_alloc_oom(i32(fail_after))
		result := C.vkr_rcu_bootstrap(u32(cpu_locals.len))
		test_alloc_oom(-1)
		if result != -12 || C.vkr_rcu_ready() || selftest_free_baseline() != before {
			lib.kpanic(unsafe { nil }, c'linuxkpi: RCU constructor rollback failed')
		}
	}
	if C.vkr_rcu_bootstrap(u32(cpu_locals.len)) != 0 || !C.vkr_rcu_ready() {
		lib.kpanic(unsafe { nil }, c'linuxkpi: ordinary RCU initialization failed')
	}
	// Both permanent worker owners and the full backend initializer are ready.
	// QS storage is permanent; activation never withdraws during native boot.
	katomic.store(mut &rcu_native_active, u32(1))
}
