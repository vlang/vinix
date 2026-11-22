// SPDX-License-Identifier: GPL-2.0-or-later
module disklayout

// The installer and its boot template share a layout. The firmware files are
// at fixed offsets; the root takes the remaining space before the backup GPT.
pub const sector_bytes = u64(512)
pub const min_disk_bytes = u64(4) << 30
pub const bios_start = u64(2048)
pub const esp_start = u64(4096)
pub const root_start = esp_start + 64 * 1024 * 1024 / sector_bytes
pub const root_index = 2
pub const table_sectors = u64(32)

const gpt_signature = u64(0x5452415020494645)
const header_bytes = u32(92)
const bios_type = Guid{0x6e6f644921686148, 0x4946456465654e74}
const esp_type = Guid{0x11d2f81fc12a7328, 0x3bc93ec9a0004bba}
const pending_type = Guid{0x410b583136c99588, 0x3d5fffc8c447b583}
const root_type = Guid{0x440be1a830c91ea5, 0x645f66a164220f83}

// These records use the on-disk byte order on the supported little-endian
// architectures. GPT CRCs cover the declared header and all 128 entries.
pub struct Guid {
pub mut:
	low  u64
	high u64
}

pub fn (a Guid) matches(b Guid) bool {
	return a.low == b.low && a.high == b.high
}

pub struct Identity {
pub mut:
	disk Guid
	bios Guid
	esp  Guid
	root Guid
}

@[packed]
pub struct Header {
mut:
	signature   u64
	revision    u32
	size        u32
	checksum    u32
	reserved    u32
	current     u64
	other       u64
	first       u64
	last        u64
	disk        Guid
	table_lba   u64
	entry_count u32
	entry_size  u32
	table_crc   u32
	padding     [420]u8
}

struct Entry {
mut:
	kind  Guid
	id    Guid
	first u64
	last  u64
	flags u64
	name  [36]u16
}

pub struct Table {
mut:
	entries [128]Entry
}

pub fn root_end(sectors u64) u64 {
	return sectors - table_sectors - 1 // exclusive
}

pub fn entries(table &Table, sectors u64, id Identity, pending bool) {
	unsafe {
		table.entries[0] = Entry{ kind: bios_type, id: id.bios, first: bios_start, last: esp_start - 1 }
		table.entries[1] = Entry{ kind: esp_type, id: id.esp, first: esp_start, last: root_start - 1 }
		table.entries[root_index] = Entry{
			kind:  if pending { pending_type } else { root_type }
			id:    id.root
			first: root_start
			last:  root_end(sectors) - 1
		}
	}
}

pub fn table_lba(sectors u64, backup bool) u64 {
	return if backup { root_end(sectors) } else { u64(2) }
}

pub fn header_lba(sectors u64, backup bool) u64 {
	return if backup { sectors - 1 } else { u64(1) }
}

pub fn header(table &Table, sectors u64, disk Guid, backup bool) Header {
	mut hdr := Header{
		signature:   gpt_signature
		revision:    0x10000
		size:        header_bytes
		current:     header_lba(sectors, backup)
		other:       header_lba(sectors, !backup)
		first:       2 + table_sectors
		last:        root_end(sectors) - 1
		disk:        disk
		table_lba:   table_lba(sectors, backup)
		entry_count: 128
		entry_size:  128
		table_crc:   crc32(unsafe { &u8(table) }, u32(sizeof(Table)))
	}
	hdr.checksum = crc32(unsafe { &u8(&hdr) }, header_bytes)
	return hdr
}

pub fn protective_mbr(sectors u64) [512]u8 {
	mut mbr := [512]u8{}
	mbr[447] = 0 // starting CHS 0/0/2
	mbr[448] = 2
	mbr[450] = 0xee
	mbr[451] = 0xff
	mbr[452] = 0xff
	mbr[453] = 0xff
	mbr[454] = 1
	length := if sectors > 0x100000000 { u32(0xffffffff) } else { u32(sectors - 1) }
	for i in 0 .. 4 {
		mbr[458 + i] = u8(length >> (i * 8))
	}
	mbr[510] = 0x55
	mbr[511] = 0xaa
	return mbr
}

pub struct Installation {
pub:
	id      Identity
	pending bool
}

// Recognise only our own layout. In particular, a similarly sized partition
// or a GPT header with an invalid checksum never authorises a retry.
pub fn inspect(hdr Header, table &Table, sectors u64, backup bool) ?Installation {
	if hdr.signature != gpt_signature || hdr.revision != 0x10000 || hdr.size != header_bytes
		|| hdr.current != header_lba(sectors, backup) || hdr.other != header_lba(sectors, !backup)
		|| hdr.first != 2 + table_sectors || hdr.last != root_end(sectors) - 1
		|| hdr.table_lba != table_lba(sectors, backup) || hdr.entry_count != 128
		|| hdr.entry_size != 128 || hdr.disk.matches(Guid{}) {
		return none
	}
	mut checked := hdr
	checked.checksum = 0
	if hdr.checksum != crc32(unsafe { &u8(&checked) }, header_bytes)
		|| hdr.table_crc != crc32(unsafe { &u8(table) }, u32(sizeof(Table))) {
		return none
	}
	bios := table.entries[0]
	esp := table.entries[1]
	root := table.entries[root_index]
	pending := root.kind.matches(pending_type)
	if !bios.kind.matches(bios_type) || bios.first != bios_start || bios.last != esp_start - 1
		|| !esp.kind.matches(esp_type) || esp.first != esp_start || esp.last != root_start - 1
		|| (!pending && !root.kind.matches(root_type)) || root.first != root_start
		|| root.last != root_end(sectors) - 1 || bios.id.matches(Guid{}) || esp.id.matches(Guid{})
		|| root.id.matches(Guid{}) {
		return none
	}
	for index in 3 .. table.entries.len {
		if !table.entries[index].kind.matches(Guid{}) {
			return none
		}
	}
	return Installation{
		id:      Identity{ disk: hdr.disk, bios: bios.id, esp: esp.id, root: root.id }
		pending: pending
	}
}

fn crc32(data &u8, len u32) u32 {
	mut crc := u32(0xffffffff)
	for i in 0 .. len {
		crc ^= unsafe { data[i] }
		for _ in 0 .. 8 {
			crc = (crc >> 1) ^ (u32(0xedb88320) & (u32(0) - (crc & 1)))
		}
	}
	return ~crc
}
