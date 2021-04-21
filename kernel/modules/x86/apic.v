module x86

const lapic_reg_icr0 = 0x300

const lapic_reg_icr1 = 0x310

const lapic_reg_spurious = 0x0f0

const lapic_reg_eoi = 0x0b0

fn lapic_read(reg u32) u32 {
	lapic_base := rdmsr(0x1b) & 0xfffff000
	return mmind(lapic_base + reg)
}

fn lapic_write(reg u32, val u32) {
	lapic_base := rdmsr(0x1b) & 0xfffff000
	mmoutd(lapic_base + reg, val)
}

pub fn lapic_enable(spurious_vect u8) {
	lapic_write(x86.lapic_reg_spurious, lapic_read(x86.lapic_reg_spurious) | (1 << 8) | spurious_vect)
}

pub fn lapic_eoi() {
	lapic_write(x86.lapic_reg_eoi, 0)
}
