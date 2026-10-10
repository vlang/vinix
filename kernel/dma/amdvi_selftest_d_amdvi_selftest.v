// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The AMD-Vi self-test. Compiled only with `-d amdvi_selftest`, for x86-64;
// it runs once, at the end of amdvi_initialise(), before any driver has the
// network card, and its verdict is at /sys/class/iommu/ivhdN/selftest.
//
// It proves three things that booting with a working network does not.
//
// That the IVRS parser reads what a table says and no further: it is handed
// tables made here, with every kind of entry and several kinds of damage.
//
// That a domain costs nothing once it is gone: fifty attaches and detaches
// leave the unit's page-table pages and the machine's free memory unchanged.
//
// And that translation isolates. A real device is made to write to memory by
// itself: an Intel 8254x network card (QEMU's e1000) is put in loopback, so
// that every frame it is told to send it receives again, into the buffer the
// receive descriptor names. The descriptor rings are always memory the card
// has been given, so the card reports each frame as received; whether the
// frame's bytes reached the buffer is up to the unit. With the buffer outside
// the card's domain the page must be found as it was left and the unit must
// have logged an I/O page fault naming the card and the page; with the same
// page mapped, the bytes must be there. That is repeated across map() and
// unmap(), across map_all() and one page taken back out of it, across
// detach(), and for memory the IVRS table keeps for a device -- which QEMU's
// own table never does, so a range is put in the list for the test.
//
// The card is driven straight through its registers. The e1000 driver cannot
// be asked: it imports this module.
@[has_globals]
module dma

import devcore
import lib
import memory
import x86.kio

// The e1000 registers the test uses, as offsets into BAR 0.
const amdvi_nic_ctrl = u64(0x0000)
const amdvi_nic_mdic = u64(0x0020)
const amdvi_nic_icr = u64(0x00c0)
const amdvi_nic_imc = u64(0x00d8)
const amdvi_nic_rctl = u64(0x0100)
const amdvi_nic_tctl = u64(0x0400)
const amdvi_nic_tipg = u64(0x0410)
const amdvi_nic_rdbal = u64(0x2800)
const amdvi_nic_rdbah = u64(0x2804)
const amdvi_nic_rdlen = u64(0x2808)
const amdvi_nic_rdh = u64(0x2810)
const amdvi_nic_rdt = u64(0x2818)
const amdvi_nic_tdbal = u64(0x3800)
const amdvi_nic_tdbah = u64(0x3804)
const amdvi_nic_tdlen = u64(0x3808)
const amdvi_nic_tdh = u64(0x3810)
const amdvi_nic_tdt = u64(0x3818)

// Sixteen descriptors a ring, both rings in one page: receive at its start,
// transmit half way up.
const amdvi_nic_ring = u32(16)
const amdvi_nic_tx_offset = u64(2048)
const amdvi_nic_frame_bytes = u64(64)
// The PHY's control register, and the bit that turns frames round.
const amdvi_nic_phy_control = u32(0)
const amdvi_nic_phy_loopback = u16(0x4000)
// How long a frame may take to come back. QEMU does it before the register
// write that sent it returns.
const amdvi_nic_wait_ns = 100 * devcore.millisecond
// QEMU's e1000 takes no frames for a second after its receive control
// register is written; the first frame is sent again until one arrives.
const amdvi_nic_warmup_tries = 40

const amdvi_test_pattern = u8(0x5a)
const amdvi_test_checks = 24

struct AmdviNic {
mut:
	dev   &devcore.Device = unsafe { nil }
	// The id the card's DMA arrives under.
	devid u16
	regs  u64
	// The PCI command register and PHY control register as found.
	command u16
	phy     u16
	// The page with the rings and the page with the frame to send.
	ring_virt  u64
	ring_bus   u64
	frame_virt u64
	frame_bus  u64
	tx_next    u32
	rx_next    u32
	sequence   u8
}

// What one frame sent round did.
struct AmdviProbe {
mut:
	// The card finished sending, and reported a frame received.
	sent      bool
	delivered bool
	// The frame's bytes are in the target page; the page is as it was left.
	arrived bool
	intact  bool
	// I/O page faults the unit logged meanwhile, and whether the last names
	// this card, and this page.
	faults     u64
	fault_card bool
	fault_here bool
	fault      AmdviEvent
}

struct AmdviCheck {
mut:
	name   string
	passed bool
	// Whether a frame was sent for it, and what happened to it.
	probed bool
	probe  AmdviProbe
	// For checks that count instead.
	counted bool
	before  u64
	after   u64
}

__global (
	amdvi_selftest_checks [amdvi_test_checks]AmdviCheck
	amdvi_selftest_count  int
	amdvi_selftest_done   bool
	amdvi_selftest_passed bool
	// Why the hardware part did not run, when it did not.
	amdvi_selftest_note string
)

fn amdvi_check(name string, passed bool) &AmdviCheck {
	if amdvi_selftest_count >= amdvi_test_checks {
		return unsafe { &amdvi_selftest_checks[amdvi_test_checks - 1] }
	}
	mut check := unsafe { &amdvi_selftest_checks[amdvi_selftest_count] }
	amdvi_selftest_count++
	check.name = name
	check.passed = passed
	check.probed = false
	check.counted = false
	C.kprintf(c'amdvi: self-test: %.*s: %s\n', i32(name.len), name.str, if passed {
		c'pass'
	} else {
		c'FAIL'
	})
	return check
}

fn amdvi_check_probe(name string, passed bool, probe AmdviProbe) {
	mut check := amdvi_check(name, passed)
	check.probed = true
	check.probe = probe
}

