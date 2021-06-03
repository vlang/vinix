module initialisation

import gdt
import idt
import cpu
import local as cpulocal
import stivale2
import apic
import katomic

pub fn initialise(smp_info &stivale2.SMPInfo) {
	mut cpu_local := &cpulocal.Local(smp_info.extra_arg)
	cpu_number := cpu_local.cpu_number

	cpu_local.lapic_id = smp_info.lapic_id

	gdt.reload()
	idt.reload()

	kernel_pagemap.switch_to()

	cpu.set_kernel_gs(u64(voidptr(cpu_local)))
	cpu.set_user_gs(u64(voidptr(cpu_local)))

	gdt.load_tss(voidptr(&cpu_local.tss))

	// Enable SSE/SSE2
	mut cr0 := cpu.read_cr0()
	cr0 &= ~(1 << 2)
	cr0 |=  (1 << 1)
	cpu.write_cr0(cr0)

	mut cr4 := cpu.read_cr4()
	cr4 |= (3 << 9)
	cpu.write_cr4(cr4)

	mut success, _, mut b, mut c, _ := cpu.cpuid(1, 0)
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
		asm volatile amd64 {
			1:
			hlt
			jmp b1
			;
			;
			; memory
		}
	}
}
