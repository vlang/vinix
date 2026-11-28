// SPDX-License-Identifier: GPL-2.0-or-later
module ext2

import errno

// Parse one extent-tree node without allocating. The caller copies just the
// header and each 12-byte record, so a malformed count cannot exhaust memory.
fn (mut inode EXT2Inode) extent_block(mut filesystem EXT2Filesystem, logical u32) ?u32 {
	mut position := u64(0)
	mut capacity := u64(sizeof(inode.blocks))
	mut expected_depth := -1
	mut lower := u64(0)
	mut upper := u64(0x100000000)
	header := unsafe { &u8(C.vinix_stack_alloc(12)) }
	entry := unsafe { &u8(C.vinix_stack_alloc(12)) }
	for _ in 0 .. 6 {
		if position == 0 {
			unsafe { C.memcpy(header, &inode.blocks[0], 12) }
		} else {
			filesystem.raw_device_read(header, position, 12)?
		}
		count := disk_u16(header, 2)
		maximum := disk_u16(header, 4)
		depth := int(disk_u16(header, 6))
		if disk_u16(header, 0) != 0xf30a || depth > 5
			|| (expected_depth >= 0 && depth != expected_depth)
			|| count > maximum || maximum == 0 || u64(maximum) > (capacity - 12) / 12
			|| (depth > 0 && count == 0) {
			errno.set(errno.eio)
			return none
		}
		mut previous_end := u64(0)
		mut found := false
		mut child := u32(0)
		mut result := u32(0)
		mut child_lower := lower
		mut child_upper := upper
		for index in 0 .. int(count) {
			offset := u64(12 + index * 12)
			if position == 0 {
				unsafe { C.memcpy(entry, voidptr(u64(&inode.blocks[0]) + offset), 12) }
			} else {
				filesystem.raw_device_read(entry, position + offset, 12)?
			}
			first := u64(disk_u32(entry, 0))
			if first < lower || first >= upper || (index > 0 && first < previous_end) {
				errno.set(errno.eio)
				return none
			}
			if depth > 0 {
				previous_end = first + 1
				address := disk_u32(entry, 4)
				if disk_u16(entry, 8) != 0 || address == 0 || address >= filesystem.superblock.block_cnt {
					errno.set(errno.eio)
					return none
				}
				if first <= logical {
					child = address
					found = true
					child_lower = first
				} else if found && child_upper == upper {
					child_upper = first
				}
			} else {
				length := disk_u16(entry, 4)
				span := u64(if length > 32768 { length - 32768 } else { length })
				address := disk_u32(entry, 8)
				if span == 0 || first + span > upper
					|| disk_u16(entry, 6) != 0 || address == 0
					|| u64(address) + span > filesystem.superblock.block_cnt {
					errno.set(errno.eio)
					return none
				}
				previous_end = first + span
				if first <= logical && u64(logical) < previous_end {
					// Unwritten extents are zero-filled holes, including when their
					// backing blocks contain stale data from an earlier file.
					result = if length > 32768 { u32(0) } else { address + logical - u32(first) }
				}
			}
		}
		if depth == 0 { return result }
		if !found { return 0 }
		expected_depth = depth - 1
		lower = child_lower
		upper = child_upper
		position = u64(child) * filesystem.block_size
		capacity = filesystem.block_size
	}
	errno.set(errno.eio)
	return none
}
