// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module linuxkpi

import event
import katomic
import proc
import sched
import x86.cpu
import x86.cpu.local as cpulocal
import x86.hpet as cpubug_clock
import x86.msr

#include "linuxkpi_cpu_bug_fixture_v_primitives.h"

fn C.vinix_linuxkpi_cpu_bug_fixture_l1tf() bool
fn C.vinix_linuxkpi_cpu_bug_fixture_bit() u32
fn C.vinix_linuxkpi_cpu_bug_fixture_sleep(i64) i64

// Fixed boot-lifetime publication and observer records. The retained actor
// pointers are forgotten only after the join helper observes off-stack exit.
struct CPUBugTestLedger {
mut:
	ready         [3]bool
	sleep_started [3]bool
	park_seen     [3]bool
	done          [3]bool
	owners        [3]voidptr
	start         bool
	quit          bool
	failures      u32
}

__global cpu_bug_test_ledger CPUBugTestLedger

fn cpu_bug_test_fail(bit u32) {
	for {
		old := katomic.load(&cpu_bug_test_ledger.failures)
		if katomic.cas(mut &cpu_bug_test_ledger.failures, old, old | bit) { return }
	}
}

fn cpu_bug_test_query_batch(expected bool, count u32) bool {
	for _ in u32(0) .. count {
		if C.vinix_linuxkpi_cpu_bug_fixture_l1tf() != expected { return false }
	}
	return true
}

// IF excludes migration while comparing this actual CPU's fresh CPUID/MSR
// observation with its pre-online record. Query policy still means the BSP,
// even when the local sample differs. Sampling and nested queries preserve
// the caller's exact interrupt and preemption state.
fn cpu_bug_test_local(target u32) bool {
	if !cpu.interrupt_state() || cpu.linuxkpi_sample_l1tf() != 0
		|| !cpu.interrupt_state() { return false }
	ints := cpu.interrupt_toggle(false)
	local := cpulocal.current()
	index := local.cpu_number
	depth := preempt_depth[index]
	expected := boot_l1tf_sample == 2
	live := cpu.linuxkpi_sample_l1tf()
	mut valid := ints && index == u64(target) && local.maskable_irq_depth == 0
		&& depth == 0 && live != 0 && live == local.linuxkpi_l1tf_sample
		&& !cpu.interrupt_state() && preempt_depth[index] == depth
		&& cpu_bug_test_query_batch(expected, 32)
	preempt_disable()
	preempt_disable()
	valid = valid && cpu_bug_test_query_batch(expected, 32)
		&& cpu.linuxkpi_sample_l1tf() == live && !cpu.interrupt_state()
		&& preempt_depth[index] == depth + 2
	release_preemption(false)
	release_preemption(false)
	valid = valid && !cpu.interrupt_state() && preempt_depth[index] == depth
	cpu.interrupt_toggle(ints)
	return valid && cpu.interrupt_state()
}

fn cpu_bug_test_actor(argument voidptr) {
	index := u32(usize(argument))
	// Every actor observes every installed CPU through real scheduler routing;
	// no synthetic Local record can substitute for a live sample here.
	for target in u32(0) .. boot_bug_count {
		if worker_bind(target) != 0 || !cpu_bug_test_local(target) {
			cpu_bug_test_fail(1)
			break
		}
		sched.reschedule()
		if !cpu_bug_test_local(target) { cpu_bug_test_fail(2) }
	}
	if worker_bind(index + 1) != 0 || !cpu_bug_test_local(index + 1) {
		cpu_bug_test_fail(4)
	}
	katomic.store(mut &cpu_bug_test_ledger.ready[index], true)
	for !katomic.load(&cpu_bug_test_ledger.start) && !katomic.load(&cpu_bug_test_ledger.quit) {
		sched.reschedule()
	}
	if !katomic.load(&cpu_bug_test_ledger.quit) {
		expected := boot_l1tf_sample == 2
		for cycle in 0 .. 10000 {
			if C.vinix_linuxkpi_cpu_bug_fixture_l1tf() != expected || !cpu.interrupt_state() {
				cpu_bug_test_fail(8)
			}
			if cycle == 5000 {
				katomic.store(mut &cpu_bug_test_ledger.sleep_started[index], true)
				if C.vinix_linuxkpi_cpu_bug_fixture_sleep(100) != 0
					|| !cpu_bug_test_local(index + 1) {
					cpu_bug_test_fail(16)
				}
			} else if cycle % 256 == 0 {
				sched.reschedule()
				if !cpu_bug_test_local(index + 1) { cpu_bug_test_fail(32) }
			}
		}
	}
	katomic.store(mut &cpu_bug_test_ledger.done[index], true)
	for !katomic.load(&cpu_bug_test_ledger.quit) { sched.reschedule() }
	event.pthread_exit(unsafe { nil })
}

