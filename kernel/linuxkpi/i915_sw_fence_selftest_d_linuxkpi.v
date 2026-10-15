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
import x86.hpet as swf_clock

#include "linuxkpi_sw_fence_fixture_v_primitives.h"
struct C.i915_sw_fence {}

struct C.vinix_swfence_fixture {}

struct C.vinix_swfence_wait_fixture {}

struct C.vinix_swfence_dma_fixture {}

@[typedef]
struct C.vswf_notify {}

fn C.vinix_linuxkpi_swf_bytes(u32) u32
fn C.vinix_linuxkpi_swf_init(voidptr, fn (&C.i915_sw_fence, C.vswf_notify) i32)
fn C.vinix_linuxkpi_swf_fini(voidptr)
fn C.vinix_linuxkpi_swf_reinit(voidptr)
fn C.vinix_linuxkpi_swf_await(voidptr) bool
fn C.vinix_linuxkpi_swf_complete(voidptr)
fn C.vinix_linuxkpi_swf_commit(voidptr)
fn C.vinix_linuxkpi_swf_wait(voidptr)
fn C.vinix_linuxkpi_swf_error(voidptr, i32)
fn C.vinix_linuxkpi_swf_state(voidptr, u32) i32
fn C.vinix_linuxkpi_swf_waiters(voidptr) u32
fn C.vinix_linuxkpi_swf_sw(voidptr, voidptr, voidptr, u32) i32
fn C.vinix_linuxkpi_swf_dma(voidptr, voidptr, voidptr, u64, u32) i32
fn C.vinix_linuxkpi_swf_resv(voidptr, voidptr, bool, u64, u32) i32
fn C.vinix_linuxkpi_swf_timed(voidptr, voidptr) voidptr
fn C.vinix_linuxkpi_swf_timed_value(voidptr, u32) u64
fn C.vinix_linuxkpi_swf_timed_sync(voidptr)
fn C.vinix_linuxkpi_swf_now() u64
fn C.vinix_linuxkpi_timer_active() usize

struct SwFenceTestNode {
mut:
	fence C.vinix_swfence_fixture
	id    u32
	mode  u32
}

// Callback owners, supplied wait records, output slots and cross-task borrows
// remain in this boot-lifetime ledger until all producers and actors retire.
struct SwFenceTestLedger {
mut:
	nodes             [129]SwFenceTestNode
	waits             [128]C.vinix_swfence_wait_fixture
	external          C.vinix_swfence_dma_fixture
	committed         [129]bool
	completes         [130]u32
	frees             [130]u32
	count             u32
	dynamic           voidptr
	dynamic_committed bool
	leaves            [4]voidptr
	leaf_count        u32
	reservations      [2]C.vinix_resv_fixture
	resv_live         bool
	ready             [3]bool
	commands          [3]u32
	started           [3]bool
	done              [3]bool
	owners            [3]voidptr
	results           [3]i32
	quit              bool
	target            voidptr
	source            voidptr
	dma               voidptr
	write             bool
	gfp               u32
	alloc_gate        i32
	reader_held       bool
	reader_release    bool
	timed             voidptr
	irq               C.vinix_irqwork_fixture
	irq_done          bool
	irq_held          bool
	failures          u32
}

__global swf_test_ledger SwFenceTestLedger

fn swf_fail(bit u32) {
	for {
		old := katomic.load(&swf_test_ledger.failures)
		if katomic.cas(mut &swf_test_ledger.failures, old, old | bit) { return }
	}
}

fn swf_wait(flag &bool) bool {
	start := swf_clock.nanoseconds()
	for !katomic.load(flag) {
		if swf_clock.nanoseconds() - start >= dmafence_test_timeout_ns { return false }
		sched.reschedule()
	}
	return katomic.load(&swf_test_ledger.failures) == 0
}

