// SPDX-License-Identifier: GPL-2.0-or-later
module linuxkpi

import memory
import katomic
import x86.cpu
import x86.cpu.local as cpulocal

struct CPUFeatureHeapSnapshot {
mut:
	count int
	sizes [64]u64
	live  [64]u64
}

fn cpu_feature_test_heap(snapshot &CPUFeatureHeapSnapshot) bool {
	$if linuxkpi ? {
		mut output := unsafe { snapshot }
		mut classes := [64]memory.HeapClass{}
		count := memory.heap_classes_into(unsafe { &classes[0] }, classes.len)
		if count < 0 || count > output.live.len { return false }
		output.count = count
		for i in 0 .. count {
			output.sizes[i] = classes[i].size
			output.live[i] = classes[i].live
		}
		return true
	} $else {
		return false
	}
}

fn cpu_feature_test_queries(expected u32) bool {
	for _ in 0 .. 10000 {
		if cpu_has(feature_movdiri) != (expected & (u32(1) << 27) != 0)
			|| cpu_has(feature_movdir64b) != (expected & (u32(1) << 28) != 0)
			|| cpu_has(feature_hw_shstk) != (boot_infrastructure_bits & (u32(1) << 7) != 0)
			|| cpu_has(feature_active_la57) != (boot_infrastructure_bits & (u32(1) << 16) != 0) {
			return false
		}
	}
	return true
}

fn cpu_feature_test_cycle() bool {
	if !cpu.interrupt_state() { return false }
	mut valid := cpu_feature_test_queries(boot_directstore_bits)
	ints := cpu.interrupt_toggle(false)
	valid = valid && ints
	local := cpulocal.current()
	index := local.cpu_number
	depth := preempt_depth[index]
	// Compare this actual CPU's original boot sample with live hardware while
	// IRQs exclude migration. The policy is an intersection, so it may omit a
	// bit this CPU supports; it may never add one missing from this CPU.
	available, _, _, ecx, _ := cpu.cpuid(7, 0)
	hardware := if available { ecx & directstore_mask } else { u32(0) }
	xsave_available, _, _, xsave_ecx, xsave_edx := cpu.cpuid(1, 0)
	xsaves_available, xsaves_eax, _, _, _ := cpu.cpuid(0xd, 1)
	shstk := available && ecx & (u32(1) << 7) != 0
		&& xsave_available && xsave_ecx & (u32(1) << 26) != 0
		&& xsave_edx & ((u32(1) << 24) | u32(1)) == ((u32(1) << 24) | u32(1))
		&& xsaves_available && xsaves_eax & (u32(1) << 3) != 0
	active_la57 := cpu.read_cr4() & (u64(1) << 12) != 0
	valid = valid && hardware == local.directstore_ecx
		&& boot_directstore_bits & ~hardware == 0
		&& shstk == local.linuxkpi_shstk_supported
		&& (boot_infrastructure_bits & (u32(1) << 7) == 0 || shstk)
		&& active_la57 == local.linuxkpi_la57_active
		&& cpu_has(feature_active_la57) == active_la57
		&& active_la57 == (memory.user_address_limit() == u64(1) << 56)
		&& cpu_feature_test_queries(boot_directstore_bits)
	preempt_disable()
	preempt_disable()
	valid = valid && cpu_feature_test_queries(boot_directstore_bits)
		&& preempt_depth[index] == depth + 2 && !cpu.interrupt_state()
	release_preemption(false)
	release_preemption(false)
	valid = valid && preempt_depth[index] == depth && !cpu.interrupt_state()
	cpu.interrupt_toggle(ints)
	return valid && cpu.interrupt_state()
}

// Query/publication validation, not positive MOVDIR instruction execution.
// This QEMU TCG host does not expose those hardware instructions. No memory
// portal, copied descriptor, callback, worker or task ownership is created.
fn cpu_features_native_selftest() bool {
	if katomic.load(&boot_directstore_ready) != 1
		|| boot_directstore_count != u32(cpu_locals.len)
		|| katomic.load(&boot_infrastructure_ready) != 1
		|| boot_infrastructure_count != u32(cpu_locals.len) {
		return false
	}
	for i in 0 .. 3 {
		before := memory.free_bytes()
		if !cpu_feature_test_cycle() { return false }
		C.kprintf(c'linuxkpi: CPU feature query warmup %lld free-byte baseline=%llu after=%llu\n',
			i64(i + 1), before, memory.free_bytes())
	}
	mut before := CPUFeatureHeapSnapshot{}
	mut after := CPUFeatureHeapSnapshot{}
	if !cpu_feature_test_heap(unsafe { &before }) { return false }
	free_before := memory.free_bytes()
	if !cpu_feature_test_cycle() || !cpu_feature_test_heap(unsafe { &after }) { return false }
	free_after := memory.free_bytes()
	mut equal := before.count == after.count
	for i in 0 .. before.count {
		if before.sizes[i] != after.sizes[i] || before.live[i] != after.live[i] { equal = false }
	}
	C.kprintf(c'linuxkpi: CPU feature fourth query batch free-byte baseline=%llu after=%llu heap_equal=%lld common=%u cpus=%u\n',
		free_before, free_after, i64(equal), boot_directstore_bits, boot_directstore_count)
	C.kprintf(c'linuxkpi: native CPU infrastructure query witness shstk=%u la57=%u geometry=%llu cpus=%u\n',
		u32(cpu_has(feature_hw_shstk)), u32(cpu_has(feature_active_la57)),
		memory.user_address_limit(), boot_infrastructure_count)
	return free_before == free_after && equal
}
