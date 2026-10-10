// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// One AMD IOMMU: its registers, the tables it reads, and switching it on.
//
// A unit is told what to do through three pieces of memory the kernel gives
// it, each named to it by a base register:
//
//	device table    one 256-bit entry per requester id: is the entry valid,
//	                where are the device's page tables, which domain is it in
//	command buffer  a ring the kernel writes commands into -- forget this
//	                device's entry, forget this domain's translations, tell
//	                me when you have got this far
//	event log       a ring the unit writes into when it turns a device away
//
// and one control register whose bits start the rings and, last, translation
// itself. The order below is the one the AMD I/O Virtualization specification
// gives and Linux follows: everything off, tables in place, command buffer,
// event log, then the unit.
//
// A unit that is on must turn away every device nobody has vouched for, so
// every entry is written in a blocked form before the unit is switched on --
// no access allowed, and tables that map nothing -- and stays that way until
// a driver asks for memory for the device (see amdvi_domain_amd64.v).
//
// Interrupts are not remapped. Every entry is left with its interrupt table
// marked invalid, which the specification defines as "forward interrupts
// unchanged", as Linux leaves them when interrupt remapping is off.
module dma

import devcore
import klock
import lib
import limine
import memory
import pci
import x86.kio

// Registers, as offsets from the base the IVHD block gives.
const amdvi_reg_device_table = u64(0x0000)
const amdvi_reg_command_base = u64(0x0008)
const amdvi_reg_event_base = u64(0x0010)
const amdvi_reg_control = u64(0x0018)
const amdvi_reg_features = u64(0x0030)
const amdvi_reg_features2 = u64(0x01a0)
const amdvi_reg_command_head = u64(0x2000)
const amdvi_reg_command_tail = u64(0x2008)
const amdvi_reg_event_head = u64(0x2010)
const amdvi_reg_event_tail = u64(0x2018)
const amdvi_reg_status = u64(0x2020)
// Everything above ends well inside the first 16 KiB, which every unit has.
const amdvi_register_span = u64(0x4000)

// Control register bits.
const amdvi_control_enable = u64(1) << 0
const amdvi_control_ht_tunnel = u64(1) << 1
const amdvi_control_event_log = u64(1) << 2
const amdvi_control_event_interrupt = u64(1) << 3
const amdvi_control_timeout_mask = u64(7) << 5
// How long the unit waits on a device's own translation cache: one second.
const amdvi_control_timeout_1s = u64(4) << 5
const amdvi_control_pass_posted = u64(1) << 8
const amdvi_control_response_pass_posted = u64(1) << 9
const amdvi_control_coherent = u64(1) << 10
const amdvi_control_isochronous = u64(1) << 11
const amdvi_control_command_buffer = u64(1) << 12
const amdvi_control_ppr_log = u64(1) << 13
const amdvi_control_ppr_interrupt = u64(1) << 14
const amdvi_control_ga_log = u64(1) << 28
const amdvi_control_ga_interrupt = u64(1) << 29

// Status register bits.
const amdvi_status_event_overflow = u32(1) << 0
const amdvi_status_event_running = u32(1) << 3
const amdvi_status_command_running = u32(1) << 4

// IVHD flags: which control bits firmware wants set.
const amdvi_ivhd_ht_tunnel = u8(0x01)
const amdvi_ivhd_pass_posted = u8(0x02)
const amdvi_ivhd_response_pass_posted = u8(0x04)
const amdvi_ivhd_isochronous = u8(0x08)

// The capability block of the unit's own PCI function.
const amdvi_capability_id = u32(0x0f)
const amdvi_capability_np_cache = u32(1) << 26
const amdvi_capability_features = u32(1) << 27

// Extended feature bits.
const amdvi_feature_invalidate_all = u64(1) << 6

