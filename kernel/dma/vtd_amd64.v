// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Intel VT-d: the IOMMU of an Intel PC.
//
// Firmware describes the machine's remapping units in the ACPI DMAR table
// (vtd_table_amd64.v). Each unit sits in front of a set of PCI devices and
// looks every address they put on the bus up in tables the kernel writes:
// the root table, indexed by bus number, points to a context table per bus,
// indexed by device and function, and a device's context entry names its
// domain -- a number, and a page table in the format of the CPU's own
// (vtd_domain_amd64.v). A device whose context entry is not present reaches
// nothing, which is the state every device behind a unit is in from the
// moment the unit is switched on until its driver asks for memory.
//
// What this file does is the unit itself: find it, read what it can do, give
// it its root table and switch translation on, and the two commands that
// make it forget what it has cached.
//
// Limits, all of which leave a unit off rather than half working:
//
//   - PCI segment 0 only, as the PCI layer itself.
//   - Legacy tables: no scalable mode, no PASIDs, no first-level translation.
//   - The register interface for invalidation, which is the one every unit
//     before architecture version 6 has. Version 6 and later only take
//     invalidations through a queue, which is not written; such a unit is
//     left alone, as is one whose firmware handed it over with the queue or
//     interrupt remapping already running.
//   - No interrupt remapping. Faults are polled (vtd_fault_amd64.v).
@[has_globals]
module dma

import acpi
import devcore
import klock
import lib
import memory
import x86.kio

// Registers. CAP, ECAP, RTADDR, CCMD and the invalidation and fault records
// are 64 bits wide, the rest 32.
const vtd_reg_ver = u64(0x00)
const vtd_reg_cap = u64(0x08)
const vtd_reg_ecap = u64(0x10)
const vtd_reg_gcmd = u64(0x18)
const vtd_reg_gsts = u64(0x1c)
const vtd_reg_rtaddr = u64(0x20)
const vtd_reg_ccmd = u64(0x28)
const vtd_reg_fsts = u64(0x34)
const vtd_reg_fectl = u64(0x38)
const vtd_reg_pmen = u64(0x64)

// GCMD starts something and GSTS says whether it is done or on; the two have
// the same layout.
const vtd_g_translation = u32(1) << 31
const vtd_g_root_pointer = u32(1) << 30
const vtd_g_write_buffer = u32(1) << 27
const vtd_g_queued = u32(1) << 26
const vtd_g_interrupt_remap = u32(1) << 25
// The bits of GSTS that are a state to keep rather than the answer to a
// command given once. GCMD is written whole, so every write starts from
// these: leaving one out would switch off something firmware or an earlier
// write switched on.
const vtd_g_states = u32(0x96ffffff)

const vtd_fectl_masked = u32(1) << 31
const vtd_pmen_enable = u32(1) << 31
const vtd_pmen_status = u32(1)

// CCMD: invalidate cached context entries -- all, a domain's, or one device's.
const vtd_ccmd_run = u64(1) << 63
const vtd_ccmd_global = u64(1) << 61
const vtd_ccmd_device = u64(3) << 61

// The IOTLB register pair at ECAP.IRO: the address at +0, the command at +8.
const vtd_iotlb_run = u64(1) << 63
const vtd_iotlb_global = u64(1) << 60
const vtd_iotlb_domain = u64(2) << 60
const vtd_iotlb_pages = u64(3) << 60
const vtd_iotlb_drain_reads = u64(1) << 49
const vtd_iotlb_drain_writes = u64(1) << 48

// A unit answers a command in microseconds. One that has not after this long
// is not going to, and the caller is told so instead of waiting for ever.
const vtd_register_timeout_ns = devcore.second

@[heap]
struct VtdUnit {
mut:
	index u32
	// "dmar0": what the DMA layer and /sys call it.
	name string
	// Its DRHD in vtd_firmware.
	drhd u32
	regs u64
	// As read from the unit.
	version u32
	cap     u64
	ecap    u64
	// What was made of them: the depth of a domain's page table and the
	// number of address bits it translates, the AW field of a context entry
	// that says so, how many domain numbers there are, where the IOTLB and
	// fault registers are, and whether the unit reads tables through the
	// CPU's caches.
	levels        u32
	address_bits  u32
	width_code    u64
	domain_limit  u32
	iotlb_reg     u64
	fault_reg     u64
	fault_records u32
	coherent      bool
	// Bit 0: 2 MiB pages. Bit 1: 1 GiB pages.
	superpages u32

