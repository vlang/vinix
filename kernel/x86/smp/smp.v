@[has_globals]
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

@[_linker_section: '.requests']
@[cinit]
__global (
	volatile smp_req = limine.LimineSMPRequest{
		flags:    1 // x2apic allowed
		response: unsafe { nil }
	}
)

fn C.vinix_x86_mitigations_setup(count u64) bool

pub fn initialise() {
	if smp_req.response == unsafe { nil } {
		panic('SMP bootloader response missing')
	}
	smp_tag := smp_req.response

	C.kprintf(c'smp: BSP LAPIC ID:    %llx\n', u64(smp_tag.bsp_lapic_id))
	C.kprintf(c'smp: Total CPU count: %llu\n', u64(smp_tag.cpu_count))
	C.kprintf(c'smp: Using x2APIC:    %s\n', if x2apic_mode { c'true' } else { c'false' })

	if !C.vinix_x86_mitigations_setup(smp_tag.cpu_count) {
		panic('Cannot allocate per-CPU speculation policies')
	}
	smp_info_array := smp_tag.cpus

	bsp_lapic_id = smp_tag.bsp_lapic_id
	topology := smt_topology()
	allow_smt := smt_enabled()
	if !allow_smt {
		C.kprintf(c'smp: SMT disabled; topology %s\n', if topology.known { c'known' } else { c'unknown (BSP only)' })
	}

	// The BSP is logical CPU zero regardless of the firmware array's order.
	// AP initialization waits for the BSP to publish scheduler state.
	mut bsp_info := unsafe { &limine.LimineSMPInfo(nil) }
	for i := u64(0); i < smp_tag.cpu_count; i++ {
		if unsafe { smp_info_array[i] }.lapic_id == bsp_lapic_id { bsp_info = unsafe { smp_info_array[i] }; break }
	}
	if bsp_info == unsafe { nil } { panic('SMP response does not contain BSP') }
	mut bsp_local := unsafe { &cpulocal.Local(memory.malloc(sizeof(cpulocal.Local))) }
	bsp_local.cpu_number = 0
	cpu_locals << bsp_local
	bsp_info.extra_argument = u64(bsp_local)
	cpuinit.initialise(bsp_info)

	for i := u64(0); i < smp_tag.cpu_count; i++ {
		mut smp_info := unsafe { smp_info_array[i] }
		if smp_info.lapic_id == bsp_lapic_id { continue }
		if !allow_smt {
			if !topology.known { continue }
			mut sibling := false
			for online in cpu_locals {
				if same_physical_core(smp_info.lapic_id, online.lapic_id, topology) { sibling = true; break }
			}
			if sibling { continue }
		}
		mut cpu_local := unsafe { &cpulocal.Local(memory.malloc(sizeof(cpulocal.Local))) }
		cpu_local.cpu_number = u64(cpu_locals.len)
		cpu_locals << cpu_local

		smp_info.extra_argument = u64(cpu_local)

		smp_info.goto_address = cpuinit.initialise

		for katomic.load(&cpu_local.online) == 0 {}
	}

	// All GS/TPIDR CPU numbers are now installed; publish cache readiness.
	memory.heap_enable_cpu_caches(u64(cpu_locals.len))
	// All CPUs still have IRQs off and APs await scheduler_vector. Counting
	// already began in their setup; only the permanent fault observer is new.
	memory.initialise_native_irq_fault_guard()
	$if heap_benchmark ? {
		memory.heap_benchmark()
	}
	$if heap_c_benchmark ? {
		memory.heap_c_benchmark()
	}
	smp_ready = true

	C.kprintf(c'smp: Online CPU count: %llu\n', u64(cpu_locals.len))
}
