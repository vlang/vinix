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
import x86.hpet as migration_clock

#include "linuxkpi_migration_fixture_v_primitives.h"

struct C.vinix_migration_completion {}

fn C.vinix_linuxkpi_migration_fixture_disable()
fn C.vinix_linuxkpi_migration_fixture_enable()
fn C.vinix_linuxkpi_migration_fixture_sleep(i64) i64
fn C.vinix_linuxkpi_migration_fixture_init_completion(voidptr)
fn C.vinix_linuxkpi_migration_fixture_complete(voidptr)
fn C.vinix_linuxkpi_migration_fixture_wait(voidptr)

// Actor controls, completion backing and the IRQ work have boot lifetime.
// Observer references keep every Thread readable until actual off-stack join.
struct MigrationTestLedger {
mut:
	ready                        [3]bool
	command                      [3]u32
	done                         [3]bool
	owners                       [3]voidptr
	entered                      bool
	quit                         bool
	woken_cpu                    u32
	final_cpu                    u32
	idle_seen                    bool
	stress_cycles                [3]u32
	completion                   C.vinix_migration_completion
	irq                          C.vinix_irqwork_fixture
	irq_ready                    bool
	irq_done                     bool
	irq_queued                   bool
	failures                     u32
	constructor_failed           int = -1
	constructor_failure_consumed bool
}

__global migration_test_ledger MigrationTestLedger

fn migration_test_fail(bit u32) {
	for {
		old := katomic.load(&migration_test_ledger.failures)
		if katomic.cas(mut &migration_test_ledger.failures, old, old | bit) { return }
	}
}

fn migration_test_wait(flag &bool) bool {
	start := migration_clock.nanoseconds()
	for !katomic.load(flag) {
		if migration_clock.nanoseconds() - start >= dmafence_test_timeout_ns { return false }
		sched.reschedule()
	}
	return true
}

fn migration_test_state(target u32, depth u32, expected_if bool, expected_preempt u32) bool {
	ints := cpu.interrupt_toggle(false)
	local := cpulocal.current()
	index := local.cpu_number
	owner := proc.current_thread()
	word := katomic.load(&owner.linuxkpi_migration_pin)
	expected := if depth == 0 { u64(0) } else { (u64(depth) << 32) | (u64(target) + 1) }
	valid := ints == expected_if && index == u64(target) && word == expected
		&& preempt_depth[index] == expected_preempt && local.maskable_irq_depth == 0
	cpu.interrupt_toggle(ints)
	return valid
}

fn migration_test_unpin() {
	for katomic.load(&proc.current_thread().linuxkpi_migration_pin) != 0 {
		C.vinix_linuxkpi_migration_fixture_enable()
	}
}

fn migration_test_reach(target u32) bool {
	start := migration_clock.nanoseconds()
	for {
		ints := cpu.interrupt_toggle(false)
		placed := cpulocal.current().cpu_number == u64(target)
		cpu.interrupt_toggle(ints)
		if placed { return true }
		if migration_clock.nanoseconds() - start >= dmafence_test_timeout_ns { return false }
		sched.reschedule()
	}
	return false
}

