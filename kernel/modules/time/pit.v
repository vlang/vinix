// pit.v: PIT driver.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module time

import x86.kio
import x86.idt
import x86.cpu.local as cpulocal

pub const pit_dividend = u64(1193182)

pub fn pit_get_current_count() u16 {
	kio.port_out<u8>(0x43, 0)
	lo := kio.port_in<u8>(0x40)
	hi := kio.port_in<u8>(0x40)
	return (u16(hi) << 8) | lo
}

pub fn pit_set_reload_value(new_count u16) {
	// Channel 0, lo/hi access mode, mode 2 (rate generator)
	kio.port_out<u8>(0x43, 0x34)
	kio.port_out<u8>(0x40, u8(new_count))
	kio.port_out<u8>(0x40, u8(new_count >> 8))
}

pub fn pit_set_frequency(frequency u64) {
	mut new_divisor := time.pit_dividend / frequency
	if time.pit_dividend % frequency > frequency / 2 {
		new_divisor++
	}

	pit_set_reload_value(u16(new_divisor))
}

fn C.x86__apic__io_apic_set_irq_redirect(lapic_id u32, vector u8, irq u8, status bool)

pub fn pit_initialise() {
	pit_set_frequency(timer_frequency)

	vect := idt.allocate_vector()

	print('timer: PIT vector is 0x${vect:x}\n')

	interrupt_table[vect] = voidptr(pit_handler)

	C.x86__apic__io_apic_set_irq_redirect(cpu_locals[0].lapic_id, vect, 0, true)
}

fn C.x86__apic__lapic_eoi()

fn pit_handler(num u32, gpr_state &cpulocal.GPRState) {
	timer_handler()
	C.x86__apic__lapic_eoi()
}
