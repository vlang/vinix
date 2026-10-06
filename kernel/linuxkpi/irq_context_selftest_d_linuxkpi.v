// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
@[manualfree]
module linuxkpi

import event
import event.eventstruct
import katomic
import lib
import memory
import proc
import sched
import x86.cpu
import x86.cpu.local as cpulocal
import x86.hpet as irq_hpet_clock
import x86.idt

#include "x86_irq_v_contract.h"
#include "linuxkpi_irq_probe_v_contract.h"
#include "linuxkpi_pagefault_v_contract.h"
#include "linuxkpi_scalar_uaccess_v_contract.h"

fn C.vinix_linuxkpi_irq_probe(u32) i32
fn C.vinix_linuxkpi_test_thread_reap_ready(voidptr) bool
fn C.faulthandler_disabled() bool

const irq_test_cpus = 4
const irq_test_rounds = u64(8)
const irq_test_timeout_ns = u64(30000000000)

// This fixed boot-lifetime ledger is never a borrowed controller stack.
// Actors receive a numeric CPU/role token, and handlers use their real CPU.
// Resetting it is permitted only after every previous actor is off-stack and
// reaped. Vectors and their immutable assembly leaves are allocated once.
struct IrqTestCpu {
mut:
	primary_wake    eventstruct.Event
	observer_wake   eventstruct.Event
	rejected_wait   eventstruct.Event
	primary_owner  voidptr
	primary_ready  bool
	observer_ready bool
	begin          bool
	observer_live  bool
	quit           bool
	in_probe       bool
	probe_done     bool
	primary_park   bool
	observer_park  bool
	wake_now       bool
	primary_woke   bool
	observer_woke  bool
	observer_runs  u64
	outer_hits     u64
	inner_hits     u64
	post_iret_ack  u64
	failures       u64
}

struct IrqTestSnapshot {
mut:
	free_bytes u64
	count      int
	sizes      [64]u64
	live       [64]u64
}

__global (
	irq_test_ledger       [irq_test_cpus]IrqTestCpu
	irq_test_outer_vector u32
	irq_test_inner_vector u32
	irq_test_vectors_set  bool
	irq_test_user_printed u32
)

fn irq_test_require(ok bool, message &char) bool {
	if !ok { C.kprintf(c'linuxkpi: maskable IRQ self-test failed: %s\n', message) }
	return ok
}

// More than one role may report a failure. A CAS loop preserves every bit
// without printing, allocating or waiting from an actual interrupt handler.
fn irq_test_fail(index u32, bit u64) {
	mut state := unsafe { &irq_test_ledger[index] }
	for {
		old := katomic.load(&state.failures)
		if katomic.cas(mut &state.failures, old, old | bit) { return }
	}
}

fn irq_test_task_zero(index u32) bool {
	ints := cpu.interrupt_toggle(false)
	local := cpulocal.current()
	ok := ints && local.cpu_number == u64(index) && local.maskable_irq_depth == 0
		&& proc.current_thread() != unsafe { nil }
	cpu.interrupt_toggle(ints)
	return ok && may_sleep() && event.may_wait() && !C.faulthandler_disabled()
}

fn irq_test_handler_queries(expected u32) bool {
	// Deliberately observe with IF enabled. IF alone must not permit sleeping
	// or waiting while the actual THUNK entry remains on this CPU's stack.
	return cpu.interrupt_state() && cpulocal.maskable_irq_depth() == expected
		&& !may_sleep() && !event.may_wait() && C.faulthandler_disabled()
}

fn irq_test_inner(vector u32, frame &cpulocal.GPRState) {
	local := cpulocal.current()
	index := u32(local.cpu_number)
	if index >= irq_test_cpus { panic('linuxkpi: private IRQ probe on an unexpected CPU') }
	mut state := unsafe { &irq_test_ledger[index] }
	if vector != irq_test_inner_vector || cpu.interrupt_state() || frame.cs & 3 != 0
		|| local.maskable_irq_depth != 2
		|| proc.current_thread() != state.primary_owner || !katomic.load(&state.in_probe) {
		irq_test_fail(index, 1)
	}
	state.inner_hits++
	cpu.interrupt_toggle(true)
	if !irq_test_handler_queries(2) { irq_test_fail(index, 2) }
	// Return with IF enabled to exercise the thunk's unconditional CLI before
	// its matching exit. There is no APIC EOI for a software INT.
}

