// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// A proof at boot that VT-d does what it is for. This file is only compiled
// with -d vtd_selftest, which is what its name says to the compiler; nothing
// of it is in an ordinary kernel.
//
// The first half needs no hardware: DMAR tables made up here are given to the
// parser, a good one and the same one cut short at every length and damaged
// in each way the parser is supposed to notice.
//
// The second half needs a unit that is on and an Intel 8254x network card
// behind it that no driver has taken yet, which is the state QEMU's e1000 is
// in when vtd_initialise() runs. The card is made to do real DMA: its PHY is
// put in loopback, so a frame it sends comes straight back and is written to
// wherever its receive descriptor points. Pointing that at a page the card's
// domain does not hold has to leave the page as it was and a fault against
// the card in the unit's records; pointing it at a page the domain holds has
// to deliver the frame. The same is done for memory unmapped again (the unit
// must have forgotten it), for a made-up reserved range (a device firmware
// uses must reach it with and without a driver, and nothing else), for a
// domain holding all of RAM, and fifty attach and detach rounds must leave
// not one page of page table behind.
//
// The card is left as it was found -- loopback off, receive and transmit
// off, its PCI command register as before -- and its driver binds it
// afterwards as on any other boot.
//
// The verdict goes to the log and to the file `selftest` in each unit's
// directory in /sys/class/iommu.
@[has_globals]
module dma

import devcore
import lib
import memory
import x86.kio

const vtd_test_max_lines = 40

struct VtdTestLine {
mut:
	name string
	ok   bool
}

__global (
	vtd_test_lines    [vtd_test_max_lines]VtdTestLine
	vtd_test_count    u32
	vtd_test_failures u32
	// Why the hardware half did not run, if it did not.
	vtd_test_skipped string
	vtd_test_done bool
	// Figures worth seeing next to the verdict: how many pages of page table
	// all of RAM took, the most the fifty rounds held, and free memory before
	// and after them.
	vtd_test_identity_tables u64
	vtd_test_round_tables    u64
	vtd_test_free_before     u64
	vtd_test_free_after      u64
)

// Record one check. `name` is a literal: it is kept, not copied.
fn vtd_check(name string, ok bool) bool {
	if vtd_test_count < vtd_test_max_lines {
		vtd_test_lines[vtd_test_count].name = name
		vtd_test_lines[vtd_test_count].ok = ok
		vtd_test_count++
	}
	if !ok {
		vtd_test_failures++
	}
	C.kprintf(c'vtd selftest: %s  %.*s\n', if ok { c'pass' } else { c'FAIL' }, i32(name.len),
		name.str)
	return ok
}

// ── Made-up tables ──────────────────────────────────────────────────────────

fn vtd_test_put(table u64, offset u64, width u64, value u64) {
	for i := u64(0); i < width; i++ {
		unsafe {
			*&u8(table + offset + i) = u8(value >> (i * 8))
		}
	}
}

const vtd_test_table_bytes = u64(170)
// Where one structure of the table below ends and the next begins.
const vtd_test_boundaries = [u64(48), 72, 114, 146, 154, 170]!
const vtd_test_range_base = u64(0x7b800000)
const vtd_test_range_last = u64(0x7bffffff)

