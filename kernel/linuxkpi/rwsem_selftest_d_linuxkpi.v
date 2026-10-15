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
import x86.hpet as rwsem_clock

#include "linuxkpi_rwsem_fixture_v_primitives.h"
struct C.vinix_rwsem_fixture {}
struct C.vinix_rwsem_completion {}
fn C.vinix_linuxkpi_rwsem_fixture_static() voidptr
fn C.vinix_linuxkpi_rwsem_fixture_init(voidptr)
fn C.vinix_linuxkpi_rwsem_fixture_read(voidptr, u32) i32
fn C.vinix_linuxkpi_rwsem_fixture_write(voidptr, bool) i32
fn C.vinix_linuxkpi_rwsem_fixture_try(voidptr, bool) i32
fn C.vinix_linuxkpi_rwsem_fixture_up(voidptr, u32)
fn C.vinix_linuxkpi_rwsem_fixture_downgrade(voidptr)
fn C.vinix_linuxkpi_rwsem_fixture_value(voidptr, u32) i64
fn C.vinix_linuxkpi_rwsem_fixture_init_completion(voidptr)
fn C.vinix_linuxkpi_rwsem_fixture_complete(voidptr)
fn C.vinix_linuxkpi_rwsem_fixture_wait(voidptr)
fn C.vinix_linuxkpi_rwsem_fixture_alloc() voidptr
fn C.vinix_linuxkpi_rwsem_fixture_free(voidptr)

// Every cross-task control and original record has boot lifetime. Each actor
// has separate join and observer references until actual off-stack retirement.
struct RwsemTestLedger {
mut:
	sem C.vinix_rwsem_fixture
	atomic_sem C.vinix_rwsem_fixture
	gates [3]C.vinix_rwsem_completion
	ready [3]bool
	command [3]u32
	mode [3]u32
	started [3]bool
	acquired [3]bool
	done [3]bool
	results [3]i32
	owners [3]voidptr
	quit bool
	readers u32
	writer bool
	controller_hold u32
	transfer_hold bool
	dynamic voidptr
	dynamic_hold bool
	dynamic_freed bool
	freed_objects u32
	irq C.vinix_irqwork_fixture
	irq_ready bool
	irq_done bool
	irq_queued bool
	failures u32
	constructor_failed int = -1
	constructor_failure_consumed bool
}
__global rwsem_test_ledger RwsemTestLedger

