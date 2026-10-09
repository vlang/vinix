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
import x86.hpet as smp_hpet_clock

#include "linuxkpi_smp_fixture_v_primitives.h"
#include "linuxkpi_work_irq_fixture_v_primitives.h"

type SmpProbeCallback = fn (voidptr)
type SmpProbeCondition = fn (i32, voidptr) bool
fn C.vinix_linuxkpi_smp_fixture_csd_bytes() u32
fn C.vinix_linuxkpi_smp_fixture_single(i32, SmpProbeCallback, voidptr, i32) i32
fn C.vinix_linuxkpi_smp_fixture_many(SmpProbeCallback, voidptr, bool, SmpProbeCondition)
fn C.vks_smp_async(i32, voidptr) i32
fn C.vks_smp_csd_set_callback(voidptr, SmpProbeCallback, voidptr)
fn C.vinix_linuxkpi_workirq_native_selftest() i32

const smp_probe_cpus = 4
const smp_probe_timeout_ns = u64(10000000000)

struct SmpProbe {
mut:
	ready           bool
	quit            bool
	hold            bool
	held            bool
	allow_irqs      bool
	pause_callback  bool
	resume_callback bool
	free_csd        bool
	csd_owner       voidptr
	sequence        u64
	entered         u64
	terminal        u64
	post_iret       u64
	failures        u64
	expected_cpu    u32
	expected_depth  u32
}

struct SmpManyProbe {
mut:
	mode     u32
	count    u32
	hits     [256]u32
	failures [256]u32
}

struct SmpBatchProbe {
mut:
	next     u32
	count    u32
	failures u32
}

__global (
	smp_probes     [4]SmpProbe
	smp_many_probe SmpManyProbe
	smp_batch_probe SmpBatchProbe
)

fn smp_probe_task(target u32) bool {
	ints := cpu.interrupt_toggle(false)
	local := cpulocal.current()
	valid := ints && local.cpu_number == u64(target) && local.maskable_irq_depth == 0
		&& proc.current_thread() != unsafe { nil } && preempt_depth[local.cpu_number] == 0
	cpu.interrupt_toggle(ints)
	return valid
}

fn smp_probe_actor(argument voidptr) {
	index := u32(usize(argument) - 1)
	mut state := unsafe { &smp_probes[index] }
	if worker_bind(index) != 0 || !smp_probe_task(index) {
		katomic.store(mut &state.failures, u64(1))
	}
	katomic.store(mut &state.ready, true)
	for !katomic.load(&state.quit) {
		if katomic.load(&state.hold) {
			ints := cpu.interrupt_toggle(false)
			katomic.store(mut &state.held, true)
			started := smp_hpet_clock.nanoseconds()
			for !katomic.load(&state.allow_irqs) && !katomic.load(&state.quit) {
				// Native TLB assistance cannot dispatch the pending SMP callback.
				spin_wait()
				if smp_hpet_clock.nanoseconds() - started >= smp_probe_timeout_ns {
					lib.kpanic(unsafe { nil }, c'linuxkpi: held SMP target deadline')
				}
			}
			katomic.store(mut &state.held, false)
			katomic.store(mut &state.hold, false)
			cpu.interrupt_toggle(ints)
		}
		terminal := katomic.load(&state.terminal)
		if terminal > katomic.load(&state.post_iret) {
			// This target TASK must run after the matching callback's final use
			// and real IRET. Another IRQ callback cannot acknowledge this phase.
			if !smp_probe_task(index) { katomic.store(mut &state.failures, u64(2)) }
			katomic.store(mut &state.post_iret, terminal)
		}
		sched.reschedule()
	}
	event.pthread_exit(unsafe { nil })
}

fn smp_probe_callback(argument voidptr) {
	mut state := unsafe { &SmpProbe(argument) }
	sequence := state.sequence
	owner := state.csd_owner
	free_owner := state.free_csd
	pause := state.pause_callback
	if cpu.interrupt_state() || cpulocal.current().cpu_number != u64(state.expected_cpu)
		|| cpulocal.current().maskable_irq_depth != state.expected_depth {
		katomic.store(mut &state.failures, u64(4))
	}
	katomic.store(mut &state.entered, sequence)
	if pause {
		started := smp_hpet_clock.nanoseconds()
		for !katomic.load(&state.resume_callback) {
			spin_wait()
			if smp_hpet_clock.nanoseconds() - started >= smp_probe_timeout_ns {
				lib.kpanic(unsafe { nil }, c'linuxkpi: paused asynchronous SMP callback deadline')
			}
		}
	}
	if free_owner { C.kfree(owner) }
	// After the final release store neither this argument nor its CSD is read.
	katomic.store(mut &state.terminal, sequence)
}

