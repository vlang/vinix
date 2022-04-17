// initialization.v: Core initialization.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module initialisation

import x86.gdt
import x86.idt
import x86.cpu
import x86.msr
import syscall
import x86.cpu.local as cpulocal
import limine
import x86.apic
import katomic
import sched
import memory

pub fn initialise(smp_info &limine.LimineSMPInfo) {
	mut cpu_local := &cpulocal.Local(smp_info.extra_argument)
	cpu_number := cpu_local.cpu_number

	cpu_local.lapic_id = smp_info.lapic_id

	gdt.reload()
	idt.reload()

	gdt.load_tss(voidptr(&cpu_local.tss))

	cpu_local.tss.ist4 = u64(&cpu_local.abort_stack[cpulocal.abort_stack_size - 1])

	kernel_pagemap.switch_to()

	unsafe {
		stack_size := u64(8192)

		common_int_stack_phys := memory.pmm_alloc(stack_size / page_size)
		mut common_int_stack := &u64(u64(common_int_stack_phys) + stack_size + higher_half)
		cpu_local.tss.rsp0 = u64(common_int_stack)

		sched_stack_phys := memory.pmm_alloc(stack_size / page_size)
		mut sched_stack := &u64(u64(sched_stack_phys) + stack_size + higher_half)
		cpu_local.tss.ist1 = u64(sched_stack)
	}
	// Enable syscall
	mut efer := msr.rdmsr(0xc0000080)
	efer |= 1
	msr.wrmsr(0xc0000080, efer)
	msr.wrmsr(0xc0000081, 0x0033002800000000)

	// Entry address
	msr.wrmsr(0xc0000082, u64(voidptr(syscall.syscall_entry)))

	// Flags mask
	msr.wrmsr(0xc0000084, u64(~u32(0x002)))

	cpu.set_gs_base(voidptr(&cpu_local.cpu_number))
	cpu.set_kernel_gs_base(voidptr(&cpu_local.cpu_number))

	// Enable SSE/SSE2
	mut cr0 := cpu.read_cr0()
	cr0 &= ~(1 << 2)
	cr0 |= (1 << 1)
	cpu.write_cr0(cr0)

	mut cr4 := cpu.read_cr4()
	cr4 |= (3 << 9)
	cpu.write_cr4(cr4)

	mut success, _, mut b, mut c, _ := cpu.cpuid(1, 0)
	if success == true && c & cpu.cpuid_xsave != 0 {
		if cpu_number == 0 {
			println('fpu: xsave supported')
		}

		// Enable XSAVE and x{get, set}bv
		cr4 = cpu.read_cr4()
		cr4 |= (1 << 18)
		cpu.write_cr4(cr4)

		mut xcr0 := u64(0)
		if cpu_number == 0 {
			println('fpu: Saving x87 state using xsave')
		}
		xcr0 |= (1 << 0)
		if cpu_number == 0 {
			println('fpu: Saving SSE state using xsave')
		}
		xcr0 |= (1 << 1)

		if c & cpu.cpuid_avx != 0 {
			if cpu_number == 0 {
				println('fpu: Saving AVX state using xsave')
			}
			xcr0 |= (1 << 2)
		}

		success, _, b, c, _ = cpu.cpuid(7, 0)
		if success == true && b & cpu.cpuid_avx512 != 0 {
			if cpu_number == 0 {
				println('fpu: Saving AVX-512 state using xsave')
			}
			xcr0 |= (1 << 5)
			xcr0 |= (1 << 6)
			xcr0 |= (1 << 7)
		}

		cpu.wrxcr(0, xcr0)

		success, _, _, c, _ = cpu.cpuid(0xd, 0)
		if success == false {
			panic('CPUID failure')
		}

		fpu_storage_size = u64(c)
		fpu_save = cpu.xsave
		fpu_restore = cpu.xrstor
	} else {
		if cpu_number == 0 {
			println('fpu: Using legacy fxsave')
		}
		fpu_storage_size = u64(512)
		fpu_save = cpu.fxsave
		fpu_restore = cpu.fxrstor
	}

	apic.lapic_enable(0xff)

	asm volatile amd64 {
		sti
	}

	apic.lapic_timer_calibrate(mut cpu_local)

	print('smp: CPU $cpu_local.cpu_number online!\n')

	katomic.inc(cpu_local.online)

	if cpu_number != 0 {
		for katomic.load(scheduler_vector) == 0 {}
		sched.await()
	}
}
