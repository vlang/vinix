// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// What a device behind an AMD IOMMU may reach: its domain.
//
// A domain is a set of page tables in AMD's I/O format, a number the unit
// tags its remembered translations with, and the device table entries that
// point at the tables. Each device has its own. The tables look like the
// CPU's: 512 eight-byte entries to a page, nine bits of address a level, the
// last level naming 4 KiB pages. Every entry also says what the level below
// it is, which is how an entry one level up can name 2 MiB directly; that is
// used only for map_all(), where it turns half a megabyte of tables per
// gigabyte of RAM into one page.
//
// A device is in one of three states:
//
//	blocked    its table entry is valid and names no tables: every access
//	           faults. Every device is here until something below happens.
//	firmware   it has tables holding only the memory the IVRS table says it
//	           must go on reaching (a "unity" range), made at boot
//	driver     a driver asked for memory for it: attach() gave it tables,
//	           holding firmware's ranges if it has any and then whatever the
//	           driver maps
//
// detach() takes it back to blocked, or to firmware's ranges alone. The
// device is never without valid tables on the way: new ones are built first,
// the table entry is switched to them in one store, and the old ones are
// freed only after the unit has confirmed that it has forgotten them.
//
// Two devices that send under one id -- they sit behind the same bridge to
// conventional PCI, and the IVRS table gives both the bridge's id as their
// alias -- cannot be told apart by the unit, so they cannot have a domain
// each. The first to be attached has the id; the second is refused until the
// first is detached. Firmware's ranges for all of them are in whichever
// domain holds the id.
//
// Locking: a table's lock guards its entries and its root. Table pages are
// allocated with no lock held, since the allocator may have to reclaim; a
// walk that needs a page it was not handed gives up, and its caller comes
// back with one. The unit's domain_lock guards the list of domains, whose
// records are made once per device and never freed, so a cookie stays good.
module dma

import devcore
import katomic
import klock
import limine
import memory
import pci

// I/O page table entries. Bits 9 to 11 say what the entry points at: a table
// of that level, or with 0 the memory itself.
const amdvi_pte_present = u64(1) << 0
const amdvi_pte_next_shift = u64(9)
const amdvi_pte_next_mask = u64(7)
const amdvi_pte_address = u64(0x000ffffffffff000)
// Set on every leaf by Linux: accesses through it are coherent.
const amdvi_pte_coherent = u64(1) << 60
const amdvi_pte_read = u64(1) << 61
const amdvi_pte_write = u64(1) << 62

const amdvi_large_bytes = u64(1) << 21
const amdvi_table_entries = u64(512)

struct AmdviTable {
mut:
	lock klock.Lock
	// Physical address of the top level; 0 when there are no tables.
	root   u64
	levels u8
	// Pages of table, the root among them, and bytes they make reachable.
	pages  u64
	mapped u64
	// Large pages broken up into small ones, which the unit has to be told.
	splits u64
}

struct AmdviDomain {
mut:
	next &AmdviDomain = unsafe { nil }
	unit &AmdviUnit   = unsafe { nil }
	// The device's own id, the one it sends as, and the domain's number.
	devid u16
	alias u16
	id    u16
	table AmdviTable
	// A driver has it, between attach() and detach().
	driver bool
	// All of RAM is mapped.
	identity bool
	// The IVRS table keeps memory reachable for it.
	has_unity bool
	// Accesses the unit turned away, and how often it has been attached.
	faults   u64
	attaches u64
}

struct AmdviSlot {
	entry &u64 = unsafe { nil }
	// The walk needs a page of table and was not handed one.
	starved bool
}

fn amdvi_devid(function &pci.PCIDevice) u16 {
	return (u16(function.bus) << 8) | (u16(function.slot) << 3) | u16(function.function)
}

// A zeroed page for a table, counted against the unit. Not under a lock.
fn amdvi_table_page(mut unit AmdviUnit) u64 {
	page := u64(memory.pmm_alloc_fallible(1))
	if page != 0 {
		katomic.inc(mut &unit.table_pages)
	}
	return page
}

fn amdvi_table_page_free(mut unit AmdviUnit, page u64) {
	memory.pmm_free(voidptr(page), 1)
	katomic.dec(mut &unit.table_pages)
}