// Device table entries: four 64-bit words per requester id.
const amdvi_dte_bytes = u64(32)
const amdvi_dte_valid = u64(1) << 0
const amdvi_dte_translation_valid = u64(1) << 1
const amdvi_dte_mode_shift = u64(9)
const amdvi_dte_read = u64(1) << 61
const amdvi_dte_write = u64(1) << 62
// Second word: the domain id, and the bits that are a device's own and stay
// whatever domain it is in.
const amdvi_dte_domain_mask = u64(0xffff)
const amdvi_dte_sysmgt1 = u64(1) << 40
const amdvi_dte_sysmgt2 = u64(1) << 41
// Third word: bit 0 would make the interrupt table valid. It never is.
const amdvi_dte_init_pass = u64(1) << 56
const amdvi_dte_extint_pass = u64(1) << 57
const amdvi_dte_nmi_pass = u64(1) << 58
const amdvi_dte_lint0_pass = u64(1) << 62
const amdvi_dte_lint1_pass = u64(1) << 63
// The base register counts 4 KiB pages in nine bits.
const amdvi_device_table_limit = u64(512)

// IVHD device entry settings.
const amdvi_setting_init_pass = u8(0x01)
const amdvi_setting_extint_pass = u8(0x02)
const amdvi_setting_nmi_pass = u8(0x04)
const amdvi_setting_sysmgt1 = u8(0x10)
const amdvi_setting_sysmgt2 = u8(0x20)
const amdvi_setting_lint0_pass = u8(0x40)
const amdvi_setting_lint1_pass = u8(0x80)

// Both rings hold 512 entries of 16 bytes; the base registers take the
// count as a power of two.
const amdvi_ring_bytes = u32(8192)
const amdvi_ring_pages = u64(2)
const amdvi_ring_size_code = u64(9) << 56

// A register settles, and a command is carried out, in microseconds. Past
// this the unit is taken to be broken.
const amdvi_register_timeout_ns = 100 * devcore.millisecond

// As many units as the DMA layer has room for.
const amdvi_max_units = max_iommus

@[heap]
struct AmdviUnit {
mut:
	index int
	// "ivhd0", as Linux names it under /sys/class/iommu.
	name string

	// What the IVHD block said.
	kind       u8
	ivhd_flags u8
	devid      u16
	cap_offset u16
	mmio_phys  u64
	entries    []AmdviEntry
	// The highest requester id the entries name.
	last_devid u32

	// The hardware.
	regs       u64
	capability u32
	features   u64
	features2  u64
	// The unit remembers that an address was not mapped, so a new mapping
	// has to be announced to it like a removed one.
	np_cache bool
	// Translation is on.
	on bool

	// Physical addresses of what the unit was given.
	device_table       u64
	device_table_pages u64
	commands           u64
	events             u64
	// Where the unit writes the number of each "tell me when you get here".
	semaphore u64
	// A page of table with no entries: what a blocked device is pointed at.
	nothing u64

	// The command buffer's tail and the last number handed out; under `lock`.
	lock             klock.Lock
	command_tail     u32
	command_head     u32
	command_sequence u64
	command_timeouts u64
	commands_queued  u64

	// What the event log has held; under event_lock. See amdvi_events_amd64.v.
	event_lock      klock.Lock
	event_stalled   u32
	events_seen     u64
	events_by_kind  [amdvi_event_kinds]u64
	events_unshown  u64
	event_overflows u64
	has_fault       bool
	last_fault      AmdviEvent

	// How many levels a device's page tables have here.
	levels u8

	// One record per device that has ever had a domain; under domain_lock.
	domains     &AmdviDomain = unsafe { nil }
	domain_lock klock.Lock
	next_domain u32
	// Pages of page table in use, and pages given up on because the unit
	// would not confirm that it had let go of them.
	table_pages  u64
	leaked_pages u64
	// The record of this unit in the DMA layer's list.
	iommu &Iommu = unsafe { nil }
}

__global (
	amdvi_units      [amdvi_max_units]&AmdviUnit
	amdvi_unit_count int
)