fn amdvi_check_count(name string, passed bool, before u64, after u64) {
	mut check := amdvi_check(name, passed)
	check.counted = true
	check.before = before
	check.after = after
}

// ── The parser, on tables made here ─────────────────────────────────────────

struct AmdviTestTable {
mut:
	bytes &u8 = unsafe { nil }
	len   u32
}

fn amdvi_put(mut table AmdviTestTable, value u64, width u32) {
	for i := u32(0); i < width; i++ {
		unsafe {
			table.bytes[table.len] = u8(value >> (8 * i))
		}
		table.len++
	}
}

// A four-byte device entry, and an eight-byte one.
fn amdvi_put_entry(mut table AmdviTestTable, kind u8, devid u16, settings u8) {
	amdvi_put(mut table, u64(kind), 1)
	amdvi_put(mut table, u64(devid), 2)
	amdvi_put(mut table, u64(settings), 1)
}

fn amdvi_put_entry8(mut table AmdviTestTable, kind u8, devid u16, settings u8, extra u32) {
	amdvi_put_entry(mut table, kind, devid, settings)
	amdvi_put(mut table, u64(extra), 4)
}

// Start an IVHD block; returns where it starts, for amdvi_close_block().
fn amdvi_open_ivhd(mut table AmdviTestTable, kind u8, devid u16, segment u16) u32 {
	start := table.len
	amdvi_put(mut table, u64(kind), 1)
	amdvi_put(mut table, 0x0e, 1)
	amdvi_put(mut table, 0, 2)
	amdvi_put(mut table, u64(devid), 2)
	amdvi_put(mut table, 0x40, 2)
	amdvi_put(mut table, 0xfeb80000, 8)
	amdvi_put(mut table, u64(segment), 2)
	amdvi_put(mut table, 0, 2)
	amdvi_put(mut table, 0, 4)
	if kind != amdvi_ivhd_10 {
		amdvi_put(mut table, 0x1234, 8)
		amdvi_put(mut table, 0, 8)
	}
	return start
}

fn amdvi_close_block(mut table AmdviTestTable, start u32) {
	bytes := table.len - start
	unsafe {
		table.bytes[start + 2] = u8(bytes)
		table.bytes[start + 3] = u8(bytes >> 8)
	}
}

fn amdvi_put_ivmd(mut table AmdviTestTable, kind u8, flags u8, devid u16, aux u16, segment u16, start u64, span u64) {
	amdvi_put(mut table, u64(kind), 1)
	amdvi_put(mut table, u64(flags), 1)
	amdvi_put(mut table, 32, 2)
	amdvi_put(mut table, u64(devid), 2)
	amdvi_put(mut table, u64(aux), 2)
	amdvi_put(mut table, u64(segment), 2)
	amdvi_put(mut table, 0, 6)
	amdvi_put(mut table, start, 8)
	amdvi_put(mut table, span, 8)
}

// Fill in the table's length and make its bytes add up to zero.
fn amdvi_seal(mut table AmdviTestTable) {
	unsafe {
		table.bytes[4] = u8(table.len)
		table.bytes[5] = u8(table.len >> 8)
		table.bytes[6] = 0
		table.bytes[7] = 0
		table.bytes[9] = 0
	}
	mut sum := u8(0)
	for i := u32(0); i < table.len; i++ {
		sum += unsafe { table.bytes[i] }
	}
	unsafe {
		table.bytes[9] = u8(0) - sum
	}
}

