module isr

import idt
import kevent
import apic
import cpu.local as cpulocal

__global (
	int_events [256]kevent.Event
)

fn generic_isr(num u32, _ voidptr) {
	apic.lapic_eoi()
	kevent.trigger(&int_events[num])
}

fn unhandled_exception(num u32, gpr_state &cpulocal.GPRState) {
	C.printf(c'Exception occurred')
	for {
		asm volatile amd64 {
			cli
			hlt
		}
	}
}

pub fn initialise() {
	for i := u16(0); i < 32; i++ {
		idt.register_handler(i, interrupt_thunks[i])
		interrupt_table[i] = voidptr(unhandled_exception)
	}

	for i := u16(32); i < 256; i++ {
		idt.register_handler(i, interrupt_thunks[i])
		interrupt_table[i] = voidptr(generic_isr)
	}
}