fn smp_probe_wait(index u32, sequence u64, entered bool) bool {
	state := unsafe { &smp_probes[index] }
	started := smp_hpet_clock.nanoseconds()
	for {
		if katomic.load(&state.failures) != 0 { return false }
		value := if entered { katomic.load(&state.entered) } else { katomic.load(&state.post_iret) }
		if value >= sequence { return true }
		if smp_hpet_clock.nanoseconds() - started >= smp_probe_timeout_ns { return false }
		sched.reschedule()
	}
	return false
}

fn smp_probe_many_condition(target i32, _argument voidptr) bool { return target & 1 == 0 }

fn smp_probe_batch_callback(argument voidptr) {
	ordinal := u32(usize(argument) - 1)
	if cpu.interrupt_state() || cpulocal.current().cpu_number != 1
		|| cpulocal.current().maskable_irq_depth == 0 || ordinal != smp_batch_probe.next {
		smp_batch_probe.failures = 1
	}
	smp_batch_probe.next++
	if smp_batch_probe.next == smp_batch_probe.count {
		// All earlier callbacks in this held batch have returned. This callback
		// has no borrowed block/argument read after its terminal publication.
		katomic.store(mut &smp_probes[1].terminal, u64(28))
	}
}

fn smp_probe_many_callback(_argument voidptr) {
	index := u32(cpulocal.current().cpu_number)
	if index >= smp_many_probe.count { lib.kpanic(unsafe { nil }, c'linuxkpi: invalid SMP many fixture CPU') }
	expected_depth := if index == 0 { u32(0) } else { u32(1) }
	if cpu.interrupt_state() || cpulocal.current().maskable_irq_depth != expected_depth {
		smp_many_probe.failures[index] = 1
	}
	smp_many_probe.hits[index]++
}

fn smp_probe_many_calls() bool {
	for mode in u32(0) .. u32(3) {
		smp_many_probe = SmpManyProbe{ mode: mode, count: u32(cpu_locals.len) }
		if mode == 2 {
			C.vinix_linuxkpi_smp_fixture_many(smp_probe_many_callback, unsafe { nil }, true, smp_probe_many_condition)
		} else {
			C.vinix_linuxkpi_smp_fixture_many(smp_probe_many_callback, unsafe { nil }, mode == 1, unsafe { nil })
		}
		for target := u32(0); target < u32(cpu_locals.len); target++ {
			expected := if mode == 0 { target != 0 } else if mode == 1 { true } else { target & 1 == 0 }
			if smp_many_probe.hits[target] != u32(expected) || smp_many_probe.failures[target] != 0 { return false }
		}
	}
	return true
}