fn amdvi_selftest_parser() {
	page := u64(memory.pmm_alloc_fallible(1))
	if page == 0 {
		amdvi_check('IVRS parser', false)
		return
	}
	mut table := AmdviTestTable{
		bytes: unsafe { &u8(page + higher_half) }
	}
	// The ACPI header, then the IVRS's own twelve bytes.
	amdvi_put(mut table, 0x53525649, 4)
	amdvi_put(mut table, 0, 4)
	amdvi_put(mut table, 1, 1)
	amdvi_put(mut table, 0, 1)
	amdvi_put(mut table, 0, 26)
	amdvi_put(mut table, 0x00203041, 4)
	amdvi_put(mut table, 0, 8)

	// A unit described twice. The older description has one of everything.
	mut start := amdvi_open_ivhd(mut table, amdvi_ivhd_10, 0x0010, 0)
	amdvi_put_entry(mut table, amdvi_dev_select, 0x0008, 0)
	amdvi_put_entry(mut table, amdvi_dev_range_start, 0x0100, 0x01)
	amdvi_put_entry(mut table, amdvi_dev_range_end, 0x01ff, 0)
	amdvi_put_entry8(mut table, amdvi_dev_alias, 0x0210, 0, 0x0018 << 8)
	amdvi_put_entry8(mut table, amdvi_dev_alias_range, 0x0300, 0, 0x0020 << 8)
	amdvi_put_entry(mut table, amdvi_dev_range_end, 0x03ff, 0)
	amdvi_put_entry8(mut table, amdvi_dev_ext_select, 0x0408, 0, 0x80000000)
	amdvi_put_entry8(mut table, amdvi_dev_special, 0, 0xd7, (u32(amdvi_special_ioapic) << 24) | (0x00a0 << 8) | 0x21)
	// A device named by ACPI id, with a three-byte unique id after it.
	amdvi_put_entry(mut table, amdvi_dev_acpi_hid, 0x0500, 0)
	amdvi_put(mut table, 0x30343030494d4441, 8)
	amdvi_put(mut table, 0, 8)
	amdvi_put(mut table, 2, 1)
	amdvi_put(mut table, 3, 1)
	amdvi_put(mut table, 0x414243, 3)
	amdvi_put_entry(mut table, amdvi_dev_select, 0x0409, 0)
	amdvi_close_block(mut table, start)
	old_block := start

	start = amdvi_open_ivhd(mut table, amdvi_ivhd_11, 0x0010, 0)
	amdvi_put_entry(mut table, amdvi_dev_select, 0x0008, 0)
	amdvi_put_entry(mut table, amdvi_dev_all, 0, 0x40)
	amdvi_close_block(mut table, start)

	// A unit on another PCI segment, and one whose last entry runs past the
	// end of its block.
	start = amdvi_open_ivhd(mut table, amdvi_ivhd_10, 0x0110, 1)
	amdvi_put_entry(mut table, amdvi_dev_select, 0x0008, 0)
	amdvi_close_block(mut table, start)
	start = amdvi_open_ivhd(mut table, amdvi_ivhd_10, 0x0210, 0)
	amdvi_put_entry(mut table, amdvi_dev_select, 0x0030, 0)
	amdvi_put_entry(mut table, amdvi_dev_alias, 0x0031, 0)
	amdvi_put(mut table, 0, 2)
	amdvi_close_block(mut table, start)
	cut_block := start

	amdvi_put_ivmd(mut table, amdvi_ivmd_one, 0x07, 0x0210, 0, 0, 0x7f001234, 0x2000)
	amdvi_put_ivmd(mut table, amdvi_ivmd_range, 0x03, 0x0100, 0x01ff, 0, 0x7e000000, 0x1000)
	amdvi_put_ivmd(mut table, amdvi_ivmd_all, 0x08, 0, 0, 0, 0x7d000000, 0x1000)
	amdvi_put_ivmd(mut table, amdvi_ivmd_one, 0x07, 0x0008, 0, 1, 0x7c000000, 0x1000)
	// Too short to be a memory block, and a type that means nothing.
	amdvi_put(mut table, 0x00100721, 4)
	amdvi_put(mut table, 0, 12)
	amdvi_put(mut table, 0x00080099, 4)
	amdvi_put(mut table, 0, 4)
	amdvi_seal(mut table)

	// Made once per boot of a test kernel, and freed below.
	mut parsed := &AmdviIvrs{}
	mut good := amdvi_parse_ivrs(table.bytes, table.len, mut parsed)
	good = good && parsed.block_count == 3 && parsed.foreign_segments == 2
		&& parsed.malformed == 1 && parsed.unknown_blocks == 1 && parsed.unity.len == 3
		&& parsed.ivinfo == 0x00203041
	// Of the unit described twice, the newer description is the one to use.
	good = good && !parsed.blocks[0].chosen && parsed.blocks[1].chosen
		&& parsed.blocks[1].kind == amdvi_ivhd_11 && parsed.blocks[1].efr == 0x1234
		&& parsed.blocks[2].chosen && parsed.blocks[0].mmio_phys == 0xfeb80000
		&& parsed.blocks[0].devid == 0x0010 && parsed.blocks[0].cap_offset == 0x40
	if good {
		good = amdvi_selftest_entries(table.bytes, parsed, old_block == parsed.blocks[0].entries_at - 24,
			cut_block == parsed.blocks[2].entries_at - 24)
	}

	// Damage: a byte changed, a table shorter than its own header, and a
	// block that claims no length at all, which ends the walk where it is.
	unsafe {
		table.bytes[60] ^= 0x01
	}
	mut bad := &AmdviIvrs{}
	good = good && !amdvi_parse_ivrs(table.bytes, table.len, mut bad)
	unsafe {
		table.bytes[60] ^= 0x01
	}
	good = good && !amdvi_parse_ivrs(table.bytes, 40, mut bad)
	unsafe {
		table.bytes[old_block + 2] = 0
		table.bytes[old_block + 3] = 0
	}
	amdvi_seal(mut table)
	good = good && amdvi_parse_ivrs(table.bytes, table.len, mut bad) && bad.block_count == 0
		&& bad.malformed == 1 && bad.unity.len == 0
	amdvi_check('IVRS parser', good)
	unsafe {
		parsed.unity.free()
		bad.unity.free()
		free(parsed)
		free(bad)
	}
	memory.pmm_free(voidptr(page), 1)
}