fn swf_notify(fence &C.i915_sw_fence, state C.vswf_notify) i32 {
	node := unsafe { &SwFenceTestNode(fence) }
	id := node.id
	mode := node.mode
	mut bits := u32(0)
	unsafe { C.memcpy(&bits, &state, 4) }
	if bits == 0 {
		if C.vinix_linuxkpi_swf_state(fence, 0) != 0 || C.vinix_linuxkpi_swf_state(fence, 2) != 1
			|| C.vinix_linuxkpi_swf_state(fence, 3) != 0 {
			swf_fail(1)
		}
		if mode & 2 != 0 && (cpu.interrupt_state() || cpulocal.current().maskable_irq_depth == 0) {
			swf_fail(2)
		}
		if mode & 4 != 0 && (cpu.interrupt_state() || cpulocal.current().maskable_irq_depth != 0
			|| preempt_depth[cpulocal.current().cpu_number] == 0 || may_sleep()) {
			swf_fail(4)
		}
		katomic.inc(mut &swf_test_ledger.completes[id])
	} else if bits == 1 {
		if C.vinix_linuxkpi_swf_state(fence, 0) != -1 || C.vinix_linuxkpi_swf_state(fence, 3) != 1 {
			swf_fail(8)
		}
		katomic.inc(mut &swf_test_ledger.frees[id])
		if mode & 1 != 0 {
			// Supplied wait records live separately in the ledger: the original
			// SW wake callback still reads its wait flags after this FREE returns.
			C.vinix_linuxkpi_swf_fini(fence)
			swf_test_ledger.dynamic = unsafe { nil }
			C.kfree(node)
		}
	} else {
		swf_fail(16)
	}
	return 0
}

fn swf_actor(argument voidptr) {
	index := u32(usize(argument))
	if worker_bind(index + 1) != 0 || !dma_fence_test_task(index + 1) { swf_fail(32) }
	katomic.store(mut &swf_test_ledger.ready[index], true)
	for !katomic.load(&swf_test_ledger.quit) {
		command := katomic.load(&swf_test_ledger.commands[index])
		if command == 0 {
			sched.reschedule()
			continue
		}
		katomic.store(mut &swf_test_ledger.started[index], true)
		if command == 1 {
			C.vinix_linuxkpi_swf_wait(swf_test_ledger.target)
			swf_test_ledger.results[index] = 0
		} else if command >= 2 && command <= 4 {
			gate := proc.current_thread().linuxkpi_alloc_fail_after
			test_alloc_oom(swf_test_ledger.alloc_gate)
			if command == 2 {
				swf_test_ledger.results[index] = C.vinix_linuxkpi_swf_sw(swf_test_ledger.target, swf_test_ledger.source, unsafe { nil }, swf_test_ledger.gfp)
			} else if command == 3 {
				swf_test_ledger.results[index] = C.vinix_linuxkpi_swf_dma(swf_test_ledger.target, swf_test_ledger.dma, unsafe { nil }, 0, swf_test_ledger.gfp)
			} else {
				swf_test_ledger.results[index] = C.vinix_linuxkpi_swf_resv(swf_test_ledger.target, unsafe { &swf_test_ledger.reservations[0] }, swf_test_ledger.write, 0, swf_test_ledger.gfp)
			}
			test_alloc_oom(gate)
		} else if command == 5 {
			C.vinix_linuxkpi_rcu_fixture_read_lock()
			katomic.store(mut &swf_test_ledger.reader_held, true)
			start := swf_clock.nanoseconds()
			for !katomic.load(&swf_test_ledger.reader_release) {
				if swf_clock.nanoseconds() - start >= dmafence_test_timeout_ns {
					lib.kpanic(unsafe { nil }, c'linuxkpi: SW-fence held reader deadline')
				}
				spin_wait()
			}
			C.vinix_linuxkpi_rcu_fixture_read_unlock()
		} else if command == 7 {
			preempt_disable()
			katomic.store(mut &swf_test_ledger.irq_held, true)
			start := swf_clock.nanoseconds()
			for !katomic.load(&swf_test_ledger.irq_done) {
				if swf_clock.nanoseconds() - start >= dmafence_test_timeout_ns {
					lib.kpanic(unsafe { nil }, c'linuxkpi: SW-fence IRQ actor deadline')
				}
				spin_wait()
			}
			preempt_enable()
		} else {
			C.vinix_linuxkpi_rcu_fixture_barrier()
		}
		if !dma_fence_test_task(index + 1) { swf_fail(64) }
		katomic.store(mut &swf_test_ledger.commands[index], u32(0))
		katomic.store(mut &swf_test_ledger.done[index], true)
	}
	event.pthread_exit(unsafe { nil })
}

fn swf_start(index u32, command u32) {
	swf_test_ledger.results[index] = -9999
	katomic.store(mut &swf_test_ledger.started[index], false)
	katomic.store(mut &swf_test_ledger.done[index], false)
	katomic.store(mut &swf_test_ledger.commands[index], command)
}