fn amdvi_entry_at(table u64, iova u64, level u8) &u64 {
	index := (iova >> (12 + 9 * (u64(level) - 1))) & (amdvi_table_entries - 1)
	return unsafe { &u64(table + higher_half + index * 8) }
}

// The entry that maps `iova` at `level`: 1 for a 4 KiB page, 2 for 2 MiB.
// Tables missing on the way down are made when `create` is set, and a 2 MiB
// page in the way of a 4 KiB one is broken up into 512 that map the same
// memory; both take the page at `spare`, which is zeroed and is set to 0 once
// used. The table's lock is held, or the table is not yet anyone else's.
fn amdvi_slot(mut table AmdviTable, iova u64, level u8, create bool, spare &u64) AmdviSlot {
	mut current := table.root
	mut at := table.levels
	for at > level {
		mut entry := amdvi_entry_at(current, iova, at)
		value := unsafe { *entry }
		next := (value >> amdvi_pte_next_shift) & amdvi_pte_next_mask
		if value & amdvi_pte_present != 0 && next == u64(at) - 1 {
			current = value & amdvi_pte_address
			at--
			continue
		}
		if value & amdvi_pte_present != 0 && !(next == 0 && at == 2) {
			// Not something this driver wrote.
			return AmdviSlot{}
		}
		if value & amdvi_pte_present == 0 && !create {
			return AmdviSlot{}
		}
		page := unsafe { *spare }
		if page == 0 {
			return AmdviSlot{
				starved: true
			}
		}
		if value & amdvi_pte_present != 0 {
			base := value & amdvi_pte_address & ~(amdvi_large_bytes - 1)
			rights := value & (amdvi_pte_read | amdvi_pte_write | amdvi_pte_coherent)
			mut small := unsafe { &u64(page + higher_half) }
			for i := u64(0); i < amdvi_table_entries; i++ {
				unsafe {
					small[i] = (base + i * amdvi_page_bytes) | rights | amdvi_pte_present
				}
			}
			table.splits++
		}
		unsafe {
			*spare = 0
			// An entry that points at a table allows everything; what a
			// page may be used for is said where the page is named.
			*entry = page | ((u64(at) - 1) << amdvi_pte_next_shift) | amdvi_pte_present | amdvi_pte_read | amdvi_pte_write
		}
		table.pages++
		current = page
		at--
	}
	return AmdviSlot{
		entry: amdvi_entry_at(current, iova, level)
	}
}

// How far a table of `levels` levels reaches.
fn amdvi_reach(levels u8) u64 {
	return u64(1) << (12 + 9 * u64(levels))
}

fn amdvi_table_create(mut unit AmdviUnit, mut table AmdviTable) bool {
	root := amdvi_table_page(mut unit)
	if root == 0 {
		return false
	}
	table.root = root
	table.levels = unit.levels
	table.pages = 1
	table.mapped = 0
	table.splits = 0
	return true
}

// Free a table of `level` at `table` and every table below it. Nothing may
// be using it: not a CPU, and not the unit, which has confirmed as much.
fn amdvi_table_destroy(mut unit AmdviUnit, table u64, level u8) {
	if level > 1 {
		entries := unsafe { &u64(table + higher_half) }
		for i := u64(0); i < amdvi_table_entries; i++ {
			value := unsafe { entries[i] }
			if value & amdvi_pte_present != 0
				&& (value >> amdvi_pte_next_shift) & amdvi_pte_next_mask == u64(level) - 1 {
				amdvi_table_destroy(mut unit, value & amdvi_pte_address, level - 1)
			}
		}
	}
	amdvi_table_page_free(mut unit, table)
}

// Whether a range is whole pages that tables of this unit can map.
fn amdvi_range_fits(unit &AmdviUnit, iova u64, phys u64, bytes u64) bool {
	low := amdvi_page_bytes - 1
	return (iova | phys | bytes) & low == 0 && bytes != 0 && iova + bytes > iova
		&& iova + bytes <= amdvi_reach(unit.levels) && phys + bytes > phys
		&& phys + bytes <= amdvi_pte_address + amdvi_page_bytes
}

