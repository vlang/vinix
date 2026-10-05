@[has_globals]
module pci

import aarch64.kio
import katomic

// ECAM base address (set during PCI init from device tree)
__global (
	ecam_base  = u64(0)
	ecam_buses = u32(0)
	config_transport_word = u64(0)
	config_transport_daif = u64(0)
)

// Save the complete DAIF state and mask only IRQs. The ordinary ARM klock
// records only I and toggles all DAIF masks; using it here would change a
// caller's independently masked FIQ/debug/SError state. NMI/FIQ recursion into
// PCI configuration remains outside this ordinary IRQ-safe lock contract.
@[export: 'vinix_pci_config_lock']
fn config_lock() {
	mut flags := u64(0)
	asm volatile aarch64 {
		mrs flags, daif
		msr daifset, 2
		; =r (flags)
		; ; memory
	}
	for !katomic.cas_acquire(mut &config_transport_word, u64(0), u64(1)) {
		asm volatile aarch64 {
			wfe
			; ; ; memory
		}
	}
	config_transport_daif = flags
}

@[export: 'vinix_pci_config_unlock']
fn config_unlock() {
	// Snapshot before publishing unlock, so a new owner cannot overwrite the
	// state this CPU must restore. Release ordering precedes its wake event.
	flags := config_transport_daif
	katomic.store(mut &config_transport_word, u64(0))
	asm volatile aarch64 {
		// Complete publication before waking CASA/WFE waiters. Otherwise a
		// waiter can consume SEV, still observe locked, and miss the unlock.
		dsb ishst
		sev
		msr daif, flags
		; ; r (flags)
		; memory
	}
}

// Publish a boot-lifetime mapped aperture covering buses from zero. Callers
// map the complete extent first; live configuration readers never remap it.
pub fn set_ecam(virt u64, buses u32) bool {
	if virt == 0 || (virt & 0xfff) != 0 || buses == 0 || buses > 256 {
		return false
	}
	size := u64(buses) << 20
	if virt > u64(-1) - (size - 1) {
		return false
	}
	config_lock()
	if ecam_base != 0 {
		same := ecam_base == virt && ecam_buses == buses
		config_unlock()
		return same
	}
	ecam_base = virt
	ecam_buses = buses
	config_unlock()
	return true
}

@[export: 'vinix_pci_config_limit']
fn config_limit(bus u32) u32 {
	return if ecam_base != 0 && bus < ecam_buses { u32(4096) } else { u32(0) }
}

// Validated transaction callers hold the transport lock; addition keeps a merely
// page-aligned virtual base independent of the bus/device/function fields.
fn ecam_address(bus u32, slot u32, function u32, offset u32) u64 {
	return ecam_base + (u64(bus) << 20) + (u64(slot) << 15) + (u64(function) << 12) + offset
}

@[export: 'vinix_pci_config_read_raw']
fn config_read_raw(bus u32, slot u32, function u32, offset u32, width u32) u32 {
	addr := ecam_address(bus, slot, function, offset)
	return match width {
		1 { u32(kio.mmin[u8](unsafe { &u8(addr) })) }
		2 { u32(kio.mmin[u16](unsafe { &u16(addr) })) }
		else { kio.mmin[u32](unsafe { &u32(addr) }) }
	}
}

@[export: 'vinix_pci_config_write_raw']
fn config_write_raw(bus u32, slot u32, function u32, offset u32, width u32, value u32) {
	addr := ecam_address(bus, slot, function, offset)
	match width {
		1 { kio.mmout[u8](unsafe { &u8(addr) }, u8(value)) }
		2 { kio.mmout[u16](unsafe { &u16(addr) }, u16(value)) }
		else { kio.mmout[u32](unsafe { &u32(addr) }, value) }
	}
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