fn swf_finish(index u32) {
	if !swf_wait(&swf_test_ledger.done[index]) {
		lib.kpanic(unsafe { nil }, c'linuxkpi: SW-fence actor cleanup deadline')
	}
}

fn swf_parked(index u32) bool {
	owner := unsafe { &proc.Thread(swf_test_ledger.owners[index]) }
	start := swf_clock.nanoseconds()
	for !(katomic.load(&swf_test_ledger.started[index])
		&& C.vinix_linuxkpi_dmafence_fixture_task_state(unsafe { &owner.linuxkpi_task[0] }) == 2
		&& !katomic.load(&owner.is_in_queue) && katomic.load(&owner.running_on) == u64(-1)
		&& !katomic.load(&owner.is_in_queue)) {
		if katomic.load(&swf_test_ledger.done[index]) || swf_clock.nanoseconds() - start >= dmafence_test_timeout_ns {
			return false
		}
		sched.reschedule()
	}
	return true
}

fn swf_node(index u32) voidptr { return unsafe { &swf_test_ledger.nodes[index] } }

fn swf_prepare(count u32) {
	swf_test_ledger.count = count
	for i in 0 .. count {
		swf_test_ledger.nodes[i].id = u32(i)
		swf_test_ledger.nodes[i].mode = 0
		swf_test_ledger.committed[i] = false
		swf_test_ledger.completes[i] = 0
		swf_test_ledger.frees[i] = 0
		C.vinix_linuxkpi_swf_init(swf_node(u32(i)), swf_notify)
	}
}

fn swf_commit(index u32) {
	swf_test_ledger.committed[index] = true
	C.vinix_linuxkpi_swf_commit(swf_node(index))
}

fn swf_finish_all() {
	for i in 0 .. swf_test_ledger.count { swf_test_ledger.nodes[i].mode &= ~u32(6) }
	for i in 0 .. swf_test_ledger.leaf_count {
		C.vinix_linuxkpi_dmafence_fixture_signal(swf_test_ledger.leaves[i], 0, 0)
	}
	for i in 0 .. swf_test_ledger.count { if !swf_test_ledger.committed[i] { swf_commit(u32(i)) } }
	if swf_test_ledger.dynamic != unsafe { nil } && !swf_test_ledger.dynamic_committed {
		swf_test_ledger.dynamic_committed = true
		C.vinix_linuxkpi_swf_commit(swf_test_ledger.dynamic)
	}
}

fn swf_clear() {
	swf_finish_all()
	for i in 0 .. swf_test_ledger.count {
		if C.vinix_linuxkpi_swf_state(swf_node(u32(i)), 3) != 1
			|| C.vinix_linuxkpi_swf_waiters(swf_node(u32(i))) != 0 {
			lib.kpanic(unsafe { nil }, c'linuxkpi: SW-fence unretired dependency')
		}
		C.vinix_linuxkpi_swf_fini(swf_node(u32(i)))
	}
	swf_test_ledger.count = 0
	if swf_test_ledger.resv_live {
		for i in 0 .. 2 {
			C.vinix_linuxkpi_resv_fixture_fini(unsafe { &swf_test_ledger.reservations[i] })
		}
		swf_test_ledger.resv_live = false
	}
	for i in 0 .. swf_test_ledger.leaf_count {
		C.vinix_linuxkpi_dmafence_fixture_put(swf_test_ledger.leaves[i])
		swf_test_ledger.leaves[i] = unsafe { nil }
	}
	swf_test_ledger.leaf_count = 0
	C.vinix_linuxkpi_rcu_fixture_barrier()
}

fn swf_leaf() bool {
	leaf := dma_fence_test_new(0, 0, C.vinix_linuxkpi_dmafence_fixture_context(1), 1)
	if leaf == unsafe { nil } { return false }
	swf_test_ledger.leaves[swf_test_ledger.leaf_count] = leaf
	swf_test_ledger.leaf_count++
	return true
}

fn swf_check(index u32, count u32, error i32) bool {
	return katomic.load(&swf_test_ledger.completes[index]) == count && katomic.load(&swf_test_ledger.frees[index]) == count
		&& C.vinix_linuxkpi_swf_state(swf_node(index), 3) == 1 && C.vinix_linuxkpi_swf_state(swf_node(index), 1) == error
}

