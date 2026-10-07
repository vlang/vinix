// SPDX-License-Identifier: GPL-2.0-or-later
module linuxkpi

import katomic
import lib
import memory
import x86.cpu
import x86.cpu.local as cpulocal

#include "linuxkpi_smp_masks_v_primitives.h"

fn C.vkm_cpu_masks_bootstrap(u32) i32
fn C.vkm_cpu_masks_ready() bool
fn C.vkm_mask_storage(u32) voidptr
fn C.vkm_mask_has(u32, u32) bool
fn C.vkm_mask_weight(u32) u32
fn C.vkm_mask_of_has(u32, u32) bool
fn C.vkm_all_has(u32) bool
fn C.vkm_online_count() u32
fn C.vkm_cpu_ids() u32

// The already-published CPU policy validated every actual native Local and
// its online acknowledgement. Masks describe those installed logical CPUs;
// this is not an inventory of firmware-disabled CPUs or hotplug candidates.
fn initialise_cpu_masks() {
	if katomic.load(&boot_directstore_ready) != 1
		|| boot_directstore_count != u32(cpu_locals.len)
		|| C.vkm_cpu_masks_bootstrap(boot_directstore_count) != 0 {
		lib.kpanic(unsafe { nil }, c'linuxkpi: boot CPU mask publication failed')
	}
}

fn cpu_mask_test_installed(count u32) bool {
	if !C.vkm_cpu_masks_ready() || C.vkm_cpu_ids() != count
		|| C.vkm_online_count() != count { return false }
	for kind in u32(0) .. u32(5) {
		expected_weight := if kind == 4 { u32(0) } else { count }
		if C.vkm_mask_weight(kind) != expected_weight {
			return false
		}
		words := unsafe { &u64(C.vkm_mask_storage(kind)) }
		if words == unsafe { nil } { return false }
		for word in u32(0) .. u32(4) {
			mut expected := u64(0)
			for bit in u32(0) .. u32(64) {
				if kind != 4 && word * 64 + bit < count {
					expected |= u64(1) << bit
				}
			}
			if unsafe { words[word] } != expected { return false }
		}
		for index in u32(0) .. u32(256) {
			if C.vkm_mask_has(kind, index) != (kind != 4 && index < count) {
				return false
			}
		}
		if C.vkm_mask_has(kind, u32(-1)) { return false }
	}
	return C.vkm_mask_storage(5) == unsafe { nil }
		&& !C.vkm_mask_has(5, 0) && C.vkm_mask_weight(5) == 0
}

fn cpu_mask_test_constants(full bool) bool {
	// These are original immutable NR_CPUS-wide masks, not installed CPU IDs.
	// The typed wrappers use original cpumask_of/bitmap primitives, avoiding a
	// cpumask_test_cpu call outside its installed-CPU argument contract.
	for bit in u32(0) .. u32(256) {
		if !C.vkm_all_has(bit) || !C.vkm_mask_of_has(bit, bit) { return false }
		if full {
			for other in u32(0) .. u32(256) {
				if C.vkm_mask_of_has(bit, other) != (bit == other) { return false }
			}
		} else {
			if C.vkm_mask_of_has(bit, (bit + 1) % 256) { return false }
		}
	}
	return !C.vkm_all_has(256) && !C.vkm_all_has(u32(-1))
		&& !C.vkm_mask_of_has(256, 0) && !C.vkm_mask_of_has(0, 256)
}

fn cpu_mask_test_cycle(count u32) bool {
	if !cpu.interrupt_state() { return false }
	mut valid := cpu_mask_test_installed(count) && cpu_mask_test_constants(true)
		&& C.vkm_cpu_masks_bootstrap(0) == -22
		&& C.vkm_cpu_masks_bootstrap(257) == -22
		&& C.vkm_cpu_masks_bootstrap(u32(-1)) == -22
		&& C.vkm_cpu_masks_bootstrap(count) == -114
	ints := cpu.interrupt_toggle(false)
	index := cpulocal.current().cpu_number
	depth := preempt_depth[index]
	valid = valid && cpu_mask_test_installed(count) && cpu_mask_test_constants(false)
		&& !cpu.interrupt_state() && preempt_depth[index] == depth
	preempt_disable()
	preempt_disable()
	valid = valid && cpu_mask_test_installed(count) && cpu_mask_test_constants(false)
		&& C.vkm_cpu_masks_bootstrap(count) == -114
		&& !cpu.interrupt_state() && preempt_depth[index] == depth + 2
	release_preemption(false)
	release_preemption(false)
	valid = valid && !cpu.interrupt_state() && preempt_depth[index] == depth
	cpu.interrupt_toggle(ints)
	return valid && cpu_mask_test_installed(count)
}

fn cpu_masks_native_selftest() bool {
	count := boot_directstore_count
	for i in 0 .. 3 {
		before := memory.free_bytes()
		if !cpu_mask_test_cycle(count) { return false }
		C.kprintf(c'linuxkpi: CPU mask query warmup %lld free-byte baseline=%llu after=%llu\n',
			i64(i + 1), before, memory.free_bytes())
	}
	// Reuse the measured stack snapshot helper; its temporary class array is
	// owned and freed inside each synchronous call. No CPU record is retained.
	mut before := CPUFeatureHeapSnapshot{}
	mut after := CPUFeatureHeapSnapshot{}
	if !cpu_feature_test_heap(unsafe { &before }) { return false }
	free_before := memory.free_bytes()
	if !cpu_mask_test_cycle(count) || !cpu_feature_test_heap(unsafe { &after }) { return false }
	free_after := memory.free_bytes()
	mut equal := before.count == after.count
	for i in 0 .. before.count {
		if before.sizes[i] != after.sizes[i] || before.live[i] != after.live[i] { equal = false }
	}
	C.kprintf(c'linuxkpi: CPU mask fourth query batch free-byte baseline=%llu after=%llu heap_equal=%lld cpus=%u\n',
		free_before, free_after, i64(equal), count)
	return free_before == free_after && equal
}
