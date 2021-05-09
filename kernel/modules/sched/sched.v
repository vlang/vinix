module sched

import x86
import klock

pub fn initialise() {
	// Set PIT tick to 1000Hz
	x86.pit_set_freq(1000)

	scheduler_vector := x86.idt_allocate_vector()
	println('sched: Scheduler interrupt vector is 0x${scheduler_vector:x}')

	x86.io_apic_set_irq_redirect(cpu_locals[0].lapic_id, scheduler_vector, 0, true)
}

__global (
	sched_lock klock.Lock
)