fn swf_basics() bool {
	swf_prepare(1)
	defer { swf_clear() }
	mut manual := false
	mut active := false
	defer {
		if manual { C.vinix_linuxkpi_swf_complete(swf_node(0)) }
		swf_finish_all()
		if active { swf_finish(0) }
	}
	if C.vinix_linuxkpi_swf_state(swf_node(0), 0) != 1 || !C.vinix_linuxkpi_swf_await(swf_node(0)) {
		return false
	}
	manual = true
	C.vinix_linuxkpi_swf_error(swf_node(0), -5)
	C.vinix_linuxkpi_swf_error(swf_node(0), -6)
	swf_commit(0)
	if C.vinix_linuxkpi_swf_state(swf_node(0), 0) != 1 { return false }
	swf_test_ledger.target = swf_node(0)
	swf_start(0, 1)
	active = true
	if !swf_parked(0) { return false }
	C.vinix_linuxkpi_swf_complete(swf_node(0))
	manual = false
	swf_finish(0)
	active = false
	if !swf_check(0, 1, -5) || C.vinix_linuxkpi_swf_await(swf_node(0)) { return false }
	C.vinix_linuxkpi_swf_reinit(swf_node(0))
	swf_test_ledger.committed[0] = false
	if C.vinix_linuxkpi_swf_state(swf_node(0), 0) != 1 || C.vinix_linuxkpi_swf_state(swf_node(0), 1) != 0 {
		return false
	}
	swf_commit(0)
	return swf_check(0, 2, 0)
}

fn swf_graph(long bool) bool {
	swf_prepare(if long { u32(129) } else { u32(4) })
	defer { swf_clear() }
	mut active := false
	defer {
		swf_finish_all()
		if active { swf_finish(0) }
	}
	if long {
		for i in 1 .. 129 {
			if C.vinix_linuxkpi_swf_sw(swf_node(u32(i)), swf_node(u32(i - 1)), unsafe { &swf_test_ledger.waits[i - 1] }, 0) != 1 {
				return false
			}
		}
	} else {
		if C.vinix_linuxkpi_swf_sw(swf_node(1), swf_node(0), unsafe { &swf_test_ledger.waits[0] }, 0) != 1
			|| C.vinix_linuxkpi_swf_sw(swf_node(2), swf_node(0), unsafe { &swf_test_ledger.waits[1] }, 0) != 1
			|| C.vinix_linuxkpi_swf_sw(swf_node(3), swf_node(1), unsafe { nil }, 3264) != 1
			|| C.vinix_linuxkpi_swf_sw(swf_node(3), swf_node(2), unsafe { &swf_test_ledger.waits[2] }, 0) != 1 {
			return false
		}
	}
	for i in 1 .. swf_test_ledger.count { swf_commit(u32(i)) }
	swf_test_ledger.target = swf_node(swf_test_ledger.count - 1)
	swf_start(0, 1)
	active = true
	if !swf_parked(0) { return false }
	C.vinix_linuxkpi_swf_error(swf_node(0), -5)
	swf_commit(0)
	swf_finish(0)
	active = false
	for i in 0 .. swf_test_ledger.count { if !swf_check(u32(i), 1, -5) { return false } }
	return true
}