fn amdvi_read32(unit &AmdviUnit, offset u64) u32 {
	return kio.mmin[u32](unsafe { &u32(unit.regs + offset) })
}

fn amdvi_write32(unit &AmdviUnit, offset u64, value u32) {
	kio.mmout[u32](unsafe { &u32(unit.regs + offset) }, value)
}

fn amdvi_read64(unit &AmdviUnit, offset u64) u64 {
	return kio.mmin[u64](unsafe { &u64(unit.regs + offset) })
}

fn amdvi_write64(unit &AmdviUnit, offset u64, value u64) {
	kio.mmout[u64](unsafe { &u64(unit.regs + offset) }, value)
}

fn amdvi_control_set(unit &AmdviUnit, bits u64) {
	amdvi_write64(unit, amdvi_reg_control, amdvi_read64(unit, amdvi_reg_control) | bits)
}

fn amdvi_control_clear(unit &AmdviUnit, bits u64) {
	amdvi_write64(unit, amdvi_reg_control, amdvi_read64(unit, amdvi_reg_control) & ~bits)
}

// The kernel's direct map covers the first 4 GiB, where firmware puts a
// unit's registers and where its MTRRs make the hole they sit in uncached.
// Registers above that are mapped here, uncached.
fn amdvi_map_registers(phys u64, length u64) u64 {
	hhdm := memory.get_hhdm_offset()
	if phys + length <= u64(0x100000000) {
		return phys + hhdm
	}
	// PWT and PCD together select the uncached PAT entry.
	flags := memory.pte_present | memory.pte_writable | memory.pte_noexec | (u64(1) << 3) | (u64(1) << 4)
	for page := phys; page < phys + length; page += amdvi_page_bytes {
		kernel_pagemap.map_page(page + hhdm, page, flags) or { return 0 }
	}
	return phys + hhdm
}

// "ivhd0": made once per unit and kept.
fn amdvi_unit_name(index int) string {
	mut text := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
	unsafe { *text = lib.new_text(8) }
	text.add('ivhd')
	text.add_unsigned(u64(index))
	return text.str()
}

// How many levels of page table reach every address a device may be told.
// Bus addresses are physical addresses here, so that is the top of RAM and of
// the memory firmware wants left reachable: three levels span 512 GiB, four
// 256 TiB. Zero when there is memory beyond that; such a machine needs a
// fifth level, which not every unit has and this driver does not make.
fn amdvi_levels_needed() u8 {
	mut top := u64(0)
	memmap := memmap_req.response
	if memmap != unsafe { nil } {
		entries := memmap.entries
		for i := u64(0); i < memmap.entry_count; i++ {
			entry := unsafe { entries[i] }
			if entry.@type == u64(limine.limine_memmap_reserved)
				|| entry.@type == u64(limine.limine_memmap_bad_memory) {
				continue
			}
			if entry.base + entry.length > top {
				top = entry.base + entry.length
			}
		}
	}
	for range in amdvi_ivrs.unity {
		if range.end > top {
			top = range.end
		}
	}
	if top <= u64(1) << 39 {
		return 3
	}
	if top <= u64(1) << 48 {
		return 4
	}
	return 0
}

// The first word of a device table entry that turns the device away: valid,
// neither read nor write allowed, and page tables that map nothing. Every
// access faults and is logged.
//
// The specification, and Linux, make do with the first two: an entry with no
// tables at all (mode 0) leaves access to the read and write bits alone. The
// empty table is there for an implementation that reads mode 0 as "pass
// everything" without looking at those bits, which QEMU's does; one that
// honours them never walks it. It is one page a unit, shared by every blocked
// device, and nothing is ever written to it.
fn amdvi_blocked_word(unit &AmdviUnit, second u64) u64 {
	mut word := unit.nothing | (u64(unit.levels) << amdvi_dte_mode_shift) | amdvi_dte_valid | amdvi_dte_translation_valid
	// AMD erratum 63: a device whose system management setting is 01 has its
	// management messages dropped unless the entry allows writes. It is the
	// southbridge of a 2009 chipset; Linux makes the same exception.
	if second & amdvi_dte_sysmgt1 != 0 && second & amdvi_dte_sysmgt2 == 0 {
		word |= amdvi_dte_write
	}
	return word
}