fn rwsem_test_fail(bit u32) {
	for {
		old := katomic.load(&rwsem_test_ledger.failures)
		if katomic.cas(mut &rwsem_test_ledger.failures, old, old | bit) { return }
	}
}
fn rwsem_test_wait(flag &bool) bool {
	start := rwsem_clock.nanoseconds()
	for !katomic.load(flag) {
		if rwsem_clock.nanoseconds() - start >= dmafence_test_timeout_ns { return false }
		sched.reschedule()
	}
	return true
}
fn rwsem_test_parked(index u32, state u32, waiters i64) bool {
	owner := unsafe { &proc.Thread(rwsem_test_ledger.owners[index]) }
	start := rwsem_clock.nanoseconds()
	sem := if katomic.load(&rwsem_test_ledger.command[index]) == 6 { rwsem_test_ledger.dynamic }
		else { voidptr(unsafe { &rwsem_test_ledger.sem }) }
	for {
		if katomic.load(&rwsem_test_ledger.started[index])
			&& C.vinix_linuxkpi_dmafence_fixture_task_state(unsafe { &owner.linuxkpi_task[0] }) == state
			&& !katomic.load(&owner.is_in_queue) && katomic.load(&owner.running_on) == u64(-1)
			&& !katomic.load(&owner.is_in_queue)
			&& C.vinix_linuxkpi_rwsem_fixture_value(sem, 2) == waiters { return true }
		if rwsem_clock.nanoseconds() - start >= dmafence_test_timeout_ns { return false }
		sched.reschedule()
	}
	return false
}
fn rwsem_test_start(index u32, command u32, mode u32) {
	C.vinix_linuxkpi_rwsem_fixture_init_completion(unsafe { &rwsem_test_ledger.gates[index] })
	rwsem_test_ledger.mode[index] = mode
	rwsem_test_ledger.results[index] = -999
	katomic.store(mut &rwsem_test_ledger.started[index], false)
	katomic.store(mut &rwsem_test_ledger.acquired[index], false)
	katomic.store(mut &rwsem_test_ledger.done[index], false)
	katomic.store(mut &rwsem_test_ledger.command[index], command)
}
fn rwsem_test_release(index u32) bool {
	C.vinix_linuxkpi_rwsem_fixture_complete(unsafe { &rwsem_test_ledger.gates[index] })
	return rwsem_test_wait(&rwsem_test_ledger.done[index])
}
fn rwsem_test_readers(add bool) {
	for {
		old := katomic.load(&rwsem_test_ledger.readers)
		if !add && old == 0 { rwsem_test_fail(4); return }
		next := if add { old + 1 } else { old - 1 }
		if katomic.cas(mut &rwsem_test_ledger.readers, old, next) { return }
	}
}
fn rwsem_test_actor(argument voidptr) {
	index := u32(usize(argument))
	if worker_bind(index + 1) != 0 || !dma_fence_test_task(index + 1) { rwsem_test_fail(1) }
	katomic.store(mut &rwsem_test_ledger.ready[index], true)
	for !katomic.load(&rwsem_test_ledger.quit) {
		command := katomic.load(&rwsem_test_ledger.command[index])
		if command == 0 { sched.reschedule(); continue }
		mut owner := proc.current_thread()
		gate := owner.linuxkpi_alloc_fail_after
		owner.linuxkpi_alloc_fail_after = 0
		katomic.store(mut &rwsem_test_ledger.started[index], true)
		if command == 7 {
			preempt_disable()
			katomic.store(mut &rwsem_test_ledger.irq_ready, true)
			start := rwsem_clock.nanoseconds()
			for !katomic.load(&rwsem_test_ledger.irq_done) {
				if rwsem_clock.nanoseconds() - start >= dmafence_test_timeout_ns {
					rwsem_test_fail(512)
					break
				}
				spin_wait()
			}
			preempt_enable()
		} else {
			sem := if command == 6 { rwsem_test_ledger.dynamic } else { voidptr(unsafe { &rwsem_test_ledger.sem }) }
			mode := rwsem_test_ledger.mode[index]
			writer := command == 2 || command == 4 || command == 6
			result := if writer { C.vinix_linuxkpi_rwsem_fixture_write(sem, mode != 0) }
				else { C.vinix_linuxkpi_rwsem_fixture_read(sem, mode) }
			rwsem_test_ledger.results[index] = result
			if result == 0 {
				if command == 5 {
					katomic.store(mut &rwsem_test_ledger.transfer_hold, true)
				} else {
					if writer {
						if !katomic.cas(mut &rwsem_test_ledger.writer, false, true)
							|| katomic.load(&rwsem_test_ledger.readers) != 0 { rwsem_test_fail(8) }
					} else {
						rwsem_test_readers(true)
						if katomic.load(&rwsem_test_ledger.writer) { rwsem_test_fail(16) }
					}
					katomic.store(mut &rwsem_test_ledger.acquired[index], true)
					if command == 1 || command == 2 {
						C.vinix_linuxkpi_rwsem_fixture_wait(unsafe { &rwsem_test_ledger.gates[index] })
					}
					if writer {
						if katomic.load(&rwsem_test_ledger.readers) != 0 { rwsem_test_fail(32) }
						katomic.store(mut &rwsem_test_ledger.writer, false)
					} else {
						if katomic.load(&rwsem_test_ledger.writer) { rwsem_test_fail(64) }
						rwsem_test_readers(false)
					}
					C.vinix_linuxkpi_rwsem_fixture_up(sem, if writer { u32(1) } else { u32(0) })
					if command == 6 {
						C.vinix_linuxkpi_rwsem_fixture_free(sem)
						katomic.store(mut &rwsem_test_ledger.dynamic_freed, true)
					}
				}
			}
		}
		if owner.linuxkpi_alloc_fail_after != 0 || !dma_fence_test_task(index + 1) || !may_sleep() { rwsem_test_fail(2) }
		owner.linuxkpi_alloc_fail_after = gate
		test_task_signal(owner, 0)
		katomic.store(mut &rwsem_test_ledger.command[index], u32(0))
		katomic.store(mut &rwsem_test_ledger.done[index], true)
	}
	event.pthread_exit(unsafe { nil })
}

