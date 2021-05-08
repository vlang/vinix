module x86

import stivale2

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

struct CPUGPRState {
pub mut:
	rax u64
	rbx u64
	rcx u64
	rdx u64
	rsi u64
	rdi u64
	rbp u64
	r8 u64
	r9 u64
	r10 u64
	r11 u64
	r12 u64
	r13 u64
	r14 u64
	r15 u64
	rip u64
	cs u64
	rflags u64
	rsp u64
	ss u64
}

__global (
	cpu_locals []&CPULocal
)

pub fn cpu_init(smp_info &stivale2.SMPInfo) {
	mut cpu_local := &CPULocal(smp_info.extra_arg)
	cpu_number := cpu_local.cpu_number

	cpu_local.lapic_id = smp_info.lapic_id

	gdt_reload()
	idt_reload()

	kernel_pagemap.switch_to()

	set_kernel_gs(u64(voidptr(cpu_local)))
	set_user_gs(u64(voidptr(cpu_local)))

	gdt_load_tss(voidptr(&cpu_local.tss))

	// Enable SSE/SSE2
	mut cr0 := read_cr0()
	cr0 &= ~(1 << 2)
	cr0 |=  (1 << 1)
	write_cr0(cr0)

	mut cr4 := read_cr4()
	cr4 |= (3 << 9)
	write_cr4(cr4)

	mut success, _, mut b, mut c, _ := cpuid(1, 0)
	if success == true && c & cpuid_xsave != 0 {
		if cpu_number == 0 { println('fpu: xsave supported') }

		// Enable XSAVE and x{get, set}bv
		cr4 = read_cr4()
		cr4 |= (1 << 18)
		write_cr4(cr4)

		mut xcr0 := u64(0)
		if cpu_number == 0 { println('fpu: Saving x87 state using xsave') }
		xcr0 |= (1 << 0)
		if cpu_number == 0 { println('fpu: Saving SSE state using xsave') }
		xcr0 |= (1 << 1)

		if c & cpuid_avx != 0 {
			if cpu_number == 0 { println('fpu: Saving AVX state using xsave') }
			xcr0 |= (1 << 2)
		}

		success, _, b, c, _ = cpuid(7, 0)
		if success == true && b & cpuid_avx512 != 0 {
			if cpu_number == 0 { println('fpu: Saving AVX-512 state using xsave') }
			xcr0 |= (1 << 5)
			xcr0 |= (1 << 6)
			xcr0 |= (1 << 7)
		}

		wrxcr(0, xcr0)

		cpu_local.fpu_storage_size = size_t(c)
		cpu_local.fpu_save = xsave
		cpu_local.fpu_restore = xrstor
	} else {
		if cpu_number == 0 { println('fpu: Using legacy fxsave') }
		cpu_local.fpu_storage_size = size_t(512)
		cpu_local.fpu_save = fxsave
		cpu_local.fpu_restore = fxrstor
	}

	lapic_enable(0xff)

	print('smp: CPU ${cpu_local.cpu_number} online!\n')

	atomic_inc(&cpus_online)

	if cpu_number != 0 {
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

pub fn wrxcr(reg u32, value u64) {
	a := u32(value)
	d := u32(value >> 32)
	asm volatile amd64 {
		xsetbv
		;
		; a (a)
		  d (d)
		  c (reg)
		; memory
	}
}

fn xsave(region voidptr) {
	asm volatile amd64 {
		xsave [region]
		;
		; r (region)
		  a (0xffffffff)
		  d (0xffffffff)
		; memory
	}
}

fn xrstor(region voidptr) {
	asm volatile amd64 {
		xrstor [region]
		;
		; r (region)
		  a (0xffffffff)
		  d (0xffffffff)
		; memory
	}
}

fn fxsave(region voidptr) {
	asm volatile amd64 {
		fxsave [region]
		;
		; r (region)
		; memory
	}
}

fn fxrstor(region voidptr) {
	asm volatile amd64 {
		fxrstor [region]
		;
		; r (region)
		; memory
	}
}

pub const cpuid_xsave = u32(1 << 26)
pub const cpuid_avx = u32(1 << 28)
pub const cpuid_avx512 = u32(1 << 16)

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