// A table with: a unit for 00:02.0 alone; a unit for "all the rest" that also
// lists an I/O APIC, an HPET and what is behind a bridge two levels down; a
// reserved range for 00:00.0; a structure of a kind nobody has defined; and
// a unit for another PCI segment.
fn vtd_test_table(table u64) {
	unsafe { C.memset(voidptr(table), 0, 0x1000) }
	vtd_test_put(table, 0, 4, 0x52414d44) // "DMAR"
	vtd_test_put(table, 4, 4, vtd_test_table_bytes)
	vtd_test_put(table, 8, 1, 1)
	vtd_test_put(table, 36, 1, 38)
	vtd_test_put(table, 37, 1, 1)

	vtd_test_put(table, 48, 2, 0)
	vtd_test_put(table, 50, 2, 24)
	vtd_test_put(table, 56, 8, 0xfed90000)
	vtd_test_put(table, 64, 1, 1)
	vtd_test_put(table, 65, 1, 8)
	vtd_test_put(table, 70, 1, 2)
	vtd_test_put(table, 71, 1, 0)

	vtd_test_put(table, 72, 2, 0)
	vtd_test_put(table, 74, 2, 42)
	vtd_test_put(table, 76, 1, 1)
	vtd_test_put(table, 80, 8, 0xfed91000)
	vtd_test_put(table, 88, 1, 3)
	vtd_test_put(table, 89, 1, 8)
	vtd_test_put(table, 92, 1, 2)
	vtd_test_put(table, 93, 1, 0xff)
	vtd_test_put(table, 94, 1, 0x1f)
	vtd_test_put(table, 95, 1, 7)
	vtd_test_put(table, 96, 1, 4)
	vtd_test_put(table, 97, 1, 8)
	vtd_test_put(table, 101, 1, 0xff)
	vtd_test_put(table, 102, 1, 0x1f)
	vtd_test_put(table, 103, 1, 6)
	vtd_test_put(table, 104, 1, 2)
	vtd_test_put(table, 105, 1, 10)
	vtd_test_put(table, 110, 1, 0x1c)
	vtd_test_put(table, 111, 1, 0)
	vtd_test_put(table, 112, 1, 0)
	vtd_test_put(table, 113, 1, 0)

	vtd_test_put(table, 114, 2, 1)
	vtd_test_put(table, 116, 2, 32)
	vtd_test_put(table, 122, 8, vtd_test_range_base)
	vtd_test_put(table, 130, 8, vtd_test_range_last)
	vtd_test_put(table, 138, 1, 1)
	vtd_test_put(table, 139, 1, 8)
	vtd_test_put(table, 144, 1, 0)
	vtd_test_put(table, 145, 1, 0)

	vtd_test_put(table, 146, 2, 0x7f)
	vtd_test_put(table, 148, 2, 8)
	vtd_test_put(table, 150, 4, 0xdeadbeef)

	vtd_test_put(table, 154, 2, 0)
	vtd_test_put(table, 156, 2, 16)
	vtd_test_put(table, 158, 1, 1)
	vtd_test_put(table, 160, 2, 1)
	vtd_test_put(table, 162, 8, 0xfed92000)
}

fn vtd_test_parse(table u64, mut firmware VtdFirmware) bool {
	unsafe { C.memset(voidptr(firmware), 0, sizeof(VtdFirmware)) }
	return vtd_parse_table(voidptr(table), mut firmware)
}

fn vtd_test_pci_device(bus u8, slot u8, function u8) &devcore.Device {
	for i := 0; i < devcore.device_count(); i++ {
		dev := devcore.device_at(i)
		if dev != unsafe { nil } && dev.pci != unsafe { nil } && dev.pci.bus == bus
			&& dev.pci.slot == slot && dev.pci.function == function {
			return dev
		}
	}
	return unsafe { nil }
}