// The device entries of the test table's first and third blocks, and what
// they and the memory blocks say of particular devices.
fn amdvi_selftest_entries(bytes &u8, parsed &AmdviIvrs, first_found bool, third_found bool) bool {
	if !first_found || !third_found {
		return false
	}
	mut none_yet := []AmdviEntry{}
	count := amdvi_block_entries(bytes, unsafe { &parsed.blocks[0] }, mut none_yet, false)
	mut entries := []AmdviEntry{cap: count}
	amdvi_block_entries(bytes, unsafe { &parsed.blocks[0] }, mut entries, true)
	defer {
		unsafe { entries.free() }
	}
	// Select, range, alias and its target, alias range and its target,
	// extended select, the I/O APIC, and the select after the ACPI device.
	mut good := count == 9 && entries.len == 9 && amdvi_last_devid(entries) == 0x0409
	good = good && amdvi_subject(entries, 0x0008).covered && !amdvi_subject(entries, 0x0009).covered
	ranged := amdvi_subject(entries, 0x0150)
	good = good && ranged.covered && ranged.alias == 0x0150 && ranged.settings == 0x01
	good = good && amdvi_subject(entries, 0x0210).alias == 0x0018 && amdvi_subject(entries,
		0x0018).covered
	good = good && amdvi_subject(entries, 0x0350).alias == 0x0020 && amdvi_subject(entries,
		0x0020).covered && !amdvi_subject(entries, 0x0400).covered
	good = good && amdvi_subject(entries, 0x0408).covered && amdvi_subject(entries, 0x0409).covered
	// The I/O APIC's id has its settings, and no PCI function is behind the
	// unit on its account; the ACPI-named device has no id at all.
	apic := amdvi_subject(entries, 0x00a0)
	good = good && !apic.covered && apic.settings == 0xd7 && !amdvi_subject(entries, 0x0500).covered

	// The block cut short keeps the entry that fitted.
	good = good && amdvi_block_entries(bytes, unsafe { &parsed.blocks[2] }, mut none_yet, false) == 1

	// Memory: rounded out to whole pages, with the rights asked for.
	one := parsed.unity[0]
	good = good && one.first == 0x0210 && one.last == 0x0210 && one.start == 0x7f001000
		&& one.end == 0x7f004000 && one.read && one.write
	some := parsed.unity[1]
	good = good && some.first == 0x0100 && some.last == 0x01ff && some.read && !some.write
	every := parsed.unity[2]
	good = good && every.first == 0 && every.last == 0xffff && every.read && every.write
	// A range for a device is also the business of the id the device sends
	// as: the tables are that id's.
	mut unit := &AmdviUnit{}
	unit.entries = entries
	good = good && amdvi_unity_names(unit, unsafe { &parsed.unity[0] }, 0x0018, 0x0018)
		&& amdvi_unity_names(unit, unsafe { &parsed.unity[0] }, 0x0210, 0x0018)
		&& !amdvi_unity_names(unit, unsafe { &parsed.unity[0] }, 0x0008, 0x0008)
		&& amdvi_unity_names(unit, unsafe { &parsed.unity[1] }, 0x0150, 0x0150)
	unsafe { free(unit) }
	return good
}

// ── The network card, by hand ───────────────────────────────────────────────

fn amdvi_nic_read(nic &AmdviNic, offset u64) u32 {
	return kio.mmin[u32](unsafe { &u32(nic.regs + offset) })
}

fn amdvi_nic_write(nic &AmdviNic, offset u64, value u32) {
	kio.mmout[u32](unsafe { &u32(nic.regs + offset) }, value)
}

fn amdvi_nic_phy_ready(context voidptr) bool {
	nic := unsafe { &AmdviNic(context) }
	return amdvi_nic_read(nic, amdvi_nic_mdic) & (u32(1) << 28) != 0
}

// Read or write a register of the card's PHY, which is PHY 1.
fn amdvi_nic_phy(nic &AmdviNic, register u32, write bool, value u16) ?u16 {
	operation := if write { u32(1) << 26 } else { u32(2) << 26 }
	amdvi_nic_write(nic, amdvi_nic_mdic, u32(value) | (register << 16) | (u32(1) << 21) | operation)
	if !devcore.spin_until(amdvi_nic_phy_ready, voidptr(nic), amdvi_nic_wait_ns) {
		return none
	}
	answer := amdvi_nic_read(nic, amdvi_nic_mdic)
	if answer & (u32(1) << 30) != 0 {
		return none
	}
	return u16(answer)
}

// The first network card of the kind QEMU's `-nic model=e1000` is, or nil.
fn amdvi_nic_find() &devcore.Device {
	for i := 0; i < devcore.device_count(); i++ {
		dev := devcore.device_at(i)
		if dev != unsafe { nil } && dev.bus == .pci && dev.pci != unsafe { nil }
			&& dev.vendor == 0x8086 && (dev.device == 0x100e || dev.device == 0x100f
			|| dev.device == 0x1004 || dev.device == 0x100c) && dev.state == .unbound {
			return dev
		}
	}
	return unsafe { nil }
}

// Map the card's registers and let it use the bus.
fn amdvi_nic_open(mut nic AmdviNic) bool {
	mut card := nic.dev.pci
	nic.command = card.read[u16](0x4)
	card.write[u16](0x4, nic.command & ~u16(0x7))
	bar := card.get_bar(0)
	card.write[u16](0x4, (nic.command & ~u16(1)) | 0x6 | (u16(1) << 10))
	if !bar.is_mmio || bar.base == 0 {
		card.write[u16](0x4, nic.command)
		return false
	}
	nic.regs = amdvi_map_registers(bar.base & ~(amdvi_page_bytes - 1), 0x20000)
	if nic.regs == 0 {
		card.write[u16](0x4, nic.command)
		return false
	}
	amdvi_nic_write(nic, amdvi_nic_imc, 0xffffffff)
	amdvi_nic_write(nic, amdvi_nic_rctl, 0)
	amdvi_nic_write(nic, amdvi_nic_tctl, 0)
	nic.phy = amdvi_nic_phy(nic, amdvi_nic_phy_control, false, 0) or {
		card.write[u16](0x4, nic.command)
		return false
	}
	return true
}