fn amdvi_dte(unit &AmdviUnit, devid u32) &u64 {
	return unsafe { &u64(unit.device_table + higher_half + u64(devid) * amdvi_dte_bytes) }
}

// Write every entry of the device table in its blocked form, with the
// settings the IVHD entries give each device. Before the unit is on.
fn amdvi_fill_device_table(mut unit AmdviUnit) {
	for entry in unit.entries {
		mut second := u64(0)
		mut third := u64(0)
		if entry.settings & amdvi_setting_sysmgt1 != 0 {
			second |= amdvi_dte_sysmgt1
		}
		if entry.settings & amdvi_setting_sysmgt2 != 0 {
			second |= amdvi_dte_sysmgt2
		}
		if entry.settings & amdvi_setting_init_pass != 0 {
			third |= amdvi_dte_init_pass
		}
		if entry.settings & amdvi_setting_extint_pass != 0 {
			third |= amdvi_dte_extint_pass
		}
		if entry.settings & amdvi_setting_nmi_pass != 0 {
			third |= amdvi_dte_nmi_pass
		}
		if entry.settings & amdvi_setting_lint0_pass != 0 {
			third |= amdvi_dte_lint0_pass
		}
		if entry.settings & amdvi_setting_lint1_pass != 0 {
			third |= amdvi_dte_lint1_pass
		}
		if second == 0 && third == 0 {
			continue
		}
		for devid := u32(entry.first); devid <= u32(entry.last) && devid <= unit.last_devid; devid++ {
			mut words := amdvi_dte(unit, devid)
			unsafe {
				words[1] |= second
				words[2] |= third
			}
		}
	}
	// Ids no entry names are blocked too, as in Linux: the table is the
	// unit's whole view of the bus, and nothing in it is left open.
	for devid := u32(0); devid <= unit.last_devid; devid++ {
		mut words := amdvi_dte(unit, devid)
		unsafe {
			words[0] = amdvi_blocked_word(unit, words[1])
		}
	}
}

// Read the capability block of the unit's own PCI function: whether it has
// an extended feature register, and whether it caches "not mapped".
fn amdvi_read_capability(mut unit AmdviUnit) {
	// Without the block, assume the cautious answer to the second question.
	unit.capability = 0
	unit.np_cache = true
	function := pci.get_device_by_coordinates(u8(unit.devid >> 8), u8((unit.devid >> 3) & 31),
		u8(unit.devid & 7), 0) or {
		C.kprintf(c'amdvi: %.*s: no PCI function at %02llx:%02llx.%llx for its capability block\n',
			i32(unit.name.len), unit.name.str, u64(unit.devid >> 8), u64((unit.devid >> 3) & 31),
			u64(unit.devid & 7))
		return
	}
	if unit.cap_offset < 0x40 || unit.cap_offset > 0xec {
		return
	}
	header := function.read[u32](u32(unit.cap_offset))
	if header == 0xffffffff || header & 0xff != amdvi_capability_id {
		C.kprintf(c'amdvi: %.*s: no IOMMU capability at offset 0x%llx of its PCI function\n',
			i32(unit.name.len), unit.name.str, u64(unit.cap_offset))
		return
	}
	unit.capability = header
	unit.np_cache = header & amdvi_capability_np_cache != 0
}

fn amdvi_free_unit_memory(mut unit AmdviUnit) {
	if unit.device_table != 0 {
		memory.pmm_free(voidptr(unit.device_table), unit.device_table_pages)
		unit.device_table = 0
	}
	if unit.commands != 0 {
		memory.pmm_free(voidptr(unit.commands), amdvi_ring_pages)
		unit.commands = 0
	}
	if unit.events != 0 {
		memory.pmm_free(voidptr(unit.events), amdvi_ring_pages)
		unit.events = 0
	}
	if unit.semaphore != 0 {
		memory.pmm_free(voidptr(unit.semaphore), 1)
		unit.semaphore = 0
	}
	if unit.nothing != 0 {
		memory.pmm_free(voidptr(unit.nothing), 1)
		unit.nothing = 0
	}
}