fn vtd_selftest_tables() {
	page := u64(memory.pmm_alloc_fallible(1))
	mut firmware := vtd_firmware_new()
	if page == 0 || firmware == unsafe { nil } {
		vtd_check('tables: memory for the test', false)
		return
	}
	table := page + higher_half

	vtd_test_table(table)
	mut good := vtd_test_parse(table, mut firmware)
	vtd_check('tables: a well-formed table is read', good)
	good = good && firmware.host_address_bits == 39 && firmware.drhd_count == 3
		&& firmware.rmrr_count == 1 && firmware.scope_count == 3
	good = good && !firmware.drhds[0].include_all && firmware.drhds[0].address == 0xfed90000
		&& firmware.drhds[0].scope_count == 1 && firmware.drhds[1].include_all
		&& firmware.drhds[1].scope_count == 1 && firmware.drhds[2].segment == 1
	if good {
		bridge := firmware.scopes[firmware.drhds[1].scope_first]
		good = bridge.kind == vtd_scope_bridge && bridge.depth == 2 && bridge.path[0] == 0x1c
			&& firmware.rmrrs[0].base == vtd_test_range_base
			&& firmware.rmrrs[0].limit == vtd_test_range_last + 1
			&& firmware.rmrrs[0].scope_count == 1
	}
	vtd_check('tables: units, scopes and reserved ranges are as written', good)
	vtd_check('tables: a unit for 00:02.0 alone is told from the others', vtd_drhd_lists_only_graphics_slot(firmware,
		0) && !vtd_drhd_lists_only_graphics_slot(firmware, 1)
		&& !vtd_drhd_lists_only_graphics_slot(firmware, 2))

	// Who is behind which unit, asked about devices this machine has.
	vtd_resolve_scopes(mut firmware)
	host := vtd_test_pci_device(0, 0, 0)
	if host != unsafe { nil } {
		vtd_check('tables: "all" covers a device no unit lists, in its own segment only',
			vtd_drhd_covers(firmware, 1, host) && !vtd_drhd_covers(firmware, 0, host)
			&& !vtd_drhd_covers(firmware, 2, host))
		vtd_check('tables: a reserved range belongs to the device it names', vtd_rmrr_mask(firmware,
			host) == 1 && vtd_rmrr_holds(firmware, 1, vtd_test_range_base)
			&& vtd_rmrr_holds(firmware, 1, vtd_test_range_last & ~u64(0xfff))
			&& !vtd_rmrr_holds(firmware, 1, vtd_test_range_last + 1)
			&& !vtd_rmrr_holds(firmware, 0, vtd_test_range_base))
	}
	second := vtd_test_pci_device(0, 2, 0)
	if second != unsafe { nil } {
		vtd_check('tables: a listed device belongs to its unit and not to "all"', vtd_drhd_covers(firmware,
			0, second) && !vtd_drhd_covers(firmware, 1, second)
			&& vtd_rmrr_mask(firmware, second) == 0)
	}

	// Cut short at every length: only a cut between two structures leaves a
	// table, and a shorter one.
	mut wrong := 0
	for length := u64(0); length < vtd_test_table_bytes; length++ {
		vtd_test_put(table, 4, 4, length)
		mut whole := false
		for boundary in vtd_test_boundaries {
			if length == boundary {
				whole = true
			}
		}
		if vtd_test_parse(table, mut firmware) != whole {
			wrong++
		}
	}
	vtd_check('tables: a table cut short inside a structure is refused, at every length',
		wrong == 0)

	// Damaged in one place at a time: a structure of no length, one too
	// short for its kind, scopes that are too short, of odd length, longer
	// than their structure or without a path, a device or function number
	// that cannot be, and a range that ends before it starts.
	offsets := [u64(74), 50, 116, 65, 65, 65, 65, 105, 70, 71, 130]!
	widths := [u64(2), 2, 2, 1, 1, 1, 1, 1, 1, 1, 8]!
	values := [u64(0), 12, 20, 5, 9, 12, 6, 9, 32, 8, 0x1000]!
	wrong = 0
	for i := 0; i < 11; i++ {
		vtd_test_table(table)
		vtd_test_put(table, offsets[i], widths[i], values[i])
		if vtd_test_parse(table, mut firmware) {
			wrong++
		}
	}
	vtd_check('tables: a table damaged in any of eleven ways is refused', wrong == 0)

	memory.free(voidptr(firmware))
	memory.pmm_free(voidptr(page), 1)
}

// ── The card ────────────────────────────────────────────────────────────────

// The few registers of an 8254x that it takes to loop one frame.
const vtd_card_mdic = u64(0x0020)
const vtd_card_icr = u64(0x00c0)
const vtd_card_imc = u64(0x00d8)
const vtd_card_rctl = u64(0x0100)
const vtd_card_tctl = u64(0x0400)
const vtd_card_rdbal = u64(0x2800)
const vtd_card_rdbah = u64(0x2804)
const vtd_card_rdlen = u64(0x2808)
const vtd_card_rdh = u64(0x2810)
const vtd_card_rdt = u64(0x2818)
const vtd_card_tdbal = u64(0x3800)
const vtd_card_tdbah = u64(0x3804)
const vtd_card_tdlen = u64(0x3808)
const vtd_card_tdh = u64(0x3810)
const vtd_card_tdt = u64(0x3818)

