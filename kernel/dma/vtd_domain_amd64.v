// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// VT-d domains: what one device behind a unit may reach.
//
// A domain is a number and a page table. The table has the shape of the
// CPU's own -- 512 entries a page, nine address bits a level, three or four
// levels -- with a read and a write bit where the CPU has present and
// writable. The device's context entry holds both, and from then on the unit
// translates every address the device puts on the bus through the table and
// refuses, and records, what is not in it.
//
// The DMA layer wants a device to find each page at the address it already
// has, so every mapping here is of a page onto itself; what the table adds is
// not a different address but the absence of every other one.
//
// Firmware's own DMA. An RMRR names memory that a device reads and writes
// without any driver's doing, from before the kernel started. A device named
// by one is given, before translation is switched on, a "firmware domain"
// holding those ranges and nothing else. When a driver takes the device its
// new domain starts with the same ranges, unmap() leaves them alone, and when
// the driver lets go the device goes back to a firmware domain. Moving a
// device from one domain to another clears its context entry and writes the
// new one; for those few instructions the device reaches nothing.
//
// Not done: a device behind a conventional PCI bridge. Such a bridge puts
// its own bus and device number on the requests of everything below it, so
// the context entry the unit looks up is the bridge's, shared by all those
// devices, and they cannot each have a domain. attach() refuses them, which
// leaves them blocked behind a unit that is on. Devices on the root bus and
// behind PCI Express ports, which pass the requester on unchanged, are what
// is handled.
//
// Locking: a domain's lock guards its page table and is never held together
// with the unit's. Pages for the table come from an allocator that may wait
// for memory, so they are taken with neither lock held.
module dma

import devcore
import katomic
import klock
import lib
import limine
import memory
import pci

// A page-table entry: permission in bits 0 and 1, "this is a large page, not
// a table" in bit 7, the address above. An entry with neither permission is
// not present; a table's entry carries both, since what a device may do with
// a page is the least of what every level allows.
const vtd_pte_read = u64(1)
const vtd_pte_write = u64(2)
const vtd_pte_access = vtd_pte_read | vtd_pte_write
const vtd_pte_large = u64(1) << 7
const vtd_pte_address = u64(0x000ffffffffff000)

// A root or context entry's present bit. A context entry's low word also has
// the translation type in bits 2 and 3, zero for "through the second-level
// table"; its high word has the table's depth in bits 0 to 2 and the domain
// number from bit 8.
const vtd_entry_present = u64(1)

const vtd_cap_caching = u64(1) << 7

struct VtdDomain {
mut:
	next &VtdDomain = unsafe { nil }
	unit &VtdUnit   = unsafe { nil }
	lock klock.Lock
	// Its number, and the device it is for: bus, device and function as the
	// device puts them on its requests.
	did u32
	sid u32
	// The top of its page table, and how many pages the table is.
	root   u64
	levels u32
	tables u64
	// The reserved ranges it holds, as a set of indexes into vtd_firmware.
	rmrr_mask u64
	// Made for firmware's use of the device, not for a driver.
	firmware bool
	// All of RAM is mapped; see vtd_map_all().
	identity bool
}

fn vtd_sid(dev &devcore.Device) u32 {
	return (u32(dev.pci.bus) << 8) | (u32(dev.pci.slot) << 3) | u32(dev.pci.function)
}

// A zeroed page of page table, or 0.
fn vtd_table_alloc(mut unit VtdUnit) u64 {
	page := u64(memory.pmm_alloc_fallible(1))
	if page != 0 {
		katomic.inc(mut &unit.table_pages)
	}
	return page
}

fn vtd_table_free(mut unit VtdUnit, page u64) {
	memory.pmm_free(voidptr(page), 1)
	katomic.dec(mut &unit.table_pages)
}

// The unit reads tables from memory. Unless it says it goes through the CPU's
// caches to do so (ECAP.C), an entry the kernel has written is pushed out of
// them.
fn vtd_sync(unit &VtdUnit, entry voidptr) {
	if unit.coherent {
		return
	}
	asm volatile amd64 {
		clflush [entry]
		; ; r (entry)
		; memory
	}
}

// ── Domain numbers ──────────────────────────────────────────────────────────