fn migration_test_pinned_case(mode u32) bool {
	if worker_bind(1) != 0 || !migration_test_state(1, 0, true, 0) { return false }
	C.vinix_linuxkpi_migration_fixture_disable()
	if mode == 1 { C.vinix_linuxkpi_migration_fixture_disable() }
	defer { migration_test_unpin() }
	expected_depth := if mode == 1 { u32(2) } else { u32(1) }
	mut valid := migration_test_state(1, expected_depth, true, 0) && may_sleep()
	if mode == 1 {
		owner := proc.current_thread()
		mask := katomic.load(&owner.affinity_mask)
		numa := katomic.load(&owner.numa_node)
		word := katomic.load(&owner.linuxkpi_migration_pin)
		valid = valid && worker_bind(2) == -16 && katomic.load(&owner.affinity_mask) == mask
			&& katomic.load(&owner.numa_node) == numa && katomic.load(&owner.linuxkpi_migration_pin) == word
			&& worker_bind(1) == 0 && migration_test_state(1, 2, true, 0)
	}
	katomic.store(mut &migration_test_ledger.entered, true)
	// The controller waits for actual off-queue park and changes the ordinary
	// requested mask to CPU2 before completing this real wait from CPU0.
	C.vinix_linuxkpi_migration_fixture_wait(unsafe { &migration_test_ledger.completion })
	valid = valid && migration_test_state(1, expected_depth, true, 0)
		&& katomic.load(&proc.current_thread().affinity_mask) == u64(4)
	migration_test_ledger.woken_cpu = 1
	if mode == 1 {
		C.vinix_linuxkpi_migration_fixture_enable()
		for _ in 0 .. 8 {
			sched.reschedule()
			valid = valid && migration_test_state(1, 1, true, 0)
		}
		valid = valid && C.vinix_linuxkpi_migration_fixture_sleep(5) == 0
			&& migration_test_state(1, 1, true, 0)
		C.vinix_linuxkpi_migration_fixture_enable()
	} else if mode == 2 {
		ints := cpu.interrupt_toggle(false)
		C.vinix_linuxkpi_migration_fixture_enable()
		valid = valid && ints && migration_test_state(1, 0, false, 0) && preempt_pending[1]
		for _ in 0 .. 1000 { spin_wait() }
		valid = valid && migration_test_state(1, 0, false, 0)
		cpu.interrupt_toggle(ints)
	} else {
		preempt_disable()
		preempt_disable()
		before := katomic.load(&preempt_deferrals[1])
		C.vinix_linuxkpi_migration_fixture_enable()
		valid = valid && migration_test_state(1, 0, true, 2) && preempt_pending[1]
		start := migration_clock.nanoseconds()
		for katomic.load(&preempt_deferrals[1]) == before {
			if migration_clock.nanoseconds() - start >= dmafence_test_timeout_ns {
				valid = false
				break
			}
			spin_wait()
		}
		valid = valid && migration_test_state(1, 0, true, 2)
		release_preemption(false)
		valid = valid && migration_test_state(1, 0, true, 1)
		preempt_enable()
	}
	valid = migration_test_reach(2) && valid && migration_test_state(2, 0, true, 0)
	migration_test_ledger.final_cpu = 2
	return valid
}

fn migration_test_irq(_work &C.irq_work) {
	local := cpulocal.current()
	owner := proc.current_thread()
	depth := preempt_depth[local.cpu_number]
	mut valid := !cpu.interrupt_state() && local.cpu_number == 1 && local.maskable_irq_depth != 0
		&& depth != 0 && usize(owner) == usize(migration_test_ledger.owners[0])
		&& katomic.load(&owner.linuxkpi_migration_pin) == 0
	C.vinix_linuxkpi_migration_fixture_disable()
	C.vinix_linuxkpi_migration_fixture_disable()
	valid = valid && katomic.load(&owner.linuxkpi_migration_pin) == ((u64(2) << 32) | u64(2))
		&& !cpu.interrupt_state() && preempt_depth[1] == depth
	C.vinix_linuxkpi_migration_fixture_enable()
	valid = valid && katomic.load(&owner.linuxkpi_migration_pin) == ((u64(1) << 32) | u64(2))
	C.vinix_linuxkpi_migration_fixture_enable()
	valid = valid && katomic.load(&owner.linuxkpi_migration_pin) == 0 && !cpu.interrupt_state()
		&& preempt_depth[1] == depth && preempt_pending[1]
		&& cpulocal.current().cpu_number == 1 && local.maskable_irq_depth != 0
	if !valid { migration_test_fail(64) }
	katomic.store(mut &migration_test_ledger.irq_done, true)
}

fn migration_test_irq_case() bool {
	if worker_bind(1) != 0 || !migration_test_state(1, 0, true, 0) { return false }
	preempt_disable()
	katomic.store(mut &migration_test_ledger.irq_ready, true)
	start := migration_clock.nanoseconds()
	mut valid := true
	for !katomic.load(&migration_test_ledger.irq_done) && !katomic.load(&migration_test_ledger.quit) {
		if migration_clock.nanoseconds() - start >= dmafence_test_timeout_ns {
			valid = false
			break
		}
		spin_wait()
	}
	valid = valid && migration_test_state(1, 0, true, 1) && preempt_pending[1]
	preempt_enable()
	return migration_test_reach(2) && valid && migration_test_state(2, 0, true, 0)
}