// Receive enabled and every unicast frame taken, so that the card's own
// address need not be touched; broadcasts and multicasts, which are all the
// network sends a card that has not spoken yet, stay out.
const vtd_card_rctl_loop = (u32(1) << 1) | (u32(1) << 3)
const vtd_card_tctl_on = (u32(1) << 1) | (u32(1) << 3)
const vtd_card_mdic_write = u32(1) << 26
const vtd_card_mdic_read = u32(2) << 26
const vtd_card_mdic_ready = u32(1) << 28
const vtd_card_mdic_error = u32(1) << 30
const vtd_card_phy = u32(1) << 21
const vtd_card_phy_loopback = u16(1) << 14

const vtd_card_ids = [u16(0x100e), 0x100f, 0x1004, 0x100c, 0x10d3]!

// Where in the page it is given vtd_test_loop() puts the two rings and the
// frame it sends.
const vtd_loop_tx_ring = u64(0x400)
const vtd_loop_frame = u64(0x800)
const vtd_loop_frame_bytes = u64(64)
const vtd_test_filler = u8(0x5a)

fn vtd_card_read(regs u64, offset u64) u32 {
	return kio.mmin[u32](unsafe { &u32(regs + offset) })
}

fn vtd_card_write(regs u64, offset u64, value u32) {
	kio.mmout[u32](unsafe { &u32(regs + offset) }, value)
}

fn vtd_card_barrier() {
	asm volatile amd64 {
		mfence
		; ; ; memory
	}
}

fn vtd_card_mdic_done(context voidptr) bool {
	return vtd_card_read(u64(context), vtd_card_mdic) & vtd_card_mdic_ready != 0
}

// Read or write a register of the card's PHY. None if the card does not
// answer or says no.
fn vtd_card_phy_access(regs u64, register u32, operation u32, value u16) ?u16 {
	vtd_card_write(regs, vtd_card_mdic, u32(value) | (register << 16) | vtd_card_phy | operation)
	if !devcore.spin_until(vtd_card_mdic_done, voidptr(regs), 100 * devcore.millisecond) {
		return none
	}
	answer := vtd_card_read(regs, vtd_card_mdic)
	if answer & vtd_card_mdic_error != 0 {
		return none
	}
	return u16(answer)
}

fn vtd_card_received(context voidptr) bool {
	return unsafe { *&u8(u64(context) + 12) } & 1 != 0
}

// Have the card send one frame to itself and receive it at bus address
// `target`. The page at `page_virt`, which the card has to be able to reach
// at `page_bus`, holds both rings and the frame. True when the card says it
// has received a frame -- which it says whether or not the unit let it write
// the frame anywhere.
fn vtd_test_loop(regs u64, page_virt u64, page_bus u64, target u64, stamp u8) bool {
	rx := page_virt
	tx := page_virt + vtd_loop_tx_ring
	unsafe {
		C.memset(voidptr(page_virt), 0, 0x1000)
		mut frame := &u8(page_virt + vtd_loop_frame)
		// To and from made-up stations, with an EtherType set aside for
		// experiments, and the rest filled with what tells this frame from
		// the one before.
		frame[0] = 0x02
		frame[1] = 0x56
		frame[2] = 0x54
		frame[3] = 0x44
		frame[5] = 0x01
		frame[6] = 0x02
		frame[7] = 0x56
		frame[8] = 0x54
		frame[9] = 0x44
		frame[11] = 0x02
		frame[12] = 0x88
		frame[13] = 0xb5
		for i := u64(14); i < vtd_loop_frame_bytes; i++ {
			frame[i] = stamp
		}
		*&u64(rx) = target
		*&u64(tx) = page_bus + vtd_loop_frame
	}
	vtd_card_barrier()
	// One receive descriptor is the card's: head 0, tail 1.
	vtd_card_write(regs, vtd_card_rdbal, u32(page_bus))
	vtd_card_write(regs, vtd_card_rdbah, u32(page_bus >> 32))
	vtd_card_write(regs, vtd_card_rdlen, 128)
	vtd_card_write(regs, vtd_card_rdh, 0)
	vtd_card_write(regs, vtd_card_rdt, 1)
	vtd_card_write(regs, vtd_card_tdbal, u32(page_bus + vtd_loop_tx_ring))
	vtd_card_write(regs, vtd_card_tdbah, u32((page_bus + vtd_loop_tx_ring) >> 32))
	vtd_card_write(regs, vtd_card_tdlen, 128)
	// QEMU's card takes nothing in for a second after its receiver is
	// switched on, and a frame looped back meanwhile is lost: it is sent
	// again until one arrives.
	limit := devcore.deadline(3 * devcore.second)
	for {
		unsafe {
			// The length, and "end of packet, add the checksum, report".
			*&u32(tx + 8) = u32(vtd_loop_frame_bytes) | (u32(0x0b) << 24)
			*&u32(tx + 12) = 0
		}
		vtd_card_barrier()
		vtd_card_write(regs, vtd_card_tdh, 0)
		vtd_card_write(regs, vtd_card_tdt, 0)
		vtd_card_write(regs, vtd_card_tdt, 1)
		if devcore.sleep_until(vtd_card_received, voidptr(rx), 100 * devcore.millisecond,
			1) {
			return true
		}
		if limit.expired() {
			return false
		}
	}
	return false
}