fn rwsem_test_empty(sem voidptr) bool {
	// A reader-owner hint may retain a dead task's address; it is not a ref.
	return C.vinix_linuxkpi_rwsem_fixture_value(sem, 0) == 0
		&& C.vinix_linuxkpi_rwsem_fixture_value(sem, 2) == 0
}
fn rwsem_test_atomic(sem voidptr) bool {
	if C.vinix_linuxkpi_rwsem_fixture_try(sem, false) != 1 { return false }
	mut valid := C.vinix_linuxkpi_rwsem_fixture_value(sem, 0) == 256
		&& C.vinix_linuxkpi_rwsem_fixture_try(sem, true) == 0
	C.vinix_linuxkpi_rwsem_fixture_up(sem, 0)
	if C.vinix_linuxkpi_rwsem_fixture_try(sem, true) != 1 { return false }
	valid = valid && C.vinix_linuxkpi_rwsem_fixture_value(sem, 0) == 1
		&& C.vinix_linuxkpi_rwsem_fixture_try(sem, false) == 0
		&& C.vinix_linuxkpi_rwsem_fixture_try(sem, true) == 0
	C.vinix_linuxkpi_rwsem_fixture_downgrade(sem)
	valid = valid && C.vinix_linuxkpi_rwsem_fixture_value(sem, 0) == 256
		&& (C.vinix_linuxkpi_rwsem_fixture_value(sem, 1) & 1) != 0
	C.vinix_linuxkpi_rwsem_fixture_up(sem, 0)
	return rwsem_test_empty(sem) && valid
}
fn rwsem_test_atomic_context() bool {
	sem := unsafe { &rwsem_test_ledger.atomic_sem }
	mut owner := proc.current_thread()
	gate := owner.linuxkpi_alloc_fail_after
	owner.linuxkpi_alloc_fail_after = 0
	ints := cpu.interrupt_toggle(false)
	index := cpulocal.current().cpu_number
	depth := preempt_depth[index]
	mut valid := ints && !may_sleep() && rwsem_test_atomic(sem)
		&& !cpu.interrupt_state() && preempt_depth[index] == depth
	cpu.interrupt_toggle(ints)
	preempt_disable()
	valid = valid && !may_sleep() && rwsem_test_atomic(sem) && cpu.interrupt_state()
		&& preempt_depth[index] == depth + 1
	preempt_enable()
	valid = valid && owner.linuxkpi_alloc_fail_after == 0 && may_sleep()
	owner.linuxkpi_alloc_fail_after = gate
	return valid
}
fn rwsem_test_irq(_work &C.irq_work) {
	ints := cpu.interrupt_toggle(false)
	local := cpulocal.current()
	owner := proc.current_thread()
	depth := preempt_depth[local.cpu_number]
	mut valid := !ints && local.cpu_number == 1 && local.maskable_irq_depth != 0
		&& depth != 0 && voidptr(owner) == rwsem_test_ledger.owners[0] && !may_sleep()
		&& rwsem_test_atomic(unsafe { &rwsem_test_ledger.atomic_sem })
	cpu.interrupt_toggle(true)
	valid = valid && !may_sleep() && rwsem_test_atomic(unsafe { &rwsem_test_ledger.atomic_sem })
	entry := cpu.interrupt_toggle(false)
	valid = valid && entry && !cpu.interrupt_state() && preempt_depth[1] == depth
		&& local.maskable_irq_depth != 0 && voidptr(proc.current_thread()) == voidptr(owner)
		&& owner.linuxkpi_alloc_fail_after == 0
	if !valid { rwsem_test_fail(1024) }
	katomic.store(mut &rwsem_test_ledger.irq_done, true)
}
fn rwsem_test_run_irq() bool {
	katomic.store(mut &rwsem_test_ledger.irq_ready, false)
	katomic.store(mut &rwsem_test_ledger.irq_done, false)
	if C.vinix_linuxkpi_irqwork_fixture_init(unsafe { &rwsem_test_ledger.irq }, rwsem_test_irq, 0) != 0 { return false }
	rwsem_test_start(0, 7, 0)
	defer {
		if rwsem_test_ledger.irq_queued {
			C.vinix_linuxkpi_irqwork_fixture_sync(unsafe { &rwsem_test_ledger.irq })
			rwsem_test_ledger.irq_queued = false
		}
		katomic.store(mut &rwsem_test_ledger.irq_done, true)
		if !rwsem_test_wait(&rwsem_test_ledger.done[0]) { lib.kpanic(unsafe { nil }, c'linuxkpi: rwsem IRQ actor cleanup deadline') }
	}
	if !rwsem_test_wait(&rwsem_test_ledger.irq_ready) { return false }
	rwsem_test_ledger.irq_queued = C.vinix_linuxkpi_irqwork_fixture_queue(unsafe { &rwsem_test_ledger.irq }, 1)
	return rwsem_test_ledger.irq_queued && rwsem_test_wait(&rwsem_test_ledger.irq_done)
		&& rwsem_test_wait(&rwsem_test_ledger.done[0])
}

