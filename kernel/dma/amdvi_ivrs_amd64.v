// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The ACPI IVRS table: which AMD IOMMUs the machine has, which devices are
// behind each, and which memory firmware expects a device to go on reaching.
//
// After a 48-byte header the table is a run of blocks, each starting with a
// type byte and a 16-bit length:
//
//	IVHD (10h, 11h, 40h)  one IOMMU: where its registers are, the PCI function
//	                      that carries its capability block, and a list of
//	                      device entries saying which requester ids reach it
//	IVMD (20h, 21h, 22h)  a range of memory that all devices, one device or a
//	                      range of devices must find mapped at its own address
//
// Firmware describes the same unit two or three times over, once per IVHD
// type, for the benefit of older systems; the highest type is the one to
// believe, as Linux does, and the others are passed over.
//
// The table is firmware's, so nothing in it is believed until it has been
// checked against the length of what holds it: the table against its
// checksum, a block against the table, a device entry against its block. What
// does not fit is counted and left out, and what was already read is kept.
//
// Nothing here touches hardware or knows where the table came from; the
// self-test hands the same parser tables of its own making.
module dma

import lib

const amdvi_ivrs_header = u32(48)
// An IVRS is a few kilobytes. A length beyond this is a corrupt header, and
// reading that far would run off the end of what is mapped.
const amdvi_ivrs_limit = u32(1 << 20)

const amdvi_ivhd_10 = u8(0x10)
const amdvi_ivhd_11 = u8(0x11)
const amdvi_ivhd_40 = u8(0x40)
const amdvi_ivmd_all = u8(0x20)
const amdvi_ivmd_one = u8(0x21)
const amdvi_ivmd_range = u8(0x22)

// IVHD device entry types. The top two bits of the type give the entry's
// length -- 4, 8, 16 or 32 bytes -- except for F0h, which says its own.
const amdvi_dev_all = u8(0x01)
const amdvi_dev_select = u8(0x02)
const amdvi_dev_range_start = u8(0x03)
const amdvi_dev_range_end = u8(0x04)
const amdvi_dev_alias = u8(0x42)
const amdvi_dev_alias_range = u8(0x43)
const amdvi_dev_ext_select = u8(0x46)
const amdvi_dev_ext_range = u8(0x47)
const amdvi_dev_special = u8(0x48)
const amdvi_dev_acpi_hid = u8(0xf0)

const amdvi_special_ioapic = u8(1)
const amdvi_special_hpet = u8(2)

// IVMD flags.
const amdvi_ivmd_unity = u8(0x01)
const amdvi_ivmd_read = u8(0x02)
const amdvi_ivmd_write = u8(0x04)
const amdvi_ivmd_exclusion = u8(0x08)

// More IVHD blocks than any machine has: a two-socket server has eight units,
// each described up to three times.
const amdvi_max_blocks = 32

// What one or more IVHD device entries say about a run of requester ids.
struct AmdviEntry {
mut:
	first u16
	last  u16
	// The entry's "data setting" byte: which legacy interrupts pass, and
	// the system management bits.
	settings u8
	extended u32
	// The devices send as `alias` instead of as themselves: they sit behind
	// a bridge that puts its own id on what it forwards.
	aliased bool
	alias   u16
	// Not a PCI function but the I/O APIC or the HPET, which send interrupts
	// under an id firmware gave them.
	special u8
	handle  u8
}

// Memory that the devices `first` to `last` must find at its own address.
struct AmdviUnity {
mut:
	first u16
	last  u16
	start u64
	end   u64
	read  bool
	write bool
}

// One IVHD block, as found.
struct AmdviBlock {
mut:
	kind       u8
	flags      u8
	devid      u16
	cap_offset u16
	mmio_phys  u64
	info       u16
	efr_attr   u32
	// Types 11h and 40h carry a copy of the extended feature register.
	has_efr bool
	efr     u64
	efr2    u64
	// Where its device entries lie in the table.
	entries_at  u32
	entries_end u32
	// The block to use for its unit: the highest type that describes it.
	chosen bool
}

struct AmdviIvrs {
mut:
	ivinfo      u32
	blocks      [amdvi_max_blocks]AmdviBlock
	block_count int
	unity       []AmdviUnity
	// What was passed over, for the log.
	malformed        u32
	foreign_segments u32
	unknown_blocks   u32
}