fn vtd_test_fill(phys u64) {
	unsafe { C.memset(voidptr(phys + higher_half), vtd_test_filler, 0x1000) }
}

fn vtd_test_untouched(phys u64) bool {
	for i := u64(0); i < 0x1000; i++ {
		if unsafe { *&u8(phys + higher_half + i) } != vtd_test_filler {
			return false
		}
	}
	return true
}

// How many faults the unit has recorded, up to this instant.
fn vtd_test_faults(mut unit VtdUnit) u64 {
	vtd_drain_faults(mut unit, true)
	return unit.faults
}

// The card receives into `target`, which it is allowed to reach: the frame
// must be there, and no fault.
fn vtd_test_reaches(mut unit VtdUnit, regs u64, page_virt u64, page_bus u64, target u64, stamp u8) bool {
	vtd_test_fill(target)
	before := vtd_test_faults(mut unit)
	arrived := vtd_test_loop(regs, page_virt, page_bus, target, stamp)
	after := vtd_test_faults(mut unit)
	return arrived && after == before && unsafe {
		C.memcmp(voidptr(target + higher_half), voidptr(page_virt + vtd_loop_frame), vtd_loop_frame_bytes) == 0
	}
}

// The card receives into `target`, which it is not allowed to reach: the
// unit must have recorded a write by this card to that page, and the page
// must be as it was.
fn vtd_test_blocked(mut unit VtdUnit, regs u64, page_virt u64, page_bus u64, target u64, sid u32, stamp u8) bool {
	vtd_test_fill(target)
	before := vtd_test_faults(mut unit)
	arrived := vtd_test_loop(regs, page_virt, page_bus, target, stamp)
	after := vtd_test_faults(mut unit)
	last := unit.last_fault
	return arrived && after > before && last.sid == sid && !last.read && last.address == target
		&& vtd_test_untouched(target)
}

fn vtd_card_stop(regs u64) {
	vtd_card_write(regs, vtd_card_imc, 0xffffffff)
	vtd_card_write(regs, vtd_card_rctl, 0)
	vtd_card_write(regs, vtd_card_tctl, 0)
	vtd_card_write(regs, vtd_card_rdh, 0)
	vtd_card_write(regs, vtd_card_rdt, 0)
	vtd_card_write(regs, vtd_card_tdh, 0)
	vtd_card_write(regs, vtd_card_tdt, 0)
	_ := vtd_card_read(regs, vtd_card_icr)
}