fn migration_test_actor(argument voidptr) {
	index := u32(usize(argument))
	if katomic.load(&proc.current_thread().linuxkpi_migration_pin) != 0 || worker_bind(index + 1) != 0 {
		migration_test_fail(1)
	}
	katomic.store(mut &migration_test_ledger.ready[index], true)
	for !katomic.load(&migration_test_ledger.quit) {
		command := katomic.load(&migration_test_ledger.command[index])
		if command == 0 {
			sched.reschedule()
			continue
		}
		mut valid := true
		if command == 5 {
			valid = migration_test_contention(index)
		} else if index == 0 {
			valid = if command == 4 {
				migration_test_irq_case()
			} else {
				migration_test_pinned_case(command)
			}
		} else {
			target := if index == 1 { u32(1) } else { u32(2) }
			valid = worker_bind(target) == 0 && migration_test_state(target, 0, true, 0)
			C.vinix_linuxkpi_migration_fixture_disable()
			valid = valid && migration_test_state(target, 1, true, 0)
				&& C.vinix_linuxkpi_migration_fixture_sleep(2) == 0
				&& migration_test_state(target, 1, true, 0)
			C.vinix_linuxkpi_migration_fixture_enable()
			valid = valid && migration_test_state(target, 0, true, 0) && worker_bind(3) == 0
		}
		if !valid { migration_test_fail(u32(2) << index) }
		katomic.store(mut &migration_test_ledger.command[index], u32(0))
		katomic.store(mut &migration_test_ledger.done[index], true)
	}
	migration_test_unpin()
	event.pthread_exit(unsafe { nil })
}

// All three actors compete in the real runqueue with an unrestricted ordinary
// mask. A concurrent steal must recheck the actual pin after locking a task;
// this is stress coverage, not a deterministic hook in production scan code.
fn migration_test_contention(index u32) bool {
	owner := proc.current_thread()
	ints := cpu.interrupt_toggle(false)
	katomic.store(mut &owner.numa_node, -1)
	katomic.store(mut &owner.affinity_mask, u64(-1))
	cpu.interrupt_toggle(ints)
	mut valid := true
	for cycle in 0 .. 200 {
		C.vinix_linuxkpi_migration_fixture_disable()
		word := katomic.load(&owner.linuxkpi_migration_pin)
		target := u32(word) - 1
		valid = valid && migration_test_state(target, 1, true, 0) && may_sleep()
		C.vinix_linuxkpi_migration_fixture_disable()
		sched.reschedule()
		valid = valid && migration_test_state(target, 2, true, 0)
		C.vinix_linuxkpi_migration_fixture_enable()
		if cycle % 16 == 0 {
			valid = valid && C.vinix_linuxkpi_migration_fixture_sleep(1) == 0
		}
		sched.reschedule()
		valid = valid && migration_test_state(target, 1, true, 0)
		C.vinix_linuxkpi_migration_fixture_enable()
		migration_test_ledger.stress_cycles[index]++
		sched.reschedule()
	}
	return worker_bind(index + 1) == 0 && valid
}

fn migration_test_start(index u32, command u32) {
	katomic.store(mut &migration_test_ledger.done[index], false)
	katomic.store(mut &migration_test_ledger.command[index], command)
}

fn migration_test_parked() bool {
	owner := unsafe { &proc.Thread(migration_test_ledger.owners[0]) }
	start := migration_clock.nanoseconds()
	for !(katomic.load(&migration_test_ledger.entered)
		&& C.vinix_linuxkpi_dmafence_fixture_task_state(unsafe { &owner.linuxkpi_task[0] }) == 2
		&& !katomic.load(&owner.is_in_queue) && katomic.load(&owner.running_on) == u64(-1)
		&& !katomic.load(&owner.is_in_queue)) {
		if migration_clock.nanoseconds() - start >= dmafence_test_timeout_ns { return false }
		sched.reschedule()
	}
	return true
}