	// Guards the registers, the root and context tables, the domain numbers
	// and the list of domains. Never held while a domain's own lock is.
	lock klock.Lock
	// What a wait on a register is for; see vtd_wait().
	wait_offset u64
	wait_wide   bool
	wait_mask   u64
	wait_want   u64

	root u64
	// One bit per domain number, set while it is in use.
	domain_bits &u64 = unsafe { nil }
	// The domains devices have now; see vtd_domain_amd64.v.
	domains      &VtdDomain = unsafe { nil }
	domain_count u32
	// Pages of page table the domains hold, which goes back to what it was
	// when a domain goes, and of root and context table: one, and one more
	// for each bus that ever had a domain.
	table_pages   u64
	context_pages u64
	enabled       bool
	// Commands the unit did not answer in time, or refused.
	timeouts u64

	// Transfers the unit refused; see vtd_fault_amd64.v.
	faults          u64
	fault_overflows u64
	last_fault      VtdFault
	// The limit on how many of them are logged.
	log_started      bool
	log_window_start u64
	log_window_lines u32
	log_suppressed   u64
}

__global (
	// Every unit that was brought up, switched on or not.
	vtd_units      [vtd_max_units]&VtdUnit
	vtd_unit_count u32
	// The DMAR table as parsed; nil when the machine has none worth using.
	vtd_firmware &VtdFirmware
)

fn vtd_read32(unit &VtdUnit, offset u64) u32 {
	return kio.mmin[u32](unsafe { &u32(unit.regs + offset) })
}

fn vtd_write32(unit &VtdUnit, offset u64, value u32) {
	kio.mmout[u32](unsafe { &u32(unit.regs + offset) }, value)
}

fn vtd_read64(unit &VtdUnit, offset u64) u64 {
	return kio.mmin[u64](unsafe { &u64(unit.regs + offset) })
}

fn vtd_write64(unit &VtdUnit, offset u64, value u64) {
	kio.mmout[u64](unsafe { &u64(unit.regs + offset) }, value)
}

// Page attribute bits: PWT and PCD together select the uncached PAT entry.
const vtd_pte_write_through = u64(1) << 3
const vtd_pte_cache_disable = u64(1) << 4

// The kernel's direct map covers the first 4 GiB, where every unit seen so far
// has its registers, and the firmware's MTRRs make the hole they are in
// uncached. Registers above that are mapped here.
fn vtd_map_registers(phys u64, length u64) u64 {
	hhdm := memory.get_hhdm_offset()
	if phys + length <= u64(0x100000000) {
		return phys + hhdm
	}
	flags := memory.pte_present | memory.pte_writable | memory.pte_noexec | vtd_pte_write_through | vtd_pte_cache_disable
	for page := phys & ~u64(0xfff); page < phys + length; page += 0x1000 {
		kernel_pagemap.map_page(page + hhdm, page, flags) or { return 0 }
	}
	return phys + hhdm
}

fn vtd_wait_ready(context voidptr) bool {
	unit := unsafe { &VtdUnit(context) }
	if unit.wait_wide {
		return vtd_read64(unit, unit.wait_offset) & unit.wait_mask == unit.wait_want
	}
	value := vtd_read32(unit, unit.wait_offset)
	// A unit that has gone reads as all ones, which would pass for every bit
	// that is waited on to be set.
	return value != 0xffffffff && u64(value) & unit.wait_mask == unit.wait_want
}

// Wait for the bits `mask` of a register to read `want`. The unit's lock is
// held: it is what makes the four fields the callback reads the caller's own.
fn vtd_wait(mut unit VtdUnit, offset u64, wide bool, mask u64, want u64) bool {
	unit.wait_offset = offset
	unit.wait_wide = wide
	unit.wait_mask = mask
	unit.wait_want = want
	if devcore.spin_until(vtd_wait_ready, voidptr(unit), vtd_register_timeout_ns) {
		return true
	}
	unit.timeouts++
	return false
}

