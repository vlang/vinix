module hpet

import acpi
import x86.kio

@[packed]
pub struct HPETTable {
pub mut:
	header acpi.SDT

	hardware_rev_id u8
	misc_bits u8
	pci_vendor_id u16
	address_space_id u8
	register_bit_width u8
	register_bit_offset u8
	reserved1 u8
	address u64
	hpet_number u8
	minimum_tick u16
	page_protection u8
}

pub struct HPET {
pub mut:
	general_capabilities u64
	unused0 u64
	general_configuration u64
	unused1 u64
	general_int_status u64
	unused2 u64
	unused3 [24]u64
	main_counter_value u64
	unused4 u64
}

__global (
	hpet &HPET
	hpet_frequency u64
)

pub fn read_counter() u64 {
	return kio.mmin(&hpet.main_counter_value)
}

pub fn initialise() {
	hpet_table := unsafe { &HPETTable(acpi.find_sdt('HPET', 0) or {
		panic('HPET ACPI table not found')
	}) }

	hpet = &HPET(hpet_table.address + higher_half)

	mut tmp := kio.mmin(&hpet.general_capabilities)

	counter_clk_period := tmp >> 32;
	hpet_frequency = u64(1000000000000000) / counter_clk_period

	println('hpet: Detected frequency of ${hpet_frequency} Hz')

	kio.mmout(&hpet.main_counter_value, 0)

	println('hpet: Enabling')
	tmp = kio.mmin(&hpet.general_configuration)
	tmp |= 0b01
	kio.mmout(&hpet.general_configuration, tmp)
}