fn swf_sw_oom_and_free() bool {
	swf_prepare(2)
	defer { swf_clear() }
	mut active := false
	defer {
		swf_finish_all()
		if active { swf_finish(0) }
	}
	test_alloc_oom(0)
	missing := C.vinix_linuxkpi_swf_sw(swf_node(0), swf_node(1), unsafe { nil }, 0)
	test_alloc_oom(-1)
	if missing != -12 || C.vinix_linuxkpi_swf_state(swf_node(0), 0) != 1 { return false }
	swf_test_ledger.target = swf_node(0)
	swf_test_ledger.source = swf_node(1)
	swf_test_ledger.gfp = 3264
	swf_test_ledger.alloc_gate = 0
	swf_start(0, 2)
	active = true
	if !swf_parked(0) { return false }
	C.vinix_linuxkpi_swf_error(swf_node(1), -5)
	swf_commit(1)
	swf_finish(0)
	active = false
	if swf_test_ledger.results[0] != 0 || C.vinix_linuxkpi_swf_state(swf_node(0), 0) != 1 {
		return false
	}
	swf_commit(0)
	if !swf_check(0, 1, -5) { return false }
	// The already-completed source returns immediately without allocation.
	if C.vinix_linuxkpi_swf_sw(swf_node(0), swf_node(1), unsafe { nil }, 0) != 0 { return false }
	mut owner := unsafe { &SwFenceTestNode(C.kzalloc(sizeof(SwFenceTestNode), 3264)) }
	if owner == unsafe { nil } { return false }
	owner.id = 129
	owner.mode = 1
	swf_test_ledger.completes[129] = 0
	swf_test_ledger.frees[129] = 0
	swf_test_ledger.dynamic = owner
	swf_test_ledger.dynamic_committed = false
	C.vinix_linuxkpi_swf_init(owner, swf_notify)
	C.vinix_linuxkpi_swf_reinit(swf_node(1))
	swf_test_ledger.committed[1] = false
	if C.vinix_linuxkpi_swf_sw(owner, swf_node(1), unsafe { &swf_test_ledger.waits[0] }, 0) != 1 {
		return false
	}
	swf_test_ledger.dynamic_committed = true
	C.vinix_linuxkpi_swf_commit(owner)
	swf_commit(1)
	return swf_test_ledger.dynamic == unsafe { nil } && katomic.load(&swf_test_ledger.completes[129]) == 1
		&& katomic.load(&swf_test_ledger.frees[129]) == 1
}

fn swf_irq(_work &C.irq_work) {
	local := cpulocal.current()
	if cpu.interrupt_state() || local.maskable_irq_depth == 0 || local.cpu_number != 1 {
		swf_fail(128)
	}
	if C.vinix_linuxkpi_dmafence_fixture_signal(swf_test_ledger.dma, 0, 0) != 0 { swf_fail(256) }
	katomic.store(mut &swf_test_ledger.irq_done, true)
}

fn swf_signal_irq(fence voidptr) bool {
	swf_test_ledger.dma = fence
	katomic.store(mut &swf_test_ledger.irq_done, false)
	katomic.store(mut &swf_test_ledger.irq_held, false)
	swf_start(0, 7)
	mut queued := false
	defer {
		if queued { C.vinix_linuxkpi_irqwork_fixture_sync(unsafe { &swf_test_ledger.irq }) }
		katomic.store(mut &swf_test_ledger.irq_done, true)
		swf_finish(0)
		swf_test_ledger.dma = unsafe { nil }
	}
	if !swf_wait(&swf_test_ledger.irq_held)
		|| C.vinix_linuxkpi_irqwork_fixture_init(unsafe { &swf_test_ledger.irq }, swf_irq, 0) != 0 {
		return false
	}
	queued = C.vinix_linuxkpi_irqwork_fixture_queue(unsafe { &swf_test_ledger.irq }, 1)
	return queued && swf_wait(&swf_test_ledger.irq_done)
}

fn swf_dma_untimed() bool {
	swf_prepare(3)
	defer { swf_clear() }
	if !swf_leaf() || !swf_leaf() { return false }
	first := swf_test_ledger.leaves[0]
	finished := swf_test_ledger.leaves[1]
	C.vinix_linuxkpi_dmafence_fixture_error(finished, -7)
	if C.vinix_linuxkpi_dmafence_fixture_signal(finished, 0, 0) != 0 { return false }
	swf_test_ledger.nodes[0].mode = 2
	swf_test_ledger.nodes[1].mode = 2
	if C.vinix_linuxkpi_swf_dma(swf_node(0), first, unsafe { nil }, 0, 3264) != 1
		|| C.vinix_linuxkpi_swf_dma(swf_node(1), first, unsafe { &swf_test_ledger.external }, 0, 0) != 1
		|| C.vinix_linuxkpi_swf_dma(swf_node(2), finished, unsafe { nil }, 0, 0) != 0 {
		return false
	}
	for i in 0 .. 3 { swf_commit(u32(i)) }
	if !swf_check(2, 1, -7) { return false }
	C.vinix_linuxkpi_dmafence_fixture_error(first, -5)
	if !swf_signal_irq(first) { return false }
	return swf_check(0, 1, -5) && swf_check(1, 1, -5)
}