// Give the unit a global command and wait for its status bit to follow. The
// lock is held.
fn vtd_global_command(mut unit VtdUnit, set u32, clear u32, status u32, want_set bool) bool {
	state := vtd_read32(unit, vtd_reg_gsts) & vtd_g_states
	vtd_write32(unit, vtd_reg_gcmd, (state | set) & ~clear)
	return vtd_wait(mut unit, vtd_reg_gsts, false, u64(status), if want_set { u64(status) } else { u64(0) })
}

// A unit that buffers the kernel's writes to its tables (CAP.RWBF, the first
// chipsets) has to be told when an entry that was not present is now.
fn vtd_flush_write_buffer_locked(mut unit VtdUnit) {
	if unit.cap & (u64(1) << 4) == 0 {
		return
	}
	if !vtd_global_command(mut unit, vtd_g_write_buffer, 0, vtd_g_write_buffer, false) {
		C.kprintf(c'vtd: %.*s did not flush its write buffer\n', i32(unit.name.len), unit.name.str)
	}
}

// Make the unit forget the context entries it has cached: every one, or the
// one of the device `sid` in domain `did`. The lock is held.
fn vtd_flush_context_locked(mut unit VtdUnit, kind u64, did u32, sid u32) {
	mut command := vtd_ccmd_run | kind
	if kind == vtd_ccmd_device {
		command |= u64(did & 0xffff) | (u64(sid & 0xffff) << 16)
	}
	vtd_write64(unit, vtd_reg_ccmd, command)
	if !vtd_wait(mut unit, vtd_reg_ccmd, true, vtd_ccmd_run, 0) {
		C.kprintf(c'vtd: %.*s did not finish a context invalidation\n', i32(unit.name.len),
			unit.name.str)
	}
}

// Make the unit forget translations: all of them, a domain's, or those of
// 2^order pages at `address` in a domain. It is asked to let transfers
// already under way finish first, so that when this returns no device is
// still using what was forgotten. The lock is held.
fn vtd_flush_iotlb_locked(mut unit VtdUnit, kind u64, did u32, address u64, order u64) {
	mut command := vtd_iotlb_run | kind
	if kind != vtd_iotlb_global {
		command |= u64(did & 0xffff) << 32
	}
	if unit.cap & (u64(1) << 55) != 0 {
		command |= vtd_iotlb_drain_reads
	}
	if unit.cap & (u64(1) << 54) != 0 {
		command |= vtd_iotlb_drain_writes
	}
	if kind == vtd_iotlb_pages {
		vtd_write64(unit, unit.iotlb_reg, address | order)
	}
	vtd_write64(unit, unit.iotlb_reg + 8, command)
	if !vtd_wait(mut unit, unit.iotlb_reg + 8, true, vtd_iotlb_run, 0) {
		C.kprintf(c'vtd: %.*s did not finish an IOTLB invalidation\n', i32(unit.name.len),
			unit.name.str)
		return
	}
	// Bits 57 and 58 say what was actually invalidated; zero is "nothing".
	if (vtd_read64(unit, unit.iotlb_reg + 8) >> 57) & 3 == 0 {
		unit.timeouts++
		C.kprintf(c'vtd: %.*s refused an IOTLB invalidation\n', i32(unit.name.len), unit.name.str)
	}
}

// Forget the translations of `bytes` at `iova` in domain `did`. The unit takes
// a block of pages that is a power of two long and aligned to its length, so
// the smallest such block around the range is what is named; when that is
// more than the unit accepts, or it cannot name pages at all, the whole
// domain's translations go, which costs the one device its cache.
fn vtd_flush_range(mut unit VtdUnit, did u32, iova u64, bytes u64) {
	first := iova >> 12
	last := (iova + bytes - 1) >> 12
	mut order := u64(0)
	for order < 64 && (first >> order) != (last >> order) {
		order++
	}
	unit.lock.acquire()
	if unit.cap & (u64(1) << 39) != 0 && order <= (unit.cap >> 48) & 0x3f {
		vtd_flush_iotlb_locked(mut unit, vtd_iotlb_pages, did, (first >> order) << (order + 12),
			order)
	} else {
		vtd_flush_iotlb_locked(mut unit, vtd_iotlb_domain, did, 0, 0)
	}
	unit.lock.release()
}

