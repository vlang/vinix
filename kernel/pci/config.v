module pci

#include "pci_config.h"

// Every native caller and compatibility client uses this one transport lock.
// Its critical sections contain only checked configuration I/O; in particular
// they never allocate, sleep, log, or acquire device/registry/mapping locks.
pub const config_ok = 0
pub const config_bad_register = 1
pub const config_unavailable = 2

fn C.vinix_pci_config_read(u32, u32, u32, u32, u64, u32, &u32) int
fn C.vinix_pci_config_write(u32, u32, u32, u32, u64, u32, u32) int
fn C.vinix_pci_config_update_command(u32, u32, u32, u32, u16, u16) int

// Results are borrowed for this synchronous call and remain untouched on error.
pub fn (dev &PCIDevice) config_read(offset u64, width u32, value &u32) int {
	return C.vinix_pci_config_read(0, dev.bus, dev.slot, dev.function, offset, width, value)
}

pub fn (dev &PCIDevice) config_write(offset u64, width u32, value u32) int {
	return C.vinix_pci_config_write(0, dev.bus, dev.slot, dev.function, offset, width, value)
}

pub fn (dev &PCIDevice) update_command(clear u16, set u16) int {
	return C.vinix_pci_config_update_command(0, dev.bus, dev.slot, dev.function, clear, set)
}

pub fn (dev &PCIDevice) read[T](offset u32) T {
	mut value := u32(0)
	if dev.config_read(u64(offset), u32(sizeof(T)), unsafe { &value }) != config_ok {
		return T(-1)
	}
	return T(value)
}

pub fn (dev &PCIDevice) write[T](offset u32, value T) {
	dev.config_write(u64(offset), u32(sizeof(T)), u32(value))
}
