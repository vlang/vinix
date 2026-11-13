// SPDX-License-Identifier: GPL-2.0-or-later
module ext2

import errno

// This reader deliberately uses the existing u32 block interface and the
// ext2 inode's low ownership/block-count fields. Refuse extensions that would
// otherwise silently change their meaning. Checksums are NOT verified.
fn ext4_inode_layout(data voidptr, bytes u64, incompat u32) ? {
	if bytes < 128 || bytes > 4096 || bytes & (bytes - 1) != 0 {
		errno.set(errno.eio); return none
	}
	flags := disk_u32(data, 32)
	mode := disk_u16(data, 0) & 0xf000
	if disk_u32(data, 20) != 0 || disk_u16(data, 26) == 0
		|| flags & u32(0x4 | 0x200 | 0x800 | 0x40000 | 0x100000 | 0x200000 | 0x10000000 | 0x40000000) != 0
		|| disk_u16(data, 116) != 0 || disk_u16(data, 118) != 0
		|| disk_u16(data, 120) != 0 || disk_u16(data, 122) != 0
		|| (flags & ext4_inode_extents != 0 && incompat & 0x40 == 0)
		|| (mode != 0x8000 && mode != 0x4000 && mode != 0xa000)
		|| (mode != 0x8000 && disk_u32(data, 108) != 0) {
		errno.set(errno.eopnotsupp)
		return none
	}
	if bytes > 128 {
		extra := u64(disk_u16(data, 128))
		if extra > bytes - 128 || extra & 3 != 0 {
			errno.set(errno.eio)
			return none
		}
		// Epoch extensions would be misreported by the seconds-only reader.
		if (extra >= 8 && disk_u32(data, 132) & 3 != 0)
			|| (extra >= 12 && disk_u32(data, 136) & 3 != 0)
			|| (extra >= 16 && disk_u32(data, 140) & 3 != 0) {
			errno.set(errno.eopnotsupp)
			return none
		}
	}
}

struct ReadDirectoryEntry {
	inode u32
	bytes u16
	name_bytes u8
	@type u8
}

// A record must fit inside ONE filesystem block, including unused records
// and checksum tails. HTree index payloads hide in unused record space; a
// linear scan of every directory block still visits all ordinary entries.
fn read_directory_entry(data voidptr, remaining u64, filetype bool) ?ReadDirectoryEntry {
	if remaining < 8 { errno.set(errno.eio); return none }
	record := ReadDirectoryEntry{
		inode: disk_u32(data, 0)
		bytes: disk_u16(data, 4)
		name_bytes: unsafe { (&u8(data))[6] }
		@type: if filetype { unsafe { (&u8(data))[7] } } else { u8(0) }
	}
	if record.bytes < 8 || record.bytes & 3 != 0 || record.bytes > remaining
		|| u16(record.name_bytes) > record.bytes - 8
		|| (!filetype && unsafe { (&u8(data))[7] } != 0) {
		errno.set(errno.eio)
		return none
	}
	if record.inode != 0 {
		if record.name_bytes == 0 || record.@type > 7 { errno.set(errno.eio); return none }
		for i in 0 .. int(record.name_bytes) {
			c := unsafe { (&u8(data))[8 + i] }
			if c == 0 || c == `/` { errno.set(errno.eio); return none }
		}
	}
	return record
}
