@[has_globals]
module smp

import limine
import memory
import katomic
import aarch64.cpu.local as cpulocal
import aarch64.cpu.initialisation as cpuinit

__global (
	smp_ready = false
)

// True when the bootloader was asked to start the other cores and answered.
// The request itself lives in request_d_limine_mp.v, so a build without
// -d limine_mp never asks: see request_notd_limine_mp.v for why.
pub fn available() bool {
	return limine_response() != unsafe { nil }
}

pub fn initialise() {
	if !available() {
		panic('SMP bootloader response missing')
	}
	smp_tag := limine_response()

	println('smp: BSP MPIDR:       ${smp_tag.bsp_mpidr:x}')
	println('smp: Total CPU count: ${smp_tag.cpu_count}')

	smp_info_array := smp_tag.cpus

	for i := u64(0); i < smp_tag.cpu_count; i++ {
		mut cpu_local := unsafe { &cpulocal.Local(memory.malloc(sizeof(cpulocal.Local))) }
		cpu_locals << cpu_local

		mut smp_info := unsafe { smp_info_array[i] }

		smp_info.extra_argument = u64(cpu_local)

		cpu_local.cpu_number = i

		if smp_info.mpidr == smp_tag.bsp_mpidr {
			cpuinit.initialise(smp_info)
			continue
		}

		smp_info.goto_address = cpuinit.initialise

		for katomic.load(&cpu_local.online) == 0 {}
	}

	smp_ready = true

	print('smp: All CPUs online!\n')
}