// Map `bytes` at `phys` to `iova` with `rights`. With `large`, 2 MiB at a
// time wherever both addresses and what is left allow it. False when the
// range is not whole pages within the table's reach, the table has gone, or
// there is no memory for a table; what was mapped by then stays mapped, for
// the caller to take back or throw away with the table.
fn amdvi_table_map(mut unit AmdviUnit, mut table AmdviTable, iova u64, phys u64, bytes u64, rights u64, large bool) bool {
	if !amdvi_range_fits(unit, iova, phys, bytes) {
		return false
	}
	mut spare := u64(0)
	mut done := u64(0)
	mut mapped := true
	table.lock.acquire()
	for done < bytes {
		if table.root == 0 {
			mapped = false
			break
		}
		at := iova + done
		from := phys + done
		mut whole := large && (at | from) & (amdvi_large_bytes - 1) == 0
			&& bytes - done >= amdvi_large_bytes
		mut slot := amdvi_slot(mut table, at, if whole { u8(2) } else { u8(1) }, true, unsafe { &spare })
		if whole && slot.entry != unsafe { nil } {
			value := unsafe { *slot.entry }
			if value & amdvi_pte_present != 0
				&& (value >> amdvi_pte_next_shift) & amdvi_pte_next_mask != 0 {
				// Small pages are mapped here already; add to them.
				whole = false
				slot = amdvi_slot(mut table, at, 1, true, unsafe { &spare })
			}
		}
		if slot.entry == unsafe { nil } {
			if !slot.starved {
				mapped = false
				break
			}
			table.lock.release()
			spare = amdvi_table_page(mut unit)
			table.lock.acquire()
			if spare == 0 {
				mapped = false
				break
			}
			continue
		}
		step := if whole { amdvi_large_bytes } else { amdvi_page_bytes }
		unsafe {
			if *slot.entry & amdvi_pte_present == 0 {
				table.mapped += step
			}
			*slot.entry = from | rights | amdvi_pte_coherent | amdvi_pte_present
		}
		done += step
	}
	table.lock.release()
	if spare != 0 {
		amdvi_table_page_free(mut unit, spare)
	}
	return mapped
}

// Take `bytes` at `iova` out of the table. Pages that firmware keeps for
// `owner` go back to what firmware asked for instead. Returns how many pages
// were taken away; the caller has the unit forget them.
fn amdvi_table_unmap(mut unit AmdviUnit, mut table AmdviTable, iova u64, bytes u64, owner &AmdviDomain) u64 {
	mut spare := u64(0)
	mut done := u64(0)
	mut removed := u64(0)
	table.lock.acquire()
	for done < bytes {
		if table.root == 0 {
			break
		}
		at := iova + done
		slot := amdvi_slot(mut table, at, 1, false, unsafe { &spare })
		if slot.entry == unsafe { nil } {
			if !slot.starved {
				// No table for these addresses: nothing is mapped up to
				// where the next one would begin.
				done = ((at | (amdvi_large_bytes - 1)) + 1) - iova
				continue
			}
			// A 2 MiB page has to be broken up to lose one page of it.
			table.lock.release()
			spare = amdvi_table_page(mut unit)
			table.lock.acquire()
			if spare != 0 {
				continue
			}
			// No memory to do it with: the whole 2 MiB goes, rather than
			// leave the device a page it has been told it has lost.
			if table.root != 0 {
				whole := amdvi_slot(mut table, at, 2, false, unsafe { &spare })
				if whole.entry != unsafe { nil } && unsafe { *whole.entry } & amdvi_pte_present != 0 {
					unsafe {
						*whole.entry = 0
					}
					table.mapped -= amdvi_large_bytes
					table.splits++
					removed += amdvi_large_bytes / amdvi_page_bytes
				}
			}
			done = ((at | (amdvi_large_bytes - 1)) + 1) - iova
			continue
		}
		if unsafe { *slot.entry } & amdvi_pte_present != 0 {
			kept := if owner != unsafe { nil } && owner.has_unity {
				amdvi_unity_rights(unit, owner.devid, owner.alias, at)
			} else {
				u64(0)
			}
			if kept != 0 {
				unsafe {
					*slot.entry = at | kept | amdvi_pte_coherent | amdvi_pte_present
				}
			} else {
				unsafe {
					*slot.entry = 0
				}
				table.mapped -= amdvi_page_bytes
			}
			// Either way the unit may remember more than is now allowed.
			removed++
		}
		done += amdvi_page_bytes
	}
	table.lock.release()
	if spare != 0 {
		amdvi_table_page_free(mut unit, spare)
	}
	return removed
}