fn amdvi_u8(table &u8, offset u32) u8 {
	return unsafe { table[offset] }
}

// Fields are read a byte at a time: nothing in the table is aligned.
fn amdvi_u16(table &u8, offset u32) u16 {
	return u16(amdvi_u8(table, offset)) | (u16(amdvi_u8(table, offset + 1)) << 8)
}

fn amdvi_u32(table &u8, offset u32) u32 {
	return u32(amdvi_u16(table, offset)) | (u32(amdvi_u16(table, offset + 2)) << 16)
}

fn amdvi_u64(table &u8, offset u32) u64 {
	return u64(amdvi_u32(table, offset)) | (u64(amdvi_u32(table, offset + 4)) << 32)
}

fn amdvi_ivhd_header_bytes(kind u8) u32 {
	return match kind {
		amdvi_ivhd_10 { u32(24) }
		amdvi_ivhd_11, amdvi_ivhd_40 { u32(40) }
		else { u32(0) }
	}
}

// How long the device entry at `offset` is, given that `room` bytes are left
// in its block. Zero when it does not fit, which ends the block.
fn amdvi_entry_bytes(table &u8, offset u32, room u32) u32 {
	if room < 4 {
		return 0
	}
	kind := amdvi_u8(table, offset)
	mut bytes := u32(4) << (kind >> 6)
	if kind == amdvi_dev_acpi_hid {
		// Fixed part, then a unique id whose length is the byte before it.
		if room < 22 {
			return 0
		}
		bytes = 22 + u32(amdvi_u8(table, offset + 21))
	}
	if bytes > room {
		return 0
	}
	return bytes
}

// Read the table of `length` bytes at `table` into `out`. False when it is not
// an IVRS at all; true otherwise, with whatever could be made sense of.
fn amdvi_parse_ivrs(table &u8, length u32, mut out AmdviIvrs) bool {
	out.block_count = 0
	out.malformed = 0
	out.foreign_segments = 0
	out.unknown_blocks = 0
	out.ivinfo = 0
	if length < amdvi_ivrs_header || length > amdvi_ivrs_limit {
		return false
	}
	mut sum := u8(0)
	for i := u32(0); i < length; i++ {
		sum += amdvi_u8(table, i)
	}
	if sum != 0 {
		return false
	}
	out.ivinfo = amdvi_u32(table, 36)

	mut unity_count := 0
	mut offset := amdvi_ivrs_header
	for offset < length {
		if length - offset < 4 {
			out.malformed++
			break
		}
		kind := amdvi_u8(table, offset)
		bytes := u32(amdvi_u16(table, offset + 2))
		if bytes < 4 || bytes > length - offset {
			// Without a length there is no finding the next block.
			out.malformed++
			break
		}
		header := amdvi_ivhd_header_bytes(kind)
		if header != 0 {
			amdvi_note_block(table, offset, bytes, header, mut out)
		} else if kind == amdvi_ivmd_all || kind == amdvi_ivmd_one || kind == amdvi_ivmd_range {
			if amdvi_unity_at(table, offset, bytes, mut out, unsafe { nil }) {
				unity_count++
			}
		} else {
			out.unknown_blocks++
		}
		offset += bytes
	}

	// The memory blocks again, now that there is somewhere to put them. The
	// counts of what was passed over were taken the first time round.
	malformed := out.malformed
	foreign := out.foreign_segments
	// Made once per table; the caller owns it.
	mut unity := []AmdviUnity{cap: unity_count}
	unity.flags |= .noslices
	offset = amdvi_ivrs_header
	for offset < length && length - offset >= 4 {
		kind := amdvi_u8(table, offset)
		bytes := u32(amdvi_u16(table, offset + 2))
		if bytes < 4 || bytes > length - offset {
			break
		}
		if kind == amdvi_ivmd_all || kind == amdvi_ivmd_one || kind == amdvi_ivmd_range {
			mut range := AmdviUnity{}
			if amdvi_unity_at(table, offset, bytes, mut out, unsafe { &range }) && unity.len < unity_count {
				unity << range
			}
		}
		offset += bytes
	}
	out.unity = unity
	out.malformed = malformed
	out.foreign_segments = foreign

	amdvi_choose_blocks(mut out)
	return true
}

