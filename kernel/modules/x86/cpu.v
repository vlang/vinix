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

	// Enable SSE/SSE2
	mut cr0 := read_cr0()
	cr0 &= ~(1 << 2)
	cr0 |=  (1 << 1)
	write_cr0(cr0)

	mut cr4 := read_cr4()
	cr4 |= (3 << 9)
	write_cr4(cr4)

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

pub fn read_cr0() u64 {
	mut ret := u64(0)
	asm volatile amd64 {
		mov ret, cr0
		; =r (ret)
		;
		; memory
	}
	return ret
}

pub fn write_cr0(value u64) {
	asm volatile amd64 {
		mov cr0, value
		;
		; r (value)
		; memory
	}
}

pub fn read_cr2() u64 {
	mut ret := u64(0)
	asm volatile amd64 {
		mov ret, cr2
		; =r (ret)
		;
		; memory
	}
	return ret
}

pub fn write_cr2(value u64) {
	asm volatile amd64 {
		mov cr2, value
		;
		; r (value)
		; memory
	}
}

pub fn read_cr3() u64 {
	mut ret := u64(0)
	asm volatile amd64 {
		mov ret, cr3
		; =r (ret)
		;
		; memory
	}
	return ret
}

pub fn write_cr3(value u64) {
	asm volatile amd64 {
		mov cr3, value
		;
		; r (value)
		; memory
	}
}

pub fn read_cr4() u64 {
	mut ret := u64(0)
	asm volatile amd64 {
		mov ret, cr4
		; =r (ret)
		;
		; memory
	}
	return ret
}

pub fn write_cr4(value u64) {
	asm volatile amd64 {
		mov cr4, value
		;
		; r (value)
		; memory
	}
}

pub fn cpuid(leaf u32, subleaf u32) (bool, u32, u32, u32, u32) {
	mut cpuid_max := u32(0)
	asm volatile amd64 {
		cpuid
		; =a (cpuid_max)
		; a (leaf & 0x80000000)
		; rbx
		  rcx
		  rdx
	}
	if leaf > cpuid_max {
		return false, 0, 0, 0, 0
	}
	mut a := u32(0)
	mut b := u32(0)
	mut c := u32(0)
	mut d := u32(0)
	asm volatile amd64 {
		cpuid
		; =a (a)
		  =b (b)
		  =c (c)
		  =d (d)
		; a (leaf)
		  c (subleaf)
	}
	return true, a, b, c, d
}
