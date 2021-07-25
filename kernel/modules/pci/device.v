module pci

import x86.kio

pub struct PCIDevice {
pub:
	bus byte
	slot byte
	function byte
	parent i64
pub mut:
	device_id u16
	vendor_id u16
	revision_id u16
	subclass byte
	device_class byte
	prog_if byte
	multifunction bool
	irq_pin byte
}

pub struct PCIBar {
pub:
	base u64
	size u64
	is_mmio bool
	is_prefetchable bool
}

pub fn (mut dev PCIDevice) read_info() {
	config0 := dev.read<int>(0)
	config8 := dev.read<int>(0x8)
	configc := dev.read<int>(0xc)
	config3c := dev.read<int>(0x3c)

	dev.device_id = u16(config0 >> 16)
	dev.vendor_id = u16(config0)
	dev.revision_id = byte(config8)
	dev.subclass = byte(config8 >> 16)
	dev.device_class = byte(config8 >> 24)
	dev.prog_if = byte(config0 >> 8)
	dev.multifunction = if configc & 0x800000 != 0 { true } else { false }
	dev.irq_pin = byte(config3c >> 8)
}

pub fn (dev &PCIDevice) read<T>(offset u32) T {
	dev.get_address(offset)
	return kio.port_in<T>(u16(0xcfc + (offset & 3)))
}

pub fn (dev &PCIDevice) write<T>(offset u32, value T) {
	dev.get_address(offset)
	kio.port_out<T>(u16(0xcfc + (offset & 3)), value)
}

pub fn (dev &PCIDevice) is_bar_present(bar byte) bool {
	assert bar <= 5
	reg_index := 0x10 + bar * 4
	return if dev.read<u32>(reg_index) != 0 { true } else { false }
}

pub fn (dev &PCIDevice) get_bar(bar byte) PCIBar {
	assert bar <= 5

	reg_index := 0x10 + bar * 4
	bar_low := dev.read<u32>(reg_index)
	mut bar_size_low := dev.read<u32>(reg_index)

	is_mmio := if bar_low & 1 == 0 { true } else { false }
	is_prefetchable := is_mmio && bar_low & (1 << 3) != 0
	is_64_bits := is_mmio && ((bar_low >> 1) & 0b11) == 0b10
	bar_high := if is_64_bits { dev.read<u32>(reg_index + 4) } else { 0 }

	base := ((u64(bar_high) << 32) | bar_low) & ~u32(if is_mmio { 0b1111 } else { 0b11 })

	dev.write<u32>(reg_index, 0xFFFFFFFF)
	bar_size_low = dev.read<u32>(reg_index)
	dev.write<u32>(reg_index, bar_low)

	bar_size_high := if is_64_bits {
		dev.write<u32>(reg_index + 4, 0xFFFFFFFF)
		ret := dev.read<u32>(reg_index + 4)
		dev.write<u32>(reg_index + 4, bar_high)
		ret
	} else {
		0xFFFFFFFF
	}

	mut size := ((bar_size_high << 32) | bar_size_low) & ~u32(if is_mmio { 0b1111 } else { 0b11 })
	size = ~size + 1

	return PCIBar{base, size, is_mmio, is_prefetchable}
}

pub fn (dev &PCIDevice) enable_bus_mastering() {
	if (dev.read<u32>(0x4) & (1 << 2)) == 0 {
		dev.write<u32>(0x4, dev.read<u32>(0x4) | (1 << 2))
	}
}

fn (dev &PCIDevice) get_address(offset u32) {
	address := (dev.bus << 16) | (dev.slot << 11) | (dev.function << 8)
		| (offset & ~(u32(3))) | 0x80000000
	kio.port_out<u32>(0xcf8, address)
}