// A mapping was added to domain `did`. A real unit caches only what it found
// present, so there is nothing for it to forget; one that is emulated for a
// virtual machine may cache absences as well (CAP.CM) and is told.
fn vtd_after_map(mut unit VtdUnit, did u32) {
	if unit.cap & ((u64(1) << 7) | (u64(1) << 4)) == 0 {
		return
	}
	unit.lock.acquire()
	if unit.cap & (u64(1) << 7) != 0 {
		vtd_flush_iotlb_locked(mut unit, vtd_iotlb_domain, did, 0, 0)
	} else {
		vtd_flush_write_buffer_locked(mut unit)
	}
	unit.lock.release()
}

fn vtd_unit_name(index u32) string {
	mut text := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
	unsafe { *text = lib.new_text(8) }
	text.add('dmar')
	text.add_unsigned(u64(index))
	return text.str()
}

// A unit that is not going to be used after all.
fn vtd_unit_discard(unit &VtdUnit) &VtdUnit {
	unsafe {
		unit.name.free()
		free(unit)
	}
	return unsafe { nil }
}

// Map a unit's registers and read what it is. Nil, with the reason logged,
// for a unit that is absent, cannot do what is needed here, or was handed
// over in a state that cannot be taken over. Nothing is written to it.
fn vtd_unit_probe(drhd_index u32) &VtdUnit {
	drhd := unsafe { &vtd_firmware.drhds[drhd_index] }
	regs := vtd_map_registers(drhd.address, 0x1000)
	if regs == 0 {
		C.kprintf(c'vtd: could not map the registers at 0x%llx\n', drhd.address)
		return unsafe { nil }
	}
	// Made once per unit at boot and kept for the life of the machine.
	mut unit := &VtdUnit{}
	unit.index = vtd_unit_count
	unit.drhd = drhd_index
	unit.regs = regs
	unit.name = vtd_unit_name(unit.index)
	name := unit.name
	unit.version = vtd_read32(unit, vtd_reg_ver)
	unit.cap = vtd_read64(unit, vtd_reg_cap)
	unit.ecap = vtd_read64(unit, vtd_reg_ecap)
	if unit.cap == ~u64(0) || unit.version == 0xffffffff {
		C.kprintf(c'vtd: nothing answers at 0x%llx\n', drhd.address)
		return vtd_unit_discard(unit)
	}

	// The page-table depths the unit walks: bit 2 is four levels and 48 bits,
	// bit 1 three levels and 39. Five levels would only be needed for memory
	// above 256 TiB.
	sagaw := (unit.cap >> 8) & 0x1f
	if sagaw & 4 != 0 {
		unit.levels = 4
		unit.address_bits = 48
		unit.width_code = 2
	} else if sagaw & 2 != 0 {
		unit.levels = 3
		unit.address_bits = 39
		unit.width_code = 1
	} else {
		C.kprintf(c'vtd: %.*s walks neither 3- nor 4-level tables (SAGAW 0x%llx); left off\n',
			i32(name.len), name.str, sagaw)
		return vtd_unit_discard(unit)
	}
	// It may translate fewer bits than its tables have.
	guest_bits := u32((unit.cap >> 16) & 0x3f) + 1
	if guest_bits < unit.address_bits {
		unit.address_bits = guest_bits
	}
	domains := u64(1) << (4 + 2 * (unit.cap & 7))
	unit.domain_limit = if domains > 65536 { u32(65536) } else { u32(domains) }
	unit.iotlb_reg = ((unit.ecap >> 8) & 0x3ff) * 16
	unit.fault_reg = ((unit.cap >> 24) & 0x3ff) * 16
	unit.fault_records = u32((unit.cap >> 40) & 0xff) + 1
	unit.coherent = unit.ecap & 1 != 0
	unit.superpages = u32((unit.cap >> 34) & 3)

	// The registers found through CAP and ECAP may lie past the first page.
	mut span := unit.iotlb_reg + 16
	if unit.fault_reg + u64(unit.fault_records) * 16 > span {
		span = unit.fault_reg + u64(unit.fault_records) * 16
	}
	if span > 0x1000 && vtd_map_registers(drhd.address, span) == 0 {
		C.kprintf(c'vtd: could not map the registers at 0x%llx\n', drhd.address)
		return vtd_unit_discard(unit)
	}

	if (unit.version >> 4) & 0xf >= 6 {
		C.kprintf(c'vtd: %.*s is architecture version %llu.%llu, which only takes invalidations through a queue; left off\n',
			i32(name.len), name.str, u64((unit.version >> 4) & 0xf), u64(unit.version & 0xf))
		return vtd_unit_discard(unit)
	}
	status := vtd_read32(unit, vtd_reg_gsts)
	if status & (vtd_g_queued | vtd_g_interrupt_remap) != 0 {
		C.kprintf(c'vtd: %.*s was handed over with queued invalidation or interrupt remapping on (GSTS 0x%llx); left as found\n',
			i32(name.len), name.str, u64(status))
		return vtd_unit_discard(unit)
	}
	return unit
}