fn migration_test_case(mode u32) bool {
	C.vinix_linuxkpi_migration_fixture_init_completion(unsafe { &migration_test_ledger.completion })
	katomic.store(mut &migration_test_ledger.entered, false)
	migration_test_ledger.woken_cpu = 0
	migration_test_ledger.final_cpu = 0
	migration_test_start(0, mode)
	defer {
		C.vinix_linuxkpi_migration_fixture_complete(unsafe { &migration_test_ledger.completion })
		if !migration_test_wait(&migration_test_ledger.done[0]) {
			lib.kpanic(unsafe { nil }, c'linuxkpi: migration actor cleanup deadline')
		}
	}
	if !migration_test_parked() || test_worker_route(migration_test_ledger.owners[0], 2) != 0 {
		return false
	}
	if mode == 1 {
		migration_test_start(1, 1)
		migration_test_start(2, 1)
		if !migration_test_wait(&migration_test_ledger.done[1]) || !migration_test_wait(&migration_test_ledger.done[2]) {
			return false
		}
		start := migration_clock.nanoseconds()
		for !katomic.load(&cpu_locals[1].is_idle) {
			if migration_clock.nanoseconds() - start >= dmafence_test_timeout_ns { return false }
			sched.reschedule()
		}
		migration_test_ledger.idle_seen = true
	}
	C.vinix_linuxkpi_migration_fixture_complete(unsafe { &migration_test_ledger.completion })
	return migration_test_wait(&migration_test_ledger.done[0])
		&& migration_test_ledger.woken_cpu == 1 && migration_test_ledger.final_cpu == 2
		&& katomic.load(&migration_test_ledger.failures) == 0
}

fn migration_test_run_irq() bool {
	katomic.store(mut &migration_test_ledger.irq_ready, false)
	katomic.store(mut &migration_test_ledger.irq_done, false)
	if C.vinix_linuxkpi_irqwork_fixture_init(unsafe { &migration_test_ledger.irq }, migration_test_irq, 0) != 0 {
		return false
	}
	migration_test_start(0, 4)
	defer {
		if migration_test_ledger.irq_queued {
			C.vinix_linuxkpi_irqwork_fixture_sync(unsafe { &migration_test_ledger.irq })
			migration_test_ledger.irq_queued = false
		}
		katomic.store(mut &migration_test_ledger.irq_done, true)
		if !migration_test_wait(&migration_test_ledger.done[0]) {
			lib.kpanic(unsafe { nil }, c'linuxkpi: migration IRQ actor cleanup deadline')
		}
	}
	if !migration_test_wait(&migration_test_ledger.irq_ready) || test_worker_route(migration_test_ledger.owners[0], 2) != 0 {
		return false
	}
	migration_test_ledger.irq_queued = C.vinix_linuxkpi_irqwork_fixture_queue(unsafe { &migration_test_ledger.irq }, 1)
	return migration_test_ledger.irq_queued && migration_test_wait(&migration_test_ledger.irq_done)
		&& migration_test_wait(&migration_test_ledger.done[0]) && katomic.load(&migration_test_ledger.failures) == 0
}