// The device table, both rings, the completion word and the empty table,
// zeroed.
fn amdvi_allocate_unit_memory(mut unit AmdviUnit) bool {
	unit.device_table_pages = lib.div_roundup((u64(unit.last_devid) + 1) * amdvi_dte_bytes,
		amdvi_page_bytes)
	if unit.device_table_pages > amdvi_device_table_limit {
		return false
	}
	unit.device_table = u64(memory.pmm_alloc_fallible(unit.device_table_pages))
	unit.commands = u64(memory.pmm_alloc_fallible(amdvi_ring_pages))
	unit.events = u64(memory.pmm_alloc_fallible(amdvi_ring_pages))
	unit.semaphore = u64(memory.pmm_alloc_fallible(1))
	unit.nothing = u64(memory.pmm_alloc_fallible(1))
	if unit.device_table == 0 || unit.commands == 0 || unit.events == 0 || unit.semaphore == 0
		|| unit.nothing == 0 {
		amdvi_free_unit_memory(mut unit)
		return false
	}
	return true
}

// Everything off: translation, both rings and every log and interrupt this
// driver does not use, in the order Linux stops a unit.
fn amdvi_quiesce(unit &AmdviUnit) {
	amdvi_control_clear(unit, amdvi_control_command_buffer)
	amdvi_control_clear(unit, amdvi_control_event_interrupt)
	amdvi_control_clear(unit, amdvi_control_event_log)
	amdvi_control_clear(unit, amdvi_control_ga_log | amdvi_control_ga_interrupt)
	amdvi_control_clear(unit, amdvi_control_ppr_log | amdvi_control_ppr_interrupt)
	amdvi_control_clear(unit, amdvi_control_enable)
}

fn amdvi_rings_running(context voidptr) bool {
	unit := unsafe { &AmdviUnit(context) }
	running := amdvi_status_command_running | amdvi_status_event_running
	return amdvi_read32(unit, amdvi_reg_status) & running == running
}

