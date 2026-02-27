module pci

import x86.kio

pub fn (dev &PCIDevice) read[T](offset u32) T {
	dev.get_address(offset)
	return kio.port_in[T](u16(0xcfc + (offset & 3)))
}

pub fn (dev &PCIDevice) write[T](offset u32, value T) {
	dev.get_address(offset)
	kio.port_out[T](u16(0xcfc + (offset & 3)), value)
}

fn (dev &PCIDevice) get_address(offset u32) {
	address := (u32(dev.bus) << 16) | (u32(dev.slot) << 11) | (u32(dev.function) << 8) | (offset & ~(u32(3))) | 0x80000000
	kio.port_out[u32](0xcf8, address)
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

	kio.mmout(unsafe { &u32(bar_base) }, address) // address low
	kio.mmout(unsafe { &u32(bar_base + 4) }, u32(0)) // address high
	kio.mmout(unsafe { &u32(bar_base + 8) }, data) // data
	kio.mmout(unsafe { &u32(bar_base + 12) }, u32(0)) // vector control
	mut message_control := dev.read[u16](dev.msix_offset + 2)

	message_control |= (1 << 15) // enable=1
	message_control &= ~(1 << 14) // mask=0
	dev.write[u16](dev.msix_offset + 2, message_control)

	return true
}
