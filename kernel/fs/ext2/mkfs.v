// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module ext2

import fs as vfs
import memory
import time

// Making an empty ext2 filesystem, for a machine that boots from an installer
// image and is given a blank disk to keep its system on. The layout is what
// `mke2fs -t ext2 -b 4096 -I 128` makes and what this driver reads: 4 KiB
// blocks, 128-byte inodes, one inode per 16 KiB, backups of the superblock and
// the group descriptors in groups 0 and 1 and the powers of 3, 5 and 7, a root
// directory and lost+found.

const mkfs_block_size = u64(4096)
const mkfs_blocks_per_group = u64(32768) // one bitmap block's worth of bits
const mkfs_inode_size = u64(128)
const mkfs_bytes_per_inode = u64(16384)
const mkfs_inodes_per_group = mkfs_blocks_per_group * mkfs_block_size / mkfs_bytes_per_inode
const mkfs_inode_table_blocks = mkfs_inodes_per_group * mkfs_inode_size / mkfs_block_size
const mkfs_first_inode = u32(11) // lost+found; 1 to 10 are reserved
const mkfs_root_inode = u32(2)

const ext2_feature_incompat_filetype = u32(0x2)
const ext2_feature_ro_compat_sparse_super = u32(0x1)
const ext2_feature_ro_compat_large_file = u32(0x2)

// Whether group `group` carries a copy of the superblock and the group
// descriptors (sparse_super).
fn mkfs_has_backup(group u64) bool {
	if group <= 1 {
		return true
	}
	for base in [u64(3), 5, 7]! {
		mut power := base
		for power < group {
			power *= base
		}
		if power == group {
			return true
		}
	}
	return false
}

struct MkfsLayout {
mut:
	blocks        u64
	groups        u64
	gdt_blocks    u64
	root_block    u64
	lost_block    u64
	free_blocks   []u64
	block_bitmaps []u64
	inode_bitmaps []u64
	inode_tables  []u64
}

// Blocks a group spends before its data: the superblock and descriptor copies
// when it has them, the two bitmaps and the inode table.
fn mkfs_overhead(group u64, gdt_blocks u64) u64 {
	mut overhead := u64(2) + mkfs_inode_table_blocks
	if mkfs_has_backup(group) {
		overhead += 1 + gdt_blocks
	}
	return overhead
}

fn mkfs_plan(device_bytes u64) ?MkfsLayout {
	mut blocks := device_bytes / mkfs_block_size
	if blocks > 0xffff_ffff {
		// 32-bit block numbers: 16 TiB is more than a system disk needs.
		blocks = 0xffff_ffff
	}
	mut groups := (blocks + mkfs_blocks_per_group - 1) / mkfs_blocks_per_group
	if groups == 0 {
		return none
	}
	mut gdt_blocks := (groups * 32 + mkfs_block_size - 1) / mkfs_block_size
	// A last group too small to hold its own metadata and some data is left
	// off, as mke2fs does.
	last := blocks - (groups - 1) * mkfs_blocks_per_group
	if last < mkfs_overhead(groups - 1, gdt_blocks) + 64 {
		if groups == 1 {
			return none
		}
		blocks -= last
		groups--
		gdt_blocks = (groups * 32 + mkfs_block_size - 1) / mkfs_block_size
	}
	mut layout := MkfsLayout{
		blocks:        blocks
		groups:        groups
		gdt_blocks:    gdt_blocks
		free_blocks:   []u64{len: int(groups)}
		block_bitmaps: []u64{len: int(groups)}
		inode_bitmaps: []u64{len: int(groups)}
		inode_tables:  []u64{len: int(groups)}
	}
	for group in 0 .. groups {
		start := group * mkfs_blocks_per_group
		in_group := if group == groups - 1 { blocks - start } else { mkfs_blocks_per_group }
		mut next := start
		if mkfs_has_backup(group) {
			next += 1 + gdt_blocks
		}
		layout.block_bitmaps[group] = next
		layout.inode_bitmaps[group] = next + 1
		layout.inode_tables[group] = next + 2
		layout.free_blocks[group] = in_group - mkfs_overhead(group, gdt_blocks)
	}
	// The root directory and lost+found take the first two data blocks.
	layout.root_block = layout.inode_tables[0] + mkfs_inode_table_blocks
	layout.lost_block = layout.root_block + 1
	layout.free_blocks[0] -= 2
	return layout
}

fn mkfs_write(device &vfs.VFSNode, buffer voidptr, offset u64, length u64) bool {
	mut res := unsafe { device.resource }
	written := res.write(unsafe { nil }, buffer, offset, length) or { return false }
	return u64(written) == length
}