// A domain number nothing else has, or 0 when the unit has none left.
fn vtd_did_take(mut unit VtdUnit) u32 {
	unit.lock.acquire()
	defer {
		unit.lock.release()
	}
	words := (unit.domain_limit + 63) / 64
	for word := u32(0); word < words; word++ {
		bits := unsafe { unit.domain_bits[word] }
		if bits == ~u64(0) {
			continue
		}
		for bit := u32(0); bit < 64; bit++ {
			if bits & (u64(1) << bit) != 0 {
				continue
			}
			did := word * 64 + bit
			if did >= unit.domain_limit {
				return 0
			}
			unsafe {
				unit.domain_bits[word] = bits | (u64(1) << bit)
			}
			return did
		}
	}
	return 0
}

fn vtd_did_give(mut unit VtdUnit, did u32) {
	unit.lock.acquire()
	unsafe {
		unit.domain_bits[did / 64] &= ~(u64(1) << (did % 64))
	}
	unit.lock.release()
}

// ── Root and context tables ─────────────────────────────────────────────────

// The two words of the context entry of `sid`, or nil if its bus has no
// context table. The unit's lock is held.
fn vtd_context_entry(unit &VtdUnit, sid u32) &u64 {
	root := unsafe { &u64(unit.root + higher_half) }
	pointer := unsafe { root[((sid >> 8) & 0xff) * 2] }
	if pointer & vtd_entry_present == 0 {
		return unsafe { nil }
	}
	table := unsafe { &u64((pointer & vtd_pte_address) + higher_half) }
	return unsafe { &table[(sid & 0xff) * 2] }
}

// Give the bus of `sid` its context table, if it has none. Once made it
// stays: a table that a unit may be reading is not something to take away
// for the sake of a page.
fn vtd_context_table(mut unit VtdUnit, sid u32) bool {
	bus := (sid >> 8) & 0xff
	mut root := unsafe { &u64(unit.root + higher_half) }
	unit.lock.acquire()
	present := unsafe { root[bus * 2] } & vtd_entry_present != 0
	unit.lock.release()
	if present {
		return true
	}
	page := u64(memory.pmm_alloc_fallible(1))
	if page == 0 {
		return false
	}
	unit.lock.acquire()
	if unsafe { root[bus * 2] } & vtd_entry_present != 0 {
		// Another device of the bus got there first.
		unit.lock.release()
		memory.pmm_free(voidptr(page), 1)
		return true
	}
	unsafe {
		root[bus * 2 + 1] = 0
		root[bus * 2] = page | vtd_entry_present
	}
	vtd_sync(unit, unsafe { voidptr(&root[bus * 2]) })
	unit.context_pages++
	if unit.enabled {
		vtd_flush_write_buffer_locked(mut unit)
	}
	unit.lock.release()
	return true
}

// ── Page tables ─────────────────────────────────────────────────────────────

// How much one entry of a table at `level` spans: 4 KiB at the bottom, then
// 2 MiB, 1 GiB, 512 GiB.
fn vtd_span(level u32) u64 {
	return u64(1) << (12 + 9 * (level - 1))
}

fn vtd_slot(table u64, address u64, level u32) &u64 {
	index := (address >> (12 + 9 * (level - 1))) & 0x1ff
	return unsafe { &u64(table + higher_half + index * 8) }
}

// The largest page the unit can map `remaining` bytes at `iova` onto `phys`
// with: one that both addresses are aligned to and that fits.
fn vtd_leaf_level(unit &VtdUnit, iova u64, phys u64, remaining u64) u32 {
	both := iova | phys
	if unit.superpages & 2 != 0 && both & (vtd_span(3) - 1) == 0 && remaining >= vtd_span(3) {
		return 3
	}
	if unit.superpages & 1 != 0 && both & (vtd_span(2) - 1) == 0 && remaining >= vtd_span(2) {
		return 2
	}
	return 1
}

