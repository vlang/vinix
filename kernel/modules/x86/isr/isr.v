// isr.v: ISR and exception handlers.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module isr

import x86.idt
import event
import event.eventstruct
import x86.apic
import x86.cpu.local as cpulocal
import memory.mmap
import katomic
import lib
import userland
import proc

__global (
	int_events [256]eventstruct.Event
)

fn generic_isr(num u32, _ voidptr) {
	apic.lapic_eoi()
	event.trigger(mut int_events[num], false)
}

const exception_names = [
	c'Division by 0',
	c'Debug',
	c'NMI',
	c'Breakpoint',
	c'Overflow',
	c'Bound range exceeded',
	c'Invalid opcode',
	c'Device not available',
	c'Double fault',
	c'???',
	c'Invalid TSS',
	c'Segment not present',
	c'Stack-segment fault',
	c'General protection fault',
	c'Page fault',
	c'???',
	c'x87 exception',
	c'Alignment check',
	c'Machine check',
	c'SIMD exception',
	c'Virtualisation',
	c'???',
	c'???',
	c'???',
	c'???',
	c'???',
	c'???',
	c'???',
	c'???',
	c'???',
	c'Security',
]

fn pf_handler(num u32, gpr_state &cpulocal.GPRState) {
	mmap.pf_handler(gpr_state) or { exception_handler(num, gpr_state) }
}

fn abort_handler(num u32, gpr_state &cpulocal.GPRState) {
	katomic.store(cpulocal.current().aborted, true)
	for {
		asm volatile amd64 {
			hlt
		}
	}
}

fn exception_handler(num u32, gpr_state &cpulocal.GPRState) {
	if gpr_state.cs == user_code_seg {
		mut signal := byte(0)

		match num {
			13, 14 {
				signal = userland.sigsegv
			}
			else {
				lib.kpanic(gpr_state, isr.exception_names[num])
			}
		}

		userland.sendsig(proc.current_thread(), signal)
		userland.dispatch_a_signal(gpr_state)
		userland.syscall_exit(voidptr(0), 128 + signal)
	} else {
		lib.kpanic(gpr_state, isr.exception_names[num])
	}
}

__global (
	abort_vector = byte(0)
)

#include <symbols.h>

fn C.interrupt_thunks()

pub fn initialise() {
	thunks := &u64(voidptr(C.interrupt_thunks))

	for i := u16(0); i < 32; i++ {
		match i {
			14 { // Page fault
				unsafe { idt.register_handler(i, voidptr(thunks[i]), 3, 0x8e) }
				interrupt_table[i] = voidptr(pf_handler)
			}
			else {
				unsafe { idt.register_handler(i, voidptr(thunks[i]), 0, 0x8e) }
				interrupt_table[i] = voidptr(exception_handler)
			}
		}
	}

	for i := u16(32); i < 256; i++ {
		unsafe { idt.register_handler(i, voidptr(thunks[i]), 0, 0x8e) }
		interrupt_table[i] = voidptr(generic_isr)
	}

	abort_vector = idt.allocate_vector()
	unsafe { idt.register_handler(abort_vector, voidptr(thunks[abort_vector]), 4, 0x8e) }
	interrupt_table[abort_vector] = voidptr(abort_handler)
}
