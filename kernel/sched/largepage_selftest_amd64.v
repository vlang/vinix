// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module sched

import katomic
import memory
import proc
import time
import dev.serial
import x86.apic
import x86.cpu.local as cpulocal
import x86.idt

const large_alias = u64(0xffff_d000_0000_0000)
const large_bytes = u64(1) << 21

__global (
	large_probe_vector u8
	large_probe_expected u64
	large_probe_ack u32
)

fn large_probe_isr(_ u32, _ &cpulocal.GPRState) {
	if cpulocal.current().cpu_number != 1
		|| katomic.load(unsafe { &u64(large_alias + page_size) }) != large_probe_expected
		|| katomic.load(unsafe { &u64(large_alias + 2 * page_size) }) != 33 {
		panic('large-page SMP stale translation or neighbor corruption')
	}
	// No alias access follows acknowledgement, including on the final probe.
	katomic.store(mut &large_probe_ack, u32(1))
	apic.lapic_eoi()
}

fn large_probe(value u64) {
	large_probe_expected = value
	katomic.store(mut &large_probe_ack, u32(0))
	katomic.sync()
	apic.lapic_send_ipi(cpu_locals[1].lapic_id, large_probe_vector)
	started := time.monotonic_ns()
	for katomic.load(&large_probe_ack) == 0 {
		if time.monotonic_ns() - started > 10000000000 { panic('large-page SMP probe timeout') }
		reschedule()
	}
	katomic.sync()
}

pub fn selftest_largepage_smp() {
	$if largepage_selftest ? {
		if cpu_locals.len < 2 { panic('large-page SMP fixture needs two CPUs') }
		mut controller := proc.current_thread()
		old_affinity := controller.affinity_mask
		katomic.store(mut &controller.affinity_mask, u64(1))
		for katomic.load(&controller.running_on) != 0 { reschedule() }
		defer { katomic.store(mut &controller.affinity_mask, old_affinity) }
		// 1024 base pages contain at least one aligned, complete 2 MiB span.
		pool := memory.pmm_alloc_fallible(1024)
		if pool == unsafe { nil } { panic('large-page SMP RAM allocation') }
		other := memory.pmm_alloc_fallible(1)
		if other == unsafe { nil } { panic('large-page SMP replacement allocation') }
		physical := (u64(pool) + large_bytes - 1) & ~(large_bytes - 1)
		unsafe {
			*(&u64(physical + higher_half + page_size)) = 17
			*(&u64(physical + higher_half + 2 * page_size)) = 33
			*(&u64(u64(other) + higher_half)) = 29
		}
		if !memory.largepage_test_alias(large_alias, physical) { panic('large-page SMP alias setup') }
		large_probe_vector = idt.allocate_vector()
		interrupt_table[large_probe_vector] = voidptr(large_probe_isr)
		large_probe(17) // CPU 1 warms an actual PS translation and returns idle.
		flags := memory.pte_present | memory.pte_noexec
		mut pagemap := unsafe { &kernel_pagemap }
		pagemap.map_page(large_alias + page_size, u64(other), flags) or { panic('large-page SMP split') }
		large_probe(29) // The old large translation must be gone before this read.
		for round := u64(0); round < 64; round++ {
			pagemap.unmap_page(large_alias + page_size) or { panic('large-page SMP partial unmap') }
			phys := if round & 1 == 0 { physical + page_size } else { u64(other) }
			pagemap.map_page(large_alias + page_size, phys, flags) or { panic('large-page SMP replacement') }
			large_probe(if round & 1 == 0 { u64(17) } else { u64(29) })
		}
		// The probe is acknowledged and will not touch the alias again. Each
		// unmap synchronously invalidates before empty table pages or RAM retire.
		for i := u64(0); i < 512; i++ {
			pagemap.unmap_page(large_alias + i * page_size) or { panic('large-page SMP cleanup') }
		}
		memory.pmm_free(other, 1)
		memory.pmm_free(pool, 1024)
		line := 'VMM: SMP large-page split, remap, neighbor survival and teardown PASS'
		println(line)
		$if prod {
			for i in 0 .. line.len { serial.out(line[i]) }
			serial.out(`\n`)
		}
	}
}