// Map `bytes` at `iova` onto `phys`, readable and writable, in 4 KiB pages
// or, when `large`, in the largest the unit has. False when memory for the
// table runs out, with whatever was mapped until then left in place for the
// caller to take out.
fn vtd_domain_map(mut domain VtdDomain, iova u64, phys u64, bytes u64, large bool) bool {
	mut unit := domain.unit
	mut done := u64(0)
	mut spare := u64(0)
	mut ok := true
	domain.lock.acquire()
	for done < bytes {
		address := iova + done
		mut leaf := u32(1)
		if large {
			leaf = vtd_leaf_level(unit, address, phys + done, bytes - done)
		}
		mut level := domain.levels
		mut slot := vtd_slot(domain.root, address, level)
		mut starved := false
		mut covered := false
		for {
			entry := unsafe { *slot }
			present := entry & vtd_pte_access != 0
			if level == leaf {
				if level == 1 || !present || entry & vtd_pte_large != 0 {
					break
				}
				// A table is here already, from smaller mappings made
				// earlier. It is filled in rather than replaced by a large
				// page: replacing it would mean freeing a page the unit may
				// be in the middle of reading.
				leaf = level - 1
			}
			mut table := entry & vtd_pte_address
			if !present {
				if spare == 0 {
					starved = true
					break
				}
				unsafe {
					*slot = spare | vtd_pte_access
				}
				vtd_sync(unit, voidptr(slot))
				domain.tables++
				table = spare
				spare = 0
			} else if entry & vtd_pte_large != 0 {
				covered = true
				break
			}
			level--
			slot = vtd_slot(table, address, level)
		}
		if starved {
			// The allocator may wait for memory to be given back, which is
			// not something to do holding a spinlock. The walk starts over:
			// the table may have changed meanwhile.
			domain.lock.release()
			spare = vtd_table_alloc(mut unit)
			if spare == 0 {
				ok = false
				break
			}
			domain.lock.acquire()
			continue
		}
		if covered {
			// A large page already maps this address, and with it everything
			// up to the page's end.
			done += vtd_span(level) - (address & (vtd_span(level) - 1))
			continue
		}
		unsafe {
			*slot = (phys + done) | vtd_pte_access | (if leaf > 1 { vtd_pte_large } else { u64(0) })
		}
		vtd_sync(unit, voidptr(slot))
		done += vtd_span(leaf)
	}
	if ok {
		domain.lock.release()
	}
	if spare != 0 {
		vtd_table_free(mut unit, spare)
	}
	return ok
}

// Take the 4 KiB pages of `bytes` at `iova` out of the table, except those
// firmware's reserved ranges hold. True if any was there. The unit still has
// to be made to forget them.
fn vtd_domain_unmap(mut domain VtdDomain, iova u64, bytes u64) bool {
	unit := domain.unit
	mut cleared := false
	domain.lock.acquire()
	for offset := u64(0); offset < bytes; offset += 0x1000 {
		address := iova + offset
		if vtd_rmrr_holds(vtd_firmware, domain.rmrr_mask, address) {
			continue
		}
		mut table := domain.root
		mut level := domain.levels
		for level > 1 {
			entry := unsafe { *vtd_slot(table, address, level) }
			if entry & vtd_pte_access == 0 || entry & vtd_pte_large != 0 {
				table = 0
				break
			}
			table = entry & vtd_pte_address
			level--
		}
		if table == 0 {
			continue
		}
		mut slot := vtd_slot(table, address, 1)
		if unsafe { *slot } != 0 {
			unsafe {
				*slot = 0
			}
			vtd_sync(unit, voidptr(slot))
			cleared = true
		}
	}
	domain.lock.release()
	return cleared
}

// Free the table at `table` and every table below it. Nothing may be
// translating through it any more.
fn vtd_tables_free(mut unit VtdUnit, table u64, level u32) {
	if level > 1 {
		for index := u64(0); index < 512; index++ {
			entry := unsafe { *&u64(table + higher_half + index * 8) }
			if entry & vtd_pte_access != 0 && entry & vtd_pte_large == 0 {
				vtd_tables_free(mut unit, entry & vtd_pte_address, level - 1)
			}
		}
	}
	vtd_table_free(mut unit, table)
}

// ── A domain's life ─────────────────────────────────────────────────────────

