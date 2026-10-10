// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The ACPI DMAR table: where firmware says which VT-d units the machine has
// and what each is in front of.
//
// After a 48-byte header come "remapping structures", each starting with a
// 16-bit type and a 16-bit length. Two kinds matter here:
//
//	DRHD (0)  a unit: its PCI segment, where its registers are, and either
//	          the devices behind it or a flag saying "every device of the
//	          segment that no other unit lists" (INCLUDE_PCI_ALL)
//	RMRR (1)  a range of memory firmware itself has devices read and write
//	          -- a USB controller it emulates a keyboard through, graphics
//	          stolen memory -- and the devices that do
//
// A device is named by a "device scope": a type, a starting bus number and a
// path of (device, function) pairs, each but the last being a bridge to go
// through. The bus a bridge leads to is not in the table; it is read from the
// bridge when the path is resolved.
//
// Everything is read through bounds checked against the table's own length,
// a byte at a time: a structure that runs past the table, or a scope that
// runs past its structure, makes the whole table unusable rather than
// partly believed. A table that says less than it should about which device
// is behind which unit is worse than none.
module dma

import devcore
import pci

const vtd_dmar_header_bytes = u64(48)
// No table is anywhere near this long; one that claims to be is not a table.
const vtd_dmar_max_bytes = u64(1) << 20
const vtd_drhd_bytes = u64(16)
const vtd_rmrr_bytes = u64(24)
const vtd_scope_bytes = u64(6)

const vtd_structure_drhd = u16(0)
const vtd_structure_rmrr = u16(1)
const vtd_drhd_include_all = u8(1)

// The DMA layer has room for eight units; firmware may describe more, and
// what each of them covers has to be known to tell what the others do not.
const vtd_max_units = 16

// The device scopes that name something on PCI. The others name an I/O APIC,
// an HPET or a device known only to ACPI, for interrupt remapping and for
// hardware that is not on PCI; nothing here translates for them.
const vtd_scope_endpoint = u8(1)
const vtd_scope_bridge = u8(2)

const vtd_max_rmrrs = 64
const vtd_max_scopes = 512
// How many bridges deep a named device may be.
const vtd_max_path = 8

struct VtdScope {
mut:
	kind      u8
	start_bus u8
	// Pairs in `path`.
	depth u8
	path  [16]u8
	// Where the path leads, once the bridges on it have been asked.
	resolved bool
	bus      u8
	devfn    u8
}

struct VtdDrhd {
mut:
	segment     u16
	include_all bool
	address     u64
	scope_first u32
	scope_count u32
}

struct VtdRmrr {
mut:
	segment u16
	// Whole pages; `limit` is the address after the last byte.
	base        u64
	limit       u64
	scope_first u32
	scope_count u32
}

struct VtdFirmware {
mut:
	host_address_bits u32
	drhds             [vtd_max_units]VtdDrhd
	drhd_count        u32
	rmrrs             [vtd_max_rmrrs]VtdRmrr
	rmrr_count        u32
	// One pool for the scopes of every structure.
	scopes      [vtd_max_scopes]VtdScope
	scope_count u32
}

fn vtd_get8(table voidptr, offset u64) u8 {
	return unsafe { *&u8(u64(table) + offset) }
}

fn vtd_get16(table voidptr, offset u64) u16 {
	return u16(vtd_get8(table, offset)) | (u16(vtd_get8(table, offset + 1)) << 8)
}

fn vtd_get32(table voidptr, offset u64) u32 {
	return u32(vtd_get16(table, offset)) | (u32(vtd_get16(table, offset + 2)) << 16)
}

fn vtd_get64(table voidptr, offset u64) u64 {
	return u64(vtd_get32(table, offset)) | (u64(vtd_get32(table, offset + 4)) << 32)
}