// Give the unit its tables and the state it starts in: no faults pending, the
// fault interrupt masked, translation off. False when there is no memory or
// the translation firmware left on could not be stopped.
fn vtd_unit_prepare(mut unit VtdUnit) bool {
	name := unit.name
	unit.lock.acquire()
	// Firmware that guards memory before the OS starts hands the unit over
	// translating through tables of its own. They are replaced whole, and the
	// root pointer may only change while translation is off.
	if vtd_read32(unit, vtd_reg_gsts) & vtd_g_translation != 0 {
		if !vtd_global_command(mut unit, 0, vtd_g_translation, vtd_g_translation, false) {
			unit.lock.release()
			C.kprintf(c'vtd: %.*s would not stop the translation firmware left on; left as found\n',
				i32(name.len), name.str)
			return false
		}
	}
	vtd_write32(unit, vtd_reg_fectl, vtd_fectl_masked)
	unit.lock.release()
	// Whatever faulted before now is firmware's business.
	vtd_drain_faults(mut unit, false)

	unit.root = u64(memory.pmm_alloc_fallible(1))
	bitmap_pages := (u64(unit.domain_limit) / 8 + page_size - 1) / page_size
	bitmap := u64(memory.pmm_alloc_fallible(bitmap_pages))
	if unit.root == 0 || bitmap == 0 {
		if unit.root != 0 {
			memory.pmm_free(voidptr(unit.root), 1)
			unit.root = 0
		}
		if bitmap != 0 {
			memory.pmm_free(voidptr(bitmap), bitmap_pages)
		}
		C.kprintf(c'vtd: no memory for the tables of %.*s\n', i32(name.len), name.str)
		return false
	}
	unit.context_pages = 1
	unit.domain_bits = unsafe { &u64(bitmap + higher_half) }
	// Domain 0 is what a unit that caches absent entries files them under,
	// and is never given to a device.
	unsafe {
		unit.domain_bits[0] = 1
	}
	return true
}

// Point the unit at its root table, make it forget whatever it cached of the
// tables before, and switch translation on. From here every device behind it
// that has no domain is blocked. False, with translation off, if the unit
// does not follow.
fn vtd_unit_enable(mut unit VtdUnit) bool {
	name := unit.name
	unit.lock.acquire()
	vtd_write64(unit, vtd_reg_rtaddr, unit.root)
	if !vtd_global_command(mut unit, vtd_g_root_pointer, 0, vtd_g_root_pointer, true) {
		unit.lock.release()
		C.kprintf(c'vtd: %.*s did not take its root table\n', i32(name.len), name.str)
		return false
	}
	vtd_flush_context_locked(mut unit, vtd_ccmd_global, 0, 0)
	vtd_flush_iotlb_locked(mut unit, vtd_iotlb_global, 0, 0, 0)
	if !vtd_global_command(mut unit, vtd_g_translation, 0, vtd_g_translation, true) {
		// It may be half on: take the bit back before giving up.
		vtd_global_command(mut unit, 0, vtd_g_translation, vtd_g_translation, false)
		unit.lock.release()
		C.kprintf(c'vtd: %.*s did not switch translation on\n', i32(name.len), name.str)
		return false
	}
	// Firmware may have left "protected memory regions" on: two ranges no
	// device may touch whatever the tables say, its guard for the time before
	// there were tables. They are in the way now.
	if unit.cap & (u64(3) << 5) != 0 && vtd_read32(unit, vtd_reg_pmen) & vtd_pmen_enable != 0 {
		vtd_write32(unit, vtd_reg_pmen, vtd_read32(unit, vtd_reg_pmen) & ~vtd_pmen_enable)
		if !vtd_wait(mut unit, vtd_reg_pmen, false, u64(vtd_pmen_status), 0) {
			C.kprintf(c'vtd: %.*s kept its protected memory regions\n', i32(name.len),
				name.str)
		}
	}
	unit.enabled = true
	unit.lock.release()
	return true
}

