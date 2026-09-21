@[has_globals]
module pci

import aarch64.kio

// ECAM base address (set during PCI init from device tree)
__global (
	ecam_base = u64(0)
)

// ECAM config space: each device's 4KB config space is memory-mapped
// at ecam_base + (bus << 20 | slot << 15 | func << 12 | offset).
fn ecam_address(bus u8, slot u8, function u8, offset u32) u64 {
	return ecam_base + (u64(bus) << 20) | (u64(slot) << 15) | (u64(function) << 12) | u64(offset & 0xffc)
}

pub fn (dev &PCIDevice) read[T](offset u32) T {
	addr := ecam_address(dev.bus, dev.slot, dev.function, offset)
	if addr == 0 {
		return T(0)
	}
	return kio.mmin[T](unsafe { &T(addr) })
}

pub fn (dev &PCIDevice) write[T](offset u32, value T) {
	addr := ecam_address(dev.bus, dev.slot, dev.function, offset)
	if addr == 0 {
		return
	}
	kio.mmout[T](unsafe { &T(addr) }, value)
}

// MSI on ARM64: uses GICv3 ITS (Interrupt Translation Service).
// For Apple Silicon, MSI is routed through the AIC.
pub fn (dev &PCIDevice) set_msi(vector u8) {
	// Apple AIC handles MSI differently -- the AIC driver maps
	// MSI doorbell addresses during PCIe init. For now, configure
	// the MSI capability with a placeholder address that the AIC
	// driver will have set up.
	mut message_control := dev.read[u16](dev.msi_offset + 2)

	mut reg0 := u16(0x4)
	mut reg1 := u16(0x8)

	if ((message_control >> 7) & 1) == 1 {
		reg1 = 0xc
	}

	// AIC MSI doorbell address (set by AIC driver during PCIe init)
	address := aic_msi_doorbell
	data := u32(vector)

	dev.write[u32](u32(dev.msi_offset + reg0), u32(address))
	dev.write[u32](u32(dev.msi_offset + reg1), data)

	message_control |= 1
	message_control &= ~(u16(0b111) << 4)
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

	address := aic_msi_doorbell
	data := u32(vector)

	kio.mmout(unsafe { &u32(bar_base) }, u32(address))
	kio.mmout(unsafe { &u32(bar_base + 4) }, u32(address >> 32))
	kio.mmout(unsafe { &u32(bar_base + 8) }, data)
	kio.mmout(unsafe { &u32(bar_base + 12) }, u32(0))

	mut message_control := dev.read[u16](dev.msix_offset + 2)
	message_control |= (1 << 15)
	message_control &= ~(u16(1) << 14)
	dev.write[u16](dev.msix_offset + 2, message_control)

	return true
}

__global (
	aic_msi_doorbell = u64(0)
)