fn swf_dma_oom() bool {
	swf_prepare(1)
	defer { swf_clear() }
	mut active := false
	defer {
		swf_finish_all()
		if active { swf_finish(0) }
	}
	if !swf_leaf() { return false }
	leaf := swf_test_ledger.leaves[0]
	test_alloc_oom(0)
	missing := C.vinix_linuxkpi_swf_dma(swf_node(0), leaf, unsafe { nil }, 0, 0)
	test_alloc_oom(-1)
	if missing != -12 || C.vinix_linuxkpi_swf_state(swf_node(0), 0) != 1 { return false }
	swf_test_ledger.target = swf_node(0)
	swf_test_ledger.dma = leaf
	swf_test_ledger.gfp = 3264
	swf_test_ledger.alloc_gate = 0
	swf_start(0, 3)
	active = true
	if !swf_parked(0) { return false }
	C.vinix_linuxkpi_dmafence_fixture_error(leaf, -5)
	if C.vinix_linuxkpi_dmafence_fixture_signal(leaf, 0, 0) != 0 { return false }
	swf_finish(0)
	active = false
	if swf_test_ledger.results[0] != 0 || C.vinix_linuxkpi_swf_state(swf_node(0), 0) != 1 {
		return false
	}
	swf_commit(0)
	return swf_check(0, 1, -5)
}

fn swf_timed(expire bool) bool {
	swf_prepare(1)
	defer { swf_clear() }
	mut reader := false
	mut barrier := false
	defer {
		// Stop context assertions before failure-path completion, but preserve
		// the reader until the actual private IRQ callback has retired.
		swf_test_ledger.nodes[0].mode = 0
		if swf_test_ledger.leaf_count != 0 {
			C.vinix_linuxkpi_dmafence_fixture_signal(swf_test_ledger.leaves[0], 0, 0)
		}
		if swf_test_ledger.timed != unsafe { nil } {
			C.vinix_linuxkpi_swf_timed_sync(swf_test_ledger.timed)
		}
		swf_test_ledger.timed = unsafe { nil }
		katomic.store(mut &swf_test_ledger.reader_release, true)
		if reader { swf_finish(2) }
		if barrier { swf_finish(1) }
	}
	if !swf_leaf() { return false }
	leaf := swf_test_ledger.leaves[0]
	active_timers := C.vinix_linuxkpi_timer_active()
	katomic.store(mut &swf_test_ledger.reader_held, false)
	katomic.store(mut &swf_test_ledger.reader_release, false)
	swf_start(2, 5)
	reader = true
	if !swf_wait(&swf_test_ledger.reader_held) { return false }
	swf_test_ledger.nodes[0].mode = if expire { u32(4) } else { u32(2) }
	if C.vinix_linuxkpi_swf_dma(swf_node(0), leaf, unsafe { nil }, if expire {
		u64(100)
	} else {
		u64(10000)
	}, 3264) != 1 {
		return false
	}
	swf_test_ledger.timed = C.vinix_linuxkpi_swf_timed(leaf, swf_node(0))
	owner := swf_test_ledger.timed
	// A successful dedicated registration must retain its private owner until
	// late DMA. Stop before releasing the reader if that invariant is broken.
	if owner == unsafe { nil } {
		lib.kpanic(unsafe { nil }, c'linuxkpi: SW-fence timed owner invariant')
	}
	if C.vinix_linuxkpi_fct_refs(leaf) != 2
		|| C.vinix_linuxkpi_swf_timed_value(owner, 3) & 0x200000 == 0 {
		return false
	}
	expires := C.vinix_linuxkpi_swf_timed_value(owner, 1)
	swf_commit(0)
	if expire {
		start := swf_clock.nanoseconds()
		for C.vinix_linuxkpi_swf_state(swf_node(0), 3) != 1 {
			if swf_clock.nanoseconds() - start >= dmafence_test_timeout_ns { return false }
			sched.reschedule()
		}
		if C.vinix_linuxkpi_swf_now() < expires || !swf_check(0, 1, -110)
			|| C.vinix_linuxkpi_swf_timed_value(owner, 0) != 0
			|| C.vinix_linuxkpi_fct_refs(leaf) != 2 {
			return false
		}
	} else if C.vinix_linuxkpi_swf_now() >= expires {
		return false
	}
	if !swf_signal_irq(leaf) { return false }
	// The remote ordinary reader keeps the 128-byte private owner valid while
	// controller task context waits for work callback and post-callback CAS.
	C.vinix_linuxkpi_swf_timed_sync(owner)
	if C.vinix_linuxkpi_fct_refs(leaf) != 1
		|| C.vinix_linuxkpi_swf_timed_value(owner, 0) != 0
		|| C.vinix_linuxkpi_swf_timed_value(owner, 2) != 0
		|| C.vinix_linuxkpi_timer_active() != active_timers
		|| !swf_check(0, 1, if expire { -110 } else { 0 }) {
		return false
	}
	force := C.vinix_linuxkpi_rcu_test_force_count()
	held := memory.free_bytes()
	swf_start(1, 6)
	barrier = true
	start := swf_clock.nanoseconds()
	for C.vinix_linuxkpi_rcu_test_force_count() == force {
		if swf_clock.nanoseconds() - start >= dmafence_test_timeout_ns { return false }
		sched.reschedule()
	}
	if katomic.load(&swf_test_ledger.done[1]) || memory.free_bytes() != held { return false }
	swf_test_ledger.timed = unsafe { nil }
	katomic.store(mut &swf_test_ledger.reader_release, true)
	swf_finish(2)
	reader = false
	swf_finish(1)
	barrier = false
	return true
}