// Free a domain no context entry points to: its table, its number, itself.
fn vtd_domain_free(mut unit VtdUnit, mut domain VtdDomain) {
	if domain.root != 0 {
		vtd_tables_free(mut unit, domain.root, domain.levels)
	}
	if domain.did != 0 {
		vtd_did_give(mut unit, domain.did)
	}
	memory.free(voidptr(domain))
}

// A domain for the device `sid` holding the reserved ranges of `rmrr_mask`
// and nothing else, not yet in use. Nil when there is no memory or no domain
// number left, or a reserved range lies beyond what the unit translates.
fn vtd_domain_new(mut unit VtdUnit, sid u32, rmrr_mask u64, firmware bool) &VtdDomain {
	allocation := memory.malloc_packed_fallible(sizeof(VtdDomain))
	if allocation == unsafe { nil } {
		return unsafe { nil }
	}
	unsafe { C.memset(allocation, 0, sizeof(VtdDomain)) }
	// Freed by vtd_domain_free().
	mut domain := unsafe { &VtdDomain(allocation) }
	domain.unit = unsafe { unit }
	domain.sid = sid
	domain.levels = unit.levels
	domain.rmrr_mask = rmrr_mask
	domain.firmware = firmware
	domain.root = vtd_table_alloc(mut unit)
	if domain.root != 0 {
		domain.tables = 1
		domain.did = vtd_did_take(mut unit)
	}
	if domain.root == 0 || domain.did == 0 || !vtd_context_table(mut unit, sid) {
		vtd_domain_free(mut unit, mut domain)
		return unsafe { nil }
	}
	for i := u32(0); i < vtd_firmware.rmrr_count; i++ {
		if rmrr_mask & (u64(1) << i) == 0 {
			continue
		}
		rmrr := unsafe { &vtd_firmware.rmrrs[i] }
		if rmrr.limit > u64(1) << unit.address_bits
			|| !vtd_domain_map(mut domain, rmrr.base, rmrr.base, rmrr.limit - rmrr.base, false) {
			vtd_domain_free(mut unit, mut domain)
			return unsafe { nil }
		}
	}
	return domain
}

// Put `incoming`, or nothing if it is nil, in place of the domain the device
// `sid` has now, and return that one for the caller to free. With `expected`
// the device must have exactly that domain; without, it must have none or a
// firmware one -- a driver's domain is not taken from under it. False, and
// nothing changed, otherwise.
fn vtd_domain_swap(mut unit VtdUnit, sid u32, incoming &VtdDomain, expected &VtdDomain) (bool, &VtdDomain) {
	unit.lock.acquire()
	mut before := &VtdDomain(unsafe { nil })
	mut current := unit.domains
	for current != unsafe { nil } && current.sid != sid {
		before = current
		current = current.next
	}
	mut entry := vtd_context_entry(unit, sid)
	refused := if expected != unsafe { nil } {
		voidptr(current) != voidptr(expected)
	} else {
		current != unsafe { nil } && !current.firmware
	}
	if refused || entry == unsafe { nil } {
		unit.lock.release()
		return false, unsafe { nil }
	}
	if current != unsafe { nil } {
		// Not present first, then the rest: the unit must never find the
		// entry half written.
		unsafe {
			entry[0] = 0
			entry[1] = 0
		}
		vtd_sync(unit, voidptr(entry))
		if unit.enabled {
			vtd_flush_context_locked(mut unit, vtd_ccmd_device, current.did, sid)
			vtd_flush_iotlb_locked(mut unit, vtd_iotlb_domain, current.did, 0, 0)
		}
		if before == unsafe { nil } {
			unit.domains = current.next
		} else {
			before.next = current.next
		}
		current.next = unsafe { nil }
		unit.domain_count--
	}
	if incoming != unsafe { nil } {
		mut fresh := unsafe { incoming }
		unsafe {
			entry[1] = unit.width_code | (u64(fresh.did) << 8)
			entry[0] = fresh.root | vtd_entry_present
		}
		vtd_sync(unit, voidptr(entry))
		if unit.enabled {
			if unit.cap & vtd_cap_caching != 0 {
				// A unit that caches absent entries has this one filed under
				// domain 0.
				vtd_flush_context_locked(mut unit, vtd_ccmd_device, 0, sid)
				vtd_flush_iotlb_locked(mut unit, vtd_iotlb_domain, fresh.did, 0, 0)
			} else {
				vtd_flush_write_buffer_locked(mut unit)
			}
		}
		fresh.next = unit.domains
		unit.domains = fresh
		unit.domain_count++
	}
	unit.lock.release()
	return true, current
}

