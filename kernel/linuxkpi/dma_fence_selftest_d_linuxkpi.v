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
import x86.hpet as dmafence_clock

#include "linuxkpi_dma_fence_fixture_v_primitives.h"

struct C.dma_fence {}
struct C.dma_fence_cb {}
struct C.vinix_dmafence_fixture {}
struct C.vinix_dmafence_cb {}
@[typedef]
struct C.vdf_test_const_char_p {}
@[typedef]
struct C.vdf_test_ktime_t {}
struct C.vinix_dmafence_ops {
mut:
	use_64bit_seqno bool
	get_driver_name fn (&C.dma_fence) C.vdf_test_const_char_p
	get_timeline_name fn (&C.dma_fence) C.vdf_test_const_char_p
	enable_signaling fn (&C.dma_fence) bool
	signaled fn (&C.dma_fence) bool
	@wait fn (&C.dma_fence, bool, i64) i64
	release fn (&C.dma_fence)
	set_deadline fn (&C.dma_fence, C.vdf_test_ktime_t)
}
fn C.vinix_linuxkpi_dmafence_fixture_bytes(u32) u32
fn C.vinix_linuxkpi_dmafence_fixture_init(voidptr, voidptr, voidptr, u64, u64)
fn C.vinix_linuxkpi_dmafence_fixture_get(voidptr, u32) voidptr
fn C.vinix_linuxkpi_dmafence_fixture_put(voidptr)
fn C.vinix_linuxkpi_dmafence_fixture_free(voidptr)
fn C.vinix_linuxkpi_dmafence_fixture_signal(voidptr, u32, i64) i32
fn C.vinix_linuxkpi_dmafence_fixture_status(voidptr) i32
fn C.vinix_linuxkpi_dmafence_fixture_signaled(voidptr, bool) bool
fn C.vinix_linuxkpi_dmafence_fixture_error(voidptr, i32)
fn C.vinix_linuxkpi_dmafence_fixture_timestamp(voidptr) i64
fn C.vinix_linuxkpi_dmafence_fixture_enable(voidptr)
fn C.vinix_linuxkpi_dmafence_fixture_add(voidptr, voidptr, fn (&C.dma_fence, &C.dma_fence_cb)) i32
fn C.vinix_linuxkpi_dmafence_fixture_remove(voidptr, voidptr) bool
fn C.vinix_linuxkpi_dmafence_fixture_wait(voidptr, u32, bool, i64) i64
fn C.vinix_linuxkpi_dmafence_fixture_any(&voidptr, u32, bool, i64, &u32) i64
fn C.vinix_linuxkpi_dmafence_fixture_stub(bool, i64) voidptr
fn C.vinix_linuxkpi_dmafence_fixture_context(u32) u64
fn C.vinix_linuxkpi_dmafence_fixture_deadline(voidptr, i64)
fn C.vinix_linuxkpi_dmafence_fixture_compare(voidptr, voidptr, u32) bool
fn C.vinix_linuxkpi_dmafence_fixture_callbacks(voidptr) u32
fn C.vinix_linuxkpi_dmafence_fixture_task_state(voidptr) u32

const dmafence_test_timeout_ns = u64(10000000000)
const dmafence_test_infinite = i64(0x7fffffffffffffff)

struct DmaFenceTestNode {
mut:
	fence C.vinix_dmafence_fixture
	guard u32
	mode u32
	wait_result i64
	magic u64
}
struct DmaFenceTestCallback {
mut:
	callback C.vinix_dmafence_cb
	self_free bool
}
// Every cross-task/IRQ borrow is published from this boot-lifetime ledger.
// Reset occurs only after callbacks drain and every retained actor retires.
struct DmaFenceTestLedger {
mut:
	ops [3]C.vinix_dmafence_ops
	ready [3]bool
	quit bool
	commands [3]u32
	started [3]bool
	done [3]bool
	owners [3]voidptr
	fences [3]voidptr
	timeouts [3]i64
	intr [3]bool
	wait_modes [3]u32
	results [3]i64
	indices [3]u32
	any [3]voidptr
	any_count u32
	reader_release bool
	reader_held bool
	irq C.vinix_irqwork_fixture
	irq_fence voidptr
	irq_done bool
	irq_target_held bool
	callbacks [2]DmaFenceTestCallback
	callback_calls u32
	callback_frees u32
	custom_releases u32
	enables u32
	custom_waits u32
	custom_intr bool
	custom_timeout i64
	deadline i64
	failures u32
}
__global dmafence_test_ledger DmaFenceTestLedger

