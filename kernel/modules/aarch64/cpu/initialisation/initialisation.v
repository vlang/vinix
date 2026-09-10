module initialisation

import aarch64.cpu
import aarch64.cpu.local as cpulocal
import limine
import memory
import katomic
import sched

fn C.exception_vectors()

pub fn initialise(smp_info &limine.LimineSMPInfo) {
	mut cpu_local := unsafe { &cpulocal.Local(smp_info.extra_argument) }
	cpu_number := cpu_local.cpu_number

	// Limine deliberately leaves VBAR undefined on every CPU. The BSP installs
	// Vinix's table during early exception setup; APs enter here directly from
	// Limine's parked trampoline and must install the same table themselves
	// before a scheduled EL0 thread can unmask IRQ/FIQ delivery.
	cpu.write_vbar_el1(u64(voidptr(C.exception_vectors)))
	cpu.isb()

	// Set TPIDR_EL1 to cpu_number for per-CPU data access
	cpu.write_tpidr_el1(cpu_number)
	cpu.enable_el0_cache_access()
	cpu.enable_el0_virtual_counter()

	// Switch to kernel page tables
	kernel_pagemap.switch_to()

	// Configure timer frequency
	cpu_local.timer_freq = cpu.read_cntfrq_el0()

	// The kernel itself uses integer registers only, but EL0 NEON/FP state is
	// architectural thread state and must be switched on every CPU.
	cpu.init_fpu_globals()

	print('smp: CPU ${cpu_local.cpu_number} online!\n')

	katomic.inc(mut &cpu_local.online)

	if cpu_number != 0 {
		for katomic.load(&scheduler_vector) == 0 {}
		sched.await()
	}
}