fn migration_test_lifecycle(fail_after int, fail_stage int) bool {
	ints := cpu.interrupt_toggle(false)
	mut controller := proc.current_thread()
	affinity := katomic.load(&controller.affinity_mask)
	numa := katomic.load(&controller.numa_node)
	cpu.interrupt_toggle(ints)
	mut owners := unsafe { [3]&proc.Thread{} }
	mut created := 0
	mut completion_live := false
	defer {
		sched.test_kernel_thread_failure(0)
		migration_test_unpin()
		if completion_live {
			C.vinix_linuxkpi_migration_fixture_complete(unsafe { &migration_test_ledger.completion })
		}
		if migration_test_ledger.irq_queued {
			C.vinix_linuxkpi_irqwork_fixture_sync(unsafe { &migration_test_ledger.irq })
		}
		katomic.store(mut &migration_test_ledger.irq_done, true)
		katomic.store(mut &migration_test_ledger.quit, true)
		for i in 0 .. created { irq_test_join(owners[i]) }
		selftest_free_baseline()
		restore := cpu.interrupt_toggle(false)
		katomic.store(mut &controller.numa_node, numa)
		katomic.store(mut &controller.affinity_mask, affinity)
		cpu.interrupt_toggle(restore)
	}
	if !ints || katomic.load(&controller.linuxkpi_migration_pin) != 0 || worker_bind(0) != 0 {
		return false
	}
	migration_test_ledger = MigrationTestLedger{}
	C.vinix_linuxkpi_migration_fixture_init_completion(unsafe { &migration_test_ledger.completion })
	completion_live = true
	// New workers made while their creator is pinned must start with zero.
	C.vinix_linuxkpi_migration_fixture_disable()
	for i in 0 .. 3 {
		if i == fail_after { sched.test_kernel_thread_failure(fail_stage) }
		mut actor := sched.try_new_kernel_thread(voidptr(migration_test_actor), voidptr(i)) or {
			migration_test_ledger.constructor_failed = i
			migration_test_ledger.constructor_failure_consumed = proc.current_thread().kernel_thread_fail_stage == 0
			return false
		}
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
		migration_test_ledger.owners[i] = actor
		created++
	}
	C.vinix_linuxkpi_migration_fixture_enable()
	for i in 0 .. 3 { if !migration_test_wait(&migration_test_ledger.ready[i]) { return false } }
	for i in 0 .. 3 { migration_test_start(u32(i), 5) }
	for i in 0 .. 3 {
		if !migration_test_wait(&migration_test_ledger.done[i]) || migration_test_ledger.stress_cycles[i] != 200 {
			return false
		}
	}
	if !migration_test_case(1) || !migration_test_case(2) || !migration_test_case(3) || !migration_test_run_irq() {
		return false
	}
	return migration_test_ledger.idle_seen && katomic.load(&migration_test_ledger.failures) == 0
}

fn migration_native_selftest() bool {
	if cpu_locals.len < 4 || cpu_locals.len > 64 { return false }
	// Exercise real per-caller constructor failure at each stack/FPU/Thread
	// allocation boundary, both before publication and after one live actor.
	// The lifecycle owns all successful actors through off-stack joins.
	for fail_after in 0 .. 2 {
		for stage in 1 .. 5 {
			before := selftest_free_baseline()
			mut heap_before := CPUFeatureHeapSnapshot{}
			mut heap_after := CPUFeatureHeapSnapshot{}
			if !cpu_feature_test_heap(unsafe { &heap_before }) || migration_test_lifecycle(fail_after, stage)
				|| migration_test_ledger.constructor_failed != fail_after
				|| !migration_test_ledger.constructor_failure_consumed
				|| selftest_free_baseline() != before || !cpu_feature_test_heap(unsafe { &heap_after })
				|| heap_before.count != heap_after.count {
				return false
			}
			for i in 0 .. heap_before.count {
				if heap_before.sizes[i] != heap_after.sizes[i] || heap_before.live[i] != heap_after.live[i] {
					return false
				}
			}
		}
	}
	C.kprintf(c'linuxkpi: migration pin constructor rollback passed all four failure stages before and after actor publication; pages and heap recovered\n')
	for round in 0 .. 3 {
		before := selftest_free_baseline()
		if !migration_test_lifecycle(-1, 0) { return false }
		C.kprintf(c'linuxkpi: migration pin lifecycle warmup %d free-byte baseline=%llu after=%llu\n', round + 1, before, selftest_free_baseline())
	}
	mut before := CPUFeatureHeapSnapshot{}
	mut after := CPUFeatureHeapSnapshot{}
	free_before := selftest_free_baseline()
	if !cpu_feature_test_heap(unsafe { &before }) || !migration_test_lifecycle(-1, 0) {
		return false
	}
	free_after := selftest_free_baseline()
	if !cpu_feature_test_heap(unsafe { &after }) { return false }
	mut equal := before.count == after.count
	for i in 0 .. before.count {
		if before.sizes[i] != after.sizes[i] || before.live[i] != after.live[i] {
			equal = false
			C.kprintf(c'linuxkpi: migration pin heap class %d size_before=%llu size_after=%llu live_before=%llu live_after=%llu\n', i, before.sizes[i], after.sizes[i], before.live[i], after.live[i])
		}
	}
	C.kprintf(c'linuxkpi: migration pin fourth lifecycle free-byte baseline=%llu after=%llu heap_equal=%u\n', free_before, free_after, u32(equal))
	return free_before == free_after && equal && katomic.load(&migration_test_ledger.failures) == 0
}
