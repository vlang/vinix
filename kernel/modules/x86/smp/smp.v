module smp

import stivale2
import memory
import katomic
import cpu.local as cpulocal
import cpu.initialisation as cpuinit

__global (
	bsp_lapic_id = u32(0)
)

pub fn initialise(smp_tag &stivale2.SMPTag) {
	println('smp: BSP LAPIC ID:    ${smp_tag.bsp_lapic_id:x}')
	println('smp: Total CPU count: ${smp_tag.cpu_count}')

	smp_info_array := unsafe { &stivale2.SMPInfo(&smp_tag.smp_info) }

	bsp_lapic_id = smp_tag.bsp_lapic_id

	for i := u64(0); i < smp_tag.cpu_count; i++ {
		mut cpu_local := &cpulocal.Local(memory.malloc(sizeof(cpulocal.Local)))
		cpu_locals << cpu_local

		mut smp_info := unsafe { &smp_info_array[i] }

		smp_info.extra_arg = u64(cpu_local)

		cpu_local.cpu_number = i

		if smp_info.lapic_id == smp_tag.bsp_lapic_id {
			cpuinit.initialise(smp_info)
			continue
		}

		stack_size := u64(4192)

		boot_stack := memory.pmm_alloc(stack_size / page_size)
		katomic.store(smp_info.target_stack, u64(boot_stack) + stack_size + higher_half)
		katomic.store(smp_info.goto_address, u64(&cpuinit.initialise))

		for katomic.load(cpu_local.online) == 0 {}
	}

	print('smp: All CPUs online!\n')
}