fn irq_test_outer(vector u32, frame &cpulocal.GPRState) {
	local := cpulocal.current()
	index := u32(local.cpu_number)
	if index >= irq_test_cpus { panic('linuxkpi: private IRQ probe on an unexpected CPU') }
	mut state := unsafe { &irq_test_ledger[index] }
	if vector != irq_test_outer_vector || cpu.interrupt_state() || frame.cs & 3 != 0
		|| frame.rflags & (u64(1) << 9) != 0
		|| local.maskable_irq_depth != 1 || proc.current_thread() != state.primary_owner
		|| !katomic.load(&state.in_probe) {
		irq_test_fail(index, 4)
	}
	state.outer_hits++
	cpu.interrupt_toggle(true)
	if !irq_test_handler_queries(1) { irq_test_fail(index, 8) }
	// A pending event prevents a broken guard from actually sleeping. A real
	// blocking await must reject before consuming it or attaching listeners;
	// merely checking may_wait() would not validate that ordering.
	if _ := event.await_one(mut state.rejected_wait, true) { irq_test_fail(index, 524288) }
	check_wait_ints := cpu.interrupt_toggle(false)
	owner := unsafe { &proc.Thread(state.primary_owner) }
	if !check_wait_ints || state.rejected_wait.pending != 1
		|| state.rejected_wait.listeners_i != 0 || state.rejected_wait.generation != 0
		|| state.rejected_wait.overflow != unsafe { nil }
		|| !katomic.load(&owner.is_in_queue)
		|| cpulocal.current().maskable_irq_depth != 1 {
		irq_test_fail(index, 524288)
	}
	cpu.interrupt_toggle(check_wait_ints)
	if C.vinix_linuxkpi_irq_probe(irq_test_inner_vector) != 0
		|| !irq_test_handler_queries(1) { irq_test_fail(index, 16) }

	// The ordinary observer is runnable on this CPU. Deliver a real scheduler
	// self-IPI while the outer maskable frame is live and IF is enabled. Its
	// actual ISR must defer, rather than resume the ready observer under us.
	ints := cpu.interrupt_toggle(false)
	before := cpulocal.current().maskable_irq_scheduler_deferrals
	runs := katomic.load(&state.observer_runs)
	cpu.interrupt_toggle(ints)
	if !sched.wake_cpu(index) { irq_test_fail(index, 32) }
	started := irq_hpet_clock.nanoseconds()
	for {
		check_ints := cpu.interrupt_toggle(false)
		now_local := cpulocal.current()
		deferred := now_local.maskable_irq_scheduler_deferrals > before
		valid := check_ints && now_local.maskable_irq_depth == 1
			&& proc.current_thread() == state.primary_owner
			&& katomic.load(&state.observer_runs) == runs
		cpu.interrupt_toggle(check_ints)
		if !valid { irq_test_fail(index, 64); break }
		if deferred { break }
		if irq_hpet_clock.nanoseconds() - started >= irq_test_timeout_ns {
			irq_test_fail(index, 128)
			break
		}
	}
	if !irq_test_handler_queries(1) { irq_test_fail(index, 256) }
	// As in the nested handler, leave IF enabled and let the actual exit pair
	// restore the interrupted primary's IF=0 through IRET.
}

fn irq_test_actor_wait(index u32, observer bool, begin bool) bool {
	mut state := unsafe { &irq_test_ledger[index] }
	for {
		if katomic.load(&state.quit) { return false }
		ready := if begin { katomic.load(&state.begin) } else { katomic.load(&state.wake_now) }
		if ready { return true }
		if observer { event.await_one(mut state.observer_wake, true) }
		else { event.await_one(mut state.primary_wake, true) }
	}
	return false
}