fn vtd_selftest_card() {
	mut dev := &devcore.Device(unsafe { nil })
	for i := 0; i < devcore.device_count() && dev == unsafe { nil }; i++ {
		candidate := devcore.device_at(i)
		if candidate == unsafe { nil } || candidate.bus != .pci || candidate.vendor != 0x8086
			|| candidate.state != .unbound {
			continue
		}
		for id in vtd_card_ids {
			if candidate.device == id {
				dev = candidate
			}
		}
	}
	if dev == unsafe { nil } {
		vtd_test_skipped = 'no Intel 8254x network card without a driver'
		return
	}
	mut unit := &VtdUnit(unsafe { nil })
	for i := u32(0); i < vtd_unit_count; i++ {
		if vtd_units[i].enabled && vtd_drhd_covers(vtd_firmware, vtd_units[i].drhd, dev) {
			unit = vtd_units[i]
		}
	}
	if unit == unsafe { nil } {
		vtd_test_skipped = 'no VT-d unit that is on in front of the network card'
		return
	}
	sid := vtd_sid(dev)

	// The card's registers, as its driver finds them: sized with decoding
	// off, then memory decoding and bus mastering on and the legacy
	// interrupt off.
	command := dev.pci.read[u16](0x4)
	dev.pci.write[u16](0x4, command & ~u16(0x7))
	bar := dev.pci.get_bar(0)
	dev.pci.write[u16](0x4, (command & ~u16(1)) | 0x6 | (u16(1) << 10))
	regs := if bar.is_mmio && bar.base != 0 { vtd_map_registers(bar.base, 0x20000) } else { u64(0) }
	outside := u64(memory.pmm_alloc_fallible(1))
	reserved := u64(memory.pmm_alloc_fallible(2))
	if regs == 0 || outside == 0 || reserved == 0 {
		vtd_test_skipped = 'the network card has no registers to map, or there is no memory'
		dev.pci.write[u16](0x4, command)
		return
	}
	tables_start := unit.table_pages
	domains_start := unit.domain_count

	vtd_card_stop(regs)
	phy_control := vtd_card_phy_access(regs, 0, vtd_card_mdic_read, 0) or { u16(0) }
	mut looping := true
	vtd_card_phy_access(regs, 0, vtd_card_mdic_write, phy_control | vtd_card_phy_loopback) or {
		looping = false
		u16(0)
	}
	vtd_card_write(regs, vtd_card_rctl, vtd_card_rctl_loop)
	vtd_card_write(regs, vtd_card_tctl, vtd_card_tctl_on)

	// A driver's domain: one page for the rings, one to receive into.
	ring := alloc_buffer(mut dev, 0x1000) or { Buffer{} }
	inside := alloc_buffer(mut dev, 0x1000) or { Buffer{} }
	attached := ring.bus != 0 && inside.bus != 0
	mut ready := attached && looping
	if !attached {
		// A card behind a conventional PCI bridge, for one.
		vtd_test_skipped = 'the unit gives the network card no domain'
	} else if !looping {
		vtd_test_skipped = 'the network card has no PHY to put in loopback'
	} else {
		before := vtd_test_faults(mut unit)
		ready = vtd_test_reaches(mut unit, regs, ring.virt, ring.bus, inside.bus, 0xa1)
		if !ready && vtd_test_faults(mut unit) == before {
			// No frame and no fault: this card does not loop frames back
			// the way QEMU's does, and nothing can be learnt from it.
			vtd_test_skipped = 'the network card does not loop frames back'
		} else {
			vtd_check('isolation: a frame is received into a page of the domain', ready)
		}
	}

	if ready {
		vtd_check('isolation: a write outside the domain faults and changes nothing', vtd_test_blocked(mut
			unit, regs, ring.virt, ring.bus, outside, sid, 0xb2))
		mut mapped := true
		map_memory(mut dev, outside, 0x1000) or {
			mapped = false
			u64(0)
		}
		vtd_check('isolation: the same page is reached once it is mapped', mapped
			&& vtd_test_reaches(mut unit, regs, ring.virt, ring.bus, outside, 0xc3))
		unmap_memory(mut dev, outside)
		vtd_check('isolation: and faults again once it is unmapped', vtd_test_blocked(mut
			unit, regs, ring.virt, ring.bus, outside, sid, 0xd4))

		// The other direction: a transmit ring where the card may not read.
		before := vtd_test_faults(mut unit)
		vtd_card_write(regs, vtd_card_tdbal, u32(outside))
		vtd_card_write(regs, vtd_card_tdbah, u32(outside >> 32))
		vtd_card_write(regs, vtd_card_tdh, 0)
		vtd_card_write(regs, vtd_card_tdt, 0)
		vtd_card_write(regs, vtd_card_tdt, 1)
		after := vtd_test_faults(mut unit)
		vtd_check('isolation: a read outside the domain faults', after > before
			&& unit.last_fault.sid == sid && unit.last_fault.read
			&& unit.last_fault.address == outside)
	}
	free_buffer(mut dev, ring)
	free_buffer(mut dev, inside)
	release(mut dev)
	if attached {
		vtd_check('domains: detach frees every page of the page table', unit.table_pages == tables_start
			&& unit.domain_count == domains_start)
	}

	if ready {
		// A domain holding all of RAM: the page nobody mapped is reachable,
		// and large pages keep the table small.
		whole := alloc_buffer(mut dev, 0x1000) or { Buffer{} }
		all := whole.bus != 0 && allow_all(mut dev)
		vtd_check('identity: a domain holding all of RAM reaches any page', all
			&& vtd_test_reaches(mut unit, regs, whole.virt, whole.bus, outside, 0xe5))
		vtd_test_identity_tables = unit.table_pages - tables_start
		release(mut dev)
		vtd_check('identity: and is freed whole', unit.table_pages == tables_start)

		vtd_selftest_reserved(mut unit, mut dev, regs, reserved, outside, sid)
	}

	// The card as it was found.
	vtd_card_stop(regs)
	if looping {
		vtd_card_phy_access(regs, 0, vtd_card_mdic_write, phy_control) or {}
	}
	dev.pci.write[u16](0x4, command)

	if attached {
		// Fifty drivers come and go, half of them without cleaning up.
		vtd_test_free_before = memory.free_bytes()
		mut rounds := 0
		for round := 0; round < 50; round++ {
			buffer := alloc_buffer(mut dev, 16 * 0x1000) or { break }
			map_memory(mut dev, outside, 0x1000) or { break }
			rounds++
			if unit.table_pages > vtd_test_round_tables {
				vtd_test_round_tables = unit.table_pages
			}
			if round % 2 == 0 {
				unmap_memory(mut dev, outside)
				free_buffer(mut dev, buffer)
			}
			release(mut dev)
		}
		// A round that stopped half way still has its domain.
		release(mut dev)
		vtd_test_free_after = memory.free_bytes()
		vtd_check('domains: fifty attach and detach rounds leave no page of page table',
			rounds == 50 && vtd_test_round_tables > tables_start && unit.table_pages == tables_start
			&& unit.domain_count == domains_start)
		// Other threads allocate while this runs; sixteen pages is their
		// noise, and far less than fifty leaked tables would be.
		vtd_check('domains: nor any other memory', vtd_test_free_after + 16 * 0x1000 >= vtd_test_free_before)
	}

	memory.pmm_free(voidptr(outside), 1)
	memory.pmm_free(voidptr(reserved), 2)
}

