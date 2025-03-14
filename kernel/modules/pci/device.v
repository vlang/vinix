module pci

import x86.kio
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

pub fn (dev &PCIDevice) read[T](offset u32) T {
	dev.get_address(offset)
	return kio.port_in[T](u16(0xcfc + (offset & 3)))
}

pub fn (dev &PCIDevice) write[T](offset u32, value T) {
	dev.get_address(offset)
	kio.port_out[T](u16(0xcfc + (offset & 3)), value)
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

pub fn (dev &PCIDevice) set_msi(vector u8) {
	mut message_control := dev.read[u16](dev.msi_offset + 2)

	mut reg0 := 0x4
	mut reg1 := 0x8

	if ((message_control >> 7) & 1) == 1 { // 64 bit support
		reg1 = 0xc
	}

	address := (0xfee << 20) | (bsp_lapic_id << 12)
	data := vector

	dev.write[u32](u32(dev.msi_offset + reg0), address)
	dev.write[u32](u32(dev.msi_offset + reg1), data)

	message_control |= 1 // enable=1
	message_control &= ~(0b111 << 4) // mme=0
	dev.write[u16](dev.msi_offset + 2, message_control)
}

pub fn (dev &PCIDevice) set_msix(vector u8) bool {
	msix_vector := dev.msix_table_bitmap.alloc() or {
		print('pci: [${dev.bus:x}:${dev.slot:x}:${dev.function:x}:${dev.parent:x}] msix no free vectors\n')
		return false
	}

	table_ptr := dev.read[u32](dev.msix_offset + 4)
	dev.read[u32](dev.msix_offset + 8)

	bar_index := table_ptr & 0b111
	bar_offset := (table_ptr >> 3) << 3

	if dev.is_bar_present(u8(bar_index)) == false {
		print('pci: [${dev.bus:x}:${dev.slot:x}:${dev.function:x}:${dev.parent:x}] msix table bar not present\n')
		return false
	}

	table_bar := dev.get_bar(u8(bar_index))
	bar_base := table_bar.base + bar_offset + u64(msix_vector * 16)

	address := (0xfee << 20) | (bsp_lapic_id << 12)
	data := vector

	kio.mmout(&u32(bar_base), address) // address low
	kio.mmout(&u32(bar_base + 4), u32(0)) // address high
	kio.mmout(&u32(bar_base + 8), data) // data
	kio.mmout(&u32(bar_base + 12), u32(0)) // vector control
	mut message_control := dev.read[u16](dev.msix_offset + 2)

	message_control |= (1 << 15) // enable=1
	message_control &= ~(1 << 14) // mask=0
	dev.write[u16](dev.msix_offset + 2, message_control)

	return true
}

pub fn (dev &PCIDevice) enable_bus_mastering() {
	if (dev.read[u32](0x4) & (1 << 2)) == 0 {
		dev.write[u32](0x4, dev.read[u32](0x4) | (1 << 2))
	}
}

fn (dev &PCIDevice) get_address(offset u32) {
	address := (u32(dev.bus) << 16) | (u32(dev.slot) << 11) | (u32(dev.function) << 8) | (offset & ~(u32(3))) | 0x80000000
	kio.port_out[u32](0xcf8, address)
}