fn irq_test_primary(index u32) {
	mut state := unsafe { &irq_test_ledger[index] }
	started := irq_hpet_clock.nanoseconds()
	for !katomic.load(&state.observer_live) && !katomic.load(&state.quit) {
		if irq_hpet_clock.nanoseconds() - started >= irq_test_timeout_ns { irq_test_fail(index, 512); return }
		sched.reschedule()
	}
	for round := u64(0); round < irq_test_rounds && !katomic.load(&state.quit); round++ {
		ints := cpu.interrupt_toggle(false)
		local := cpulocal.current()
		if !ints || local.maskable_irq_depth != 0 || local.cpu_number != u64(index) {
			irq_test_fail(index, 1024)
		}
		runs := katomic.load(&state.observer_runs)
		katomic.store(mut &state.in_probe, true)
		result := C.vinix_linuxkpi_irq_probe(irq_test_outer_vector)
		// This acknowledgement executes only after the real outer IRET. The
		// saved IF was zero, so a legal post-IRET switch cannot race this check.
		if result != 0 || cpu.interrupt_state() || cpulocal.current().maskable_irq_depth != 0
			|| katomic.load(&state.observer_runs) != runs
			|| state.outer_hits != round + 1 || state.inner_hits != round + 1 {
			irq_test_fail(index, 2048)
		}
		katomic.store(mut &state.post_iret_ack, round + 1)
		katomic.store(mut &state.in_probe, false)
		cpu.interrupt_toggle(ints)
		// Once the outer frame has gone, an ordinary scheduler handoff is
		// permitted and must not transfer this CPU's IRQ depth to either task.
		progress_started := irq_hpet_clock.nanoseconds()
		for katomic.load(&state.observer_runs) == runs && !katomic.load(&state.quit) {
			sched.reschedule()
			if !irq_test_task_zero(index) { irq_test_fail(index, 4096) }
			if irq_hpet_clock.nanoseconds() - progress_started >= irq_test_timeout_ns {
				irq_test_fail(index, 8192)
				break
			}
		}
		if katomic.load(&state.failures) != 0 { break }
	}
	if katomic.load(&state.failures) == 0 && !katomic.load(&state.quit) {
		if which := event.await_one(mut state.rejected_wait, true) {
			if which != 0 || state.rejected_wait.pending != 0 || !irq_test_task_zero(index) {
				irq_test_fail(index, 1048576)
			}
		} else { irq_test_fail(index, 1048576) }
	}
	katomic.store(mut &state.probe_done, true)
	katomic.store(mut &state.primary_park, true)
	if irq_test_actor_wait(index, false, false) {
		if !irq_test_task_zero(index) { irq_test_fail(index, 16384) }
		katomic.store(mut &state.primary_woke, true)
	}
}

fn irq_test_observer(index u32) {
	mut state := unsafe { &irq_test_ledger[index] }
	katomic.store(mut &state.observer_live, true)
	for !katomic.load(&state.probe_done) && !katomic.load(&state.quit) {
		ints := cpu.interrupt_toggle(false)
		if katomic.load(&state.in_probe) || cpulocal.current().maskable_irq_depth != 0
			|| cpulocal.current().cpu_number != u64(index) || !ints {
			irq_test_fail(index, 32768)
		}
		katomic.inc(mut &state.observer_runs)
		cpu.interrupt_toggle(ints)
		sched.reschedule()
		if !irq_test_task_zero(index) { irq_test_fail(index, 65536) }
	}
	katomic.store(mut &state.observer_park, true)
	if irq_test_actor_wait(index, true, false) {
		if !irq_test_task_zero(index) { irq_test_fail(index, 131072) }
		katomic.store(mut &state.observer_woke, true)
	}
}