// Point the card at rings in the page at `ring` and start it, in loopback.
fn amdvi_nic_start(mut nic AmdviNic, ring_virt u64, ring_bus u64, frame_virt u64, frame_bus u64) bool {
	amdvi_nic_stop(nic)
	nic.ring_virt = ring_virt
	nic.ring_bus = ring_bus
	nic.frame_virt = frame_virt
	nic.frame_bus = frame_bus
	nic.tx_next = 0
	nic.rx_next = 0
	unsafe {
		C.memset(voidptr(ring_virt), 0, amdvi_page_bytes)
	}
	// Link up, and frames turned round in the PHY.
	amdvi_nic_write(nic, amdvi_nic_ctrl, (amdvi_nic_read(nic, amdvi_nic_ctrl) | (u32(1) << 6) | (u32(1) << 5)) & ~((u32(1) << 3) | (u32(1) << 7) | (u32(1) << 30) | (u32(1) << 31)))
	amdvi_nic_phy(nic, amdvi_nic_phy_control, true, nic.phy | amdvi_nic_phy_loopback) or {
		return false
	}
	bytes := amdvi_nic_ring * 16
	amdvi_nic_write(nic, amdvi_nic_rdbal, u32(ring_bus))
	amdvi_nic_write(nic, amdvi_nic_rdbah, u32(ring_bus >> 32))
	amdvi_nic_write(nic, amdvi_nic_rdlen, bytes)
	amdvi_nic_write(nic, amdvi_nic_rdh, 0)
	amdvi_nic_write(nic, amdvi_nic_rdt, amdvi_nic_ring - 1)
	amdvi_nic_write(nic, amdvi_nic_tdbal, u32(ring_bus + amdvi_nic_tx_offset))
	amdvi_nic_write(nic, amdvi_nic_tdbah, u32((ring_bus + amdvi_nic_tx_offset) >> 32))
	amdvi_nic_write(nic, amdvi_nic_tdlen, bytes)
	amdvi_nic_write(nic, amdvi_nic_tdh, 0)
	amdvi_nic_write(nic, amdvi_nic_tdt, 0)
	amdvi_nic_write(nic, amdvi_nic_tipg, u32(10) | (u32(8) << 10) | (u32(6) << 20))
	// Transmit on, short frames padded; receive on, taking every frame,
	// with 2048-byte buffers and the checksum stripped.
	amdvi_nic_write(nic, amdvi_nic_tctl, (u32(1) << 1) | (u32(1) << 3) | (u32(0x0f) << 4) | (u32(0x40) << 12))
	amdvi_nic_write(nic, amdvi_nic_rctl, (u32(1) << 1) | (u32(1) << 3) | (u32(1) << 4) | (u32(1) << 15) | (u32(1) << 26))
	return true
}

// Stop the card touching memory.
fn amdvi_nic_stop(nic &AmdviNic) {
	amdvi_nic_write(nic, amdvi_nic_imc, 0xffffffff)
	amdvi_nic_write(nic, amdvi_nic_rctl, 0)
	amdvi_nic_write(nic, amdvi_nic_tctl, 0)
	_ := amdvi_nic_read(nic, amdvi_nic_icr)
}

// Leave the card as it was found, for its driver.
fn amdvi_nic_close(mut nic AmdviNic) bool {
	amdvi_nic_stop(nic)
	amdvi_nic_write(nic, amdvi_nic_rdbal, 0)
	amdvi_nic_write(nic, amdvi_nic_rdbah, 0)
	amdvi_nic_write(nic, amdvi_nic_rdlen, 0)
	amdvi_nic_write(nic, amdvi_nic_tdbal, 0)
	amdvi_nic_write(nic, amdvi_nic_tdbah, 0)
	amdvi_nic_write(nic, amdvi_nic_tdlen, 0)
	_ := amdvi_nic_phy(nic, amdvi_nic_phy_control, true, nic.phy) or { u16(0) }
	now := amdvi_nic_phy(nic, amdvi_nic_phy_control, false, 0) or { u16(0xffff) }
	mut card := nic.dev.pci
	card.write[u16](0x4, nic.command)
	return now & amdvi_nic_phy_loopback == 0
}

// Whether the byte at `address`, which the card writes, has bit 0 set: the
// "descriptor done" bit of either ring.
fn amdvi_nic_done(address u64) bool {
	return kio.mmin[u8](unsafe { &u8(address) }) & 1 != 0
}

// Send one frame, to be received into the page at bus address `target`.
fn amdvi_nic_send(mut nic AmdviNic, target u64, mut probe AmdviProbe) {
	receive := nic.ring_virt + u64(nic.rx_next) * 16
	transmit := nic.ring_virt + amdvi_nic_tx_offset + u64(nic.tx_next) * 16
	nic.sequence++
	mut frame := unsafe { &u8(nic.frame_virt) }
	text := 'VINIX AMD-Vi self-test'
	for i := u64(0); i < amdvi_nic_frame_bytes; i++ {
		unsafe {
			frame[i] = if i < 6 {
				u8(0xff)
			} else if i < 12 {
				u8(if i == 6 { 0x02 } else { 0x00 })
			} else if i == 12 {
				u8(0x88)
			} else if i == 13 {
				u8(0xb5)
			} else if i - 14 < u64(text.len) {
				text[i - 14]
			} else {
				nic.sequence
			}
		}
	}
	unsafe {
		*&u64(receive) = target
		*&u64(receive + 8) = 0
		*&u64(transmit) = nic.frame_bus
		// The length; end of packet, add the checksum, report when done.
		*&u32(transmit + 8) = u32(amdvi_nic_frame_bytes) | (u32(0x0b) << 24)
		*&u32(transmit + 12) = 0
	}
	asm volatile amd64 {
		mfence
		; ; ; memory
	}
	nic.tx_next = (nic.tx_next + 1) % amdvi_nic_ring
	amdvi_nic_write(nic, amdvi_nic_tdt, nic.tx_next)

	limit := devcore.deadline(amdvi_nic_wait_ns)
	for {
		probe.sent = amdvi_nic_done(transmit + 12)
		probe.delivered = amdvi_nic_done(receive + 12)
		if probe.delivered || limit.expired() {
			break
		}
		devcore.relax()
	}
	if probe.delivered {
		// The descriptor is used; hand the card the one before the next.
		nic.rx_next = (nic.rx_next + 1) % amdvi_nic_ring
		amdvi_nic_write(nic, amdvi_nic_rdt, (nic.rx_next + amdvi_nic_ring - 1) % amdvi_nic_ring)
	}
}

