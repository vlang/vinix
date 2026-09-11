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

// Bring up at most max_cpus logical CPUs. A limit of zero means every CPU in
// the Limine response. Limine has already bootstrapped the remaining APs, but
// they stay safely parked in its acquire loop until goto_address is published.
pub fn initialise(max_cpus u64) {
	if !available() {
		panic('SMP bootloader response missing')
	}
	smp_tag := limine_response()
	if smp_tag.cpu_count == 0 {
		panic('SMP bootloader response contains no CPUs')
	}

	mut online_target := smp_tag.cpu_count
	if max_cpus != 0 && max_cpus < online_target {
		online_target = max_cpus
	}

	println('smp: BSP MPIDR:       ${smp_tag.bsp_mpidr:x}')
	println('smp: Discovered CPUs: ${smp_tag.cpu_count}')
	println('smp: Starting CPUs:   ${online_target}')

	smp_info_array := smp_tag.cpus
	mut bsp_index := smp_tag.cpu_count
	for i := u64(0); i < smp_tag.cpu_count; i++ {
		smp_info := unsafe { smp_info_array[i] }
		if smp_info.mpidr == smp_tag.bsp_mpidr {
			bsp_index = i
			break
		}
	}
	if bsp_index == smp_tag.cpu_count {
		panic('SMP response does not contain its BSP')
	}

	// Logical CPU numbers are dense indices into cpu_locals, independent of
	// firmware response ordering. Always install the BSP as logical CPU 0.
	mut bsp_local := unsafe { &cpulocal.Local(memory.malloc(sizeof(cpulocal.Local))) }
	cpu_locals << bsp_local
	mut bsp_info := unsafe { smp_info_array[bsp_index] }
	bsp_info.extra_argument = u64(bsp_local)
	bsp_local.cpu_number = 0
	cpuinit.initialise(bsp_info)

	mut logical_cpu := u64(1)
	for i := u64(0); i < smp_tag.cpu_count; i++ {
		if i == bsp_index || logical_cpu >= online_target {
			continue
		}
		mut cpu_local := unsafe { &cpulocal.Local(memory.malloc(sizeof(cpulocal.Local))) }
		cpu_locals << cpu_local

		mut smp_info := unsafe { smp_info_array[i] }

		smp_info.extra_argument = u64(cpu_local)
		cpu_local.cpu_number = logical_cpu

		// The Limine MP contract requires release ordering: extra_argument and
		// the Local contents must be visible before the parked AP observes its
		// non-null entry point.
		// goto_address is the 64-bit slot at offset 24 in Limine's AArch64
		// mp_info ABI. V does not permit taking an integer view of a function
		// field directly, so address the protocol slot rather than weakening
		// katomic.store's width-checked release semantics.
		mut goto_slot := unsafe { &u64(u64(smp_info) + 24) }
		katomic.store(mut goto_slot, u64(voidptr(cpuinit.initialise)))

		for katomic.load(&cpu_local.online) == 0 {}
		logical_cpu++
	}

	// All GS/TPIDR CPU numbers are now installed; publish cache readiness.
	memory.heap_enable_cpu_caches(u64(cpu_locals.len))
	smp_ready = true

	println('smp: ${logical_cpu} CPUs online')
}