// ── Firmware's memory ───────────────────────────────────────────────────────

// Whether a unity range is meant for the device `devid`, which sends as
// `alias`. The tables are per id sent, so a range for any device that sends
// as one of the two is this domain's as well.
fn amdvi_unity_names(unit &AmdviUnit, range &AmdviUnity, devid u16, alias u16) bool {
	if (devid >= range.first && devid <= range.last) || (alias >= range.first && alias <= range.last) {
		return true
	}
	for entry in unit.entries {
		if entry.aliased && (entry.alias == devid || entry.alias == alias)
			&& entry.first <= range.last && entry.last >= range.first {
			return true
		}
	}
	return false
}

fn amdvi_unity_any(unit &AmdviUnit, devid u16, alias u16) bool {
	for i in 0 .. amdvi_ivrs.unity.len {
		if amdvi_unity_names(unit, unsafe { &amdvi_ivrs.unity[i] }, devid, alias) {
			return true
		}
	}
	return false
}

// The rights firmware asks for the device at `address`, as entry bits; 0 when
// it asks for none.
fn amdvi_unity_rights(unit &AmdviUnit, devid u16, alias u16, address u64) u64 {
	mut rights := u64(0)
	for i in 0 .. amdvi_ivrs.unity.len {
		range := unsafe { &amdvi_ivrs.unity[i] }
		if address < range.start || address >= range.end
			|| !amdvi_unity_names(unit, range, devid, alias) {
			continue
		}
		if range.read {
			rights |= amdvi_pte_read
		}
		if range.write {
			rights |= amdvi_pte_write
		}
	}
	return rights
}

// Map every unity range of the device into `table`, each at its own address.
fn amdvi_map_unity(mut unit AmdviUnit, mut table AmdviTable, devid u16, alias u16) bool {
	for i in 0 .. amdvi_ivrs.unity.len {
		range := unsafe { &amdvi_ivrs.unity[i] }
		if !amdvi_unity_names(unit, range, devid, alias) {
			continue
		}
		mut rights := u64(0)
		if range.read {
			rights |= amdvi_pte_read
		}
		if range.write {
			rights |= amdvi_pte_write
		}
		if !amdvi_table_map(mut unit, mut table, range.start, range.start, range.end - range.start,
			rights, false) {
			return false
		}
	}
	return true
}

// ── Device table entries ────────────────────────────────────────────────────

// Point the entry of `devid` at tables. The domain number goes in first: an
// entry read between the two stores is the blocked one with a number that
// does not matter yet, or the old tables under their own number.
fn amdvi_point_entry(unit &AmdviUnit, devid u16, root u64, levels u8, id u16) {
	mut words := amdvi_dte(unit, u32(devid))
	unsafe {
		words[1] = (words[1] & ~amdvi_dte_domain_mask) | u64(id)
		words[0] = root | (u64(levels) << amdvi_dte_mode_shift) | amdvi_dte_read | amdvi_dte_write | amdvi_dte_translation_valid | amdvi_dte_valid
	}
}

fn amdvi_block_entry(unit &AmdviUnit, devid u16) {
	mut words := amdvi_dte(unit, u32(devid))
	unsafe {
		words[0] = amdvi_blocked_word(unit, words[1])
		words[1] &= ~amdvi_dte_domain_mask
	}
}

// Have the unit forget the device's entries and everything it remembers
// under the domain's number. False if it did not confirm.
fn amdvi_forget(mut unit AmdviUnit, domain &AmdviDomain) bool {
	if !unit.on {
		// Not switched on yet: it remembers nothing.
		return true
	}
	mut queued := amdvi_forget_device(mut unit, domain.devid)
	if domain.alias != domain.devid {
		queued = amdvi_forget_device(mut unit, domain.alias) && queued
	}
	queued = amdvi_forget_domain(mut unit, domain.id, true) && queued
	return amdvi_sync(mut unit) && queued
}

