module smp

import stivale2
import memory
import katomic
import cpu.local as cpulocal
import cpu.initialisation as cpuinit

__global (
	cpus_online = u64(0)
	bsp_lapic_id = u32(0)
)

pub fn initialise(smp_tag &stivale2.SMPTag) {
	println('smp: BSP LAPIC ID:    ${smp_tag.bsp_lapic_id:x}')
	println('smp: Total CPU count: ${smp_tag.cpu_count}')

	cpu_locals = []&cpulocal.Local{}

	smp_info_array := unsafe { &stivale2.SMPInfo(&smp_tag.smp_info) }

	bsp_lapic_id = smp_tag.bsp_lapic_id

	for i := u64(0); i < smp_tag.cpu_count; i++ {
		mut cpu_local := &cpulocal.Local(memory.malloc(sizeof(cpulocal.Local)))
		cpu_locals << cpu_local

		mut smp_info := unsafe { &smp_info_array[i] }

		smp_info.extra_arg = u64(cpu_local)

		stack_size := 8192

		stack := &[]u8{cap: stack_size, len: stack_size, init: 0}
		sched_stack := &[]u8{cap: stack_size, len: stack_size, init: 0}

		cpu_local.tss.rsp0 = unsafe { u64(&stack[0]) + u64(stack_size) }
		cpu_local.tss.ist1 = unsafe { u64(&sched_stack[0]) + u64(stack_size) }
		cpu_local.cpu_number = i

		if smp_info.lapic_id == smp_tag.bsp_lapic_id {
			cpuinit.initialise(smp_info)
			continue
		}

		katomic.store(smp_info.target_stack, cpu_local.tss.rsp0)
		katomic.store(smp_info.goto_address, u64(&cpuinit.initialise))
	}

	for katomic.load(cpus_online) != smp_tag.cpu_count {}

	print('smp: All CPUs online!\n')
}