fn irq_test_actor(argument voidptr) {
	token := u32(usize(argument) - 1)
	index := token / 2
	observer := token & 1 != 0
	mut state := unsafe { &irq_test_ledger[index] }
	if worker_bind(index) != 0 || !irq_test_task_zero(index) { irq_test_fail(index, 262144) }
	if observer { katomic.store(mut &state.observer_ready, true) }
	else { katomic.store(mut &state.primary_ready, true) }
	if irq_test_actor_wait(index, observer, true) && katomic.load(&state.failures) == 0 {
		if observer { irq_test_observer(index) } else { irq_test_primary(index) }
	}
	for !katomic.load(&state.quit) {
		if observer { event.await_one(mut state.observer_wake, true) }
		else { event.await_one(mut state.primary_wake, true) }
	}
	// No callback, controller frame or borrowed object is accessed after exit.
	event.pthread_exit(unsafe { nil })
}

fn irq_test_wait(index u32, stage int, primary &proc.Thread, observer &proc.Thread) bool {
	state := unsafe { &irq_test_ledger[index] }
	started := irq_hpet_clock.nanoseconds()
	for {
		if katomic.load(&state.failures) != 0 {
			C.kprintf(c'linuxkpi: maskable IRQ CPU %u stage %d failure bits=%llu\n',
				index, stage, katomic.load(&state.failures))
			return false
		}
		ready := match stage {
			0 { katomic.load(&state.primary_ready) && katomic.load(&state.observer_ready) }
			1 { katomic.load(&state.primary_park) && katomic.load(&state.observer_park)
				&& !katomic.load(&primary.is_in_queue) && katomic.load(&primary.running_on) == u64(-1)
				&& !katomic.load(&observer.is_in_queue) && katomic.load(&observer.running_on) == u64(-1) }
			else { katomic.load(&state.primary_woke) && katomic.load(&state.observer_woke) }
		}
		if ready { return katomic.load(&state.failures) == 0 }
		if irq_hpet_clock.nanoseconds() - started >= irq_test_timeout_ns {
			return irq_test_require(false, c'actual actor stage/sleep deadline')
		}
		sched.reschedule()
	}
	return false
}

fn irq_test_join(actor &proc.Thread) bool {
	started := irq_hpet_clock.nanoseconds()
	for !katomic.load(&actor.pthread_exited) {
		if irq_hpet_clock.nanoseconds() - started >= irq_test_timeout_ns {
			lib.kpanic(unsafe { nil }, c'linuxkpi: IRQ actor stop/exit deadline')
		}
		sched.reschedule()
	}
	mut owner := unsafe { actor }
	if !katomic.cas(mut &owner.pthread_joinable, u32(1), u32(0)) {
		lib.kpanic(unsafe { nil }, c'linuxkpi: IRQ actor join owner lost')
	}
	event.pthread_wait(actor)
	// The second pin retains this observer after pthread_wait drops the join
	// pin. Do not reset ledger entries until every actor has left its stack.
	for !C.vinix_linuxkpi_test_thread_reap_ready(actor) {
		if irq_hpet_clock.nanoseconds() - started >= irq_test_timeout_ns {
			lib.kpanic(unsafe { nil }, c'linuxkpi: IRQ actor off-stack deadline')
		}
		sched.reschedule()
	}
	proc.unpin_thread(actor)
	// The actor pointer is dead after this final pin; never inspect it again.
	sched.reap_deferred()
	return true
}