// Record the IVHD block at `offset`, if it is one this driver can use.
fn amdvi_note_block(table &u8, offset u32, bytes u32, header u32, mut out AmdviIvrs) {
	if bytes < header {
		out.malformed++
		return
	}
	// Only PCI segment 0 is supported: the PCI layer scans that one, and
	// every table of this driver is indexed by bus, device and function.
	if amdvi_u16(table, offset + 16) != 0 {
		out.foreign_segments++
		return
	}
	if out.block_count >= amdvi_max_blocks {
		out.malformed++
		return
	}
	kind := amdvi_u8(table, offset)
	mut ivhd := unsafe { &out.blocks[out.block_count] }
	ivhd.kind = kind
	ivhd.flags = amdvi_u8(table, offset + 1)
	ivhd.devid = amdvi_u16(table, offset + 4)
	ivhd.cap_offset = amdvi_u16(table, offset + 6)
	ivhd.mmio_phys = amdvi_u64(table, offset + 8)
	ivhd.info = amdvi_u16(table, offset + 18)
	ivhd.efr_attr = amdvi_u32(table, offset + 20)
	ivhd.has_efr = header >= 40
	ivhd.efr = if ivhd.has_efr { amdvi_u64(table, offset + 24) } else { u64(0) }
	ivhd.efr2 = if ivhd.has_efr { amdvi_u64(table, offset + 32) } else { u64(0) }
	ivhd.entries_at = offset + header
	ivhd.entries_end = offset + bytes
	ivhd.chosen = false
	out.block_count++
}

// Decode the IVMD block at `offset` into `range`, when one is given. False
// when the block asks for nothing this driver acts on.
fn amdvi_unity_at(table &u8, offset u32, bytes u32, mut out AmdviIvrs, range &AmdviUnity) bool {
	if bytes < 32 {
		out.malformed++
		return false
	}
	kind := amdvi_u8(table, offset)
	flags := amdvi_u8(table, offset + 1)
	if flags & (amdvi_ivmd_unity | amdvi_ivmd_exclusion) == 0 {
		return false
	}
	if amdvi_u16(table, offset + 8) != 0 {
		out.foreign_segments++
		return false
	}
	devid := amdvi_u16(table, offset + 4)
	aux := amdvi_u16(table, offset + 6)
	start := amdvi_u64(table, offset + 16)
	span := amdvi_u64(table, offset + 24)
	if span == 0 || start + span < start || (kind == amdvi_ivmd_range && aux < devid) {
		out.malformed++
		return false
	}
	// An exclusion range was once passed through untranslated by a pair of
	// registers. There is one pair and firmware may list several ranges, so
	// each is mapped at its own address for reading and writing instead, as
	// Linux does.
	read := flags & amdvi_ivmd_exclusion != 0 || flags & amdvi_ivmd_read != 0
	write := flags & amdvi_ivmd_exclusion != 0 || flags & amdvi_ivmd_write != 0
	if !read && !write {
		return false
	}
	if range == unsafe { nil } {
		return true
	}
	mut found := unsafe { range }
	found.first = if kind == amdvi_ivmd_all { u16(0) } else { devid }
	found.last = match kind {
		amdvi_ivmd_all { u16(0xffff) }
		amdvi_ivmd_range { aux }
		else { devid }
	}
	// Out to whole pages: a page is the least a device can be given.
	found.start = lib.align_down(start, amdvi_page_bytes)
	found.end = lib.align_up(start + span, amdvi_page_bytes)
	found.read = read
	found.write = write
	return true
}

fn amdvi_kind_rank(kind u8) int {
	return match kind {
		amdvi_ivhd_40 { 3 }
		amdvi_ivhd_11 { 2 }
		else { 1 }
	}
}

