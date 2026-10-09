// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module linuxkpi

import errno
import event
import katomic
import proc
import sched
import x86.cpu
import x86.cpu.local as cpulocal
import x86.hpet as worker_irq_clock

// The typed facade calls the original Linux synchronous SMP API. Its genuine
// stack CSD remains owned until the remote callback has returned.
#include "linuxkpi_smp_fixture_v_primitives.h"

const worker_irq_rounds = u64(200)
const worker_irq_timeout_ns = u64(30000000000)

struct WorkerIrqLedger {
mut:
	owner     voidptr
	ready     bool
	quit      bool
	failures  u32
	terminal  u64
	post_iret u64
}

struct WorkerIrqObservation {
mut:
	sequence u64
	eligible bool
	failures u32
}

// This one boot-lifetime ledger is reset only after the previous actor has
// actually left its stack, dropped its final retained pin and been reaped.
__global worker_irq_ledger WorkerIrqLedger

fn worker_irq_actor(_argument voidptr) {
	if worker_bind(1) != 0 {
		katomic.store(mut &worker_irq_ledger.failures, u32(1))
		katomic.store(mut &worker_irq_ledger.ready, true)
		event.pthread_exit(unsafe { nil })
		return
	}
	mut owner := proc.current_thread()
	ints := cpu.interrupt_toggle(false)
	old_failure_gate := owner.linuxkpi_alloc_fail_after
	owner.linuxkpi_alloc_fail_after = 0
	// A valid local NUMA hint makes an erroneous same-CPU bind observable,
	// independently of its already single-CPU affinity mask.
	katomic.store(mut &owner.numa_node, int(cpulocal.current().numa_node))
	if !ints || cpulocal.current().maskable_irq_depth != 0 || preempt_depth[1] != 0
		|| voidptr(owner) != worker_irq_ledger.owner
		|| voidptr(owner.process) != voidptr(kernel_process) {
		katomic.store(mut &worker_irq_ledger.failures, u32(2))
	}
	katomic.store(mut &worker_irq_ledger.ready, true)
	cpu.interrupt_toggle(ints)
	for !katomic.load(&worker_irq_ledger.quit) {
		check_ints := cpu.interrupt_toggle(false)
		terminal := katomic.load(&worker_irq_ledger.terminal)
		if terminal > katomic.load(&worker_irq_ledger.post_iret) {
			// An ordinary target TASK provides this acknowledgement after the
			// matching real IRQ return, rather than another interrupt callback.
			if !check_ints || cpulocal.current().cpu_number != 1
				|| cpulocal.current().maskable_irq_depth != 0 || preempt_depth[1] != 0
				|| voidptr(proc.current_thread()) != voidptr(owner) {
				katomic.store(mut &worker_irq_ledger.failures, u32(4))
			}
			katomic.store(mut &worker_irq_ledger.post_iret, terminal)
		}
		cpu.interrupt_toggle(check_ints)
		// Service genuine native TLB requests; this cannot deliver an SMP
		// callback by polling. The real LAPIC vector supplies every callback.
		spin_wait()
	}
	restore_ints := cpu.interrupt_toggle(false)
	owner.linuxkpi_alloc_fail_after = old_failure_gate
	cpu.interrupt_toggle(restore_ints)
	event.pthread_exit(unsafe { nil })
}

fn worker_irq_callback(argument voidptr) {
	mut result := unsafe { &WorkerIrqObservation(argument) }
	local := cpulocal.current()
	mut owner := proc.current_thread()
	// A scheduler tick can switch this CPU before the IPI arrives. Only an
	// actual interruption of our ordinary pin-zero actor is a test attempt.
	if voidptr(owner) == worker_irq_ledger.owner && preempt_depth[1] == 0 {
		result.eligible = true
		mask := katomic.load(&owner.affinity_mask)
		node := katomic.load(&owner.numa_node)
		failure_gate := owner.linuxkpi_alloc_fail_after
		depth := local.maskable_irq_depth
		if cpu.interrupt_state() || local.cpu_number != 1 || depth == 0
			|| voidptr(owner.process) != voidptr(kernel_process) || failure_gate != 0 {
			result.failures |= 1
		}
		// IF is deliberately enabled while the real maskable frame is live.
		// A binding attempt must reject before changing this borrowed task.
		cpu.interrupt_toggle(true)
		bound := worker_bind(1)
		// Native CPU/task accessors require IRQs disabled. Capture the state
		// restored by bind before closing it for the identity observations.
		bind_ints := cpu.interrupt_toggle(false)
		if bound != -errno.ewouldblock || !bind_ints
			|| voidptr(cpulocal.current()) != voidptr(local) || local.cpu_number != 1
			|| local.maskable_irq_depth != depth || preempt_depth[1] != 0
			|| voidptr(proc.current_thread()) != voidptr(owner)
			|| katomic.load(&owner.affinity_mask) != mask
			|| katomic.load(&owner.numa_node) != node
			|| owner.linuxkpi_alloc_fail_after != failure_gate {
			result.failures |= 2
		}
		// Negative-control builds restore the actor even if the old predicate
		// wrongly publishes affinity/NUMA state. The regression still fails.
		katomic.store(mut &owner.affinity_mask, mask)
		katomic.store(mut &owner.numa_node, node)
	}
	// No borrowed argument access follows this terminal publication. The
	// controller additionally retains it until synchronous completion and a
	// target-task acknowledgement of the matching actual interrupt return.
	katomic.store(mut &worker_irq_ledger.terminal, result.sequence)
}

