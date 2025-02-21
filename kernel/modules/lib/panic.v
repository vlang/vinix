// panic.v: Kernel panic function.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module lib

import x86.apic
import x86.cpu.local as cpulocal
import x86.cpu
import katomic

fn C.printf_panic(charptr, ...voidptr)

@[noreturn]
pub fn kpanic(gpr_state &cpulocal.GPRState, message charptr) {
	asm volatile amd64 {
		cli
	}
	if smp_ready {
		for cpu_local in cpu_locals {
			if cpulocal.current().lapic_id == cpu_local.lapic_id {
				continue
			}
			apic.lapic_send_ipi(u8(cpu_local.lapic_id), abort_vector)
			for katomic.load(&cpu_local.aborted) == false {}
		}
	}

	cpu_number := if smp_ready { cpulocal.current().cpu_number } else { 0 }

	C.printf_panic(c'KERNEL PANIC: "%s" on CPU %d\n', message, cpu_number)
	if gpr_state != unsafe { nil } {
		C.printf_panic(c'Error code: 0x%016llx\n', gpr_state.err)
		C.printf_panic(c'Register dump:\n')
		C.printf_panic(c'CS:RIP=%04llx:%016llx\n', gpr_state.cs, gpr_state.rip)
		C.printf_panic(c'SS:RSP=%04llx:%016llx\n', gpr_state.ss, gpr_state.rsp)
		C.printf_panic(c'RFLAGS=%08llx       CR2=%016llx\n', gpr_state.rflags, cpu.read_cr2())
		C.printf_panic(c'RAX=%016llx  RBX=%016llx  RCX=%016llx  RDX=%016llx\n', gpr_state.rax,
			gpr_state.rbx, gpr_state.rcx, gpr_state.rdx)
		C.printf_panic(c'RSI=%016llx  RDI=%016llx  RBP=%016llx  RSP=%016llx\n', gpr_state.rsi,
			gpr_state.rdi, gpr_state.rbp, gpr_state.rsp)
		C.printf_panic(c'R08=%016llx  R09=%016llx  R10=%016llx  R11=%016llx\n', gpr_state.r8,
			gpr_state.r9, gpr_state.r10, gpr_state.r11)
		C.printf_panic(c'R12=%016llx  R13=%016llx  R14=%016llx  R15=%016llx\n', gpr_state.r12,
			gpr_state.r13, gpr_state.r14, gpr_state.r15)
	}

	for {
		asm volatile amd64 {
			hlt
		}
	}

	for {}
}