// Read the device scopes in [start, end) of the table into the pool. Returns
// how many were kept, or -1 if they do not fit their structure or the pool.
fn vtd_parse_scopes(table voidptr, start u64, end u64, mut firmware VtdFirmware) i64 {
	mut offset := start
	mut kept := i64(0)
	for offset < end {
		if end - offset < vtd_scope_bytes {
			return -1
		}
		kind := vtd_get8(table, offset)
		size := u64(vtd_get8(table, offset + 1))
		if size < vtd_scope_bytes || size > end - offset || (size - vtd_scope_bytes) % 2 != 0 {
			return -1
		}
		hops := (size - vtd_scope_bytes) / 2
		if kind == vtd_scope_endpoint || kind == vtd_scope_bridge {
			if hops == 0 || hops > vtd_max_path || firmware.scope_count >= vtd_max_scopes {
				return -1
			}
			mut scope := unsafe { &firmware.scopes[firmware.scope_count] }
			scope.kind = kind
			scope.start_bus = vtd_get8(table, offset + 5)
			scope.depth = u8(hops)
			scope.resolved = false
			for hop := u64(0); hop < hops; hop++ {
				device := vtd_get8(table, offset + vtd_scope_bytes + hop * 2)
				function := vtd_get8(table, offset + vtd_scope_bytes + hop * 2 + 1)
				if device > 31 || function > 7 {
					return -1
				}
				scope.path[hop * 2] = device
				scope.path[hop * 2 + 1] = function
			}
			firmware.scope_count++
			kept++
		}
		offset += size
	}
	return kept
}

// Read the DMAR table at `table` into `firmware`, which is zeroed. False if
// any of it does not fit, in which case none of it is to be used.
fn vtd_parse_table(table voidptr, mut firmware VtdFirmware) bool {
	length := u64(vtd_get32(table, 4))
	if length < vtd_dmar_header_bytes || length > vtd_dmar_max_bytes {
		return false
	}
	firmware.host_address_bits = u32(vtd_get8(table, 36)) + 1
	mut offset := vtd_dmar_header_bytes
	for offset < length {
		if length - offset < 4 {
			return false
		}
		kind := vtd_get16(table, offset)
		size := u64(vtd_get16(table, offset + 2))
		// A length of zero would be read again for ever.
		if size < 4 || size > length - offset {
			return false
		}
		if kind == vtd_structure_drhd {
			if size < vtd_drhd_bytes || firmware.drhd_count >= vtd_max_units {
				return false
			}
			first := firmware.scope_count
			kept := vtd_parse_scopes(table, offset + vtd_drhd_bytes, offset + size, mut
				firmware)
			if kept < 0 {
				return false
			}
			mut drhd := unsafe { &firmware.drhds[firmware.drhd_count] }
			drhd.include_all = vtd_get8(table, offset + 4) & vtd_drhd_include_all != 0
			drhd.segment = vtd_get16(table, offset + 6)
			drhd.address = vtd_get64(table, offset + 8)
			drhd.scope_first = first
			drhd.scope_count = u32(kept)
			firmware.drhd_count++
		} else if kind == vtd_structure_rmrr {
			if size < vtd_rmrr_bytes || firmware.rmrr_count >= vtd_max_rmrrs {
				return false
			}
			first := firmware.scope_count
			kept := vtd_parse_scopes(table, offset + vtd_rmrr_bytes, offset + size, mut
				firmware)
			if kept < 0 {
				return false
			}
			base := vtd_get64(table, offset + 8)
			last := vtd_get64(table, offset + 16)
			// The range is given by its first and last byte. One that ends
			// before it starts, or at the very top of the address space,
			// describes nothing a device could be using.
			if last < base || last >= ~u64(0xfff) {
				return false
			}
			mut rmrr := unsafe { &firmware.rmrrs[firmware.rmrr_count] }
			rmrr.segment = vtd_get16(table, offset + 6)
			// Firmware is supposed to give whole pages. Where it does not,
			// the pages its bytes are in are what the device has to reach.
			rmrr.base = base & ~u64(0xfff)
			rmrr.limit = (last + 0x1000) & ~u64(0xfff)
			rmrr.scope_first = first
			rmrr.scope_count = u32(kept)
			firmware.rmrr_count++
		}
		// Anything else -- root-port ATS, NUMA affinity, ACPI-only devices,
		// kinds defined after this was written -- is stepped over.
		offset += size
	}
	return true
}

// The bus behind the bridge at bus:device.function, or none if there is no
// bridge there or firmware has not given it a bus.
fn vtd_bus_behind(bus u8, device u8, function u8) ?u8 {
	bridge := pci.get_device_by_coordinates(bus, device, function, 0) or { return none }
	if bridge.header_type & 0x7f != 1 {
		return none
	}
	secondary := bridge.read[u8](0x19)
	if secondary == 0 || secondary == 0xff {
		return none
	}
	return secondary
}