fn cpu_bug_test_wait_ready() bool {
	started := cpubug_clock.nanoseconds()
	for {
		mut ready := true
		for i in 0 .. 3 { ready = ready && katomic.load(&cpu_bug_test_ledger.ready[i]) }
		if ready { return katomic.load(&cpu_bug_test_ledger.failures) == 0 }
		if cpubug_clock.nanoseconds() - started >= dmafence_test_timeout_ns { return false }
		sched.reschedule()
	}
	return false
}

fn cpu_bug_test_wait_done() bool {
	started := cpubug_clock.nanoseconds()
	for {
		mut done := true
		for i in 0 .. 3 {
			actor := unsafe { &proc.Thread(cpu_bug_test_ledger.owners[i]) }
			if katomic.load(&cpu_bug_test_ledger.sleep_started[i])
				&& C.vinix_linuxkpi_dmafence_fixture_task_state(unsafe { &actor.linuxkpi_task[0] }) == 2
				&& !katomic.load(&actor.is_in_queue) && katomic.load(&actor.running_on) == u64(-1)
				&& !katomic.load(&actor.is_in_queue) {
				cpu_bug_test_ledger.park_seen[i] = true
			}
			done = done && katomic.load(&cpu_bug_test_ledger.done[i])
		}
		if done {
			return cpu_bug_test_ledger.park_seen[0] && cpu_bug_test_ledger.park_seen[1]
				&& cpu_bug_test_ledger.park_seen[2] && katomic.load(&cpu_bug_test_ledger.failures) == 0
		}
		if cpubug_clock.nanoseconds() - started >= dmafence_test_timeout_ns { return false }
		sched.reschedule()
	}
	return false
}

fn cpu_bug_test_lifecycle() bool {
	ints := cpu.interrupt_toggle(false)
	mut controller := proc.current_thread()
	affinity := katomic.load(&controller.affinity_mask)
	numa := katomic.load(&controller.numa_node)
	cpu.interrupt_toggle(ints)
	mut owners := unsafe { [3]&proc.Thread{} }
	mut created := 0
	defer {
		katomic.store(mut &cpu_bug_test_ledger.quit, true)
		for i in 0 .. created { irq_test_join(owners[i]) }
		selftest_free_baseline()
		restore := cpu.interrupt_toggle(false)
		katomic.store(mut &controller.numa_node, numa)
		katomic.store(mut &controller.affinity_mask, affinity)
		cpu.interrupt_toggle(restore)
	}
	if !ints || worker_bind(0) != 0 || !cpu_bug_test_local(0) { return false }
	cpu_bug_test_ledger = CPUBugTestLedger{}
	for i in 0 .. 3 {
		mut actor := sched.try_new_kernel_thread(voidptr(cpu_bug_test_actor), voidptr(i)) or { return false }
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
		cpu_bug_test_ledger.owners[i] = actor
		created++
	}
	if !cpu_bug_test_wait_ready() { return false }
	katomic.store(mut &cpu_bug_test_ledger.start, true)
	return cpu_bug_test_query_batch(boot_l1tf_sample == 2, 10000) && cpu_bug_test_wait_done()
}

