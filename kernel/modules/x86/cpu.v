module x86

import stivale2
import memory

[packed]
struct TSS {
pub mut:
	unused0 u32
	rsp0    u64
	rsp1    u64
	rsp2    u64
	unused1 u64
	ist1    u64
	ist2    u64
	ist3    u64
	ist4    u64
	ist5    u64
	ist6    u64
	ist7    u64
	unused2 u64
	iopb    u32
}

struct CPULocal {
pub mut:
	cpu_number       u64
	kernel_stack     u64
	user_stack       u64
	errno            i64
	tss              TSS
	lapic_id         u32
	fpu_storage_size size_t
	fpu_save         fn (voidptr)
	fpu_restore      fn (voidptr)
}

__global (
	cpu_locals []&CPULocal
)

pub fn cpu_init(smp_info &stivale2.SMPInfo) {
	cpu_local := &CPULocal(smp_info.extra_arg)

	gdt_reload()
	idt_reload()

	kernel_pagemap.switch_to()

	set_kernel_gs(u64(voidptr(cpu_local)))
	set_user_gs(u64(voidptr(cpu_local)))

	print('smp: CPU ${cpu_local.cpu_number} online!\n')

	atomic_inc(&cpus_online)

	if cpu_local.cpu_number != 0 {
		for {
			asm volatile amd64 {
				hlt
			}
		}
	}
}

pub fn set_kernel_gs(ptr u64) {
	wrmsr(0xc0000101, ptr)
}

pub fn set_user_gs(ptr u64) {
	wrmsr(0xc0000102, ptr)
}