// The PCI Express device type of a function -- bits 4 to 7 of the flags of
// its PCI Express capability -- or -1 if it has no such capability.
fn vtd_express_type(function &pci.PCIDevice) int {
	status := function.read[u16](0x06)
	if status == 0xffff || status & 0x10 == 0 {
		return -1
	}
	mut offset := u32(function.read[u8](0x34)) & 0xfc
	// The list is at most 48 capabilities long; one that is longer loops.
	for _ in 0 .. 48 {
		if offset < 0x40 {
			break
		}
		if function.read[u8](offset) == 0x10 {
			return int((function.read[u16](offset + 2) >> 4) & 0xf)
		}
		offset = u32(function.read[u8](offset + 1)) & 0xfc
	}
	return -1
}

// Whether something between `dev` and the root bus rewrites the requester of
// its transfers: a conventional PCI bridge, or a PCI Express bridge to
// conventional PCI (type 7). See the top of this file.
fn vtd_requester_aliased(dev &devcore.Device) bool {
	mut node := dev.parent
	for node != unsafe { nil } {
		if node.pci != unsafe { nil } {
			kind := vtd_express_type(node.pci)
			if kind < 0 || kind == 7 {
				return true
			}
		}
		node = node.parent
	}
	return false
}

// Give `dev` a firmware domain if an RMRR names it. Called for every device
// behind the unit before translation is switched on.
fn vtd_firmware_domain(mut unit VtdUnit, dev &devcore.Device) {
	mask := vtd_rmrr_mask(vtd_firmware, dev)
	if mask == 0 {
		return
	}
	sid := vtd_sid(dev)
	mut domain := &VtdDomain(unsafe { nil })
	if !vtd_requester_aliased(dev) {
		domain = vtd_domain_new(mut unit, sid, mask, true)
	}
	if domain != unsafe { nil } {
		ok, _ := vtd_domain_swap(mut unit, sid, domain, unsafe { nil })
		if ok {
			return
		}
		vtd_domain_free(mut unit, mut domain)
	}
	C.kprintf(c'vtd: %.*s could not be given the memory firmware reserved for it; what firmware does with it will fault\n',
		i32(dev.name.len), dev.name.str)
}

fn vtd_firmware_domains(mut unit VtdUnit) {
	if vtd_firmware.rmrr_count == 0 {
		return
	}
	for i := 0; i < devcore.device_count(); i++ {
		dev := devcore.device_at(i)
		if dev != unsafe { nil } && dev.pci != unsafe { nil }
			&& vtd_drhd_covers(vtd_firmware, unit.drhd, dev) {
			vtd_firmware_domain(mut unit, dev)
		}
	}
}

// ── What the DMA layer calls ────────────────────────────────────────────────

fn vtd_covers(iommu &Iommu, dev &devcore.Device) bool {
	unit := unsafe { &VtdUnit(iommu.data) }
	return vtd_drhd_covers(vtd_firmware, unit.drhd, dev)
}

// A domain for `dev`'s driver: empty but for what firmware reserved for the
// device. Nil leaves the device as it was, which behind a unit that is on is
// blocked, or reaching firmware's ranges only.
fn vtd_attach(iommu &Iommu, mut dev devcore.Device) voidptr {
	mut unit := unsafe { &VtdUnit(iommu.data) }
	if dev.pci == unsafe { nil } {
		return unsafe { nil }
	}
	if vtd_requester_aliased(dev) {
		C.kprintf(c'vtd: %.*s is behind a conventional PCI bridge, which answers for it on the bus; it cannot have a domain of its own\n',
			i32(dev.name.len), dev.name.str)
		return unsafe { nil }
	}
	sid := vtd_sid(dev)
	mut domain := vtd_domain_new(mut unit, sid, vtd_rmrr_mask(vtd_firmware, dev), false)
	if domain == unsafe { nil } {
		return unsafe { nil }
	}
	ok, displaced := vtd_domain_swap(mut unit, sid, domain, unsafe { nil })
	if !ok {
		vtd_domain_free(mut unit, mut domain)
		return unsafe { nil }
	}
	if displaced != unsafe { nil } {
		mut firmware := unsafe { displaced }
		vtd_domain_free(mut unit, mut firmware)
	}
	return voidptr(domain)
}

