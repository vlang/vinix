// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// AMD-Vi, AMD's IOMMU.
//
// The parts, in the order a boot goes through them:
//
//	amdvi_ivrs_amd64.v  what the ACPI IVRS table says: units, devices, memory
//	amdvi_amd64.v       this file: find the table and start each unit
module dma

import acpi

const amdvi_page_bytes = u64(4096)

__global (
	// What the machine's IVRS table said. Read once at boot.
	amdvi_ivrs AmdviIvrs
)

// Find the machine's AMD IOMMUs. Called once, by dma.initialise(), and only
// when the command line asked for translation.
fn amdvi_initialise() {
	table := acpi.find_sdt('IVRS', 0) or { return }
	length := unsafe { *&u32(u64(table) + 4) }
	if !amdvi_parse_ivrs(unsafe { &u8(table) }, length, mut amdvi_ivrs) {
		C.kprintf(c'amdvi: the IVRS table is not valid (%llu bytes); no unit is switched on\n',
			u64(length))
		return
	}
	if amdvi_ivrs.malformed != 0 || amdvi_ivrs.foreign_segments != 0 {
		C.kprintf(c'amdvi: IVRS: %llu malformed blocks and %llu for PCI segments other than 0 passed over\n',
			u64(amdvi_ivrs.malformed), u64(amdvi_ivrs.foreign_segments))
	}
}
