// SPDX-License-Identifier: GPL-2.0-only
module pci

#include "pci_config.h"

// These synchronous platform operations share the IRQ-safe transport lock.
// The critical section cannot allocate, sleep, log or acquire mapping locks.
fn C.vinix_pci_config_lock()
fn C.vinix_pci_config_unlock()
fn C.vinix_pci_config_limit(bus u32) u32
fn C.vinix_pci_config_read_raw(bus u32, slot u32, function u32, offset u32, width u32) u32
fn C.vinix_pci_config_write_raw(bus u32, slot u32, function u32, offset u32, width u32, value u32)

fn valid_config_address(bus u32, slot u32, function u32, offset u64, width u32) bool {
	return bus <= 255 && slot <= 31 && function <= 7
		&& (width == 1 || width == 2 || width == 4) && offset & u64(width - 1) == 0
}

// Query under the lock; check width before subtracting so short windows cannot
// wrap the upper bound. Transport and mapping stay stable for the transaction.
fn config_register_status(bus u32, offset u64, width u32) i32 {
	limit := C.vinix_pci_config_limit(bus)
	if limit == 0 { return 2 }
	if width > limit || offset > u64(limit - width) { return 1 }
	return 0
}

fn config_width_mask(width u32) u32 {
	if width == 1 { return 0xff }
	if width == 2 { return 0xffff }
	return ~u32(0)
}

// Keep the native and LinuxKPI C ABI. Borrow the output only during this call
// and leave it untouched on error; absent functions are successful all-ones reads.
@[export: 'vinix_pci_config_read']
fn checked_config_read(domain u32, bus u32, slot u32, function u32,
	offset u64, width u32, value &u32) i32 {
	if usize(value) == 0 || !valid_config_address(bus, slot, function, offset, width) {
		return 1
	}
	if domain != 0 { return 2 }
	C.vinix_pci_config_lock()
	status := config_register_status(bus, offset, width)
	if status == 0 {
		raw := C.vinix_pci_config_read_raw(bus, slot, function, u32(offset), width)
		unsafe {
			*value = raw & config_width_mask(width)
		}
	}
	C.vinix_pci_config_unlock()
	return status
}

@[export: 'vinix_pci_config_write']
fn checked_config_write(domain u32, bus u32, slot u32, function u32,
	offset u64, width u32, value u32) i32 {
	if !valid_config_address(bus, slot, function, offset, width) { return 1 }
	if domain != 0 { return 2 }
	C.vinix_pci_config_lock()
	status := config_register_status(bus, offset, width)
	if status == 0 {
		C.vinix_pci_config_write_raw(bus, slot, function, u32(offset), width,
			value & config_width_mask(width))
	}
	C.vinix_pci_config_unlock()
	return status
}

// One locked 16-bit read-modify-write of COMMAND. Never write the adjacent
// STATUS register, whose bits have write-one-to-clear semantics.
@[export: 'vinix_pci_config_update_command']
fn checked_update_command(domain u32, bus u32, slot u32, function u32,
	clear u16, set u16) i32 {
	if !valid_config_address(bus, slot, function, 4, 2) { return 1 }
	if domain != 0 { return 2 }
	C.vinix_pci_config_lock()
	status := config_register_status(bus, 4, 2)
	if status == 0 {
		old := u16(C.vinix_pci_config_read_raw(bus, slot, function, 4, 2))
		updated := (old & ~clear) | set
		if updated != old {
			C.vinix_pci_config_write_raw(bus, slot, function, 4, 2, u32(updated))
		}
	}
	C.vinix_pci_config_unlock()
	return status
}