fn vtd_unit_disable(mut unit VtdUnit) {
	unit.lock.acquire()
	vtd_global_command(mut unit, 0, vtd_g_translation, vtd_g_translation, false)
	unit.enabled = false
	unit.lock.release()
}

// Bring one unit all the way up: its tables, the domains firmware's own DMA
// needs, translation, and its entry in the DMA layer.
fn vtd_unit_start(drhd_index u32) {
	drhd := unsafe { &vtd_firmware.drhds[drhd_index] }
	if drhd.segment != 0 {
		C.kprintf(c'vtd: the unit at 0x%llx is for PCI segment %llu; only segment 0 is supported, left off\n',
			drhd.address, u64(drhd.segment))
		return
	}
	// Linux's "igfx_off", and for its reason: nothing here drives the
	// graphics device, and the picture firmware put on the screen is read
	// out of memory through this unit. Switched on, it would block that.
	if vtd_drhd_graphics_only(vtd_firmware, drhd_index)
		&& !devcore.boot_flag('vinix.iommu_igfx=', false) {
		C.kprintf(c'vtd: the unit at 0x%llx serves only the integrated graphics at 00:02.0; left off (vinix.iommu_igfx=1 to switch it on)\n',
			drhd.address)
		return
	}
	mut unit := vtd_unit_probe(drhd_index)
	if unit == unsafe { nil } {
		return
	}
	name := unit.name
	vtd_units[vtd_unit_count] = unit
	vtd_unit_count++
	if !vtd_unit_prepare(mut unit) {
		return
	}
	// Before translation is on, so that a device firmware is using -- a USB
	// keyboard it emulates a PS/2 one with, a management controller -- never
	// sees a moment in which its memory is gone.
	vtd_firmware_domains(mut unit)
	if !vtd_unit_enable(mut unit) {
		return
	}
	mut record := Iommu{}
	record.name = unit.name
	record.covers = vtd_covers
	record.attach = vtd_attach
	record.detach = vtd_detach
	record.map = vtd_map
	record.unmap = vtd_unmap
	record.map_all = vtd_map_all
	record.data = voidptr(unit)
	register_iommu(record) or {
		// A unit that is on and that nothing can ask for a domain would block
		// its devices for good.
		vtd_unit_disable(mut unit)
		C.kprintf(c'vtd: no room to register %.*s; switched off again\n', i32(name.len),
			name.str)
		return
	}
	C.kprintf(c'vtd: %.*s at 0x%llx on: version %llu.%llu, %llu-bit addresses, %llu domains, cap 0x%llx ecap 0x%llx\n',
		i32(name.len), name.str, drhd.address, u64((unit.version >> 4) & 0xf), u64(unit.version & 0xf),
		u64(unit.address_bits), u64(unit.domain_limit), unit.cap, unit.ecap)
}

// A zeroed record to parse a DMAR table into, or nil.
fn vtd_firmware_new() &VtdFirmware {
	firmware := memory.malloc_packed_fallible(sizeof(VtdFirmware))
	if firmware != unsafe { nil } {
		unsafe { C.memset(firmware, 0, sizeof(VtdFirmware)) }
	}
	return unsafe { &VtdFirmware(firmware) }
}

// Find the machine's VT-d units and switch them on. Called by dma.initialise()
// when the command line has vinix.iommu=1, after PCI has been enumerated and
// before the first driver that does DMA registers.
fn vtd_initialise() {
	table := acpi.find_sdt('DMAR', 0) or {
		$if vtd_selftest ? {
			vtd_selftest_run()
		}
		return
	}
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
	for i := u32(0); i < firmware.drhd_count; i++ {
		vtd_unit_start(i)
	}
	if vtd_unit_count != 0 {
		vtd_start_poller()
	}
	$if vtd_selftest ? {
		vtd_selftest_run()
	}
}
