@[has_globals]
module pci

import x86.kio
import klock

__global (
	config_transport_lock = klock.Lock{}
)

@[export: 'vinix_pci_config_lock']
fn config_lock() {
	config_transport_lock.acquire()
}

@[export: 'vinix_pci_config_unlock']
fn config_unlock() {
	config_transport_lock.release()
}

@[export: 'vinix_pci_config_limit']
fn config_limit(bus u32) u32 {
	return 256 // Conventional CF8/CFC only; extended ECAM is not configured.
}

// The C core validates BDF/offset/width and holds the shared transport lock
// throughout the address/data pair. Subword accesses use actual subword I/O.
fn config_select(bus u32, slot u32, function u32, offset u32) {
	address := (bus << 16) | (slot << 11) | (function << 8) | (offset & ~u32(3)) | 0x80000000
	kio.port_out[u32](0xcf8, address)
}

@[export: 'vinix_pci_config_read_raw']
fn config_read_raw(bus u32, slot u32, function u32, offset u32, width u32) u32 {
	config_select(bus, slot, function, offset)
	port := u16(0xcfc + (offset & 3))
	return match width {
		1 { u32(kio.port_in[u8](port)) }
		2 { u32(kio.port_in[u16](port)) }
		else { kio.port_in[u32](port) }
	}
}

@[export: 'vinix_pci_config_write_raw']
fn config_write_raw(bus u32, slot u32, function u32, offset u32, width u32, value u32) {
	config_select(bus, slot, function, offset)
	port := u16(0xcfc + (offset & 3))
	match width {
		1 { kio.port_out[u8](port, u8(value)) }
		2 { kio.port_out[u16](port, u16(value)) }
		else { kio.port_out[u32](port, value) }
	}
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
		C.kprintf(c'pci: [%llx:%llx:%llx:%lld] msix no free vectors\n', u64(dev.bus), u64(dev.slot),
			u64(dev.function), i64(dev.parent))
		return false
	}

	table_ptr := dev.read[u32](dev.msix_offset + 4)
	dev.read[u32](dev.msix_offset + 8)

	bar_index := table_ptr & 0b111
	bar_offset := (table_ptr >> 3) << 3

	if dev.is_bar_present(u8(bar_index)) == false {
		C.kprintf(c'pci: [%llx:%llx:%llx:%lld] msix table bar not present\n', u64(dev.bus),
			u64(dev.slot), u64(dev.function), i64(dev.parent))
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
