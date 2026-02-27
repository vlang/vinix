module pci

import bitmap

pub struct PCIDevice {
pub:
	bus      u8
	slot     u8
	function u8
	parent   i64
pub mut:
	device_id         u16
	vendor_id         u16
	revision_id       u16
	class             u8
	subclass          u8
	prog_if           u8
	multifunction     bool
	irq_pin           u8
	msi_offset        u16
	msix_offset       u16
	msi_support       bool
	msix_support      bool
	msix_table_bitmap bitmap.GenericBitmap
	msix_table_size   u16
}

pub struct PCIBar {
pub:
	base            u64
	size            u64
	is_mmio         bool
	is_prefetchable bool
}

pub fn (mut dev PCIDevice) read_info() {
	config0 := dev.read[int](0)
	config8 := dev.read[int](0x8)
	configc := dev.read[int](0xc)
	config3c := dev.read[int](0x3c)

	dev.device_id = u16(config0 >> 16)
	dev.vendor_id = u16(config0)
	dev.revision_id = u8(config8)
	dev.subclass = u8(config8 >> 16)
	dev.class = u8(config8 >> 24)
	dev.prog_if = u8(config8 >> 8)
	dev.multifunction = if configc & 0x800000 != 0 { true } else { false }
	dev.irq_pin = u8(config3c >> 8)
}

pub fn (dev &PCIDevice) is_bar_present(bar u8) bool {
	assert bar <= 5
	reg_index := 0x10 + bar * 4
	return if dev.read[u32](reg_index) != 0 { true } else { false }
}

pub fn (dev &PCIDevice) get_bar(bar u8) PCIBar {
	assert bar <= 5

	reg_index := 0x10 + bar * 4
	bar_low := dev.read[u32](reg_index)
	mut bar_size_low := dev.read[u32](reg_index)

	is_mmio := if bar_low & 1 == 0 { true } else { false }
	is_prefetchable := is_mmio && bar_low & (1 << 3) != 0
	is_64_bits := is_mmio && ((bar_low >> 1) & 0b11) == 0b10
	bar_high := if is_64_bits { dev.read[u32](reg_index + 4) } else { 0 }

	base := ((u64(bar_high) << 32) | bar_low) & ~u32(if is_mmio { 0b1111 } else { 0b11 })

	dev.write[u32](reg_index, 0xFFFFFFFF)
	bar_size_low = dev.read[u32](reg_index)
	dev.write[u32](reg_index, bar_low)

	bar_size_high := if is_64_bits {
		dev.write[u32](reg_index + 4, 0xFFFFFFFF)
		ret := dev.read[u32](reg_index + 4)
		dev.write[u32](reg_index + 4, bar_high)
		ret
	} else {
		0xFFFFFFFF
	}

	mut size := ((u64(bar_size_high) << 32) | bar_size_low) & ~u64(if is_mmio {
		0b1111
	} else {
		0b11
	})
	size = ~size + 1

	return PCIBar{base, size, is_mmio, is_prefetchable}
}

pub fn (dev &PCIDevice) enable_bus_mastering() {
	if (dev.read[u32](0x4) & (1 << 2)) == 0 {
		dev.write[u32](0x4, dev.read[u32](0x4) | (1 << 2))
	}
}
