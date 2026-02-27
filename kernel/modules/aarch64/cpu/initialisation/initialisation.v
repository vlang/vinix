module initialisation

import aarch64.cpu
import aarch64.cpu.local as cpulocal
import limine
import memory
import katomic
import sched

pub fn initialise(smp_info &limine.LimineSMPInfo) {
	mut cpu_local := unsafe { &cpulocal.Local(smp_info.extra_argument) }
	cpu_number := cpu_local.cpu_number

	// Set TPIDR_EL1 to cpu_number for per-CPU data access
	cpu.write_tpidr_el1(cpu_number)

	// Switch to kernel page tables
	kernel_pagemap.switch_to()

	// Configure timer frequency
	cpu_local.timer_freq = cpu.read_cntfrq_el0()

	// FPU is not used in kernel (mgeneral-regs-only), just set defaults
	fpu_storage_size = 512
	fpu_save = cpu.dummy_fpu_save
	fpu_restore = cpu.dummy_fpu_restore

	print('smp: CPU ${cpu_local.cpu_number} online!\n')

	katomic.inc(mut &cpu_local.online)

	if cpu_number != 0 {
		for katomic.load(&scheduler_vector) == 0 {}
		sched.await()
	}
}