// Fill the page at `virt` with a pattern, send a frame at it, and report
// what the page and the unit's event log look like afterwards.
fn amdvi_probe(mut unit AmdviUnit, mut nic AmdviNic, virt u64, bus u64) AmdviProbe {
	mut probe := AmdviProbe{}
	unsafe {
		C.memset(voidptr(virt), amdvi_test_pattern, amdvi_page_bytes)
	}
	amdvi_drain_events(mut unit)
	before := unit.events_by_kind[amdvi_event_page_fault]
	amdvi_nic_send(mut nic, bus, mut probe)
	amdvi_drain_events(mut unit)

	page := unsafe { &u8(virt) }
	probe.arrived = unsafe { C.memcmp(voidptr(virt), voidptr(nic.frame_virt), amdvi_nic_frame_bytes) } == 0
	probe.intact = true
	for i := u64(0); i < amdvi_page_bytes; i++ {
		if unsafe { page[i] } != amdvi_test_pattern {
			probe.intact = false
			break
		}
	}
	probe.faults = unit.events_by_kind[amdvi_event_page_fault] - before
	if probe.faults != 0 {
		probe.fault = unit.last_fault
		probe.fault_card = probe.fault.devid == nic.devid
		probe.fault_here = probe.fault_card && probe.fault.address >= bus
			&& probe.fault.address < bus + amdvi_page_bytes
	}
	return probe
}

// The frame reached the page, and the unit had nothing to say about it.
fn amdvi_reached(probe AmdviProbe) bool {
	return probe.sent && probe.delivered && probe.arrived && probe.faults == 0
}

// The card was turned away at this page: it thinks it received a frame, the
// page is as it was left, and the unit logged a fault naming the card.
//
// The fault should name the page as well, and whether it does is reported
// beside the verdict rather than being part of it: QEMU 11.1's unit logs
// address 0 for every fault, where hardware logs the address.
fn amdvi_turned_away(probe AmdviProbe) bool {
	return probe.sent && probe.delivered && probe.intact && !probe.arrived && probe.faults != 0
		&& probe.fault_card
}

// The card could not even read its rings: nothing was sent, nothing came
// back, and the page is as it was left.
fn amdvi_cut_off(probe AmdviProbe) bool {
	return !probe.sent && !probe.delivered && probe.intact && !probe.arrived
}

// Before anything has attached the card: a device nobody has asked memory
// for must reach none, not even rings it was pointed at.
fn amdvi_selftest_unattached(mut unit AmdviUnit, mut nic AmdviNic) {
	pages := u64(memory.pmm_alloc_fallible(3))
	if pages == 0 {
		amdvi_check('memory for the first check', false)
		return
	}
	virt := pages + higher_half
	mut probe := AmdviProbe{}
	started := amdvi_nic_start(mut nic, virt, pages, virt + amdvi_page_bytes, pages + amdvi_page_bytes)
	if started {
		probe = amdvi_probe(mut unit, mut nic, virt + 2 * amdvi_page_bytes, pages + 2 * amdvi_page_bytes)
	}
	amdvi_check_probe('a device never given a domain reaches nothing', started && amdvi_cut_off(probe),
		probe)
	amdvi_nic_stop(nic)
	memory.pmm_free(voidptr(pages), 3)
}

// ── The checks on a unit ────────────────────────────────────────────────────

// Fifty domains made, filled and destroyed for one device.
fn amdvi_selftest_cycles(mut unit AmdviUnit, mut dev devcore.Device) {
	scratch := u64(memory.pmm_alloc_fallible(16))
	if scratch == 0 {
		amdvi_check('attach and detach, fifty times', false)
		return
	}
	// Once first: the device's record is made on its first attach, and kept.
	mut cookie := amdvi_attach(unit.iommu, mut dev)
	mut good := cookie != unsafe { nil }
	if good {
		amdvi_detach(cookie)
	}
	pages := unit.table_pages
	free_before := memory.free_bytes()
	for i := 0; good && i < 50; i++ {
		cookie = amdvi_attach(unit.iommu, mut dev)
		if cookie == unsafe { nil } {
			good = false
			break
		}
		// Sixteen pages near the bottom of memory and one far up, so that
		// tables are made at every level.
		good = amdvi_map(cookie, scratch, scratch, 16 * amdvi_page_bytes)
			&& amdvi_map(cookie, amdvi_reach(unit.levels) - amdvi_page_bytes, scratch, amdvi_page_bytes)
		amdvi_unmap(cookie, scratch, amdvi_page_bytes)
		amdvi_detach(cookie)
	}
	free_after := memory.free_bytes()
	amdvi_check_count('attach and detach, fifty times: page-table pages', good && unit.table_pages == pages,
		pages, unit.table_pages)
	amdvi_check_count('attach and detach, fifty times: free memory in pages', good
		&& free_after == free_before, free_before / amdvi_page_bytes, free_after / amdvi_page_bytes)
	memory.pmm_free(voidptr(scratch), 16)
}

