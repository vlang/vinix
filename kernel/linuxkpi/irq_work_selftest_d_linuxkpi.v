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
import x86.hpet as irqwork_clock

#include "linuxkpi_irq_work_fixture_v_primitives.h"
#include "linuxkpi_irq_work_v_primitives.h"

struct C.irq_work {}
struct C.vinix_irqwork_fixture {}
fn C.vinix_linuxkpi_irqwork_fixture_bytes() u32
fn C.vinix_linuxkpi_irqwork_fixture_init(voidptr, fn (&C.irq_work), u32) i32
fn C.vinix_linuxkpi_irqwork_fixture_queue(voidptr, i32) bool
fn C.vinix_linuxkpi_irqwork_fixture_sync(voidptr)
fn C.vinix_linuxkpi_irqwork_fixture_pending(voidptr) bool
fn C.vinix_linuxkpi_irqwork_fixture_busy(voidptr) bool
fn C.vinix_linuxkpi_irqwork_fixture_defer(voidptr, voidptr)
fn C.vkiw_running_count(voidptr) u32
fn C.vkiw_sync_wait_count() u64

const irqwork_test_timeout_ns = u64(10000000000)
const irqwork_test_deferred_count = 9

struct IrqWorkTestNode {
mut:
	work C.vinix_irqwork_fixture
	rcu C.vinix_rcu_fixture_head
	mode u32
	remaining u32
	target u32
	magic u64
}
struct IrqWorkTestLedger {
mut:
	ready [2]bool
	quit bool
	command [2]u32
	done [2]bool
	started [2]bool
	parallel IrqWorkTestNode
	borrowed voidptr
	entered [4]u32
	release [4]bool
	calls u32
	deferred u32
	observed_tick u64
	failures u32
}
__global irqwork_test_ledger IrqWorkTestLedger