fn worker_irq_wait(sequence u64, ready bool) bool {
	started := worker_irq_clock.nanoseconds()
	for {
		if katomic.load(&worker_irq_ledger.failures) != 0 { return false }
		if ready {
			if katomic.load(&worker_irq_ledger.ready) { return true }
		} else if katomic.load(&worker_irq_ledger.post_iret) >= sequence {
			return true
		}
		if worker_irq_clock.nanoseconds() - started >= worker_irq_timeout_ns { return false }
		sched.reschedule()
	}
	return false
}

fn worker_irq_batch() bool {
	mut controller := proc.current_thread()
	ints := cpu.interrupt_toggle(false)
	original_mask := katomic.load(&controller.affinity_mask)
	original_node := katomic.load(&controller.numa_node)
	cpu.interrupt_toggle(ints)
	defer {
		restore_ints := cpu.interrupt_toggle(false)
		katomic.store(mut &controller.affinity_mask, original_mask)
		katomic.store(mut &controller.numa_node, original_node)
		cpu.interrupt_toggle(restore_ints)
	}
	if worker_bind(0) != 0 { return false }
	worker_irq_ledger = WorkerIrqLedger{}
	mut actor := sched.try_new_kernel_thread(voidptr(worker_irq_actor), unsafe { nil }) or { return false }
	proc.pin_thread(actor)
	proc.pin_thread(actor)
	actor.pthread_joinable = 1
	worker_irq_ledger.owner = actor
	if !sched.enqueue_thread(actor, false) {
		worker_irq_ledger.owner = unsafe { nil }
		proc.unpin_thread(actor)
		proc.unpin_thread(actor)
		sched.discard_unstarted_thread(actor)
		return false
	}
	defer {
		katomic.store(mut &worker_irq_ledger.quit, true)
		irq_test_join(actor)
		selftest_free_baseline()
		worker_irq_ledger.owner = unsafe { nil }
	}
	if !worker_irq_wait(0, true) { return false }
	mut completed := u64(0)
	mut sequence := u64(0)
	started := worker_irq_clock.nanoseconds()
	for completed < worker_irq_rounds {
		if worker_irq_clock.nanoseconds() - started >= worker_irq_timeout_ns { return false }
		sequence++
		mut observation := WorkerIrqObservation{ sequence: sequence }
		if C.vinix_linuxkpi_smp_fixture_single(1, worker_irq_callback, unsafe { &observation }, 1) != 0
			|| !worker_irq_wait(sequence, false) || observation.failures != 0 { return false }
		if observation.eligible { completed++ }
	}
	return true
}

fn worker_irq_selftest() bool {
	if cpu_locals.len < 2 || cpu_locals.len > 64 { return false }
	for round in 0 .. 3 {
		before := selftest_free_baseline()
		if !worker_irq_batch() { return false }
		C.kprintf(c'linuxkpi: worker IRQ rejection warmup %d free-byte baseline=%llu after=%llu\n', round + 1, before, selftest_free_baseline())
	}
	mut before := CPUFeatureHeapSnapshot{}
	mut after := CPUFeatureHeapSnapshot{}
	free_before := selftest_free_baseline()
	if !cpu_feature_test_heap(unsafe { &before }) || !worker_irq_batch() { return false }
	free_after := selftest_free_baseline()
	if !cpu_feature_test_heap(unsafe { &after }) { return false }
	mut equal := before.count == after.count
	for index in 0 .. before.count {
		if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] { equal = false }
	}
	C.kprintf(c'linuxkpi: worker IRQ rejection fourth batch free-byte baseline=%llu after=%llu heap_equal=%d\n', free_before, free_after, int(equal))
	return free_before == free_after && equal
}
