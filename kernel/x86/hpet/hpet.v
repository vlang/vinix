@[has_globals]
module hpet

import acpi
import x86.cpu
import x86.kio

@[packed]
pub struct HPETTable {
pub mut:
	header acpi.SDT

	hardware_rev_id     u8
	misc_bits           u8
	pci_vendor_id       u16
	address_space_id    u8
	register_bit_width  u8
	register_bit_offset u8
	reserved1           u8
	address             u64
	hpet_number         u8
	minimum_tick        u16
	page_protection     u8
}

pub struct HPET {
pub mut:
	general_capabilities  u64
	unused0               u64
	general_configuration u64
	unused1               u64
	general_int_status    u64
	unused2               u64
	unused3               [24]u64
	main_counter_value    u64
	unused4               u64
}

__global (
	hpet_device    &HPET
	hpet_frequency u64
	// A machine without an HPET -- VirtualBox by default -- counts time with
	// the TSC instead, calibrated against the PIT. hpet_frequency is then the
	// TSC's.
	hpet_uses_tsc bool
	hpet_tsc_base u64
)

const pit_frequency = u64(1193182)

pub fn read_counter() u64 {
	if hpet_uses_tsc {
		return cpu.rdtsc() - hpet_tsc_base
	}
	return kio.mmin(&hpet_device.main_counter_value)
}

// Time since initialise(), in nanoseconds.
pub fn nanoseconds() u64 {
	ticks := read_counter()
	return (ticks / hpet_frequency) * 1000000000 +
		(ticks % hpet_frequency) * 1000000000 / hpet_frequency
}

fn pit_count() u64 {
	// Latch channel 0, then read its count low byte first.
	kio.port_out[u8](0x43, 0)
	lo := kio.port_in[u8](0x40)
	hi := kio.port_in[u8](0x40)
	return (u64(hi) << 8) | u64(lo)
}

// Count TSC ticks across ~27 ms of the PIT. Channel 0 is reprogrammed later
// by time.pit_initialise(), so it is free to borrow here.
fn calibrate_tsc() {
	// Rate generator counting down from 0xffff, a 55 ms period.
	kio.port_out[u8](0x43, 0x34)
	kio.port_out[u8](0x40, 0xff)
	kio.port_out[u8](0x40, 0xff)
	// The new count is loaded on the next PIT clock. Until then a read can
	// return whatever channel 0 held before.
	for pit_count() < 0xf000 {}

	pit_start := pit_count()
	tsc_start := cpu.rdtsc()
	mut pit_now := pit_start
	for pit_now <= pit_start && pit_start - pit_now < 0x8000 {
		pit_now = pit_count()
	}
	tsc_end := cpu.rdtsc()
	pit_ticks := if pit_now <= pit_start { pit_start - pit_now } else { u64(0x8000) }

	hpet_frequency = (tsc_end - tsc_start) * pit_frequency / pit_ticks
	hpet_tsc_base = cpu.rdtsc()
	hpet_uses_tsc = true
	println('hpet: No HPET; using the TSC at ${hpet_frequency} Hz')
}

pub fn initialise() {
	hpet_table := unsafe {
		&HPETTable(acpi.find_sdt('HPET', 0) or {
			calibrate_tsc()
			return
		})
	}

	hpet_device = unsafe { &HPET(hpet_table.address + higher_half) }

	mut tmp := kio.mmin(&hpet_device.general_capabilities)

	counter_clk_period := tmp >> 32
	hpet_frequency = u64(1000000000000000) / counter_clk_period

	println('hpet: Detected frequency of ${hpet_frequency} Hz')

	kio.mmout(&hpet_device.main_counter_value, 0)

	println('hpet: Enabling')
	tmp = kio.mmin(&hpet_device.general_configuration)
	tmp |= 0b01
	kio.mmout(&hpet_device.general_configuration, tmp)
}