fn smp_probe_lifecycle() bool {
	mut owners := unsafe { [4]&proc.Thread{} }
	mut created := 0
	mut controller := proc.current_thread()
	ints := cpu.interrupt_toggle(false)
	affinity := katomic.load(&controller.affinity_mask)
	node := katomic.load(&controller.numa_node)
	cpu.interrupt_toggle(ints)
	defer {
		for index in 0 .. smp_probe_cpus {
			katomic.store(mut &smp_probes[index].allow_irqs, true)
			katomic.store(mut &smp_probes[index].resume_callback, true)
			katomic.store(mut &smp_probes[index].quit, true)
		}
		// Existing independently reviewed IRQ fixture join retains Thread storage
		// until its actual off-stack exit, then drops the final pin and reaps.
		for index in 0 .. created { irq_test_join(owners[index]) }
		selftest_free_baseline()
		restore_ints := cpu.interrupt_toggle(false)
		katomic.store(mut &controller.numa_node, node)
		katomic.store(mut &controller.affinity_mask, affinity)
		cpu.interrupt_toggle(restore_ints)
	}
	for index in 0 .. smp_probe_cpus { smp_probes[index] = SmpProbe{} }
	for index in 0 .. smp_probe_cpus {
		mut actor := sched.try_new_kernel_thread(voidptr(smp_probe_actor), voidptr(usize(index + 1))) or { return false }
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
	if worker_bind(0) != 0 { return false }
	for index in 0 .. smp_probe_cpus {
		started := smp_hpet_clock.nanoseconds()
		for !katomic.load(&smp_probes[index].ready) {
			if smp_hpet_clock.nanoseconds() - started >= smp_probe_timeout_ns { return false }
			sched.reschedule()
		}
		if katomic.load(&smp_probes[index].failures) != 0 { return false }
	}
	for target in u32(0) .. u32(4) {
		mut state := unsafe { &smp_probes[target] }
		state.sequence = 1
		state.expected_cpu = target
		state.expected_depth = if target == 0 { u32(0) } else { u32(1) }
		if C.vinix_linuxkpi_smp_fixture_single(i32(target), smp_probe_callback, state, 1) != 0
			|| !smp_probe_wait(target, 1, false) || !smp_probe_task(0) { return false }
	}
	if !smp_probe_many_calls() { return false }
	// The target disables hardware interrupts while calling the ordinary native
	// spin helper. Queued work must stay pending until its real IF restoration.
	mut held := unsafe { &smp_probes[1] }
	held.sequence = 2
	held.csd_owner = C.kmalloc(32, 3264)
	if held.csd_owner == unsafe { nil } { return false }
	C.memset(held.csd_owner, 0, 32)
	held.free_csd = true
	katomic.store(mut &held.hold, true)
	started := smp_hpet_clock.nanoseconds()
	for !katomic.load(&held.held) {
		if smp_hpet_clock.nanoseconds() - started >= smp_probe_timeout_ns { lib.kpanic(unsafe { nil }, c'linuxkpi: SMP target hold publication deadline') }
		sched.reschedule()
	}
	C.vks_smp_csd_set_callback(held.csd_owner, smp_probe_callback, held)
	if C.vks_smp_async(1, held.csd_owner) != 0 { lib.kpanic(unsafe { nil }, c'linuxkpi: SMP held-target submission failed') }
	observe := smp_hpet_clock.nanoseconds()
	for smp_hpet_clock.nanoseconds() - observe < 2000000 { spin_wait() }
	if katomic.load(&held.entered) != 1 { lib.kpanic(unsafe { nil }, c'linuxkpi: SMP callback bypassed real interrupt deferral') }
	katomic.store(mut &held.allow_irqs, true)
	if !smp_probe_wait(1, 2, false) { lib.kpanic(unsafe { nil }, c'linuxkpi: held-target callback retirement failed') }
	// Repeated remote callbacks free their detached original CSD themselves.
	for round in u64(0) .. u64(24) {
		held.sequence = round + 3
		held.csd_owner = C.kmalloc(32, 3264)
		if held.csd_owner == unsafe { nil } { return false }
		C.memset(held.csd_owner, 0, 32)
		C.vks_smp_csd_set_callback(held.csd_owner, smp_probe_callback, held)
		if C.vks_smp_async(1, held.csd_owner) != 0 { lib.kpanic(unsafe { nil }, c'linuxkpi: SMP self-free submission failed') }
		if !smp_probe_wait(1, held.sequence, false) { lib.kpanic(unsafe { nil }, c'linuxkpi: SMP self-free retirement failed') }
	}
	// Reuse an unlocked CSD on another CPU while its old callback is held. The
	// new callback frees it before the old dispatcher can return from callback.
	mut old := unsafe { &smp_probes[1] }
	mut replacement := unsafe { &smp_probes[2] }
	old.sequence = 27
	old.csd_owner = C.kmalloc(32, 3264)
	if old.csd_owner == unsafe { nil } { return false }
	C.memset(old.csd_owner, 0, 32)
	old.free_csd = false
	old.pause_callback = true
	C.vks_smp_csd_set_callback(old.csd_owner, smp_probe_callback, old)
	if C.vks_smp_async(1, old.csd_owner) != 0 || !smp_probe_wait(1, 27, true) {
		lib.kpanic(unsafe { nil }, c'linuxkpi: SMP overlap publication failed')
	}
	replacement.sequence = 2
	replacement.csd_owner = old.csd_owner
	replacement.free_csd = true
	C.vks_smp_csd_set_callback(replacement.csd_owner, smp_probe_callback, replacement)
	if C.vks_smp_async(2, replacement.csd_owner) != 0 || !smp_probe_wait(2, 2, false) {
		lib.kpanic(unsafe { nil }, c'linuxkpi: SMP overlapping owner retirement failed')
	}
	katomic.store(mut &old.resume_callback, true)
	if !smp_probe_wait(1, 27, false) { lib.kpanic(unsafe { nil }, c'linuxkpi: SMP old callback retirement failed') }
	// More than a fixed ring's worth of original intrusive CSDs coexist while
	// real target IRQs are disabled. The raw owner remains alive through every
	// callback and the target task's matching post-IRET acknowledgement.
	batch_count := u32(2048)
	raw := C.kmalloc(usize(batch_count) * 32 + 31, 3264)
	if raw == unsafe { nil } { return false }
	C.memset(raw, 0, usize(batch_count) * 32 + 31)
	aligned := (usize(raw) + 31) & ~usize(31)
	smp_batch_probe = SmpBatchProbe{ count: batch_count }
	katomic.store(mut &old.allow_irqs, false)
	katomic.store(mut &old.hold, true)
	batch_started := smp_hpet_clock.nanoseconds()
	for !katomic.load(&old.held) {
		if smp_hpet_clock.nanoseconds() - batch_started >= smp_probe_timeout_ns { lib.kpanic(unsafe { nil }, c'linuxkpi: SMP batch hold deadline') }
		sched.reschedule()
	}
	for ordinal := u32(0); ordinal < batch_count; ordinal++ {
		csd := voidptr(aligned + usize(ordinal) * 32)
		C.vks_smp_csd_set_callback(csd, smp_probe_batch_callback, voidptr(usize(ordinal + 1)))
		if C.vks_smp_async(1, csd) != 0 { lib.kpanic(unsafe { nil }, c'linuxkpi: SMP intrusive batch submission failed') }
	}
	if smp_batch_probe.next != 0 { lib.kpanic(unsafe { nil }, c'linuxkpi: SMP batch bypassed hardware IRQ deferral') }
	katomic.store(mut &old.allow_irqs, true)
	if !smp_probe_wait(1, 28, false) || smp_batch_probe.next != batch_count || smp_batch_probe.failures != 0 {
		lib.kpanic(unsafe { nil }, c'linuxkpi: SMP intrusive batch retirement or FIFO failed')
	}
	C.kfree(raw)
	return true
}

fn smp_calls_native_selftest() bool {
	if cpu_locals.len < smp_probe_cpus || C.vinix_linuxkpi_smp_fixture_csd_bytes() != 32 { return false }
	for round in 0 .. 3 {
		before := selftest_free_baseline()
		if !smp_probe_lifecycle() { return false }
		C.kprintf(c'linuxkpi: SMP call lifecycle warmup %d free-byte baseline=%llu after=%llu\n', round + 1, before, selftest_free_baseline())
	}
	mut before := CPUFeatureHeapSnapshot{}
	mut after := CPUFeatureHeapSnapshot{}
	free_before := selftest_free_baseline()
	if !cpu_feature_test_heap(unsafe { &before }) || !smp_probe_lifecycle() { return false }
	free_after := selftest_free_baseline()
	if !cpu_feature_test_heap(unsafe { &after }) { return false }
	mut equal := before.count == after.count
	for index in 0 .. before.count {
		if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] { equal = false }
	}
	C.kprintf(c'linuxkpi: SMP call fourth lifecycle free-byte baseline=%llu after=%llu heap_equal=%d\n', free_before, free_after, int(equal))
	return free_before == free_after && equal
}

fn work_irq_native_selftest() bool {
	for round in 0 .. 3 {
		before := selftest_free_baseline()
		if C.vinix_linuxkpi_workirq_native_selftest() != 0 { return false }
		C.kprintf(c'linuxkpi: work IRQ identity warmup %d free-byte baseline=%llu after=%llu\n', round + 1, before, selftest_free_baseline())
	}
	mut before := CPUFeatureHeapSnapshot{}
	mut after := CPUFeatureHeapSnapshot{}
	free_before := selftest_free_baseline()
	if !cpu_feature_test_heap(unsafe { &before }) || C.vinix_linuxkpi_workirq_native_selftest() != 0 { return false }
	free_after := selftest_free_baseline()
	if !cpu_feature_test_heap(unsafe { &after }) { return false }
	mut equal := before.count == after.count
	for index in 0 .. before.count {
		if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] { equal = false }
	}
	C.kprintf(c'linuxkpi: work IRQ identity fourth lifecycle free-byte baseline=%llu after=%llu heap_equal=%d\n', free_before, free_after, int(equal))
	return free_before == free_after && equal
}