fn irq_test_lifecycle() bool {
	mut owners := unsafe { [irq_test_cpus * 2]&proc.Thread{} }
	mut created := 0
	mut controller := proc.current_thread()
	ints := cpu.interrupt_toggle(false)
	original_affinity := katomic.load(&controller.affinity_mask)
	original_node := katomic.load(&controller.numa_node)
	cpu.interrupt_toggle(ints)
	defer {
		// Publish stop to all actors before joining any one of them. Every
		// failure path retains all created actors through their actual exit.
		for i in 0 .. irq_test_cpus {
			mut state := unsafe { &irq_test_ledger[i] }
			katomic.store(mut &state.quit, true)
			event.trigger(mut state.primary_wake, false)
			event.trigger(mut state.observer_wake, false)
		}
		for i in 0 .. created { irq_test_join(owners[i]) }
		started := irq_hpet_clock.nanoseconds()
		for !C.vinix_linuxkpi_test_reap_quiescent() {
			if irq_hpet_clock.nanoseconds() - started >= irq_test_timeout_ns {
				lib.kpanic(unsafe { nil }, c'linuxkpi: IRQ actor final reclamation deadline')
			}
			sched.reap_deferred()
			sched.reschedule()
		}
		for i in 0 .. irq_test_cpus { irq_test_ledger[i].primary_owner = unsafe { nil } }
		restore_ints := cpu.interrupt_toggle(false)
		katomic.store(mut &controller.numa_node, original_node)
		katomic.store(mut &controller.affinity_mask, original_affinity)
		cpu.interrupt_toggle(restore_ints)
	}
	for i in 0 .. irq_test_cpus {
		irq_test_ledger[i] = IrqTestCpu{}
		irq_test_ledger[i].rejected_wait.pending = 1
	}
	for i in 0 .. irq_test_cpus * 2 {
		mut actor := sched.try_new_kernel_thread(voidptr(irq_test_actor), voidptr(usize(i + 1))) or {
			return irq_test_require(false, c'IRQ actor creation')
		}
		proc.pin_thread(actor)
		proc.pin_thread(actor)
		actor.pthread_joinable = 1
		if i & 1 == 0 { irq_test_ledger[i / 2].primary_owner = actor }
		if !sched.enqueue_thread(actor, false) {
			proc.unpin_thread(actor)
			proc.unpin_thread(actor)
			sched.discard_unstarted_thread(actor)
			return irq_test_require(false, c'IRQ actor enqueue')
		}
		owners[i] = actor
		created++
	}
	for i in 0 .. irq_test_cpus {
		if !irq_test_wait(u32(i), 0, owners[i * 2], owners[i * 2 + 1]) { return false }
	}
	for i in 0 .. irq_test_cpus {
		mut state := unsafe { &irq_test_ledger[i] }
		katomic.store(mut &state.begin, true)
		event.trigger(mut state.primary_wake, false)
		event.trigger(mut state.observer_wake, false)
	}
	for i in 0 .. irq_test_cpus {
		if !irq_test_wait(u32(i), 1, owners[i * 2], owners[i * 2 + 1]) { return false }
	}
	for i in 0 .. irq_test_cpus {
		// Move the controller away from this target. Both target actors really
		// slept; require the actual CPU idle flag and balanced native depth
		// before an event wake makes them runnable again.
		if worker_bind(u32((i + 1) % irq_test_cpus)) != 0 { return false }
		started := irq_hpet_clock.nanoseconds()
		local := cpu_locals[i]
		for !(katomic.load(&local.is_idle) && katomic.load(&local.maskable_irq_depth) == 0
			&& katomic.load(&local.is_idle)) {
			if irq_hpet_clock.nanoseconds() - started >= irq_test_timeout_ns {
				return irq_test_require(false, c'actual idle CPU/depth-zero deadline')
			}
			sched.reschedule()
		}
		mut state := unsafe { &irq_test_ledger[i] }
		katomic.store(mut &state.wake_now, true)
		event.trigger(mut state.primary_wake, false)
		event.trigger(mut state.observer_wake, false)
		if !irq_test_wait(u32(i), 2, owners[i * 2], owners[i * 2 + 1]) { return false }
		if !irq_test_require(katomic.load(&state.post_iret_ack) == irq_test_rounds
			&& state.outer_hits == irq_test_rounds && state.inner_hits == irq_test_rounds
			&& katomic.load(&local.maskable_irq_peak_depth) >= 2,
			c'actual outer/nested entry counts and post-IRET acknowledgements') { return false }
	}
	return true
}