// Put `fresh` in place of the domain's tables -- or nothing, when it has no
// root, which blocks the device -- and free the old ones once the unit has
// let go of them. `fresh` is the caller's own and unpublished until now. False
// when the unit did not confirm that it has taken the change in.
fn amdvi_replace_tables(mut unit AmdviUnit, mut domain AmdviDomain, fresh &AmdviTable) bool {
	domain.table.lock.acquire()
	old_root := domain.table.root
	old_levels := domain.table.levels
	old_pages := domain.table.pages
	domain.table.root = fresh.root
	domain.table.levels = fresh.levels
	domain.table.pages = fresh.pages
	domain.table.mapped = fresh.mapped
	domain.table.splits = 0
	domain.table.lock.release()

	if fresh.root != 0 {
		amdvi_point_entry(unit, domain.devid, fresh.root, fresh.levels, domain.id)
		if domain.alias != domain.devid {
			amdvi_point_entry(unit, domain.alias, fresh.root, fresh.levels, domain.id)
		}
	} else {
		amdvi_block_entry(unit, domain.devid)
		if domain.alias != domain.devid {
			amdvi_block_entry(unit, domain.alias)
		}
	}
	confirmed := amdvi_forget(mut unit, domain)
	if old_root == 0 {
		return confirmed
	}
	if confirmed {
		amdvi_table_destroy(mut unit, old_root, old_levels)
	} else {
		// The unit may still be walking them. Pages lost are better than
		// pages a device reads its translations from after they are reused.
		unit.lock.acquire()
		unit.leaked_pages += old_pages
		unit.lock.release()
		C.kprintf(c'amdvi: %.*s: %llu pages of table for %02llx:%02llx.%llx not freed: the unit did not confirm it had let go of them\n',
			i32(unit.name.len), unit.name.str, old_pages, u64(domain.devid >> 8), u64((domain.devid >> 3) & 31),
			u64(domain.devid & 7))
	}
	return confirmed
}

// ── Domains ─────────────────────────────────────────────────────────────────

// The record for the device `devid`, made the first time it is needed and
// kept from then on: it is what attach() hands out as the cookie.
fn amdvi_domain_of(mut unit AmdviUnit, devid u16, alias u16) &AmdviDomain {
	unit.domain_lock.acquire()
	mut found := unit.domains
	for found != unsafe { nil } && found.devid != devid {
		found = found.next
	}
	unit.domain_lock.release()
	if found != unsafe { nil } {
		return found
	}
	allocation := memory.malloc_packed_fallible(sizeof(AmdviDomain))
	if allocation == unsafe { nil } {
		return unsafe { nil }
	}
	mut domain := unsafe { &AmdviDomain(allocation) }
	unsafe {
		*domain = AmdviDomain{
			devid: devid
			alias: alias
		}
	}
	domain.unit = unsafe { unit }

	unit.domain_lock.acquire()
	found = unit.domains
	for found != unsafe { nil } && found.devid != devid {
		found = found.next
	}
	// Domain numbers are sixteen bits, and 0 is left to mean "none".
	if found == unsafe { nil } && unit.next_domain <= 0xffff {
		domain.id = u16(unit.next_domain)
		unit.next_domain++
		domain.next = unit.domains
		unit.domains = domain
		found = domain
	}
	unit.domain_lock.release()
	if voidptr(found) != voidptr(domain) {
		// Another CPU made it first, or the numbers ran out.
		memory.free(allocation)
	}
	return found
}

fn amdvi_find_domain(mut unit AmdviUnit, devid u16) &AmdviDomain {
	unit.domain_lock.acquire()
	mut found := unit.domains
	for found != unsafe { nil } && found.devid != devid {
		found = found.next
	}
	unit.domain_lock.release()
	return found
}

// Whether another domain with tables already has one of the ids this one
// would be written under.
fn amdvi_ids_taken(mut unit AmdviUnit, domain &AmdviDomain) bool {
	unit.domain_lock.acquire()
	mut taken := false
	mut other := unit.domains
	for other != unsafe { nil } {
		if voidptr(other) != voidptr(domain) && other.table.root != 0
			&& (other.devid == domain.devid || other.devid == domain.alias
			|| other.alias == domain.devid || other.alias == domain.alias) {
			taken = true
			break
		}
		other = other.next
	}
	unit.domain_lock.release()
	return taken
}