// A reserved range made up for the card: two pages, the first for the rings
// and the frame, the second to receive into. What firmware would have said
// in an RMRR is added to the table by hand, and taken out again.
fn vtd_selftest_reserved(mut unit VtdUnit, mut dev devcore.Device, regs u64, reserved u64, outside u64, sid u32) {
	mut firmware := vtd_firmware
	if firmware.rmrr_count >= vtd_max_rmrrs || firmware.scope_count >= vtd_max_scopes {
		return
	}
	tables_start := unit.table_pages
	domains_start := unit.domain_count
	mut scope := unsafe { &firmware.scopes[firmware.scope_count] }
	scope.kind = vtd_scope_endpoint
	scope.start_bus = dev.pci.bus
	scope.depth = 1
	scope.path[0] = dev.pci.slot
	scope.path[1] = dev.pci.function
	scope.resolved = true
	scope.bus = dev.pci.bus
	scope.devfn = u8(sid)
	mut rmrr := unsafe { &firmware.rmrrs[firmware.rmrr_count] }
	rmrr.segment = 0
	rmrr.base = reserved
	rmrr.limit = reserved + 0x2000
	rmrr.scope_first = firmware.scope_count
	rmrr.scope_count = 1
	firmware.scope_count++
	firmware.rmrr_count++

	page := reserved + higher_half
	second := reserved + 0x1000
	// What vtd_unit_start() does for every such device before translation
	// goes on.
	vtd_firmware_domain(mut unit, dev)
	vtd_check('reserved: a device firmware uses gets a domain before any driver', unit.domain_count == domains_start + 1)
	vtd_check('reserved: without a driver it reaches its reserved range', vtd_test_reaches(mut
		unit, regs, page, reserved, second, 0x11))
	vtd_check('reserved: and nothing else', vtd_test_blocked(mut unit, regs, page, reserved,
		outside, sid, 0x22))

	own := alloc_buffer(mut dev, 0x1000) or { Buffer{} }
	vtd_check('reserved: a driver attaching keeps the range and adds its own', own.bus != 0
		&& vtd_test_reaches(mut unit, regs, page, reserved, second, 0x33)
		&& vtd_test_reaches(mut unit, regs, page, reserved, own.bus, 0x44))
	// A driver that maps and unmaps a page of the range does not take it
	// away from firmware.
	map_memory(mut dev, second, 0x1000) or {}
	unmap_memory(mut dev, second)
	vtd_check('reserved: unmapping a page of the range leaves it mapped', vtd_test_reaches(mut
		unit, regs, page, reserved, second, 0x55))
	release(mut dev)
	vtd_check('reserved: the driver gone, the device is back to its range alone', unit.domain_count == domains_start + 1
		&& vtd_test_reaches(mut unit, regs, page, reserved, second, 0x66)
		&& vtd_test_blocked(mut unit, regs, page, reserved, outside, sid, 0x77))

	// Out again: the firmware domain, then what was added to the table.
	unit.lock.acquire()
	mut current := unit.domains
	for current != unsafe { nil } && current.sid != sid {
		current = current.next
	}
	unit.lock.release()
	if current != unsafe { nil } {
		ok, _ := vtd_domain_swap(mut unit, sid, unsafe { nil }, current)
		if ok {
			vtd_domain_free(mut unit, mut current)
		}
	}
	firmware.rmrr_count--
	firmware.scope_count--
	vtd_check('reserved: nothing of it is left afterwards', unit.table_pages == tables_start
		&& unit.domain_count == domains_start)
}