fn rwsem_test_controller_up() {
	mode := rwsem_test_ledger.controller_hold
	if mode != 0 {
		rwsem_test_ledger.controller_hold = 0
		C.vinix_linuxkpi_rwsem_fixture_up(unsafe { &rwsem_test_ledger.sem }, mode - 1)
	}
}
fn rwsem_test_fairness() bool {
	sem := unsafe { &rwsem_test_ledger.sem }
	if C.vinix_linuxkpi_rwsem_fixture_read(sem, 0) != 0 { return false }
	rwsem_test_ledger.controller_hold = 1
	rwsem_test_start(0, 2, 0)
	if !rwsem_test_parked(0, 2, 1) { return false }
	rwsem_test_start(1, 1, 0)
	if !rwsem_test_parked(1, 2, 2) { return false }
	rwsem_test_start(2, 1, 0)
	if !rwsem_test_parked(2, 2, 3) || C.vinix_linuxkpi_rwsem_fixture_try(sem, false) != 0 { return false }
	rwsem_test_controller_up()
	if !rwsem_test_wait(&rwsem_test_ledger.acquired[0]) || katomic.load(&rwsem_test_ledger.acquired[1])
		|| katomic.load(&rwsem_test_ledger.acquired[2]) || C.vinix_linuxkpi_rwsem_fixture_value(sem, 2) != 2 { return false }
	if !rwsem_test_release(0) || !rwsem_test_wait(&rwsem_test_ledger.acquired[1])
		|| !rwsem_test_wait(&rwsem_test_ledger.acquired[2]) || katomic.load(&rwsem_test_ledger.readers) != 2
		|| C.vinix_linuxkpi_rwsem_fixture_try(sem, true) != 0 { return false }
	return rwsem_test_release(1) && rwsem_test_release(2) && rwsem_test_empty(sem)
}
fn rwsem_test_batch_downgrade() bool {
	sem := unsafe { &rwsem_test_ledger.sem }
	if C.vinix_linuxkpi_rwsem_fixture_write(sem, false) != 0 { return false }
	rwsem_test_ledger.controller_hold = 2
	rwsem_test_start(0, 1, 0)
	if !rwsem_test_parked(0, 2, 1) { return false }
	rwsem_test_start(2, 2, 0)
	if !rwsem_test_parked(2, 2, 2) { return false }
	rwsem_test_start(1, 1, 0)
	if !rwsem_test_parked(1, 2, 3) { return false }
	C.vinix_linuxkpi_rwsem_fixture_downgrade(sem)
	rwsem_test_ledger.controller_hold = 1
	if !rwsem_test_wait(&rwsem_test_ledger.acquired[0]) || !rwsem_test_wait(&rwsem_test_ledger.acquired[1])
		|| katomic.load(&rwsem_test_ledger.acquired[2]) || katomic.load(&rwsem_test_ledger.readers) != 2
		|| C.vinix_linuxkpi_rwsem_fixture_value(sem, 0) != 770
		|| C.vinix_linuxkpi_rwsem_fixture_value(sem, 2) != 1 { return false }
	rwsem_test_controller_up()
	if !rwsem_test_release(0) || katomic.load(&rwsem_test_ledger.acquired[2])
		|| !rwsem_test_release(1) || !rwsem_test_wait(&rwsem_test_ledger.acquired[2]) { return false }
	return rwsem_test_release(2) && rwsem_test_empty(sem)
}
fn rwsem_test_signal(command u32, mode u32) bool {
	sem := unsafe { &rwsem_test_ledger.sem }
	if C.vinix_linuxkpi_rwsem_fixture_write(sem, false) != 0 { return false }
	rwsem_test_ledger.controller_hold = 2
	rwsem_test_start(0, command, mode)
	state := if mode == 1 && command == 3 { u32(1) } else { u32(258) }
	if !rwsem_test_parked(0, state, 1) { return false }
	test_task_signal(rwsem_test_ledger.owners[0], u64(1) << 14)
	if state == 258 {
		C.vinix_linuxkpi_migration_fixture_sleep(2)
		if katomic.load(&rwsem_test_ledger.done[0]) || !rwsem_test_parked(0, state, 1) { return false }
		test_task_signal(rwsem_test_ledger.owners[0], u64(1) << 8)
	}
	if !rwsem_test_wait(&rwsem_test_ledger.done[0]) || rwsem_test_ledger.results[0] != -4
		|| C.vinix_linuxkpi_rwsem_fixture_value(sem, 2) != 0
		|| C.vinix_linuxkpi_rwsem_fixture_value(sem, 0) != 1 { return false }
	rwsem_test_controller_up()
	return rwsem_test_empty(sem)
}
fn rwsem_test_races() bool {
	sem := unsafe { &rwsem_test_ledger.sem }
	for round in 0 .. 48 {
		if C.vinix_linuxkpi_rwsem_fixture_write(sem, false) != 0 { return false }
		rwsem_test_ledger.controller_hold = 2
		writer := round % 3 == 0
		mode := if writer || round % 4 == 1 { u32(1) } else { u32(2) }
		state := if !writer && mode == 1 { u32(1) } else { u32(258) }
		rwsem_test_start(0, if writer { u32(4) } else { u32(3) }, mode)
		if !rwsem_test_parked(0, state, 1) { return false }
		if round % 2 == 0 { test_task_signal(rwsem_test_ledger.owners[0], u64(1) << 8) }
		rwsem_test_controller_up()
		if round % 2 != 0 { test_task_signal(rwsem_test_ledger.owners[0], u64(1) << 8) }
		if !rwsem_test_wait(&rwsem_test_ledger.done[0]) { return false }
		// Grant-first may let the actor finish before this producer publishes
		// its signal. Stop that producer before starting the next command.
		test_task_signal(rwsem_test_ledger.owners[0], 0)
		result := rwsem_test_ledger.results[0]
		if (result != 0 && result != -4) || (round % 2 != 0 && result != 0) || !rwsem_test_empty(sem) { return false }
	}
	return true
}
fn rwsem_test_uninterruptible(writer bool) bool {
	sem := unsafe { &rwsem_test_ledger.sem }
	if C.vinix_linuxkpi_rwsem_fixture_write(sem, false) != 0 { return false }
	rwsem_test_ledger.controller_hold = 2
	rwsem_test_start(0, if writer { u32(4) } else { u32(3) }, 0)
	if !rwsem_test_parked(0, 2, 1) { return false }
	test_task_signal(rwsem_test_ledger.owners[0], u64(1) << 8)
	C.vinix_linuxkpi_migration_fixture_sleep(2)
	if katomic.load(&rwsem_test_ledger.done[0]) || !rwsem_test_parked(0, 2, 1) { return false }
	rwsem_test_controller_up()
	if !rwsem_test_wait(&rwsem_test_ledger.done[0]) || rwsem_test_ledger.results[0] != 0 { return false }
	return rwsem_test_empty(sem)
}
fn rwsem_test_cancel_head() bool {
	sem := unsafe { &rwsem_test_ledger.sem }
	if C.vinix_linuxkpi_rwsem_fixture_read(sem, 0) != 0 { return false }
	rwsem_test_ledger.controller_hold = 1
	rwsem_test_start(0, 4, 1)
	if !rwsem_test_parked(0, 258, 1) { return false }
	rwsem_test_start(1, 1, 0)
	if !rwsem_test_parked(1, 2, 2) { return false }
	test_task_signal(rwsem_test_ledger.owners[0], u64(1) << 8)
	if !rwsem_test_wait(&rwsem_test_ledger.done[0]) || rwsem_test_ledger.results[0] != -4
		|| !rwsem_test_wait(&rwsem_test_ledger.acquired[1])
		|| C.vinix_linuxkpi_rwsem_fixture_value(sem, 0) != 512
		|| C.vinix_linuxkpi_rwsem_fixture_value(sem, 2) != 0 { return false }
	rwsem_test_controller_up()
	return rwsem_test_release(1) && rwsem_test_empty(sem)
}
fn rwsem_test_transfer() bool {
	sem := unsafe { &rwsem_test_ledger.sem }
	rwsem_test_start(0, 5, 3)
	if !rwsem_test_wait(&rwsem_test_ledger.done[0]) || !katomic.load(&rwsem_test_ledger.transfer_hold)
		|| C.vinix_linuxkpi_rwsem_fixture_try(sem, true) != 0 { return false }
	C.vinix_linuxkpi_rwsem_fixture_up(sem, 2)
	katomic.store(mut &rwsem_test_ledger.transfer_hold, false)
	return rwsem_test_empty(sem)
}
fn rwsem_test_self_free() bool {
	for _ in 0 .. 12 {
		rwsem_test_ledger.dynamic = C.vinix_linuxkpi_rwsem_fixture_alloc()
		if rwsem_test_ledger.dynamic == unsafe { nil } { return false }
		katomic.store(mut &rwsem_test_ledger.dynamic_freed, false)
		if C.vinix_linuxkpi_rwsem_fixture_write(rwsem_test_ledger.dynamic, false) != 0 { return false }
		rwsem_test_ledger.dynamic_hold = true
		rwsem_test_start(0, 6, 0)
		if !rwsem_test_parked(0, 2, 1) { return false }
		rwsem_test_ledger.dynamic_hold = false
		// A granted actor may unlock/free before this releaser returns. Only
		// boot-ledger flags, never the detached sem, may be read after this call.
		C.vinix_linuxkpi_rwsem_fixture_up(rwsem_test_ledger.dynamic, 1)
		if !rwsem_test_wait(&rwsem_test_ledger.done[0]) || !katomic.load(&rwsem_test_ledger.dynamic_freed) { return false }
		rwsem_test_ledger.dynamic = unsafe { nil }
		rwsem_test_ledger.freed_objects++
	}
	return true
}