fn swf_reservation() bool {
	swf_prepare(3)
	defer { swf_clear() }
	obj := unsafe { &swf_test_ledger.reservations[0] }
	empty := unsafe { &swf_test_ledger.reservations[1] }
	mut locked := false
	mut active := false
	defer {
		if locked { C.vinix_linuxkpi_resv_fixture_unlock(obj) }
		swf_finish_all()
		if active { swf_finish(0) }
	}
	for i in 0 .. 2 {
		C.vinix_linuxkpi_resv_fixture_init(unsafe { &swf_test_ledger.reservations[i] })
	}
	swf_test_ledger.resv_live = true
	for _ in 0 .. 4 { if !swf_leaf() { return false } }
	if C.vinix_linuxkpi_resv_fixture_lock(obj, 0) != 0 { return false }
	locked = true
	if C.vinix_linuxkpi_resv_fixture_reserve(obj, 4) != 0 { return false }
	for i in 0 .. 4 { C.vinix_linuxkpi_resv_fixture_add(obj, swf_test_ledger.leaves[i], u32(i)) }
	// Original unlocked iteration completes on CPU1 while CPU0 owns the writer
	// mutex; callback references survive removing the reservation's references.
	swf_test_ledger.target = swf_node(0)
	swf_test_ledger.write = false
	swf_test_ledger.gfp = 3264
	swf_test_ledger.alloc_gate = -1
	swf_start(0, 4)
	active = true
	swf_finish(0)
	active = false
	if swf_test_ledger.results[0] != 1 || C.vinix_linuxkpi_swf_state(swf_node(0), 0) != 3
		|| C.vinix_linuxkpi_swf_resv(swf_node(1), obj, true, 0, 3264) != 1
		|| C.vinix_linuxkpi_swf_state(swf_node(1), 0) != 4 {
		return false
	}
	test_alloc_oom(1)
	partial := C.vinix_linuxkpi_swf_resv(swf_node(2), obj, false, 0, 0)
	test_alloc_oom(-1)
	if partial != -12 || C.vinix_linuxkpi_swf_state(swf_node(2), 0) != 2 { return false }
	C.vinix_linuxkpi_resv_fixture_unlock(obj)
	locked = false
	if C.vinix_linuxkpi_resv_fixture_lock(obj, 0) != 0 { return false }
	locked = true
	if C.vinix_linuxkpi_resv_fixture_copy(obj, empty) != 0 { return false }
	C.vinix_linuxkpi_resv_fixture_unlock(obj)
	locked = false
	for i in 0 .. 4 {
		if C.vinix_linuxkpi_fct_refs(swf_test_ledger.leaves[i]) != 1 { return false }
	}
	for i in 0 .. 3 { swf_commit(u32(i)) }
	C.vinix_linuxkpi_dmafence_fixture_signal(swf_test_ledger.leaves[3], 0, 0)
	for i in 0 .. 3 { if C.vinix_linuxkpi_swf_state(swf_node(u32(i)), 3) != 0 { return false } }
	C.vinix_linuxkpi_dmafence_fixture_error(swf_test_ledger.leaves[0], -5)
	C.vinix_linuxkpi_dmafence_fixture_error(swf_test_ledger.leaves[1], -6)
	C.vinix_linuxkpi_dmafence_fixture_signal(swf_test_ledger.leaves[0], 0, 0)
	if !swf_check(2, 1, -5) || C.vinix_linuxkpi_swf_state(swf_node(0), 3) != 0
		|| C.vinix_linuxkpi_swf_state(swf_node(1), 3) != 0 {
		return false
	}
	C.vinix_linuxkpi_dmafence_fixture_signal(swf_test_ledger.leaves[1], 0, 0)
	if !swf_check(0, 1, -5) || C.vinix_linuxkpi_swf_state(swf_node(1), 3) != 0 { return false }
	C.vinix_linuxkpi_dmafence_fixture_signal(swf_test_ledger.leaves[2], 0, 0)
	return swf_check(1, 1, -5)
}