// Walk every scope's path to the bus, device and function it ends at. One
// that cannot be walked -- a bridge on it is absent -- stays unresolved and
// names nothing.
fn vtd_resolve_scopes(mut firmware VtdFirmware) {
	for i := u32(0); i < firmware.scope_count; i++ {
		mut scope := unsafe { &firmware.scopes[i] }
		mut bus := scope.start_bus
		mut walked := true
		for hop := 0; hop + 1 < int(scope.depth); hop++ {
			bus = vtd_bus_behind(bus, scope.path[hop * 2], scope.path[hop * 2 + 1]) or {
				walked = false
				break
			}
		}
		if !walked {
			continue
		}
		last := (int(scope.depth) - 1) * 2
		scope.bus = bus
		scope.devfn = (scope.path[last] << 3) | scope.path[last + 1]
		scope.resolved = true
	}
}

// Whether the scopes [first, first + count) name `dev`: itself, or a bridge
// it sits behind, which stands for everything below it.
fn vtd_scopes_name(firmware &VtdFirmware, first u32, count u32, dev &devcore.Device) bool {
	mut node := unsafe { dev }
	mut own := true
	for node != unsafe { nil } {
		if node.pci != unsafe { nil } {
			bus := node.pci.bus
			devfn := (node.pci.slot << 3) | node.pci.function
			for i := first; i < first + count; i++ {
				scope := unsafe { &firmware.scopes[i] }
				if scope.resolved && scope.bus == bus && scope.devfn == devfn
					&& (own || scope.kind == vtd_scope_bridge) {
					return true
				}
			}
		}
		own = false
		node = node.parent
	}
	return false
}

// Whether the unit described by DRHD `index` is the one in front of `dev`.
fn vtd_drhd_covers(firmware &VtdFirmware, index u32, dev &devcore.Device) bool {
	drhd := unsafe { &firmware.drhds[index] }
	// The PCI layer knows one segment, so every device it has is in it.
	if drhd.segment != 0 || dev.pci == unsafe { nil } {
		return false
	}
	if vtd_scopes_name(firmware, drhd.scope_first, drhd.scope_count, dev) {
		return true
	}
	if !drhd.include_all {
		return false
	}
	// "All" is all that no other unit of the segment lists, whether or not
	// that unit was switched on.
	for other := u32(0); other < firmware.drhd_count; other++ {
		if other == index || firmware.drhds[other].segment != 0 {
			continue
		}
		if vtd_scopes_name(firmware, firmware.drhds[other].scope_first, firmware.drhds[other].scope_count,
			dev) {
			return false
		}
	}
	return true
}

// Whether a unit lists devices rather than "all", and every one it lists is
// 00:02.0, where Intel puts the integrated graphics.
fn vtd_drhd_lists_only_graphics_slot(firmware &VtdFirmware, index u32) bool {
	drhd := unsafe { &firmware.drhds[index] }
	if drhd.include_all || drhd.scope_count == 0 {
		return false
	}
	for i := drhd.scope_first; i < drhd.scope_first + drhd.scope_count; i++ {
		scope := unsafe { &firmware.scopes[i] }
		if scope.kind != vtd_scope_endpoint || scope.depth != 1 || scope.start_bus != 0
			|| scope.path[0] != 2 || scope.path[1] != 0 {
			return false
		}
	}
	return true
}

// Whether a unit is there for the integrated graphics alone. A machine with
// something else in that slot -- a virtual one, say -- is not meant.
fn vtd_drhd_graphics_only(firmware &VtdFirmware, index u32) bool {
	if !vtd_drhd_lists_only_graphics_slot(firmware, index) {
		return false
	}
	graphics := pci.get_device_by_coordinates(0, 2, 0, 0) or { return true }
	return graphics.class == 0x03
}

// The reserved ranges `dev` has to keep reaching, as a set of indexes into
// firmware.rmrrs.
fn vtd_rmrr_mask(firmware &VtdFirmware, dev &devcore.Device) u64 {
	mut mask := u64(0)
	for i := u32(0); i < firmware.rmrr_count; i++ {
		rmrr := unsafe { &firmware.rmrrs[i] }
		if rmrr.segment == 0 && vtd_scopes_name(firmware, rmrr.scope_first, rmrr.scope_count, dev) {
			mask |= u64(1) << i
		}
	}
	return mask
}

// Whether `address` lies in one of the ranges of `mask`.
fn vtd_rmrr_holds(firmware &VtdFirmware, mask u64, address u64) bool {
	if mask == 0 {
		return false
	}
	for i := u32(0); i < firmware.rmrr_count; i++ {
		if mask & (u64(1) << i) != 0 && address >= firmware.rmrrs[i].base
			&& address < firmware.rmrrs[i].limit {
			return true
		}
	}
	return false
}
