[manualfree] module initialisation

import gdt
import idt
import syscall
import cpu
import local as cpulocal
import stivale2
import apic
import katomic
import sched
import memory
import msr

pub fn initialise(smp_info &stivale2.SMPInfo) {
	mut cpu_local := &cpulocal.Local(smp_info.extra_arg)
	cpu_number := cpu_local.cpu_number

	cpu_local.lapic_id = smp_info.lapic_id

	gdt.reload()
	idt.reload()

	gdt.load_tss(voidptr(&cpu_local.tss))

	cpu_local.tss.ist4 = u64(&cpu_local.abort_stack[cpulocal.abort_stack_size - 1])

	mut success, _, mut b, mut c, mut d := cpu.cpuid(0x80000001, 0)
	if success == false || d & (1 << 27) == 0 {
		if cpu_number > 0 {
			panic('This CPU does not support RDTSCP. Vinix requires RDTSCP to run.')
		}
		cpu_set_id = cpu.set_id_zero
		cpu_get_id = cpu.get_id_zero
	} else {
		cpu_set_id = cpu.set_id_rdtscp
		cpu_get_id = cpu.get_id_rdtscp

		cpu_set_id(cpu_local.cpu_number)
	}

	kernel_pagemap.switch_to()

	success, _, _, _, d = cpu.cpuid(1, 0)
	if success == true && d & (1 << 11) != 0 {
		msr.wrmsr(0x174, kernel_code_seg)
		msr.wrmsr(0x176, u64(voidptr(syscall.sysenter_entry)))
	} else {
		panic('This CPU does not support SEP. Vinix requires SEP to run.')
	}

	unsafe {
		stack_size := u64(8192)

		common_int_stack_phys := memory.pmm_alloc(stack_size / page_size)
		mut common_int_stack := &u64(u64(common_int_stack_phys) + stack_size + higher_half)
		cpu_local.tss.rsp0 = u64(common_int_stack)

		sched_stack_phys := memory.pmm_alloc(stack_size / page_size)
		mut sched_stack := &u64(u64(sched_stack_phys) + stack_size + higher_half)
		cpu_local.tss.ist1 = u64(sched_stack)
	}

	// Enable SSE/SSE2
	mut cr0 := cpu.read_cr0()
	cr0 &= ~(1 << 2)
	cr0 |=  (1 << 1)
	cpu.write_cr0(cr0)

	mut cr4 := cpu.read_cr4()
	cr4 |= (3 << 9)
	cpu.write_cr4(cr4)

	success, _, b, c, _ = cpu.cpuid(1, 0)
	if success == true && c & cpu.cpuid_xsave != 0 {
		if cpu_number == 0 { println('fpu: xsave supported') }

		// Enable XSAVE and x{get, set}bv
		cr4 = cpu.read_cr4()
		cr4 |= (1 << 18)
		cpu.write_cr4(cr4)

		mut xcr0 := u64(0)
		if cpu_number == 0 { println('fpu: Saving x87 state using xsave') }
		xcr0 |= (1 << 0)
		if cpu_number == 0 { println('fpu: Saving SSE state using xsave') }
		xcr0 |= (1 << 1)

		if c & cpu.cpuid_avx != 0 {
			if cpu_number == 0 { println('fpu: Saving AVX state using xsave') }
			xcr0 |= (1 << 2)
		}

		success, _, b, c, _ = cpu.cpuid(7, 0)
		if success == true && b & cpu.cpuid_avx512 != 0 {
			if cpu_number == 0 { println('fpu: Saving AVX-512 state using xsave') }
			xcr0 |= (1 << 5)
			xcr0 |= (1 << 6)
			xcr0 |= (1 << 7)
		}

		cpu.wrxcr(0, xcr0)

		cpu_local.fpu_storage_size = u64(c)
		cpu_local.fpu_save = cpu.xsave
		cpu_local.fpu_restore = cpu.xrstor
	} else {
		if cpu_number == 0 { println('fpu: Using legacy fxsave') }
		cpu_local.fpu_storage_size = u64(512)
		cpu_local.fpu_save = cpu.fxsave
		cpu_local.fpu_restore = cpu.fxrstor
	}

	apic.lapic_enable(0xff)

	asm volatile amd64 { sti }

	apic.lapic_timer_calibrate()

	print('smp: CPU ${cpu_local.cpu_number} online!\n')

	katomic.inc(cpu_local.online)

	if cpu_number != 0 {
		for katomic.load(scheduler_vector) == 0 {}
		sched.await()
	}
}