// A driver's view: memory from the DMA layer, a page that is not in the
// domain, and the same page as map() and unmap() and map_all() come and go.
fn amdvi_selftest_isolation(mut unit AmdviUnit, mut nic AmdviNic) {
	mut dev := nic.dev
	rings := alloc_buffer(mut dev, amdvi_page_bytes) or {
		amdvi_check('memory for the test rings', false)
		return
	}
	frame := alloc_buffer(mut dev, amdvi_page_bytes) or {
		amdvi_check('memory for the test frame', false)
		release(mut dev)
		return
	}
	inbox := alloc_buffer(mut dev, amdvi_page_bytes) or {
		amdvi_check('memory for the test buffer', false)
		release(mut dev)
		return
	}
	// Two pages at the start of a 2 MiB run, which the card is not given.
	outside := u64(memory.pmm_alloc_aligned_fallible(2, 512))
	domain := unsafe { &Domain(dev.dma) }
	if outside == 0 || domain.cookie == unsafe { nil } {
		amdvi_check('a domain and a page outside it', false)
		release(mut dev)
		return
	}
	target := outside + higher_half
	if !amdvi_nic_start(mut nic, rings.virt, rings.bus, frame.virt, frame.bus) {
		amdvi_check('the card in loopback', false)
		release(mut dev)
		memory.pmm_free(voidptr(outside), 2)
		return
	}

	// First that frames come round at all, into a page the card was given.
	mut probe := AmdviProbe{}
	for try := 0; try < amdvi_nic_warmup_tries; try++ {
		probe = amdvi_probe(mut unit, mut nic, inbox.virt, inbox.bus)
		if probe.delivered {
			break
		}
	}
	amdvi_check_probe('a page of the domain is written', amdvi_reached(probe), probe)
	if !probe.delivered {
		// Without loopback nothing below can tell blocked from broken.
		amdvi_nic_stop(nic)
		release(mut dev)
		memory.pmm_free(voidptr(outside), 2)
		return
	}

	probe = amdvi_probe(mut unit, mut nic, target, outside)
	amdvi_check_probe('a page outside the domain is not written, and the fault is logged',
		amdvi_turned_away(probe), probe)

	mapped := map_memory(mut dev, outside, amdvi_page_bytes) or { u64(0) }
	probe = amdvi_probe(mut unit, mut nic, target, outside)
	amdvi_check_probe('the same page after map() is written', mapped == outside && amdvi_reached(probe),
		probe)

	unmap_memory(mut dev, outside)
	probe = amdvi_probe(mut unit, mut nic, target, outside)
	amdvi_check_probe('the same page after unmap() is not written', amdvi_turned_away(probe),
		probe)

	// All of RAM, in 2 MiB pages where it can be; then one page back out,
	// which breaks one of those up.
	everything := allow_all(mut dev)
	probe = amdvi_probe(mut unit, mut nic, target, outside)
	amdvi_check_probe('the same page after map_all() is written', everything && amdvi_reached(probe),
		probe)

	mut held := unsafe { &AmdviDomain(domain.cookie) }
	splits := held.table.splits
	amdvi_unmap(domain.cookie, outside, amdvi_page_bytes)
	probe = amdvi_probe(mut unit, mut nic, target, outside)
	amdvi_check_probe('one page unmapped from a 2 MiB page is not written', amdvi_turned_away(probe)
		&& held.table.splits == splits + 1, probe)
	probe = amdvi_probe(mut unit, mut nic, target + amdvi_page_bytes, outside + amdvi_page_bytes)
	amdvi_check_probe('the page next to it still is', amdvi_reached(probe), probe)

	// The driver gives up on the card: it keeps its memory, the card
	// reaches none of it, its own rings included, so nothing is even sent.
	block(mut dev)
	probe = amdvi_probe(mut unit, mut nic, inbox.virt, inbox.bus)
	amdvi_check_probe('a detached device reaches nothing', amdvi_cut_off(probe), probe)

	amdvi_nic_stop(nic)
	release(mut dev)
	memory.pmm_free(voidptr(outside), 2)
}

// Memory the IVRS table keeps for a device: reachable with no driver, kept
// when one attaches, and all that is left when it detaches.
fn amdvi_selftest_firmware(mut unit AmdviUnit, mut nic AmdviNic) {
	mut dev := nic.dev
	// Rings, frame and a buffer inside the range; one page outside it.
	pages := u64(memory.pmm_alloc_fallible(4))
	if pages == 0 {
		amdvi_check('memory for the firmware range', false)
		return
	}
	virt := pages + higher_half
	inside := pages + 2 * amdvi_page_bytes
	outside := pages + 3 * amdvi_page_bytes
	real_ranges := amdvi_ivrs.unity
	// Made once per boot of a test kernel, and freed below.
	own := amdvi_devid(dev.pci)
	mut ranges := []AmdviUnity{cap: 1}
	ranges << AmdviUnity{
		first: own
		last:  own
		start: pages
		end:   pages + 3 * amdvi_page_bytes
		read:  true
		write: true
	}
	amdvi_ivrs.unity = ranges

	// What boot does for a device with such a range.
	amdvi_unity_domains(mut unit)
	mut held := amdvi_find_domain(mut unit, own)
	mut good := held != unsafe { nil } && held.table.root != 0 && !held.driver
		&& held.table.mapped == 3 * amdvi_page_bytes
	mut probe := AmdviProbe{}
	if good && amdvi_nic_start(mut nic, virt, pages, virt + amdvi_page_bytes, pages + amdvi_page_bytes) {
		for try := 0; try < amdvi_nic_warmup_tries; try++ {
			probe = amdvi_probe(mut unit, mut nic, inside + higher_half, inside)
			if probe.delivered {
				break
			}
		}
	}
	amdvi_check_probe('with no driver, a firmware range is written', good && amdvi_reached(probe),
		probe)
	if good && probe.delivered {
		probe = amdvi_probe(mut unit, mut nic, outside + higher_half, outside)
		amdvi_check_probe('with no driver, a page outside the range is not', amdvi_turned_away(probe),
			probe)

		// A driver comes and maps the outside page.
		mapped := map_memory(mut dev, outside, amdvi_page_bytes) or { u64(0) }
		probe = amdvi_probe(mut unit, mut nic, outside + higher_half, outside)
		amdvi_check_probe('with a driver, the page it mapped is written', mapped == outside
			&& held.driver && amdvi_reached(probe), probe)
		probe = amdvi_probe(mut unit, mut nic, inside + higher_half, inside)
		amdvi_check_probe('with a driver, the firmware range still is', amdvi_reached(probe),
			probe)

		// And goes: its page with it, firmware's range not.
		release(mut dev)
		probe = amdvi_probe(mut unit, mut nic, outside + higher_half, outside)
		amdvi_check_probe('after the driver, its page is not written', amdvi_turned_away(probe)
			&& !held.driver, probe)
		probe = amdvi_probe(mut unit, mut nic, inside + higher_half, inside)
		amdvi_check_probe('after the driver, the firmware range still is', amdvi_reached(probe)
			&& held.table.mapped == 3 * amdvi_page_bytes, probe)
	}
	amdvi_nic_stop(nic)

	// Take the pretend range away again, and the tables made for it.
	amdvi_ivrs.unity = real_ranges
	unsafe { ranges.free() }
	if held != unsafe { nil } {
		nothing := AmdviTable{}
		amdvi_replace_tables(mut unit, mut held, unsafe { &nothing })
		held.has_unity = false
	}
	memory.pmm_free(voidptr(pages), 4)
}

