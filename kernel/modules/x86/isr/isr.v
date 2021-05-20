module isr

import idt
import kevent
import apic

__global (
	int_events [256]kevent.Event
)

fn generic_isr(num u32, _ voidptr) {
	apic.lapic_eoi()
	//kevent.trigger(&int_event[num])
}

pub fn initialise() {
	for i := u16(0); i < 256; i++ {
		idt.register_handler(i, interrupt_thunks[i])
		interrupt_table[i] = voidptr(generic_isr)
	}
}