fn swf_lifecycle() bool {
	ints := cpu.interrupt_toggle(false)
	mut controller := proc.current_thread()
	affinity := katomic.load(&controller.affinity_mask)
	numa := katomic.load(&controller.numa_node)
	gate := controller.linuxkpi_alloc_fail_after
	cpu.interrupt_toggle(ints)
	mut owners := unsafe { [3]&proc.Thread{} }
	mut created := 0
	defer {
		katomic.store(mut &swf_test_ledger.reader_release, true)
		katomic.store(mut &swf_test_ledger.irq_done, true)
		katomic.store(mut &swf_test_ledger.quit, true)
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
	swf_test_ledger = SwFenceTestLedger{}
	for i in 0 .. 3 {
		mut actor := sched.try_new_kernel_thread(voidptr(swf_actor), voidptr(i)) or { return false }
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
		swf_test_ledger.owners[i] = actor
		created++
	}
	for i in 0 .. 3 { if !swf_wait(&swf_test_ledger.ready[i]) { return false } }
	if !swf_basics() {
		C.kprintf(c'linuxkpi: i915 software fence basic case failed\n')
		return false
	}
	if !swf_graph(false) || !swf_graph(true) {
		C.kprintf(c'linuxkpi: i915 software fence graph case failed\n')
		return false
	}
	if !swf_sw_oom_and_free() {
		C.kprintf(c'linuxkpi: i915 software fence SW OOM/FREE case failed\n')
		return false
	}
	if !swf_dma_untimed() {
		C.kprintf(c'linuxkpi: i915 software fence DMA callback case failed\n')
		return false
	}
	if !swf_dma_oom() {
		C.kprintf(c'linuxkpi: i915 software fence DMA OOM case failed\n')
		return false
	}
	if !swf_timed(false) || !swf_timed(true) {
		C.kprintf(c'linuxkpi: i915 software fence timer/IRQ/RCU case failed\n')
		return false
	}
	if !swf_reservation() {
		C.kprintf(c'linuxkpi: i915 software fence reservation case failed\n')
		return false
	}
	return true
}

fn i915_sw_fence_native_selftest() bool {
	if cpu_locals.len < 4 || cpu_locals.len > 64 || C.vinix_linuxkpi_swf_bytes(0) != 40
		|| C.vinix_linuxkpi_swf_bytes(1) != 40 || C.vinix_linuxkpi_swf_bytes(2) != 32
		|| C.vinix_linuxkpi_swf_bytes(3) != 128 {
		return false
	}
	for round in 0 .. 3 {
		before := selftest_free_baseline()
		if !swf_lifecycle() { return false }
		C.kprintf(c'linuxkpi: i915 software fence lifecycle warmup %d free-byte baseline=%llu after=%llu\n', round + 1, before, selftest_free_baseline())
	}
	mut before := CPUFeatureHeapSnapshot{}
	mut after := CPUFeatureHeapSnapshot{}
	free_before := selftest_free_baseline()
	if !cpu_feature_test_heap(unsafe { &before }) || !swf_lifecycle() { return false }
	free_after := selftest_free_baseline()
	if !cpu_feature_test_heap(unsafe { &after }) { return false }
	mut equal := before.count == after.count
	for i in 0 .. before.count {
		if before.sizes[i] != after.sizes[i] || before.live[i] != after.live[i] {
			equal = false
			C.kprintf(c'linuxkpi: i915 software fence heap class %d size_before=%llu size_after=%llu live_before=%llu live_after=%llu\n',
				i, before.sizes[i], after.sizes[i], before.live[i], after.live[i])
		}
	}
	C.kprintf(c'linuxkpi: i915 software fence fourth lifecycle free-byte baseline=%llu after=%llu heap_equal=%u\n', free_before, free_after, u32(equal))
	return free_before == free_after && equal && katomic.load(&swf_test_ledger.failures) == 0
}