// Of the blocks that describe one unit -- they name the same PCI function --
// mark the one of the highest type, and the first of those.
fn amdvi_choose_blocks(mut out AmdviIvrs) {
	for i in 0 .. out.block_count {
		mut best := i
		for j in 0 .. out.block_count {
			if out.blocks[j].devid != out.blocks[i].devid {
				continue
			}
			if amdvi_kind_rank(out.blocks[j].kind) > amdvi_kind_rank(out.blocks[best].kind) {
				best = j
			} else if amdvi_kind_rank(out.blocks[j].kind) == amdvi_kind_rank(out.blocks[best].kind)
				&& j < best {
				best = j
			}
		}
		if best == i {
			out.blocks[i].chosen = true
		}
	}
}

// Go through a block's device entries. With `entries` given they are added to
// it; either way the number of records they come to is returned, so that a
// first call can size the list for the second.
//
// A start-of-range entry only takes effect at the end-of-range that follows
// it. An alias gives two records: the devices, and the id they send as, which
// the unit sees and so has a device table entry of its own.
fn amdvi_block_entries(table &u8, ivhd &AmdviBlock, mut entries []AmdviEntry, fill bool) int {
	mut count := 0
	mut pending := false
	mut open := AmdviEntry{}
	mut offset := ivhd.entries_at
	for offset < ivhd.entries_end {
		bytes := amdvi_entry_bytes(table, offset, ivhd.entries_end - offset)
		if bytes == 0 {
			break
		}
		kind := amdvi_u8(table, offset)
		devid := amdvi_u16(table, offset + 1)
		settings := amdvi_u8(table, offset + 3)
		extra := if bytes >= 8 { amdvi_u32(table, offset + 4) } else { u32(0) }
		mut record := AmdviEntry{
			first:    devid
			last:     devid
			settings: settings
		}
		mut complete := false
		match kind {
			amdvi_dev_all {
				record.first = 0
				record.last = 0xffff
				complete = true
			}
			amdvi_dev_select {
				complete = true
			}
			amdvi_dev_ext_select {
				record.extended = extra
				complete = true
			}
			amdvi_dev_alias {
				record.aliased = true
				record.alias = u16(extra >> 8)
				complete = true
			}
			amdvi_dev_special {
				// The id is in the second word; the first names nothing.
				record.first = u16(extra >> 8)
				record.last = record.first
				record.special = u8(extra >> 24)
				record.handle = u8(extra)
				complete = true
			}
			amdvi_dev_range_start, amdvi_dev_ext_range, amdvi_dev_alias_range {
				open = record
				if kind == amdvi_dev_ext_range {
					open.extended = extra
				}
				if kind == amdvi_dev_alias_range {
					open.aliased = true
					open.alias = u16(extra >> 8)
				}
				pending = true
			}
			amdvi_dev_range_end {
				if pending && devid >= open.first {
					record = open
					record.last = devid
					complete = true
				}
				pending = false
			}
			else {
				// Padding, an ACPI-named device (which has no requester id
				// to look up), or a type newer than this driver.
			}
		}
		if complete {
			if fill {
				entries << record
			}
			count++
			if record.aliased {
				if fill {
					entries << AmdviEntry{
						first:    record.alias
						last:     record.alias
						settings: record.settings
					}
				}
				count++
			}
		}
		offset += bytes
	}
	return count
}

// The highest requester id any of `entries` names, which is how long the
// unit's device table has to be.
fn amdvi_last_devid(entries []AmdviEntry) u32 {
	mut last := u32(0)
	for entry in entries {
		if u32(entry.last) > last {
			last = u32(entry.last)
		}
		if entry.aliased && u32(entry.alias) > last {
			last = u32(entry.alias)
		}
	}
	return last
}

struct AmdviSubject {
mut:
	// An entry of the unit names the id.
	covered  bool
	settings u8
	// What it sends as: itself, unless an entry gives it an alias.
	alias u16
}

// What the unit's entries say of the requester id `devid`. Settings add up
// over every entry that names it, as they do in Linux; the last alias wins.
fn amdvi_subject(entries []AmdviEntry, devid u16) AmdviSubject {
	mut subject := AmdviSubject{
		alias: devid
	}
	for entry in entries {
		if devid < entry.first || devid > entry.last {
			continue
		}
		// The I/O APIC and the HPET send interrupts under an id; that does
		// not put the PCI function with the same number behind the unit.
		if entry.special == 0 {
			subject.covered = true
		}
		subject.settings |= entry.settings
		if entry.aliased {
			subject.alias = entry.alias
		}
	}
	return subject
}