// Bring one unit from whatever state firmware left it in to translating,
// with every device behind it blocked. False, with the unit off and its
// memory given back, when any step fails.
fn amdvi_start_unit(mut unit AmdviUnit) bool {
	if unit.mmio_phys == 0 || unit.mmio_phys & (amdvi_page_bytes - 1) != 0
		|| unit.mmio_phys >= u64(1) << 52 {
		C.kprintf(c'amdvi: %.*s: IVRS gives no usable register base (0x%llx)\n', i32(unit.name.len),
			unit.name.str, unit.mmio_phys)
		return false
	}
	unit.regs = amdvi_map_registers(unit.mmio_phys, amdvi_register_span)
	if unit.regs == 0 {
		C.kprintf(c'amdvi: %.*s: could not map registers at 0x%llx\n', i32(unit.name.len),
			unit.name.str, unit.mmio_phys)
		return false
	}
	// Registers that are not decoded read as all ones.
	before := amdvi_read64(unit, amdvi_reg_control)
	if before == ~u64(0) {
		C.kprintf(c'amdvi: %.*s: registers at 0x%llx do not answer\n', i32(unit.name.len),
			unit.name.str, unit.mmio_phys)
		return false
	}

	amdvi_read_capability(mut unit)
	if unit.capability & amdvi_capability_features != 0 {
		features := amdvi_read64(unit, amdvi_reg_features)
		features2 := amdvi_read64(unit, amdvi_reg_features2)
		if unit.features == 0 && unit.features2 == 0 {
			unit.features = features
			unit.features2 = features2
		} else if unit.features != features || unit.features2 != features2 {
			// Firmware's copy is the one it has vouched for; Linux keeps it.
			C.kprintf(c'amdvi: %.*s: the feature register reads 0x%llx but IVRS says 0x%llx; going by IVRS\n',
				i32(unit.name.len), unit.name.str, features, unit.features)
		}
	}

	if !amdvi_allocate_unit_memory(mut unit) {
		C.kprintf(c'amdvi: %.*s: no memory for a device table of %llu entries\n', i32(unit.name.len),
			unit.name.str, u64(unit.last_devid) + 1)
		return false
	}
	amdvi_fill_device_table(mut unit)
	unit.next_domain = 1
	amdvi_unity_domains(mut unit)

	if before & amdvi_control_enable != 0 {
		// Firmware that guards against DMA before the system starts leaves
		// its own tables in force. They are replaced, not adopted.
		C.kprintf(c'amdvi: %.*s: firmware left translation on; restarting it with tables of our own\n',
			i32(unit.name.len), unit.name.str)
	}
	amdvi_quiesce(unit)

	// The control bits firmware asks for, and Linux's two: memory the unit
	// touches is reported coherent, and a device gets a second to answer an
	// invalidation of its own cache.
	mut wanted := amdvi_control_coherent
	if unit.ivhd_flags & amdvi_ivhd_ht_tunnel != 0 {
		wanted |= amdvi_control_ht_tunnel
	}
	if unit.ivhd_flags & amdvi_ivhd_pass_posted != 0 {
		wanted |= amdvi_control_pass_posted
	}
	if unit.ivhd_flags & amdvi_ivhd_response_pass_posted != 0 {
		wanted |= amdvi_control_response_pass_posted
	}
	if unit.ivhd_flags & amdvi_ivhd_isochronous != 0 {
		wanted |= amdvi_control_isochronous
	}
	configurable := amdvi_control_ht_tunnel | amdvi_control_pass_posted | amdvi_control_response_pass_posted | amdvi_control_isochronous | amdvi_control_coherent | amdvi_control_timeout_mask
	amdvi_write64(unit, amdvi_reg_control, (amdvi_read64(unit, amdvi_reg_control) & ~configurable) | wanted | amdvi_control_timeout_1s)

	amdvi_write64(unit, amdvi_reg_device_table, unit.device_table | (unit.device_table_pages - 1))

	amdvi_write64(unit, amdvi_reg_command_base, unit.commands | amdvi_ring_size_code)
	amdvi_write32(unit, amdvi_reg_command_head, 0)
	amdvi_write32(unit, amdvi_reg_command_tail, 0)
	unit.command_head = 0
	unit.command_tail = 0
	unit.command_sequence = 0
	amdvi_control_set(unit, amdvi_control_command_buffer)

	amdvi_write64(unit, amdvi_reg_event_base, unit.events | amdvi_ring_size_code)
	amdvi_write32(unit, amdvi_reg_event_head, 0)
	amdvi_write32(unit, amdvi_reg_event_tail, 0)
	amdvi_control_set(unit, amdvi_control_event_log)

	// From here every device behind the unit is blocked.
	amdvi_control_set(unit, amdvi_control_enable)

	// Both rings report that they run once the unit is on. Whether they do
	// is settled by the flush below, which needs a command carried out; this
	// only gives a slow unit its time first.
	devcore.spin_until(amdvi_rings_running, voidptr(unit), amdvi_register_timeout_ns)

	// Whatever the unit remembers from before -- firmware's tables, or a
	// kernel started from another -- must go before a device is given a
	// domain under an id that was in use then.
	if !amdvi_flush_everything(mut unit) {
		C.kprintf(c'amdvi: %.*s: the unit does not carry out commands (status 0x%llx); switched off again\n',
			i32(unit.name.len), unit.name.str, u64(amdvi_read32(unit, amdvi_reg_status)))
		amdvi_quiesce(unit)
		amdvi_free_unit_memory(mut unit)
		return false
	}
	unit.on = true
	return true
}