// Give a blocked device tables that hold firmware's ranges for it and
// nothing else.
fn amdvi_domain_build(mut unit AmdviUnit, mut domain AmdviDomain) bool {
	domain.has_unity = amdvi_unity_any(unit, domain.devid, domain.alias)
	mut fresh := AmdviTable{}
	if !amdvi_table_create(mut unit, mut fresh) {
		return false
	}
	if !amdvi_map_unity(mut unit, mut fresh, domain.devid, domain.alias) {
		amdvi_table_destroy(mut unit, fresh.root, fresh.levels)
		return false
	}
	if !amdvi_replace_tables(mut unit, mut domain, unsafe { &fresh }) {
		// A unit that does not answer cannot be trusted to have seen the
		// new entry either. Back to blocked; the tables are written off.
		nothing := AmdviTable{}
		amdvi_replace_tables(mut unit, mut domain, unsafe { &nothing })
		return false
	}
	return true
}

// At boot, before the unit is on: every device present that firmware keeps
// memory reachable for gets tables holding just that. A device added later
// gets its ranges when a driver attaches to it.
fn amdvi_unity_domains(mut unit AmdviUnit) {
	if amdvi_ivrs.unity.len == 0 {
		return
	}
	for function in scanned_devices {
		devid := amdvi_devid(function)
		subject := amdvi_subject(unit.entries, devid)
		if !subject.covered || devid == unit.devid || !amdvi_unity_any(unit, devid, subject.alias) {
			continue
		}
		mut domain := amdvi_domain_of(mut unit, devid, subject.alias)
		if domain == unsafe { nil } || domain.table.root != 0 || amdvi_ids_taken(mut unit, domain) {
			// With the id taken, the ranges are in the domain that has it.
			continue
		}
		if !amdvi_domain_build(mut unit, mut domain) {
			C.kprintf(c'amdvi: %.*s: no memory to keep firmware ranges reachable for %02llx:%02llx.%llx\n',
				i32(unit.name.len), unit.name.str, u64(devid >> 8), u64((devid >> 3) & 31),
				u64(devid & 7))
		}
	}
}

// ── What the DMA layer calls ────────────────────────────────────────────────

fn amdvi_covers(iommu &Iommu, dev &devcore.Device) bool {
	unit := unsafe { &AmdviUnit(iommu.data) }
	if dev.bus != .pci || dev.pci == unsafe { nil } {
		return false
	}
	devid := amdvi_devid(dev.pci)
	// The IVRS table lists the unit's own function as behind the unit. It is
	// not, as Linux notes.
	return devid != unit.devid && amdvi_subject(unit.entries, devid).covered
}

fn amdvi_attach(iommu &Iommu, mut dev devcore.Device) voidptr {
	mut unit := unsafe { &AmdviUnit(iommu.data) }
	if !unit.on || dev.bus != .pci || dev.pci == unsafe { nil } {
		return unsafe { nil }
	}
	devid := amdvi_devid(dev.pci)
	subject := amdvi_subject(unit.entries, devid)
	if !subject.covered || devid == unit.devid {
		return unsafe { nil }
	}
	mut domain := amdvi_domain_of(mut unit, devid, subject.alias)
	if domain == unsafe { nil } || domain.driver {
		return unsafe { nil }
	}
	if domain.table.root == 0 {
		if amdvi_ids_taken(mut unit, domain) {
			C.kprintf(c'amdvi: %.*s sends as %02llx:%02llx.%llx, which another device has a domain under; it stays blocked\n',
				i32(dev.name.len), dev.name.str, u64(subject.alias >> 8), u64((subject.alias >> 3) & 31),
				u64(subject.alias & 7))
			return unsafe { nil }
		}
		if !amdvi_domain_build(mut unit, mut domain) {
			return unsafe { nil }
		}
	}
	// Otherwise it has had tables since boot, with firmware's ranges in
	// them; the driver's memory joins those.
	domain.driver = true
	domain.attaches++
	return voidptr(domain)
}

fn amdvi_detach(cookie voidptr) {
	mut domain := unsafe { &AmdviDomain(cookie) }
	mut unit := domain.unit
	if !domain.driver {
		return
	}
	domain.driver = false
	domain.identity = false
	// What the driver mapped goes with the tables. Firmware's ranges are
	// put in new ones first, so the device is never without them.
	mut fresh := AmdviTable{}
	if domain.has_unity {
		if !amdvi_table_create(mut unit, mut fresh) || !amdvi_map_unity(mut unit, mut fresh,
			domain.devid, domain.alias) {
			if fresh.root != 0 {
				amdvi_table_destroy(mut unit, fresh.root, fresh.levels)
			}
			fresh = AmdviTable{}
			C.kprintf(c'amdvi: %.*s: no memory to keep firmware ranges reachable for %02llx:%02llx.%llx; it is blocked\n',
				i32(unit.name.len), unit.name.str, u64(domain.devid >> 8), u64((domain.devid >> 3) & 31),
				u64(domain.devid & 7))
		}
	}
	amdvi_replace_tables(mut unit, mut domain, unsafe { &fresh })
}