fn irq_test_snapshot(_snapshot &IrqTestSnapshot) bool {
	mut snapshot := unsafe { _snapshot }
	mut classes := memory.heap_classes() @[freed]
	defer { unsafe { classes.free() } }
	if classes.len > snapshot.live.len { return irq_test_require(false, c'heap snapshot capacity') }
	snapshot.count = classes.len
	for i, class in classes { snapshot.sizes[i] = class.size; snapshot.live[i] = class.live }
	return true
}

pub fn irq_context_native_selftest() bool {
	if !irq_test_require(cpu.interrupt_state() && cpulocal.maskable_irq_depth() == 0
		&& may_sleep() && event.may_wait() && cpu_locals.len >= irq_test_cpus,
		c'ordinary task context with four native fixture CPUs online') { return false }
	if !irq_test_vectors_set {
		irq_test_outer_vector = u32(idt.allocate_vector())
		irq_test_inner_vector = u32(idt.allocate_vector())
		interrupt_table[irq_test_outer_vector] = voidptr(irq_test_outer)
		interrupt_table[irq_test_inner_vector] = voidptr(irq_test_inner)
		irq_test_vectors_set = true
	}
	// Invalid vectors are rejected before dispatch; no exception is executed.
	if !irq_test_require(C.vinix_linuxkpi_irq_probe(0) == -22
		&& C.vinix_linuxkpi_irq_probe(31) == -22 && C.vinix_linuxkpi_irq_probe(240) == -22
		&& C.vinix_linuxkpi_irq_probe(u32(-1)) == -22, c'private probe vector bounds') { return false }
	for i in 0 .. 3 {
		before := selftest_free_baseline()
		if !irq_test_lifecycle() { return false }
		C.kprintf(c'linuxkpi: maskable IRQ complete-lifecycle warmup %d free-byte baseline=%llu after=%llu\n',
			i + 1, before, selftest_free_baseline())
	}
	mut before := IrqTestSnapshot{}
	mut after := IrqTestSnapshot{}
	before.free_bytes = selftest_free_baseline()
	if !irq_test_snapshot(unsafe { &before }) || !irq_test_lifecycle() { return false }
	after.free_bytes = selftest_free_baseline()
	if !irq_test_snapshot(unsafe { &after }) { return false }
	mut heap_equal := before.count == after.count
	for i in 0 .. before.count {
		if before.sizes[i] != after.sizes[i] || before.live[i] != after.live[i] {
			C.kprintf(c'linuxkpi: maskable IRQ heap class before=%llu after=%llu live before=%llu after=%llu\n',
				before.sizes[i], after.sizes[i], before.live[i], after.live[i])
			heap_equal = false
		}
	}
	C.kprintf(c'linuxkpi: maskable IRQ fourth lifecycle free-byte baseline=%llu after=%llu heap_equal=%d\n',
		before.free_bytes, after.free_bytes, int(heap_equal))
	if !irq_test_require(before.free_bytes == after.free_bytes && heap_equal,
		c'fourth complete lifecycle retains no pages or live heap objects') { return false }
	return true
}

// Called from the normal syscall return path, never from an IRQ handler.
// The counter was incremented by a real THUNK with its actual saved CS=3.
// Sampling saved IF, CPU, depth and entries together under CLI ties that
// evidence to a later ordinary task return without retaining a Thread.
@[export: 'vinix_linuxkpi_test_maskable_user_return']
fn irq_test_maskable_user_return() {
	ints := cpu.interrupt_toggle(false)
	local := cpulocal.current()
	index := local.cpu_number
	entries := local.maskable_irq_user_entries
	depth := local.maskable_irq_depth
	task := proc.current_thread()
	valid := index < u64(cpu_locals.len) && entries > 0 && depth == 0
		&& task != unsafe { nil } && voidptr(task.process) != voidptr(kernel_process)
	print_once := valid && katomic.cas(mut &irq_test_user_printed, u32(0), u32(1))
	cpu.interrupt_toggle(ints)
	if print_once {
		C.kprintf(c'linuxkpi: native maskable userspace interrupt and depth-zero task return passed\n')
	}
}
