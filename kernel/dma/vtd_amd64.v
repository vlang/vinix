// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module dma

import acpi
import memory

__global (
	// The DMAR table as parsed; nil when the machine has none worth using.
	vtd_firmware &VtdFirmware
)

// A zeroed record to parse a DMAR table into, or nil.
fn vtd_firmware_new() &VtdFirmware {
	firmware := memory.malloc_packed_fallible(sizeof(VtdFirmware))
	if firmware != unsafe { nil } {
		unsafe { C.memset(firmware, 0, sizeof(VtdFirmware)) }
	}
	return unsafe { &VtdFirmware(firmware) }
}

// Intel VT-d. So far the DMAR table is read and what it describes is
// reported; no unit is switched on, so none is registered.
fn vtd_initialise() {
	table := acpi.find_sdt('DMAR', 0) or { return }
	// Kept for the life of the machine: what each unit covers is asked of it
	// for every device.
	mut firmware := vtd_firmware_new()
	if firmware == unsafe { nil } {
		print('vtd: no memory to read the DMAR table\n')
		return
	}
	if !vtd_parse_table(table, mut firmware) {
		print('vtd: the DMAR table is malformed or beyond what is supported; no unit switched on\n')
		memory.free(voidptr(firmware))
		return
	}
	vtd_resolve_scopes(mut firmware)
	vtd_firmware = firmware
	C.kprintf(c'vtd: the DMAR table describes %llu units and %llu reserved ranges\n', u64(firmware.drhd_count),
		u64(firmware.rmrr_count))
}