fn rwsem_test_lifecycle(fail_after int, fail_stage int) bool {
	ints := cpu.interrupt_toggle(false)
	mut controller := proc.current_thread()
	affinity := katomic.load(&controller.affinity_mask)
	numa := katomic.load(&controller.numa_node)
	cpu.interrupt_toggle(ints)
	mut owners := unsafe { [3]&proc.Thread{} }
	mut created := 0
	mut records_live := false
	defer {
		sched.test_kernel_thread_failure(0)
		if records_live {
			rwsem_test_controller_up()
			if rwsem_test_ledger.dynamic_hold {
				rwsem_test_ledger.dynamic_hold = false
				C.vinix_linuxkpi_rwsem_fixture_up(rwsem_test_ledger.dynamic, 1)
			}
			for i in 0 .. 3 { C.vinix_linuxkpi_rwsem_fixture_complete(unsafe { &rwsem_test_ledger.gates[i] }) }
			if rwsem_test_ledger.irq_queued {
				C.vinix_linuxkpi_irqwork_fixture_sync(unsafe { &rwsem_test_ledger.irq })
			}
			katomic.store(mut &rwsem_test_ledger.irq_done, true)
			katomic.store(mut &rwsem_test_ledger.quit, true)
			for i in 0 .. created { test_task_signal(owners[i], 0); irq_test_join(owners[i]) }
			if rwsem_test_ledger.transfer_hold {
				C.vinix_linuxkpi_rwsem_fixture_up(unsafe { &rwsem_test_ledger.sem }, 2)
				rwsem_test_ledger.transfer_hold = false
			}
			if rwsem_test_ledger.dynamic != unsafe { nil } && !katomic.load(&rwsem_test_ledger.dynamic_freed) {
				C.vinix_linuxkpi_rwsem_fixture_free(rwsem_test_ledger.dynamic)
			}
			rwsem_test_ledger.dynamic = unsafe { nil }
		}
		selftest_free_baseline()
		restore := cpu.interrupt_toggle(false)
		katomic.store(mut &controller.numa_node, numa)
		katomic.store(mut &controller.affinity_mask, affinity)
		cpu.interrupt_toggle(restore)
	}
	if !ints || worker_bind(0) != 0 { return false }
	rwsem_test_ledger = RwsemTestLedger{}
	C.vinix_linuxkpi_rwsem_fixture_init(unsafe { &rwsem_test_ledger.sem })
	C.vinix_linuxkpi_rwsem_fixture_init(unsafe { &rwsem_test_ledger.atomic_sem })
	for i in 0 .. 3 { C.vinix_linuxkpi_rwsem_fixture_init_completion(unsafe { &rwsem_test_ledger.gates[i] }) }
	records_live = true
	for i in 0 .. 3 {
		if i == fail_after { sched.test_kernel_thread_failure(fail_stage) }
		mut actor := sched.try_new_kernel_thread(voidptr(rwsem_test_actor), voidptr(i)) or {
			rwsem_test_ledger.constructor_failed = i
			rwsem_test_ledger.constructor_failure_consumed = controller.kernel_thread_fail_stage == 0
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
		rwsem_test_ledger.owners[i] = actor
		created++
	}
	for i in 0 .. 3 { if !rwsem_test_wait(&rwsem_test_ledger.ready[i]) { return false } }
	static_sem := C.vinix_linuxkpi_rwsem_fixture_static()
	if !rwsem_test_empty(static_sem) || !rwsem_test_atomic(static_sem) || !rwsem_test_atomic_context()
		|| !rwsem_test_run_irq() || !rwsem_test_fairness() || !rwsem_test_batch_downgrade()
		|| !rwsem_test_signal(3, 1) || !rwsem_test_signal(3, 2) || !rwsem_test_signal(4, 1)
		|| !rwsem_test_uninterruptible(false) || !rwsem_test_uninterruptible(true) || !rwsem_test_cancel_head()
		|| !rwsem_test_races() || !rwsem_test_transfer() || !rwsem_test_self_free() { return false }
	return rwsem_test_empty(unsafe { &rwsem_test_ledger.sem }) && rwsem_test_ledger.freed_objects == 12
		&& katomic.load(&rwsem_test_ledger.failures) == 0
}
fn rwsem_native_selftest() bool {
	if cpu_locals.len < 4 || cpu_locals.len > 64 { return false }
	for fail_after in 0 .. 2 {
		for stage in 1 .. 5 {
			before := selftest_free_baseline()
			mut heap_before := CPUFeatureHeapSnapshot{}
			mut heap_after := CPUFeatureHeapSnapshot{}
			if !cpu_feature_test_heap(unsafe { &heap_before }) || rwsem_test_lifecycle(fail_after, stage)
				|| rwsem_test_ledger.constructor_failed != fail_after || !rwsem_test_ledger.constructor_failure_consumed
				|| selftest_free_baseline() != before || !cpu_feature_test_heap(unsafe { &heap_after })
				|| heap_before.count != heap_after.count { return false }
			for i in 0 .. heap_before.count {
				if heap_before.sizes[i] != heap_after.sizes[i] || heap_before.live[i] != heap_after.live[i] { return false }
			}
		}
	}
	C.kprintf(c'linuxkpi: rwsem constructor rollback passed all four failure stages before and after actor publication; pages and heap recovered\n')
	for round in 0 .. 3 {
		before := selftest_free_baseline()
		if !rwsem_test_lifecycle(-1, 0) { return false }
		C.kprintf(c'linuxkpi: rwsem lifecycle warmup %d free-byte baseline=%llu after=%llu\n', round + 1, before, selftest_free_baseline())
	}
	mut before := CPUFeatureHeapSnapshot{}
	mut after := CPUFeatureHeapSnapshot{}
	free_before := selftest_free_baseline()
	if !cpu_feature_test_heap(unsafe { &before }) || !rwsem_test_lifecycle(-1, 0) { return false }
	free_after := selftest_free_baseline()
	if !cpu_feature_test_heap(unsafe { &after }) { return false }
	mut equal := before.count == after.count
	for i in 0 .. before.count {
		if before.sizes[i] != after.sizes[i] || before.live[i] != after.live[i] {
			equal = false
			C.kprintf(c'linuxkpi: rwsem heap class %d size_before=%llu size_after=%llu live_before=%llu live_after=%llu\n', i, before.sizes[i], after.sizes[i], before.live[i], after.live[i])
		}
	}
	C.kprintf(c'linuxkpi: rwsem fourth lifecycle free-byte baseline=%llu after=%llu heap_equal=%u\n', free_before, free_after, u32(equal))
	return free_before == free_after && equal && katomic.load(&rwsem_test_ledger.failures) == 0
}