fn cpu_bug_test_witness() bool {
	entry_ints := cpu.interrupt_toggle(false)
	mut controller := proc.current_thread()
	affinity := katomic.load(&controller.affinity_mask)
	numa := katomic.load(&controller.numa_node)
	cpu.interrupt_toggle(entry_ints)
	defer {
		restore := cpu.interrupt_toggle(false)
		katomic.store(mut &controller.numa_node, numa)
		katomic.store(mut &controller.affinity_mask, affinity)
		cpu.interrupt_toggle(restore)
	}
	if !entry_ints { return false }
	if worker_bind(0) != 0 { return false }
	ints := cpu.interrupt_toggle(false)
	defer { cpu.interrupt_toggle(ints) }
	available, max_leaf, vendor_b, vendor_c, vendor_d := cpu.cpuid(0, 0)
	leaf1_available, signature, _, _, _ := cpu.cpuid(1, 0)
	mut leaf7_edx := u32(0)
	if max_leaf >= 7 {
		ok, _, _, _, value := cpu.cpuid(7, 0)
		if !ok { return false }
		leaf7_edx = value
	}
	mut arch_caps := u64(0)
	mut arch_caps_read := false
	if leaf7_edx & (u32(1) << 29) != 0 {
		arch_caps = msr.read_safe(0x10a) or { return false }
		arch_caps_read = true
	}
	sample := cpu.linuxkpi_sample_l1tf()
	query := C.vinix_linuxkpi_cpu_bug_fixture_l1tf()
	if !available || max_leaf < 1 || !leaf1_available || cpulocal.current().cpu_number != 0
		|| sample != boot_l1tf_sample || query != (sample == 2) { return false }
	C.kprintf(c'linuxkpi: native L1TF BSP witness vendor_b=%08x vendor_d=%08x vendor_c=%08x signature=%08x leaf7_edx=%08x arch_caps_read=%u arch_caps=%llu sample=%u query=%u cpus=%u\n',
		vendor_b, vendor_d, vendor_c, signature, leaf7_edx, u32(arch_caps_read), arch_caps,
		sample, u32(query), boot_bug_count)
	return true
}

fn cpu_bugs_native_selftest() bool {
	if cpu_locals.len < 4 || cpu_locals.len > 64 || katomic.load(&boot_bug_ready) != 1
		|| boot_bug_count != u32(cpu_locals.len) || C.vinix_linuxkpi_cpu_bug_fixture_bit() != 722
		|| boot_l1tf_sample != cpu_locals[0].linuxkpi_l1tf_sample { return false }
	for i in 0 .. cpu_locals.len {
		local := cpu_locals[i]
		if local == unsafe { nil } || local.cpu_number != u64(i) || katomic.load(&local.online) != 1
			|| (local.linuxkpi_l1tf_sample != 1 && local.linuxkpi_l1tf_sample != 2) { return false }
	}
	for round in 0 .. 3 {
		before := selftest_free_baseline()
		if !cpu_bug_test_lifecycle() { return false }
		C.kprintf(c'linuxkpi: CPU bug lifecycle warmup %d free-byte baseline=%llu after=%llu\n',
			round + 1, before, selftest_free_baseline())
	}
	mut before := CPUFeatureHeapSnapshot{}
	mut after := CPUFeatureHeapSnapshot{}
	free_before := selftest_free_baseline()
	if !cpu_feature_test_heap(unsafe { &before }) || !cpu_bug_test_lifecycle() { return false }
	free_after := selftest_free_baseline()
	if !cpu_feature_test_heap(unsafe { &after }) { return false }
	mut equal := before.count == after.count
	for i in 0 .. before.count {
		if before.sizes[i] != after.sizes[i] || before.live[i] != after.live[i] {
			equal = false
			C.kprintf(c'linuxkpi: CPU bug heap class %d size_before=%llu size_after=%llu live_before=%llu live_after=%llu\n',
				i, before.sizes[i], after.sizes[i], before.live[i], after.live[i])
		}
	}
	C.kprintf(c'linuxkpi: CPU bug fourth lifecycle free-byte baseline=%llu after=%llu heap_equal=%u\n',
		free_before, free_after, u32(equal))
	return free_before == free_after && equal && katomic.load(&cpu_bug_test_ledger.failures) == 0
		&& cpu_bug_test_witness()
}
