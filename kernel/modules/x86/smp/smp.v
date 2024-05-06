// smp.v: Core initialization.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module smp

import limine
import memory
import katomic
import x86.cpu.local as cpulocal
import x86.cpu.initialisation as cpuinit

__global (
	bsp_lapic_id = u32(0)
	smp_ready    = false
)

@[cinit]
@[_linker_section: '.requests']
__global (
	volatile smp_req = limine.LimineSMPRequest{
		response: 0
	}
)

pub fn initialise() {
	smp_tag := smp_req.response

	println('smp: BSP LAPIC ID:    ${smp_tag.bsp_lapic_id:x}')
	println('smp: Total CPU count: ${smp_tag.cpu_count}')

	smp_info_array := smp_tag.cpus

	bsp_lapic_id = smp_tag.bsp_lapic_id

	for i := u64(0); i < smp_tag.cpu_count; i++ {
		mut cpu_local := unsafe { &cpulocal.Local(memory.malloc(sizeof(cpulocal.Local))) }
		cpu_locals << cpu_local

		mut smp_info := unsafe { smp_info_array[i] }

		smp_info.extra_argument = u64(cpu_local)

		cpu_local.cpu_number = i

		if smp_info.lapic_id == smp_tag.bsp_lapic_id {
			cpuinit.initialise(smp_info)
			continue
		}

		smp_info.goto_address = cpuinit.initialise

		for katomic.load(cpu_local.online) == 0 {}
	}

	smp_ready = true

	print('smp: All CPUs online!\n')
}