// A directory entry at `offset` in `block`; returns the offset after it.
fn mkfs_dir_entry(block voidptr, offset u64, inode u32, rec_len u16, name string) u64 {
	mut entry := unsafe { &EXT2DirectoryEntry(u64(block) + offset) }
	entry.inode_index = inode
	entry.entry_size = rec_len
	entry.name_length = u8(name.len)
	entry.dir_type = 2 // directory
	unsafe {
		C.memcpy(voidptr(u64(block) + offset + sizeof(EXT2DirectoryEntry)), name.str,
			name.len)
	}
	return offset + rec_len
}

fn mkfs_dir_inode(mode u16, links u16, block u64, now u32) EXT2Inode {
	mut inode := EXT2Inode{}
	inode.permissions = mode | 0x4000
	inode.size32l = u32(mkfs_block_size)
	inode.access_time = now
	inode.creation_time = now
	inode.mod_time = now
	inode.hard_link_cnt = links
	inode.sector_cnt = u32(mkfs_block_size / 512)
	inode.blocks[0] = u32(block)
	return inode
}

// Make an empty ext2 filesystem on the whole of `device`. Everything the
// filesystem uses is written, inode tables included, so a disk that was not
// zeroed comes out the same as one that was. Returns false on an I/O error or
// a device too small to hold a filesystem.
pub fn format(device &vfs.VFSNode, label string) bool {
	if device.resource == unsafe { nil } {
		return false
	}
	layout := mkfs_plan(u64(device.resource.stat.size)) or { return false }
	defer {
		unsafe {
			layout.free_blocks.free()
			layout.block_bitmaps.free()
			layout.inode_bitmaps.free()
			layout.inode_tables.free()
		}
	}
	wall := time.clock_now(time.clock_type_realtime) or { time.TimeSpec{} }
	now := u32(wall.tv_sec)

	// One MiB of zeroes to clear inode tables with, a block to build metadata
	// in, and the descriptor table.
	chunk := u64(1024 * 1024)
	zeroes := memory.calloc(chunk, 1)
	block := memory.calloc(mkfs_block_size, 1)
	gdt := memory.calloc(layout.gdt_blocks * mkfs_block_size, 1)
	if zeroes == unsafe { nil } || block == unsafe { nil } || gdt == unsafe { nil } {
		memory.free(zeroes)
		memory.free(block)
		memory.free(gdt)
		return false
	}
	defer {
		memory.free(zeroes)
		memory.free(block)
		memory.free(gdt)
	}

	mut total_free := u64(0)
	for group in 0 .. layout.groups {
		start := group * mkfs_blocks_per_group
		in_group := if group == layout.groups - 1 {
			layout.blocks - start
		} else {
			mkfs_blocks_per_group
		}
		// The inode table, zeroed.
		table_bytes := mkfs_inode_table_blocks * mkfs_block_size
		for done := u64(0); done < table_bytes; done += chunk {
			length := if table_bytes - done < chunk { table_bytes - done } else { chunk }
			if !mkfs_write(device, zeroes, layout.inode_tables[group] * mkfs_block_size + done,
				length) {
				return false
			}
		}
		// The block bitmap: the group's metadata is in use, and so are the
		// bits past the end of a short last group.
		unsafe { C.memset(block, 0, mkfs_block_size) }
		used := in_group - layout.free_blocks[group]
		for bit := u64(0); bit < mkfs_blocks_per_group; bit++ {
			if bit < used || bit >= in_group {
				unsafe {
					mut p := &u8(u64(block) + bit / 8)
					*p |= u8(1) << (bit % 8)
				}
			}
		}
		if !mkfs_write(device, block, layout.block_bitmaps[group] * mkfs_block_size,
			mkfs_block_size) {
			return false
		}
		// The inode bitmap: the reserved inodes and lost+found in group 0, and
		// the padding past the group's inodes in every group.
		unsafe { C.memset(block, 0, mkfs_block_size) }
		for bit := u64(0); bit < mkfs_block_size * 8; bit++ {
			if bit >= mkfs_inodes_per_group || (group == 0 && bit < u64(mkfs_first_inode)) {
				unsafe {
					mut p := &u8(u64(block) + bit / 8)
					*p |= u8(1) << (bit % 8)
				}
			}
		}
		if !mkfs_write(device, block, layout.inode_bitmaps[group] * mkfs_block_size,
			mkfs_block_size) {
			return false
		}
		// This group's descriptor.
		unsafe {
			mut descriptor := &EXT2BlockGroupDescriptor(u64(gdt) + group * 32)
			descriptor.block_addr_bitmap = u32(layout.block_bitmaps[group])
			descriptor.block_addr_inode = u32(layout.inode_bitmaps[group])
			descriptor.inode_table_block = u32(layout.inode_tables[group])
			descriptor.unallocated_blocks = u16(layout.free_blocks[group])
			mut free_inodes := mkfs_inodes_per_group
			mut directories := u16(0)
			if group == 0 {
				free_inodes -= u64(mkfs_first_inode)
				directories = 2
			}
			descriptor.unallocated_inodes = u16(free_inodes)
			descriptor.dir_cnt = directories
		}
		total_free += layout.free_blocks[group]
	}

	// The root directory and lost+found.
	unsafe { C.memset(block, 0, mkfs_block_size) }
	mut offset := mkfs_dir_entry(block, 0, mkfs_root_inode, 12, '.')
	offset = mkfs_dir_entry(block, offset, mkfs_root_inode, 12, '..')
	mkfs_dir_entry(block, offset, mkfs_first_inode, u16(mkfs_block_size - offset), 'lost+found')
	if !mkfs_write(device, block, layout.root_block * mkfs_block_size, mkfs_block_size) {
		return false
	}
	unsafe { C.memset(block, 0, mkfs_block_size) }
	offset = mkfs_dir_entry(block, 0, mkfs_first_inode, 12, '.')
	mkfs_dir_entry(block, offset, mkfs_root_inode, u16(mkfs_block_size - offset), '..')
	if !mkfs_write(device, block, layout.lost_block * mkfs_block_size, mkfs_block_size) {
		return false
	}
	// Their inodes, in the first block of group 0's inode table, which holds
	// inodes 1 to 32.
	unsafe { C.memset(block, 0, mkfs_block_size) }
	root := mkfs_dir_inode(0o755, 3, layout.root_block, now)
	lost := mkfs_dir_inode(0o700, 2, layout.lost_block, now)
	unsafe {
		C.memcpy(voidptr(u64(block) + u64(mkfs_root_inode - 1) * mkfs_inode_size), &root,
			sizeof(EXT2Inode))
		C.memcpy(voidptr(u64(block) + u64(mkfs_first_inode - 1) * mkfs_inode_size), &lost,
			sizeof(EXT2Inode))
	}
	if !mkfs_write(device, block, layout.inode_tables[0] * mkfs_block_size, mkfs_block_size) {
		return false
	}

	// The superblock, and its copies with the descriptor table.
	mut superblock := EXT2Superblock{}
	superblock.inode_cnt = u32(layout.groups * mkfs_inodes_per_group)
	superblock.block_cnt = u32(layout.blocks)
	superblock.unallocated_blocks = u32(total_free)
	superblock.unallocated_inodes = superblock.inode_cnt - mkfs_first_inode
	superblock.sb_block = 0 // the first data block: 0 with 4 KiB blocks
	superblock.block_size = 2 // 1024 << 2
	superblock.frag_size = 2
	superblock.blocks_per_group = u32(mkfs_blocks_per_group)
	superblock.frags_per_group = u32(mkfs_blocks_per_group)
	superblock.inodes_per_group = u32(mkfs_inodes_per_group)
	superblock.last_written_time = now
	superblock.mnt_allowed = 0xffff
	superblock.signature = 0xef53
	superblock.fs_state = 1 // clean
	superblock.error_response = 1 // continue
	superblock.last_fsck = now
	superblock.version_maj = 1 // dynamic inode sizes and features
	superblock.first_inode = mkfs_first_inode
	superblock.inode_size = u16(mkfs_inode_size)
	superblock.req_features = ext2_feature_incompat_filetype
	superblock.non_supported_features = ext2_feature_ro_compat_sparse_super | ext2_feature_ro_compat_large_file
	superblock.uuid[0] = u64(now) * 0x9e3779b97f4a7c15 ^ u64(layout.blocks)
	superblock.uuid[1] = time.monotonic_ns() * 0xbf58476d1ce4e5b9 ^ 0x76696e6978
	unsafe {
		C.memcpy(&superblock.volume_name[0], label.str,
			if label.len < 16 { label.len } else { 16 })
	}
	for group in 0 .. layout.groups {
		if !mkfs_has_backup(group) {
			continue
		}
		start := group * mkfs_blocks_per_group
		superblock.sb_bgd = u16(group)
		// Group 0's superblock is 1 KiB into its first block, after the boot
		// sector; a backup starts its group's first block.
		unsafe { C.memset(block, 0, mkfs_block_size) }
		sb_offset := if group == 0 { u64(1024) } else { u64(0) }
		unsafe { C.memcpy(voidptr(u64(block) + sb_offset), &superblock, sizeof(EXT2Superblock)) }
		if !mkfs_write(device, block, start * mkfs_block_size, mkfs_block_size) {
			return false
		}
		if !mkfs_write(device, gdt, (start + 1) * mkfs_block_size,
			layout.gdt_blocks * mkfs_block_size) {
			return false
		}
	}
	return true
}