fn amdvi_map(cookie voidptr, iova u64, phys u64, bytes u64) bool {
	mut domain := unsafe { &AmdviDomain(cookie) }
	mut unit := domain.unit
	if !domain.driver || !amdvi_range_fits(unit, iova, phys, bytes) {
		return false
	}
	mut mapped := amdvi_table_map(mut unit, mut domain.table, iova, phys, bytes, amdvi_pte_read | amdvi_pte_write,
		false)
	if mapped && unit.np_cache {
		// The unit may remember that these addresses led nowhere.
		if bytes == amdvi_page_bytes {
			amdvi_forget_page(mut unit, domain.id, iova)
		} else {
			amdvi_forget_domain(mut unit, domain.id, false)
		}
		mapped = amdvi_sync(mut unit)
	}
	if !mapped {
		amdvi_unmap(cookie, iova, bytes)
	}
	return mapped
}

// Does not return until the unit has confirmed that it has forgotten the
// pages -- or, for a unit that has stopped answering, until it has been given
// its time and the failure has been logged.
fn amdvi_unmap(cookie voidptr, iova u64, bytes u64) {
	mut domain := unsafe { &AmdviDomain(cookie) }
	mut unit := domain.unit
	domain.table.lock.acquire()
	splits := domain.table.splits
	domain.table.lock.release()
	removed := amdvi_table_unmap(mut unit, mut domain.table, iova, bytes, domain)
	if removed == 0 {
		return
	}
	if removed == 1 && bytes == amdvi_page_bytes && domain.table.splits == splits {
		amdvi_forget_page(mut unit, domain.id, iova)
	} else {
		// One command for the lot. A device's domain is small, and what
		// else the unit forgets it reads again.
		amdvi_forget_domain(mut unit, domain.id, true)
	}
	amdvi_sync(mut unit)
}

// Whether a memory map entry is RAM the kernel hands out or lives in: what a
// driver that picks its own addresses could have picked.
fn amdvi_is_ram(kind u64) bool {
	return kind == u64(limine.limine_memmap_usable)
		|| kind == u64(limine.limine_memmap_bootloader_reclaimable)
		|| kind == u64(limine.limine_memmap_kernel_and_modules)
}

// Every page of RAM, each at its own address, in 2 MiB pages wherever the
// memory map allows: a page of table per gigabyte and a few for the ragged
// ends of each run. Built aside and switched to in one go, so a failure half
// way leaves the device with exactly what it had.
fn amdvi_map_all(cookie voidptr) bool {
	mut domain := unsafe { &AmdviDomain(cookie) }
	mut unit := domain.unit
	memmap := memmap_req.response
	if !domain.driver || memmap == unsafe { nil } {
		return false
	}
	mut fresh := AmdviTable{}
	if !amdvi_table_create(mut unit, mut fresh) {
		return false
	}
	mut built := amdvi_map_unity(mut unit, mut fresh, domain.devid, domain.alias)
	entries := memmap.entries
	for i := u64(0); built && i < memmap.entry_count; i++ {
		entry := unsafe { entries[i] }
		if !amdvi_is_ram(entry.@type) {
			continue
		}
		base := entry.base & ~(amdvi_page_bytes - 1)
		top := (entry.base + entry.length + amdvi_page_bytes - 1) & ~(amdvi_page_bytes - 1)
		if top > base {
			built = amdvi_table_map(mut unit, mut fresh, base, base, top - base, amdvi_pte_read | amdvi_pte_write,
				true)
		}
	}
	if !built {
		amdvi_table_destroy(mut unit, fresh.root, fresh.levels)
		return false
	}
	// Whatever the driver had mapped is RAM, so it is in the new tables too.
	amdvi_replace_tables(mut unit, mut domain, unsafe { &fresh })
	domain.identity = true
	return true
}