fn irq_work_test_fail(bit u32) {
	for {
		old := katomic.load(&irqwork_test_ledger.failures)
		if katomic.cas(mut &irqwork_test_ledger.failures, old, old | bit) { return }
	}
}
fn irq_work_test_wait(flag &bool) bool {
	started := irqwork_clock.nanoseconds()
	for !katomic.load(flag) {
		if katomic.load(&irqwork_test_ledger.failures) != 0
			|| irqwork_clock.nanoseconds() - started >= irqwork_test_timeout_ns { return false }
		sched.reschedule()
	}
	return katomic.load(&irqwork_test_ledger.failures) == 0
}
fn irq_work_test_wait_calls(target u32, cleanup bool) bool {
	started := irqwork_clock.nanoseconds()
	for katomic.load(&irqwork_test_ledger.calls) < target {
		if (!cleanup && katomic.load(&irqwork_test_ledger.failures) != 0)
			|| irqwork_clock.nanoseconds() - started >= irqwork_test_timeout_ns { return false }
		sched.reschedule()
	}
	return true
}
fn irq_work_test_task(target u32) bool {
	ints := cpu.interrupt_toggle(false)
	local := cpulocal.current()
	ok := ints && local.cpu_number == u64(target) && local.maskable_irq_depth == 0
		&& preempt_depth[local.cpu_number] == 0 && proc.current_thread() != unsafe { nil }
	cpu.interrupt_toggle(ints)
	return ok
}
fn irq_work_test_actor(argument voidptr) {
	index := u32(usize(argument))
	if worker_bind(index + 1) != 0 || !irq_work_test_task(index + 1) { irq_work_test_fail(1) }
	katomic.store(mut &irqwork_test_ledger.ready[index], true)
	for !katomic.load(&irqwork_test_ledger.quit) {
		if katomic.load(&irqwork_test_ledger.command[index]) == 0 { sched.reschedule(); continue }
		katomic.store(mut &irqwork_test_ledger.started[index], true)
		if index == 0 {
			test_alloc_oom(0)
			accepted := C.vinix_linuxkpi_irqwork_fixture_queue(irqwork_test_ledger.borrowed, -1)
			ints := cpu.interrupt_toggle(false)
			allocation_free := proc.current_thread().linuxkpi_alloc_fail_after == 0
			cpu.interrupt_toggle(ints)
			test_alloc_oom(-1)
			if !accepted || !allocation_free { irq_work_test_fail(2) }
		} else { C.vinix_linuxkpi_irqwork_fixture_sync(irqwork_test_ledger.borrowed) }
		if !irq_work_test_task(index + 1) { irq_work_test_fail(4) }
		katomic.store(mut &irqwork_test_ledger.command[index], u32(0))
		katomic.store(mut &irqwork_test_ledger.done[index], true)
	}
	event.pthread_exit(unsafe { nil })
}
fn irq_work_test_callback(argument &C.irq_work) {
	mut node := unsafe { &IrqWorkTestNode(argument) }
	local := cpulocal.current()
	index := u32(local.cpu_number)
	mode := node.mode
	if cpu.interrupt_state() || local.maskable_irq_depth == 0 || index >= 4
		|| C.vinix_linuxkpi_irqwork_fixture_pending(node)
		|| !C.vinix_linuxkpi_irqwork_fixture_busy(node) || may_sleep()
		|| node.magic != 0x6972712d776f726b { irq_work_test_fail(8) }
	if mode != 3 && index != node.target { irq_work_test_fail(16) }
	katomic.inc(mut &irqwork_test_ledger.calls)
	if mode == 3 {
		if index != 1 && index != 3 { irq_work_test_fail(32); return }
		katomic.inc(mut &irqwork_test_ledger.entered[index])
		started := irqwork_clock.nanoseconds()
		for !katomic.load(&irqwork_test_ledger.release[index]) {
			spin_wait()
			if irqwork_clock.nanoseconds() - started >= irqwork_test_timeout_ns {
				lib.kpanic(unsafe { nil }, c'linuxkpi: held concurrent IRQ work deadline')
			}
		}
	} else if mode == 4 {
		C.vinix_linuxkpi_irqwork_fixture_defer(node, unsafe { &node.rcu })
		// Actual outer IRQ return protects the backend's required postcallback
		// flag operation. Only this permanent scalar is touched after enqueue.
		katomic.inc(mut &irqwork_test_ledger.deferred)
	} else if node.remaining > 1 {
		node.remaining--
		if !C.vinix_linuxkpi_irqwork_fixture_queue(node, i32(node.target)) { irq_work_test_fail(64) }
	} else { katomic.store(mut &irqwork_test_ledger.observed_tick, irqwork_tick_count()) }
}
fn irq_work_test_init(node &IrqWorkTestNode, mode u32, target u32, remaining u32, flags u32) bool {
	mut owner := unsafe { node }
	owner.mode = mode
	owner.target = target
	owner.remaining = remaining
	owner.magic = 0x6972712d776f726b
	return C.vinix_linuxkpi_irqwork_fixture_init(owner, irq_work_test_callback, flags) == 0
}
fn irq_work_test_lazy() bool {
	mut node := IrqWorkTestNode{}
	if !irq_work_test_init(unsafe { &node }, 0, 0, 1, 4) { return false }
	before := katomic.load(&irqwork_test_ledger.calls)
	ints := cpu.interrupt_toggle(false)
	ticks := irqwork_tick_count()
	ipis := irqwork_ipi_count(0)
	accepted := C.vinix_linuxkpi_irqwork_fixture_queue(unsafe { &node }, -1)
	quiet := C.vinix_linuxkpi_irqwork_fixture_pending(unsafe { &node })
		&& C.vinix_linuxkpi_irqwork_fixture_busy(unsafe { &node }) && irqwork_ipi_count(0) == ipis
		&& irqwork_tick_count() == ticks && katomic.load(&irqwork_test_ledger.calls) == before
	cpu.interrupt_toggle(ints)
	C.vinix_linuxkpi_irqwork_fixture_sync(unsafe { &node })
	return accepted && quiet && irq_work_test_wait_calls(before + 1, false)
		&& katomic.load(&irqwork_test_ledger.observed_tick) > ticks
}
fn irq_work_test_basic(controller &proc.Thread, flags u32, target i32, repeats u32) bool {
	mut node := IrqWorkTestNode{}
	cpu_id := if target < 0 { u32(0) } else { u32(target) }
	if !irq_work_test_init(unsafe { &node }, 1, cpu_id, repeats, flags) { return false }
	before := katomic.load(&irqwork_test_ledger.calls)
	if target == 3 {
		started := irqwork_clock.nanoseconds()
		for !katomic.load(&cpu_locals[3].is_idle) {
			if irqwork_clock.nanoseconds() - started >= irqwork_test_timeout_ns { return false }
			sched.reschedule()
		}
	}
	test_alloc_oom(0)
	preempt_disable()
	ints := cpu.interrupt_toggle(false)
	accepted := C.vinix_linuxkpi_irqwork_fixture_queue(unsafe { &node }, target)
	// A remote target may already have completed. Duplicate-pending is tested
	// on the CLI-protected local CPU, where delivery cannot race the witness.
	duplicate := if target < 0 { C.vinix_linuxkpi_irqwork_fixture_queue(unsafe { &node }, target) } else { false }
	valid := !cpu.interrupt_state() && preempt_depth[0] == 1
		&& controller.linuxkpi_alloc_fail_after == 0
	cpu.interrupt_toggle(ints)
	preempt_enable()
	test_alloc_oom(-1)
	C.vinix_linuxkpi_irqwork_fixture_sync(unsafe { &node })
	return accepted && !duplicate && valid && irq_work_test_wait_calls(before + repeats, false)
		&& !C.vinix_linuxkpi_irqwork_fixture_pending(unsafe { &node })
		&& !C.vinix_linuxkpi_irqwork_fixture_busy(unsafe { &node })
}
fn irq_work_test_parallel() bool {
	// This fixture record has boot lifetime. Reset occurs only after the prior
	// lifecycle drained callbacks and joined both actors off their stacks.
	node := unsafe { &irqwork_test_ledger.parallel }
	if !irq_work_test_init(node, 3, 1, 1, 0) { return false }
	mut producer_started := false
	mut sync_started := false
	defer {
		katomic.store(mut &irqwork_test_ledger.release[1], true)
		katomic.store(mut &irqwork_test_ledger.release[3], true)
		if producer_started || sync_started {
			started := irqwork_clock.nanoseconds()
			// Stop the producer before the final synchronization snapshot. A
			// failure can occur before its queue call has published this node.
			for producer_started && !katomic.load(&irqwork_test_ledger.done[0]) {
				if irqwork_clock.nanoseconds() - started >= irqwork_test_timeout_ns {
					lib.kpanic(unsafe { nil }, c'linuxkpi: IRQ work borrowed owner cleanup deadline')
				}
				sched.reschedule()
			}
			C.vinix_linuxkpi_irqwork_fixture_sync(node)
			for sync_started && !katomic.load(&irqwork_test_ledger.done[1]) {
				if irqwork_clock.nanoseconds() - started >= irqwork_test_timeout_ns {
					lib.kpanic(unsafe { nil }, c'linuxkpi: IRQ work borrowed sync cleanup deadline')
				}
				sched.reschedule()
			}
		}
		irqwork_test_ledger.borrowed = unsafe { nil }
	}
	irqwork_test_ledger.borrowed = node
	katomic.store(mut &irqwork_test_ledger.command[0], u32(1))
	producer_started = true
	started := irqwork_clock.nanoseconds()
	for katomic.load(&irqwork_test_ledger.entered[1]) != 1 {
		if katomic.load(&irqwork_test_ledger.failures) != 0
			|| irqwork_clock.nanoseconds() - started >= irqwork_test_timeout_ns { return false }
		sched.reschedule()
	}
	if !C.vinix_linuxkpi_irqwork_fixture_queue(node, 3) { return false }
	for katomic.load(&irqwork_test_ledger.entered[3]) != 1 {
		if katomic.load(&irqwork_test_ledger.failures) != 0
			|| irqwork_clock.nanoseconds() - started >= irqwork_test_timeout_ns { return false }
		sched.reschedule()
	}
	if C.vkiw_running_count(node) != 2 { return false }
	waits := C.vkiw_sync_wait_count()
	katomic.store(mut &irqwork_test_ledger.command[1], u32(1))
	sync_started = true
	for C.vkiw_sync_wait_count() == waits {
		if katomic.load(&irqwork_test_ledger.failures) != 0
			|| irqwork_clock.nanoseconds() - started >= irqwork_test_timeout_ns { return false }
		sched.reschedule()
	}
	katomic.store(mut &irqwork_test_ledger.release[1], true)
	for C.vkiw_running_count(node) != 1
		|| C.vinix_linuxkpi_irqwork_fixture_busy(node) {
		if katomic.load(&irqwork_test_ledger.failures) != 0
			|| irqwork_clock.nanoseconds() - started >= irqwork_test_timeout_ns { return false }
		sched.reschedule()
	}
	// BUSY is now zero while CPU3 remains in the same work's callback. The
	// independent stack running record must continue to pin synchronous users.
	if katomic.load(&irqwork_test_ledger.done[1]) { return false }
	new_waits := C.vkiw_sync_wait_count()
	for C.vkiw_sync_wait_count() == new_waits {
		if irqwork_clock.nanoseconds() - started >= irqwork_test_timeout_ns { return false }
		sched.reschedule()
	}
	if katomic.load(&irqwork_test_ledger.done[1]) { return false }
	katomic.store(mut &irqwork_test_ledger.release[3], true)
	return irq_work_test_wait(&irqwork_test_ledger.done[0])
		&& irq_work_test_wait(&irqwork_test_ledger.done[1])
		&& C.vkiw_running_count(node) == 0
}
fn irq_work_test_deferred(controller &proc.Thread) bool {
	mut nodes := unsafe { [irqwork_test_deferred_count]&IrqWorkTestNode{} }
	mut allocated := 0
	mut submitted := 0
	defer {
		for index in submitted .. allocated { C.kfree(nodes[index]) }
		if submitted != 0 {
			started := irqwork_clock.nanoseconds()
			for katomic.load(&irqwork_test_ledger.deferred) < u32(submitted) {
				if irqwork_clock.nanoseconds() - started >= irqwork_test_timeout_ns {
					lib.kpanic(unsafe { nil }, c'linuxkpi: IRQ work RCU self-defer cleanup deadline')
				}
				sched.reschedule()
			}
			C.vinix_linuxkpi_rcu_fixture_barrier()
		}
	}
	for index in 0 .. irqwork_test_deferred_count {
		node := unsafe { &IrqWorkTestNode(C.kzalloc(sizeof(IrqWorkTestNode), 3264)) }
		if node == unsafe { nil } { return false }
		nodes[index] = node
		allocated++
		if !irq_work_test_init(node, 4, u32(index % 3 + 1), 1, if index % 3 == 0 { u32(8) } else { u32(0) }) { return false }
	}
	test_alloc_oom(0)
	ints := cpu.interrupt_toggle(false)
	for index in 0 .. allocated {
		if !C.vinix_linuxkpi_irqwork_fixture_queue(nodes[index], i32(index % 3 + 1)) {
			irq_work_test_fail(128)
			break
		}
		submitted++
	}
	valid := !cpu.interrupt_state() && controller.linuxkpi_alloc_fail_after == 0
	cpu.interrupt_toggle(ints)
	test_alloc_oom(-1)
	return valid && submitted == allocated
}
fn irq_work_test_lifecycle() bool {
	ints := cpu.interrupt_toggle(false)
	mut controller := proc.current_thread()
	affinity := katomic.load(&controller.affinity_mask)
	numa := katomic.load(&controller.numa_node)
	gate := controller.linuxkpi_alloc_fail_after
	cpu.interrupt_toggle(ints)
	mut owners := unsafe { [2]&proc.Thread{} }
	mut created := 0
	defer {
		katomic.store(mut &irqwork_test_ledger.release[1], true)
		katomic.store(mut &irqwork_test_ledger.release[3], true)
		katomic.store(mut &irqwork_test_ledger.quit, true)
		for index in 0 .. created { irq_test_join(owners[index]) }
		selftest_free_baseline()
		restore := cpu.interrupt_toggle(false)
		controller.linuxkpi_alloc_fail_after = gate
		katomic.store(mut &controller.numa_node, numa)
		katomic.store(mut &controller.affinity_mask, affinity)
		cpu.interrupt_toggle(restore)
	}
	if !ints || worker_bind(0) != 0 { return false }
	irqwork_test_ledger = IrqWorkTestLedger{}
	if !irq_work_test_lazy() || !irq_work_test_basic(controller, 0, -1, 1)
		|| !irq_work_test_basic(controller, 8, -1, 1)
		|| !irq_work_test_basic(controller, 0, 3, 1)
		|| !irq_work_test_basic(controller, 0, 1, 3) { return false }
	for index in 0 .. 2 {
		mut actor := sched.try_new_kernel_thread(voidptr(irq_work_test_actor), voidptr(index)) or { return false }
		proc.pin_thread(actor)
		proc.pin_thread(actor)
		actor.pthread_joinable = 1
		if !sched.enqueue_thread(actor, false) {
			proc.unpin_thread(actor)
			proc.unpin_thread(actor)
			sched.discard_unstarted_thread(actor)
			return false
		}
		owners[index] = actor
		created++
	}
	if !irq_work_test_wait(&irqwork_test_ledger.ready[0])
		|| !irq_work_test_wait(&irqwork_test_ledger.ready[1]) { return false }
	return irq_work_test_parallel() && irq_work_test_deferred(controller)
}
fn irq_work_native_selftest() bool {
	if cpu_locals.len < 4 || cpu_locals.len > 64 || C.vinix_linuxkpi_irqwork_fixture_bytes() != 32 { return false }
	for round in 0 .. 3 {
		before := selftest_free_baseline()
		if !irq_work_test_lifecycle() { return false }
		C.kprintf(c'linuxkpi: IRQ work lifecycle warmup %d free-byte baseline=%llu after=%llu\n',
			round + 1, before, selftest_free_baseline())
	}
	mut before := CPUFeatureHeapSnapshot{}
	mut after := CPUFeatureHeapSnapshot{}
	free_before := selftest_free_baseline()
	if !cpu_feature_test_heap(unsafe { &before }) || !irq_work_test_lifecycle() { return false }
	free_after := selftest_free_baseline()
	if !cpu_feature_test_heap(unsafe { &after }) { return false }
	mut equal := before.count == after.count
	if before.count != after.count {
		C.kprintf(c'linuxkpi: IRQ work heap class count before=%d after=%d\n', before.count, after.count)
	}
	for index in 0 .. before.count {
		if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] {
			equal = false
			C.kprintf(c'linuxkpi: IRQ work heap class %d size_before=%llu size_after=%llu live_before=%llu live_after=%llu\n',
				index, before.sizes[index], after.sizes[index], before.live[index], after.live[index])
		}
	}
	C.kprintf(c'linuxkpi: IRQ work fourth lifecycle free-byte baseline=%llu after=%llu heap_equal=%d\n',
		free_before, free_after, int(equal))
	return free_before == free_after && equal && katomic.load(&irqwork_test_ledger.failures) == 0
}
