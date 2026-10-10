// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// AMD-Vi, AMD's IOMMU.
//
// The parts, in the order a boot goes through them:
//
//	amdvi_ivrs_amd64.v      what the ACPI IVRS table says: units, devices, memory
//	amdvi_amd64.v           this file: find the table and start each unit
//	amdvi_unit_amd64.v      a unit's registers and tables, and switching it on
//	amdvi_commands_amd64.v  the command buffer: making a unit forget
//	amdvi_domain_amd64.v    page tables for a device, and the DMA layer's six calls
//	amdvi_events_amd64.v    the event log, and /sys/class/iommu
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
	levels := amdvi_levels_needed()
	if levels == 0 {
		print('amdvi: this machine has memory beyond 256 TiB, which needs page tables of five levels; no unit is switched on\n')
		return
	}
	for i in 0 .. amdvi_ivrs.block_count {
		ivhd := unsafe { &amdvi_ivrs.blocks[i] }
		if !ivhd.chosen {
			continue
		}
		if amdvi_unit_count >= amdvi_max_units || dma_iommu_count + amdvi_unit_count >= max_iommus {
			C.kprintf(c'amdvi: more units than the %llu there is room for; the one at 0x%llx is left off\n',
				u64(max_iommus), ivhd.mmio_phys)
			continue
		}
		mut unit := amdvi_new_unit(unsafe { &u8(table) }, ivhd, levels)
		if !amdvi_start_unit(mut unit) {
			unsafe {
				unit.name.free()
				unit.entries.free()
				free(unit)
			}
			continue
		}
		C.kprintf(c'amdvi: %.*s at 0x%llx (%02llx:%02llx.%llx, IVHD type %llxh): ids to 0x%llx, %llu-level tables, features 0x%llx\n',
			i32(unit.name.len), unit.name.str, unit.mmio_phys, u64(unit.devid >> 8), u64((unit.devid >> 3) & 31),
			u64(unit.devid & 7), u64(unit.kind), u64(unit.last_devid), u64(unit.levels),
			unit.features)
		unit.iommu = register_iommu(Iommu{
			name:    unit.name
			covers:  amdvi_covers
			attach:  amdvi_attach
			detach:  amdvi_detach
			map:     amdvi_map
			unmap:   amdvi_unmap
			map_all: amdvi_map_all
			data:    voidptr(unit)
		}) or {
			// Checked for above; but a unit nobody can ask for a domain
			// must not stay on, with every device behind it cut off.
			amdvi_quiesce(unit)
			unit.on = false
			continue
		}
		amdvi_units[amdvi_unit_count] = unit
		amdvi_unit_count++
	}
	if amdvi_unit_count != 0 {
		amdvi_start_poller()
	}
}

// The record for the unit an IVHD block describes. Made once per unit at
// boot and kept for the life of the machine.
fn amdvi_new_unit(table &u8, ivhd &AmdviBlock, levels u8) &AmdviUnit {
	mut unit := &AmdviUnit{}
	unit.index = amdvi_unit_count
	unit.name = amdvi_unit_name(amdvi_unit_count)
	unit.kind = ivhd.kind
	unit.ivhd_flags = ivhd.flags
	unit.devid = ivhd.devid
	unit.cap_offset = ivhd.cap_offset
	unit.mmio_phys = ivhd.mmio_phys
	unit.levels = levels
	// Counted first, so that the list is made at its final size.
	mut none_yet := []AmdviEntry{}
	count := amdvi_block_entries(table, ivhd, mut none_yet, false)
	mut entries := []AmdviEntry{cap: count}
	entries.flags |= .noslices
	amdvi_block_entries(table, ivhd, mut entries, true)
	unit.entries = entries
	unit.last_devid = amdvi_last_devid(entries)
	// Firmware's copy of the feature register, where the block has one. It
	// is what Linux goes by when the register itself disagrees.
	if ivhd.has_efr {
		unit.features = ivhd.efr
		unit.features2 = ivhd.efr2
	}
	return unit
}