fn dma_fence_test_fail(bit u32) {
	for {
		old := katomic.load(&dmafence_test_ledger.failures)
		if katomic.cas(mut &dmafence_test_ledger.failures, old, old | bit) { return }
	}
}
fn dma_fence_test_wait(flag &bool, cleanup bool) bool {
	started := dmafence_clock.nanoseconds()
	for !katomic.load(flag) {
		if (!cleanup && katomic.load(&dmafence_test_ledger.failures) != 0)
			|| dmafence_clock.nanoseconds() - started >= dmafence_test_timeout_ns { return false }
		sched.reschedule()
	}
	return cleanup || katomic.load(&dmafence_test_ledger.failures) == 0
}
fn dma_fence_test_task(target u32) bool {
	ints := cpu.interrupt_toggle(false)
	local := cpulocal.current()
	ok := ints && local.cpu_number == u64(target) && local.maskable_irq_depth == 0
		&& preempt_depth[local.cpu_number] == 0 && proc.current_thread() != unsafe { nil }
	cpu.interrupt_toggle(ints)
	return ok
}
fn dma_fence_test_actor(argument voidptr) {
	index := u32(usize(argument))
	if worker_bind(index + 1) != 0 || !dma_fence_test_task(index + 1) { dma_fence_test_fail(1) }
	katomic.store(mut &dmafence_test_ledger.ready[index], true)
	for !katomic.load(&dmafence_test_ledger.quit) {
		command := katomic.load(&dmafence_test_ledger.commands[index])
		if command == 0 { sched.reschedule(); continue }
		katomic.store(mut &dmafence_test_ledger.started[index], true)
		if command == 1 {
			dmafence_test_ledger.results[index] = C.vinix_linuxkpi_dmafence_fixture_wait(
				dmafence_test_ledger.fences[index], dmafence_test_ledger.wait_modes[index],
				dmafence_test_ledger.intr[index], dmafence_test_ledger.timeouts[index])
		} else if command == 2 {
			dmafence_test_ledger.results[index] = C.vinix_linuxkpi_dmafence_fixture_any(
				unsafe { &dmafence_test_ledger.any[0] }, dmafence_test_ledger.any_count,
				dmafence_test_ledger.intr[index], dmafence_test_ledger.timeouts[index],
				unsafe { &dmafence_test_ledger.indices[index] })
		} else if command == 3 {
			preempt_disable()
			preempt_disable()
			katomic.store(mut &dmafence_test_ledger.reader_held, true)
			started := dmafence_clock.nanoseconds()
			for !katomic.load(&dmafence_test_ledger.reader_release) {
				spin_wait()
				if dmafence_clock.nanoseconds() - started >= dmafence_test_timeout_ns {
					lib.kpanic(unsafe { nil }, c'linuxkpi: DMA fence implicit reader deadline')
				}
			}
			preempt_enable()
			preempt_enable()
		} else if command == 5 {
			// Keep a real owner current while the target IRQ invokes the OOM
			// injection helper; an interrupt of the idle loop has no Thread.
			preempt_disable()
			katomic.store(mut &dmafence_test_ledger.irq_target_held, true)
			started := dmafence_clock.nanoseconds()
			for !katomic.load(&dmafence_test_ledger.irq_done) {
				spin_wait()
				if dmafence_clock.nanoseconds() - started >= dmafence_test_timeout_ns {
					lib.kpanic(unsafe { nil }, c'linuxkpi: DMA fence target IRQ deadline')
				}
			}
			preempt_enable()
		} else { C.vinix_linuxkpi_rcu_fixture_barrier() }
		if !dma_fence_test_task(index + 1) { dma_fence_test_fail(2) }
		katomic.store(mut &dmafence_test_ledger.commands[index], u32(0))
		katomic.store(mut &dmafence_test_ledger.done[index], true)
	}
	event.pthread_exit(unsafe { nil })
}
fn dma_fence_test_name(_fence &C.dma_fence) C.vdf_test_const_char_p {
	mut name := C.vdf_test_const_char_p{}
	text := unsafe { &char(c'vinix-dma-fence-test') }
	unsafe { C.memcpy(&name, &text, sizeof(voidptr)) }
	return name
}
fn dma_fence_test_enable(fence &C.dma_fence) bool {
	node := unsafe { &DmaFenceTestNode(fence) }
	katomic.inc(mut &dmafence_test_ledger.enables)
	return node.mode & 1 == 0
}
fn dma_fence_test_signaled(fence &C.dma_fence) bool {
	node := unsafe { &DmaFenceTestNode(fence) }
	return node.mode & 2 != 0
}
fn dma_fence_test_custom_wait(fence &C.dma_fence, intr bool, timeout i64) i64 {
	node := unsafe { &DmaFenceTestNode(fence) }
	dmafence_test_ledger.custom_intr = intr
	dmafence_test_ledger.custom_timeout = timeout
	katomic.inc(mut &dmafence_test_ledger.custom_waits)
	return node.wait_result
}
fn dma_fence_test_release(fence &C.dma_fence) {
	node := unsafe { &DmaFenceTestNode(fence) }
	if node.magic != 0x646d612d66656e63 { dma_fence_test_fail(4) }
	C.kfree(node)
	// The custom release has already destroyed the complete fence owner.
	katomic.inc(mut &dmafence_test_ledger.custom_releases)
}
fn dma_fence_test_deadline(_fence &C.dma_fence, deadline C.vdf_test_ktime_t) {
	unsafe { C.memcpy(&dmafence_test_ledger.deadline, &deadline, 8) }
}
fn dma_fence_test_callback(_fence &C.dma_fence, callback &C.dma_fence_cb) {
	node := unsafe { &DmaFenceTestCallback(callback) }
	if cpu.interrupt_state() || may_sleep() { dma_fence_test_fail(8) }
	self_free := node.self_free
	katomic.inc(mut &dmafence_test_ledger.callback_calls)
	if self_free {
		C.kfree(node)
		katomic.inc(mut &dmafence_test_ledger.callback_frees)
	}
}
fn dma_fence_test_irq(_work &C.irq_work) {
	local := cpulocal.current()
	if cpu.interrupt_state() || local.maskable_irq_depth == 0 || local.cpu_number != 3 { dma_fence_test_fail(16) }
	test_alloc_oom(0)
	ret := C.vinix_linuxkpi_dmafence_fixture_signal(dmafence_test_ledger.irq_fence, 0, 0)
	// Direct default_wait has an original already-signaled fast return, even
	// from this real IRQ. It must preserve the positive timeout without sleep.
	fast := C.vinix_linuxkpi_dmafence_fixture_wait(dmafence_test_ledger.irq_fence, 0, false, 100)
	valid := !cpu.interrupt_state() && proc.current_thread().linuxkpi_alloc_fail_after == 0
	test_alloc_oom(-1)
	if ret != 0 || fast != 100 || !valid { dma_fence_test_fail(32) }
	katomic.store(mut &dmafence_test_ledger.irq_done, true)
}
fn dma_fence_test_ops() {
	dmafence_test_ledger.ops[0] = C.vinix_dmafence_ops{
		use_64bit_seqno: true
		get_driver_name: dma_fence_test_name
		get_timeline_name: dma_fence_test_name
	}
	dmafence_test_ledger.ops[1] = C.vinix_dmafence_ops{
		use_64bit_seqno: true
		get_driver_name: dma_fence_test_name
		get_timeline_name: dma_fence_test_name
		enable_signaling: dma_fence_test_enable
		signaled: dma_fence_test_signaled
		release: dma_fence_test_release
		set_deadline: dma_fence_test_deadline
	}
	dmafence_test_ledger.ops[2] = dmafence_test_ledger.ops[1]
	dmafence_test_ledger.ops[2].@wait = dma_fence_test_custom_wait
}
fn dma_fence_test_new(kind u32, mode u32, context u64, seqno u64) &DmaFenceTestNode {
	mut node := unsafe { &DmaFenceTestNode(C.kzalloc(sizeof(DmaFenceTestNode), 3264)) }
	if node == unsafe { nil } { return node }
	node.mode = mode
	node.magic = 0x646d612d66656e63
	C.vinix_linuxkpi_dmafence_fixture_init(node, unsafe { &dmafence_test_ledger.ops[kind] }, unsafe { &node.guard }, context, seqno)
	return node
}
fn dma_fence_test_start(index u32, command u32, fence voidptr, mode u32, intr bool, timeout i64) {
	dmafence_test_ledger.fences[index] = fence
	dmafence_test_ledger.wait_modes[index] = mode
	dmafence_test_ledger.intr[index] = intr
	dmafence_test_ledger.timeouts[index] = timeout
	dmafence_test_ledger.results[index] = -9999
	dmafence_test_ledger.indices[index] = 0xffffffff
	katomic.store(mut &dmafence_test_ledger.started[index], false)
	katomic.store(mut &dmafence_test_ledger.done[index], false)
	katomic.store(mut &dmafence_test_ledger.commands[index], command)
}
fn dma_fence_test_parked(index u32, expected u32) bool {
	owner := unsafe { &proc.Thread(dmafence_test_ledger.owners[index]) }
	started := dmafence_clock.nanoseconds()
	for !(katomic.load(&dmafence_test_ledger.started[index])
		&& C.vinix_linuxkpi_dmafence_fixture_task_state(unsafe { &owner.linuxkpi_task[0] }) == expected
		&& !katomic.load(&owner.is_in_queue) && katomic.load(&owner.running_on) == u64(-1)
		&& !katomic.load(&owner.is_in_queue)) {
		if katomic.load(&dmafence_test_ledger.done[index]) || katomic.load(&dmafence_test_ledger.failures) != 0
			|| dmafence_clock.nanoseconds() - started >= dmafence_test_timeout_ns { return false }
		sched.reschedule()
	}
	return true
}
fn dma_fence_test_finish(index u32) {
	if !dma_fence_test_wait(&dmafence_test_ledger.done[index], true) {
		lib.kpanic(unsafe { nil }, c'linuxkpi: DMA fence actor cleanup deadline')
	}
	dmafence_test_ledger.fences[index] = unsafe { nil }
}

