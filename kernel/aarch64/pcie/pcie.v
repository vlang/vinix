@[has_globals]
module pcie

// Apple PCIe controller -- ECAM (Enhanced Configuration Access Mechanism)
// On Apple Silicon, PCIe config space is accessed via MMIO instead of port I/O.
// The ECAM base address is obtained from the device tree.

import aarch64.kio
import memory

__global (
	ecam_base = u64(0)
)

pub fn initialise(base u64) {
	ecam_base = base + higher_half
	println('pcie: Apple PCIe ECAM at 0x${base:x}')
}

// Calculate the ECAM address for a given BDF + register offset
fn ecam_addr(bus u8, slot u8, function u8, offset u32) u64 {
	return ecam_base + (u64(bus) << 20) | (u64(slot) << 15) | (u64(function) << 12) | (u64(offset) & 0xfff)
}

// Read a value from PCIe config space via ECAM
pub fn config_read[T](bus u8, slot u8, function u8, offset u32) T {
	addr := ecam_addr(bus, slot, function, offset)
	return kio.mmin(unsafe { &T(addr) })
}

// Write a value to PCIe config space via ECAM
pub fn config_write[T](bus u8, slot u8, function u8, offset u32, value T) {
	addr := ecam_addr(bus, slot, function, offset)
	kio.mmout(unsafe { &T(addr) }, value)
}

pub fn config_read32(bus u8, slot u8, function u8, offset u32) u32 {
	addr := ecam_addr(bus, slot, function, offset)
	return kio.mmin32(unsafe { &u32(addr) })
}

pub fn config_write32(bus u8, slot u8, function u8, offset u32, value u32) {
	addr := ecam_addr(bus, slot, function, offset)
	kio.mmout32(unsafe { &u32(addr) }, value)
}