// Run everything. Called once, with the units on and no driver bound.
fn amdvi_selftest_run() {
	amdvi_selftest_parser()
	mut found := amdvi_nic_find()
	mut nic := AmdviNic{}
	if found == unsafe { nil } {
		amdvi_selftest_note = 'no unbound e1000 to test with'
	} else if iommu_for(found) == unsafe { nil } {
		amdvi_selftest_note = 'the e1000 is behind no AMD-Vi unit'
	} else {
		mut unit := unsafe { &AmdviUnit(iommu_for(found).data) }
		nic.dev = found
		nic.devid = amdvi_subject(unit.entries, amdvi_devid(found.pci)).alias
		pages_at_start := unit.table_pages

		opened := amdvi_nic_open(mut nic)
		if opened {
			amdvi_selftest_unattached(mut unit, mut nic)
		}
		amdvi_selftest_cycles(mut unit, mut found)
		// The long way of making a unit forget, which one with INVALIDATE_ALL
		// is never asked to go: some 65000 commands through a ring of 512.
		commands := unit.commands_queued
		amdvi_check_count('every domain forgotten one by one: commands', amdvi_forget_domains(mut unit)
			&& unit.command_timeouts == 0, commands, unit.commands_queued)

		if opened {
			amdvi_selftest_isolation(mut unit, mut nic)
			amdvi_selftest_firmware(mut unit, mut nic)
			amdvi_check('the card left as it was found', amdvi_nic_close(mut nic))
		} else {
			amdvi_selftest_note = 'the e1000 could not be driven'
		}
		amdvi_check_count('page-table pages at the end', unit.table_pages == pages_at_start
			&& unit.leaked_pages == 0, pages_at_start, unit.table_pages)
	}

	mut passed := amdvi_selftest_note.len == 0 && amdvi_selftest_count != 0
	for i in 0 .. amdvi_selftest_count {
		passed = passed && amdvi_selftest_checks[i].passed
	}
	amdvi_selftest_passed = passed
	amdvi_selftest_done = true
	if amdvi_selftest_note.len != 0 {
		C.kprintf(c'amdvi: self-test: %.*s\n', i32(amdvi_selftest_note.len), amdvi_selftest_note.str)
	}
	C.kprintf(c'amdvi: self-test %s (%lld checks)\n', if passed { c'PASS' } else { c'FAIL' },
		i64(amdvi_selftest_count))
}

// /sys/class/iommu/ivhdN/selftest: the verdict, then a line a check.
fn amdvi_selftest_show(context voidptr, mut text lib.Text) {
	text.add('result: ')
	text.add(if !amdvi_selftest_done {
		'not run'
	} else if amdvi_selftest_passed {
		'PASS'
	} else {
		'FAIL'
	})
	text.add_byte(`\n`)
	if amdvi_selftest_note.len != 0 {
		text.add('note: ')
		text.add(amdvi_selftest_note)
		text.add_byte(`\n`)
	}
	for i in 0 .. amdvi_selftest_count {
		check := unsafe { &amdvi_selftest_checks[i] }
		text.add(if check.passed { 'pass: ' } else { 'FAIL: ' })
		text.add(check.name)
		if check.counted {
			text.add(' (')
			text.add_unsigned(check.before)
			text.add(' -> ')
			text.add_unsigned(check.after)
			text.add(')')
		}
		if check.probed {
			text.add(if check.probe.sent { ' (sent' } else { ' (not sent' })
			text.add(if check.probe.delivered { ', received' } else { ', not received' })
			text.add(if check.probe.arrived {
				', bytes in page'
			} else if check.probe.intact {
				', page intact'
			} else {
				', page changed'
			})
			text.add(', faults ')
			text.add_unsigned(check.probe.faults)
			if check.probe.faults != 0 {
				text.add(': ')
				amdvi_add_device(mut text, check.probe.fault.devid)
				text.add(' address 0x')
				text.add_radix(check.probe.fault.address, 16, 0)
				text.add(' flags 0x')
				text.add_radix(u64(check.probe.fault.flags), 16, 0)
				text.add(if check.probe.fault_here {
					', address is in the page'
				} else {
					', address is NOT in the page'
				})
			}
			text.add(')')
		}
		text.add_byte(`\n`)
	}
}