fn dma_fence_test_basics() bool {
	context := C.vinix_linuxkpi_dmafence_fixture_context(2)
	node := dma_fence_test_new(1, 0, context, 2)
	if node == unsafe { nil } { return false }
	defer {
		// Also dispatch an already-registered self-free callback on failures.
		C.vinix_linuxkpi_dmafence_fixture_signal(node, 0, 0)
		C.vinix_linuxkpi_dmafence_fixture_put(node)
	}
	other := dma_fence_test_new(1, 0, context, 1)
	if other == unsafe { nil } { return false }
	defer { C.vinix_linuxkpi_dmafence_fixture_put(other) }
	if C.vinix_linuxkpi_dmafence_fixture_context(1) != context + 2
		|| C.vinix_linuxkpi_dmafence_fixture_status(node) != 0
		|| C.vinix_linuxkpi_dmafence_fixture_wait(node, 0, false, 0) != 0
		|| !C.vinix_linuxkpi_dmafence_fixture_compare(node, other, 0)
		|| !C.vinix_linuxkpi_dmafence_fixture_compare(node, node, 1)
		|| !C.vinix_linuxkpi_dmafence_fixture_compare(node, other, 2) { return false }
	for mode in 0 .. 3 {
		preempt_disable()
		got := C.vinix_linuxkpi_dmafence_fixture_get(node, u32(mode))
		preempt_enable()
		if got != voidptr(node) { return false }
		C.vinix_linuxkpi_dmafence_fixture_put(got)
	}
	C.vinix_linuxkpi_dmafence_fixture_deadline(node, 1234567)
	if dmafence_test_ledger.deadline != 1234567 { return false }
	mut callback := unsafe { &DmaFenceTestCallback(C.kzalloc(sizeof(DmaFenceTestCallback), 3264)) }
	if callback == unsafe { nil } { return false }
	callback.self_free = true
	if C.vinix_linuxkpi_dmafence_fixture_add(node, callback, dma_fence_test_callback) != 0 { C.kfree(callback); return false }
	// Ownership of callback ends when the fence's signal path invokes it.
	removed := unsafe { &dmafence_test_ledger.callbacks[0] }
	if C.vinix_linuxkpi_dmafence_fixture_add(node, removed, dma_fence_test_callback) != 0 { return false }
	if !C.vinix_linuxkpi_dmafence_fixture_remove(node, removed)
		|| C.vinix_linuxkpi_dmafence_fixture_remove(node, removed) { return false }
	before := katomic.load(&dmafence_test_ledger.enables)
	C.vinix_linuxkpi_dmafence_fixture_enable(node)
	C.vinix_linuxkpi_dmafence_fixture_enable(node)
	if katomic.load(&dmafence_test_ledger.enables) != before { return false }
	C.vinix_linuxkpi_dmafence_fixture_error(node, -5)
	if C.vinix_linuxkpi_dmafence_fixture_signal(node, 3, 998877) != 0
		|| C.vinix_linuxkpi_dmafence_fixture_status(node) != -5
		|| C.vinix_linuxkpi_dmafence_fixture_timestamp(node) != 998877
		|| C.vinix_linuxkpi_dmafence_fixture_signal(node, 0, 0) != -22
		|| C.vinix_linuxkpi_dmafence_fixture_add(node, removed, dma_fence_test_callback) != -2
		|| C.vinix_linuxkpi_dmafence_fixture_wait(node, 0, true, 0) != 1 { return false }
	return true
}
fn dma_fence_test_custom() bool {
	context := C.vinix_linuxkpi_dmafence_fixture_context(3)
	first := dma_fence_test_new(1, 1, context, 0)
	if first == unsafe { nil } { return false }
	defer { C.vinix_linuxkpi_dmafence_fixture_put(first) }
	before := katomic.load(&dmafence_test_ledger.enables)
	C.vinix_linuxkpi_dmafence_fixture_enable(first)
	C.vinix_linuxkpi_dmafence_fixture_enable(first)
	if C.vinix_linuxkpi_dmafence_fixture_status(first) != 1
		|| katomic.load(&dmafence_test_ledger.enables) != before + 1 { return false }
	second := dma_fence_test_new(1, 2, context + 1, 0)
	if second == unsafe { nil } { return false }
	defer { C.vinix_linuxkpi_dmafence_fixture_put(second) }
	if !C.vinix_linuxkpi_dmafence_fixture_signaled(second, true)
		|| C.vinix_linuxkpi_dmafence_fixture_status(second) != 1 { return false }
	mut third := dma_fence_test_new(2, 0, context + 2, 0)
	if third == unsafe { nil } { return false }
	defer { C.vinix_linuxkpi_dmafence_fixture_put(third) }
	third.wait_result = -7
	return C.vinix_linuxkpi_dmafence_fixture_wait(third, 1, true, 17) == -7
		&& katomic.load(&dmafence_test_ledger.custom_waits) != 0
		&& dmafence_test_ledger.custom_intr && dmafence_test_ledger.custom_timeout == 17
}
fn dma_fence_test_stubs() bool {
	first := C.vinix_linuxkpi_dmafence_fixture_stub(false, 0)
	if first == unsafe { nil } { return false }
	defer { C.vinix_linuxkpi_dmafence_fixture_put(first) }
	second := C.vinix_linuxkpi_dmafence_fixture_stub(false, 0)
	if second != first { C.vinix_linuxkpi_dmafence_fixture_put(second); return false }
	C.vinix_linuxkpi_dmafence_fixture_put(second)
	test_alloc_oom(0)
	missing := C.vinix_linuxkpi_dmafence_fixture_stub(true, 111)
	test_alloc_oom(-1)
	if missing != unsafe { nil } { C.vinix_linuxkpi_dmafence_fixture_put(missing); return false }
	private := C.vinix_linuxkpi_dmafence_fixture_stub(true, 123456789)
	if private == unsafe { nil } { return false }
	defer { C.vinix_linuxkpi_dmafence_fixture_put(private) }
	return C.vinix_linuxkpi_dmafence_fixture_status(first) == 1
		&& C.vinix_linuxkpi_dmafence_fixture_status(private) == 1
		&& C.vinix_linuxkpi_dmafence_fixture_timestamp(private) == 123456789
}
fn dma_fence_test_waits() bool {
	node := dma_fence_test_new(1, 0, C.vinix_linuxkpi_dmafence_fixture_context(1), 0)
	if node == unsafe { nil } { return false }
	mut active := false
	defer {
		if active { C.vinix_linuxkpi_dmafence_fixture_signal(node, 0, 0); dma_fence_test_finish(0) }
		test_task_signal(dmafence_test_ledger.owners[0], 0)
		C.vinix_linuxkpi_dmafence_fixture_put(node)
	}
	dma_fence_test_start(0, 1, node, 0, false, 4)
	active = true
	if !dma_fence_test_wait(&dmafence_test_ledger.done[0], false) { return false }
	active = false
	if dmafence_test_ledger.results[0] != 0 || C.vinix_linuxkpi_dmafence_fixture_callbacks(node) != 0 { return false }
	dma_fence_test_start(0, 1, node, 0, true, dmafence_test_infinite)
	active = true
	if !dma_fence_test_parked(0, 1) { return false }
	test_task_signal(dmafence_test_ledger.owners[0], u64(1) << 14)
	if !dma_fence_test_wait(&dmafence_test_ledger.done[0], false) { return false }
	active = false
	test_task_signal(dmafence_test_ledger.owners[0], 0)
	if dmafence_test_ledger.results[0] != -512 || C.vinix_linuxkpi_dmafence_fixture_callbacks(node) != 0 { return false }
	dma_fence_test_start(0, 1, node, 0, false, 1000)
	active = true
	if !dma_fence_test_parked(0, 2) { return false }
	// An ordinary native wake without signaling must not satisfy the fence.
	owner := unsafe { &proc.Thread(dmafence_test_ledger.owners[0]) }
	if !sched.enqueue_thread(owner, true) || !dma_fence_test_parked(0, 2)
		|| katomic.load(&dmafence_test_ledger.done[0]) { return false }
	if C.vinix_linuxkpi_dmafence_fixture_signal(node, 1, 0) != 0
		|| !dma_fence_test_wait(&dmafence_test_ledger.done[0], false) { return false }
	active = false
	if dmafence_test_ledger.results[0] <= 0 || dmafence_test_ledger.results[0] > 1000 { return false }
	// The original dma_fence_wait wrapper maps an infinite successful result to0.
	return C.vinix_linuxkpi_dmafence_fixture_wait(node, 2, false, 0) == 0
}
fn dma_fence_test_irq_wait() bool {
	node := dma_fence_test_new(1, 0, C.vinix_linuxkpi_dmafence_fixture_context(1), 0)
	if node == unsafe { nil } { return false }
	mut active := false
	mut queued := false
	mut target_active := false
	defer {
		if queued { C.vinix_linuxkpi_irqwork_fixture_sync(unsafe { &dmafence_test_ledger.irq }) }
		katomic.store(mut &dmafence_test_ledger.irq_done, true)
		if target_active { dma_fence_test_finish(2) }
		C.vinix_linuxkpi_dmafence_fixture_signal(node, 0, 0)
		if active { dma_fence_test_finish(0) }
		dmafence_test_ledger.irq_fence = unsafe { nil }
		C.vinix_linuxkpi_dmafence_fixture_put(node)
	}
	mut callback := unsafe { &DmaFenceTestCallback(C.kzalloc(sizeof(DmaFenceTestCallback), 3264)) }
	if callback == unsafe { nil } { return false }
	callback.self_free = true
	if C.vinix_linuxkpi_dmafence_fixture_add(node, callback, dma_fence_test_callback) != 0 { C.kfree(callback); return false }
	dma_fence_test_start(2, 5, unsafe { nil }, 0, false, 0)
	target_active = true
	if !dma_fence_test_wait(&dmafence_test_ledger.irq_target_held, false) { return false }
	dma_fence_test_start(0, 1, node, 1, false, dmafence_test_infinite)
	active = true
	if !dma_fence_test_parked(0, 2) { return false }
	dmafence_test_ledger.irq_fence = node
	if C.vinix_linuxkpi_irqwork_fixture_init(unsafe { &dmafence_test_ledger.irq }, dma_fence_test_irq, 8) != 0 { return false }
	test_alloc_oom(0)
	ints := cpu.interrupt_toggle(false)
	accepted := C.vinix_linuxkpi_irqwork_fixture_queue(unsafe { &dmafence_test_ledger.irq }, 3)
	valid := !cpu.interrupt_state() && proc.current_thread().linuxkpi_alloc_fail_after == 0
	cpu.interrupt_toggle(ints)
	test_alloc_oom(-1)
	queued = accepted
	if !accepted || !valid || !dma_fence_test_wait(&dmafence_test_ledger.irq_done, false)
		|| !dma_fence_test_wait(&dmafence_test_ledger.done[0], false) { return false }
	active = false
	return dmafence_test_ledger.results[0] == dmafence_test_infinite
}
fn dma_fence_test_any() bool {
	mut nodes := unsafe { [3]&DmaFenceTestNode{} }
	mut allocated := 0
	mut active := false
	defer {
		if active {
			for index in 0 .. allocated { C.vinix_linuxkpi_dmafence_fixture_signal(nodes[index], 0, 0) }
			dma_fence_test_finish(0)
		}
		test_task_signal(dmafence_test_ledger.owners[0], 0)
		for index in 0 .. allocated { C.vinix_linuxkpi_dmafence_fixture_put(nodes[index]); dmafence_test_ledger.any[index] = unsafe { nil } }
	}
	for index in 0 .. 3 {
		nodes[index] = dma_fence_test_new(1, 0, C.vinix_linuxkpi_dmafence_fixture_context(1), 0)
		if nodes[index] == unsafe { nil } { return false }
		allocated++
		dmafence_test_ledger.any[index] = nodes[index]
	}
	dmafence_test_ledger.any_count = 3
	mut result_index := u32(0xffffffff)
	test_alloc_oom(0)
	missing := C.vinix_linuxkpi_dmafence_fixture_any(unsafe { &dmafence_test_ledger.any[0] }, 3, false, 100, unsafe { &result_index })
	test_alloc_oom(-1)
	if missing != -12 { return false }
	for index in 0 .. 3 { if C.vinix_linuxkpi_dmafence_fixture_callbacks(nodes[index]) != 0 { return false } }
	dma_fence_test_start(0, 2, unsafe { nil }, 0, false, 4)
	active = true
	if !dma_fence_test_wait(&dmafence_test_ledger.done[0], false) { return false }
	active = false
	if dmafence_test_ledger.results[0] != 0 { return false }
	for index in 0 .. 3 { if C.vinix_linuxkpi_dmafence_fixture_callbacks(nodes[index]) != 0 { return false } }
	dma_fence_test_start(0, 2, unsafe { nil }, 0, true, 1000)
	active = true
	if !dma_fence_test_parked(0, 1) { return false }
	test_task_signal(dmafence_test_ledger.owners[0], u64(1) << 14)
	if !dma_fence_test_wait(&dmafence_test_ledger.done[0], false) { return false }
	active = false
	test_task_signal(dmafence_test_ledger.owners[0], 0)
	if dmafence_test_ledger.results[0] != -512 { return false }
	for index in 0 .. 3 { if C.vinix_linuxkpi_dmafence_fixture_callbacks(nodes[index]) != 0 { return false } }
	dma_fence_test_start(0, 2, unsafe { nil }, 0, false, 1000)
	active = true
	if !dma_fence_test_parked(0, 2) { return false }
	for index in 0 .. 3 { if C.vinix_linuxkpi_dmafence_fixture_callbacks(nodes[index]) != 1 { return false } }
	if C.vinix_linuxkpi_dmafence_fixture_signal(nodes[1], 2, 445566) != 0
		|| !dma_fence_test_wait(&dmafence_test_ledger.done[0], false) { return false }
	active = false
	if dmafence_test_ledger.results[0] <= 0 || dmafence_test_ledger.indices[0] != 1 { return false }
	for index in 0 .. 3 { if C.vinix_linuxkpi_dmafence_fixture_callbacks(nodes[index]) != 0 { return false } }
	// Positive waits allocate before discovering an already-signaled member;
	// the zero-time query uses the original allocation-free fast path.
	test_alloc_oom(0)
	positive_oom := C.vinix_linuxkpi_dmafence_fixture_any(unsafe { &dmafence_test_ledger.any[0] }, 3, false, 100, unsafe { &result_index })
	zero_oom := C.vinix_linuxkpi_dmafence_fixture_any(unsafe { &dmafence_test_ledger.any[0] }, 3, false, 0, unsafe { &result_index })
	test_alloc_oom(-1)
	if positive_oom != -12 || zero_oom != 1 || result_index != 1 { return false }
	// Replace the completed middle entry with an unsignaled fence whose first
	// enable returns false. Adding callbacks publishes entry0 before entry1
	// ends registration, so successful cleanup must detach that earlier link.
	C.vinix_linuxkpi_dmafence_fixture_put(nodes[1])
	nodes[1] = dma_fence_test_new(1, 1, C.vinix_linuxkpi_dmafence_fixture_context(1), 0)
	if nodes[1] == unsafe { nil } {
		// The original put accepts NULL, so the three-slot cleanup remains safe.
		return false
	}
	dmafence_test_ledger.any[1] = nodes[1]
	dma_fence_test_start(0, 2, unsafe { nil }, 0, false, 1000)
	active = true
	if !dma_fence_test_wait(&dmafence_test_ledger.done[0], false) { return false }
	active = false
	return dmafence_test_ledger.results[0] > 0 && dmafence_test_ledger.indices[0] == 1
		&& C.vinix_linuxkpi_dmafence_fixture_callbacks(nodes[0]) == 0
		&& C.vinix_linuxkpi_dmafence_fixture_callbacks(nodes[2]) == 0
}
fn dma_fence_test_deferred() bool {
	node := dma_fence_test_new(0, 0, C.vinix_linuxkpi_dmafence_fixture_context(1), 0)
	if node == unsafe { nil } { return false }
	mut released := false
	mut direct_freed := false
	mut direct := unsafe { &DmaFenceTestNode(nil) }
	mut reader := false
	mut barrier := false
	defer {
		katomic.store(mut &dmafence_test_ledger.reader_release, true)
		if reader { dma_fence_test_finish(2) }
		if barrier { dma_fence_test_finish(1) }
		if !released { C.vinix_linuxkpi_dmafence_fixture_put(node) }
		if !direct_freed && direct != unsafe { nil } { C.vinix_linuxkpi_dmafence_fixture_put(direct) }
		C.vinix_linuxkpi_rcu_fixture_barrier()
	}
	direct = dma_fence_test_new(0, 0, C.vinix_linuxkpi_dmafence_fixture_context(1), 0)
	if direct == unsafe { nil } { return false }
	dma_fence_test_start(2, 3, unsafe { nil }, 0, false, 0)
	reader = true
	if !dma_fence_test_wait(&dmafence_test_ledger.reader_held, false) { return false }
	held := memory.free_bytes()
	force := C.vinix_linuxkpi_rcu_test_force_count()
	test_alloc_oom(0)
	ints := cpu.interrupt_toggle(false)
	C.vinix_linuxkpi_dmafence_fixture_put(node)
	released = true
	// The public free service itself owns this distinct page-backed base.
	C.vinix_linuxkpi_dmafence_fixture_free(direct)
	direct_freed = true
	valid := !cpu.interrupt_state() && proc.current_thread().linuxkpi_alloc_fail_after == 0
	cpu.interrupt_toggle(ints)
	test_alloc_oom(-1)
	// Refcount-zero storage remains backed while the genuine implicit reader
	// is held. get_rcu may inspect that count but must never resurrect it.
	preempt_disable()
	dead := C.vinix_linuxkpi_dmafence_fixture_get(node, 1) == unsafe { nil }
	valid_magic := node.magic == 0x646d612d66656e63
	preempt_enable()
	if !valid || !dead || !valid_magic { return false }
	dma_fence_test_start(1, 4, unsafe { nil }, 0, false, 0)
	barrier = true
	if !dma_fence_test_parked(1, 2) { return false }
	started := dmafence_clock.nanoseconds()
	for C.vinix_linuxkpi_rcu_test_force_count() == force {
		if dmafence_clock.nanoseconds() - started >= dmafence_test_timeout_ns { return false }
		sched.reschedule()
	}
	if memory.free_bytes() != held || katomic.load(&dmafence_test_ledger.done[1]) { return false }
	katomic.store(mut &dmafence_test_ledger.reader_release, true)
	// No pointer access follows release of the protecting reader scope.
	return dma_fence_test_wait(&dmafence_test_ledger.done[2], false)
		&& dma_fence_test_wait(&dmafence_test_ledger.done[1], false)
}
fn dma_fence_test_lifecycle() bool {
	ints := cpu.interrupt_toggle(false)
	mut controller := proc.current_thread()
	affinity := katomic.load(&controller.affinity_mask)
	numa := katomic.load(&controller.numa_node)
	gate := controller.linuxkpi_alloc_fail_after
	cpu.interrupt_toggle(ints)
	mut owners := unsafe { [3]&proc.Thread{} }
	mut created := 0
	defer {
		katomic.store(mut &dmafence_test_ledger.reader_release, true)
		katomic.store(mut &dmafence_test_ledger.quit, true)
		for index in 0 .. created { irq_test_join(owners[index]) }
		C.vinix_linuxkpi_rcu_fixture_barrier()
		selftest_free_baseline()
		restore := cpu.interrupt_toggle(false)
		controller.linuxkpi_alloc_fail_after = gate
		katomic.store(mut &controller.numa_node, numa)
		katomic.store(mut &controller.affinity_mask, affinity)
		cpu.interrupt_toggle(restore)
	}
	if !ints || worker_bind(0) != 0 { return false }
	dmafence_test_ledger = DmaFenceTestLedger{}
	dma_fence_test_ops()
	if !dma_fence_test_basics() || !dma_fence_test_custom() || !dma_fence_test_stubs() { return false }
	// Isolate the later held-reader measurement from the private stub's free.
	C.vinix_linuxkpi_rcu_fixture_barrier()
	for index in 0 .. 3 {
		mut actor := sched.try_new_kernel_thread(voidptr(dma_fence_test_actor), voidptr(index)) or { return false }
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
		dmafence_test_ledger.owners[index] = actor
		created++
	}
	for index in 0 .. 3 { if !dma_fence_test_wait(&dmafence_test_ledger.ready[index], false) { return false } }
	return dma_fence_test_waits() && dma_fence_test_irq_wait()
		&& dma_fence_test_any() && dma_fence_test_deferred()
}
fn dma_fence_native_selftest() bool {
	if cpu_locals.len < 4 || cpu_locals.len > 64
		|| C.vinix_linuxkpi_dmafence_fixture_bytes(0) != 64
		|| C.vinix_linuxkpi_dmafence_fixture_bytes(1) != 24
		|| C.vinix_linuxkpi_dmafence_fixture_bytes(2) != 80 { return false }
	for round in 0 .. 3 {
		before := selftest_free_baseline()
		if !dma_fence_test_lifecycle() { return false }
		C.kprintf(c'linuxkpi: DMA fence lifecycle warmup %d free-byte baseline=%llu after=%llu\n', round + 1, before, selftest_free_baseline())
	}
	mut before := CPUFeatureHeapSnapshot{}
	mut after := CPUFeatureHeapSnapshot{}
	free_before := selftest_free_baseline()
	if !cpu_feature_test_heap(unsafe { &before }) || !dma_fence_test_lifecycle() { return false }
	free_after := selftest_free_baseline()
	if !cpu_feature_test_heap(unsafe { &after }) { return false }
	mut equal := before.count == after.count
	for index in 0 .. before.count {
		if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] {
			equal = false
			C.kprintf(c'linuxkpi: DMA fence heap class %d size_before=%llu size_after=%llu live_before=%llu live_after=%llu\n',
				index, before.sizes[index], after.sizes[index], before.live[index], after.live[index])
		}
	}
	C.kprintf(c'linuxkpi: DMA fence fourth lifecycle free-byte baseline=%llu after=%llu heap_equal=%d\n', free_before, free_after, int(equal))
	return free_before == free_after && equal && katomic.load(&dmafence_test_ledger.failures) == 0
}