// ── The verdict ─────────────────────────────────────────────────────────────

fn vtd_selftest_run() {
	vtd_selftest_tables()
	if vtd_unit_count == 0 {
		vtd_test_skipped = 'no VT-d unit'
	} else {
		vtd_selftest_card()
	}
	vtd_test_done = true
	if vtd_test_failures != 0 {
		C.kprintf(c'vtd selftest: FAIL (%llu of %llu checks failed)\n', u64(vtd_test_failures),
			u64(vtd_test_count))
	} else if vtd_test_skipped.len != 0 {
		C.kprintf(c'vtd selftest: SKIPPED (%.*s); %llu checks passed\n', i32(vtd_test_skipped.len),
			vtd_test_skipped.str, u64(vtd_test_count))
	} else {
		C.kprintf(c'vtd selftest: PASS (%llu checks)\n', u64(vtd_test_count))
	}
}

fn vtd_selftest_show(_ voidptr, mut text lib.Text) {
	text.add('result: ')
	text.add(if !vtd_test_done {
		'RUNNING'
	} else if vtd_test_failures != 0 {
		'FAIL'
	} else if vtd_test_skipped.len != 0 {
		'SKIPPED'
	} else {
		'PASS'
	})
	text.add('\nchecks: ')
	text.add_unsigned(u64(vtd_test_count))
	text.add('\nfailed: ')
	text.add_unsigned(u64(vtd_test_failures))
	text.add_byte(`\n`)
	if vtd_test_skipped.len != 0 {
		text.add('skipped: ')
		text.add(vtd_test_skipped)
		text.add_byte(`\n`)
	}
	if vtd_test_identity_tables != 0 {
		text.add('note: all of RAM was mapped with ')
		text.add_unsigned(vtd_test_identity_tables)
		text.add(' pages of page table\n')
	}
	if vtd_test_free_before != 0 {
		text.add('note: fifty rounds held at most ')
		text.add_unsigned(vtd_test_round_tables)
		text.add(' pages of page table; free memory ')
		text.add_unsigned(vtd_test_free_before / 1024)
		text.add(' -> ')
		text.add_unsigned(vtd_test_free_after / 1024)
		text.add(' kB\n')
	}
	for i := u32(0); i < vtd_test_count; i++ {
		text.add(if vtd_test_lines[i].ok { 'pass  ' } else { 'FAIL  ' })
		text.add(vtd_test_lines[i].name)
		text.add_byte(`\n`)
	}
}

fn vtd_selftest_publish(unit &VtdUnit) {
	vtd_publish_file(unit, 'selftest', vtd_selftest_show)
}