// Take the device's domain away and free every page of its table. The device
// reaches nothing afterwards, or, if firmware reserved memory for it, that
// memory and nothing else.
fn vtd_detach(cookie voidptr) {
	mut domain := unsafe { &VtdDomain(cookie) }
	mut unit := domain.unit
	mut successor := &VtdDomain(unsafe { nil })
	if domain.rmrr_mask != 0 {
		successor = vtd_domain_new(mut unit, domain.sid, domain.rmrr_mask, true)
		if successor == unsafe { nil } {
			C.kprintf(c'vtd: no memory to give device %02llx:%02llx.%llx back the ranges firmware reserved for it; what firmware does with it will fault\n',
				u64(domain.sid >> 8), u64((domain.sid >> 3) & 0x1f), u64(domain.sid & 7))
		}
	}
	ok, _ := vtd_domain_swap(mut unit, domain.sid, successor, domain)
	if !ok {
		// The device does not have this domain, which would mean it was
		// detached twice. Freeing it again would be worse than keeping it.
		if successor != unsafe { nil } {
			vtd_domain_free(mut unit, mut successor)
		}
		return
	}
	vtd_domain_free(mut unit, mut domain)
}

fn vtd_map(cookie voidptr, iova u64, phys u64, bytes u64) bool {
	mut domain := unsafe { &VtdDomain(cookie) }
	mut unit := domain.unit
	if bytes == 0 || (iova | phys | bytes) & 0xfff != 0 || iova + bytes < iova
		|| iova + bytes > u64(1) << unit.address_bits {
		return false
	}
	if domain.identity {
		return true
	}
	if !vtd_domain_map(mut domain, iova, phys, bytes, false) {
		vtd_unmap(cookie, iova, bytes)
		return false
	}
	vtd_after_map(mut unit, domain.did)
	return true
}

// Does not return until the unit has forgotten the pages: once it does, the
// memory may be anyone's.
fn vtd_unmap(cookie voidptr, iova u64, bytes u64) {
	mut domain := unsafe { &VtdDomain(cookie) }
	mut unit := domain.unit
	// A domain that holds all of RAM keeps it until it goes: its pages are
	// not counted one by one, so none can be known to be unused.
	if domain.identity || bytes == 0 || (iova | bytes) & 0xfff != 0 {
		return
	}
	if vtd_domain_unmap(mut domain, iova, bytes) {
		vtd_flush_range(mut unit, domain.did, iova, bytes)
	}
}

// Map every page of RAM onto itself, for a driver that still chooses its own
// addresses: what is free to be allocated, what the boot loader left, and the
// kernel and its modules. Memory firmware keeps for itself is not RAM in this
// sense, nor is any device's. Large pages are used where the unit has them
// and the memory map allows.
fn vtd_map_all(cookie voidptr) bool {
	mut domain := unsafe { &VtdDomain(cookie) }
	mut unit := domain.unit
	if domain.identity {
		return true
	}
	memmap := memmap_req.response
	if memmap == unsafe { nil } {
		return false
	}
	limit := u64(1) << unit.address_bits
	for i := u64(0); i < memmap.entry_count; i++ {
		entry := unsafe { memmap.entries[i] }
		if entry.@type != limine.limine_memmap_usable
			&& entry.@type != limine.limine_memmap_bootloader_reclaimable
			&& entry.@type != limine.limine_memmap_kernel_and_modules {
			continue
		}
		base := lib.align_down(entry.base, 0x1000)
		top := lib.align_up(entry.base + entry.length, 0x1000)
		if top > limit || !vtd_domain_map(mut domain, base, base, top - base, true) {
			return false
		}
	}
	domain.identity = true
	vtd_after_map(mut unit, domain.did)
	return true
}
