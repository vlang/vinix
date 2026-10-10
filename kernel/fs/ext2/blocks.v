module ext2

import errno
import memory
import stat

// i_dir_acl is the size high word only for regular files.
fn (inode &EXT2Inode) size() u64 {
	if stat.isreg(u32(inode.permissions)) {
		return u64(inode.size32l) | (u64(inode.size32h) << 32)
	}
	return u64(inode.size32l)
}

fn (filesystem &EXT2Filesystem) file_capacity() u64 {
	pointers := filesystem.block_size / 4
	blocks := u64(12) + pointers + pointers * pointers + pointers * pointers * pointers
	// The on-disk block address and the driver's logical-block interface are u32.
	addressable := if blocks < u64(0x100000000) { blocks } else { u64(0x100000000) }
	return addressable * filesystem.block_size
}

// At most three indices, ordered from the inode's root towards the data page.
fn (filesystem &EXT2Filesystem) block_path(logical u32) ?(int, int, [3]u32) {
	mut indices := [3]u32{}
	if logical < 12 { return int(logical), 0, indices }
	pointers := filesystem.block_size / 4
	mut relative := u64(logical) - 12
	mut span := pointers
	for depth in 1 .. 4 {
		if relative < span {
			mut divisor := span / pointers
			for level in 0 .. depth {
				indices[level] = u32(relative / divisor)
				relative %= divisor
				if level + 1 < depth { divisor /= pointers }
			}
			return 11 + depth, depth, indices
		}
		relative -= span
		span *= pointers
	}
	errno.set(errno.efbig)
	return none
}

fn (mut inode EXT2Inode) get_block(mut filesystem EXT2Filesystem, logical u32) ?u32 {
	root, depth, indices := filesystem.block_path(logical)?
	mut block := inode.blocks[root]
	value := unsafe { &u32(C.vinix_stack_alloc(sizeof(u32))) }
	for level in 0 .. depth {
		// A missing intermediate table is a hole, never block zero on the device.
		if block == 0 { return 0 }
		filesystem.raw_device_read(value, u64(block) * filesystem.block_size + u64(indices[level]) * 4, 4)?
		block = unsafe { *value }
	}
	return block
}

// EXT2 i_blocks always counts 512-byte sectors, irrespective of device geometry.
fn (mut inode EXT2Inode) allocate_accounted_block(mut filesystem EXT2Filesystem) ?u32 {
	sectors := u32(filesystem.block_size / 512)
	if inode.sector_cnt > u32(0xffffffff) - sectors {
		errno.set(errno.efbig)
		return none
	}
	block := filesystem.allocate_block()?
	inode.sector_cnt += sectors
	return block
}

fn (mut inode EXT2Inode) free_accounted_block(mut filesystem EXT2Filesystem, block u32) ? {
	filesystem.free_block(block)?
	sectors := u32(filesystem.block_size / 512)
	inode.sector_cnt = if inode.sector_cnt >= sectors { inode.sector_cnt - sectors } else { 0 }
	filesystem.checkpoint_cleanup(mut inode)?
}

// Build missing tables while detached. No published pointer may name a block
// freed by allocation or table-write rollback.
fn (mut inode EXT2Inode) attach_block_chain(mut filesystem EXT2Filesystem, inode_index u32,
	root int, parent u64, first int, depth int, indices [3]u32, data u32) ? {
	mut tables := [3]u32{}
	mut published := false
	defer {
		if !published {
			for table in tables {
				if table != 0 { inode.free_accounted_block(mut filesystem, table) or {} }
			}
		}
	}
	for level in first .. depth {
		tables[level] = inode.allocate_accounted_block(mut filesystem)?
	}
	value := unsafe { &u32(C.vinix_stack_alloc(sizeof(u32))) }
	for level in first .. depth {
		unsafe { *value = if level + 1 == depth { data } else { tables[level + 1] } }
		filesystem.raw_device_write(value, u64(tables[level]) * filesystem.block_size + u64(indices[level]) * 4, 4)?
	}
	if first == 0 {
		inode.blocks[root] = tables[0]
		inode.write_entry(mut filesystem, inode_index) or {
			inode.blocks[root] = 0
			return none
		}
		published = true
	} else {
		unsafe { *value = tables[first] }
		filesystem.raw_device_write(value, parent, 4)?
		published = true
		// The existing inode already owns this parent. The write caller
		// checkpoints the new counters together with its completed size.
	}
}

fn (mut inode EXT2Inode) set_block(mut filesystem EXT2Filesystem, inode_index u32,
	logical u32, data u32) ?u32 {
	root, depth, indices := filesystem.block_path(logical)?
	if depth == 0 {
		old := inode.blocks[root]
		inode.blocks[root] = data
		inode.write_entry(mut filesystem, inode_index) or { inode.blocks[root] = old; return none }
		return data
	}
	mut table := inode.blocks[root]
	mut parent := u64(0)
	value := unsafe { &u32(C.vinix_stack_alloc(sizeof(u32))) }
	for level in 0 .. depth {
		if table == 0 {
			if data == 0 { return 0 }
			inode.attach_block_chain(mut filesystem, inode_index, root, parent, level, depth, indices, data)?
			return data
		}
		parent = u64(table) * filesystem.block_size + u64(indices[level]) * 4
		if level + 1 == depth {
			unsafe { *value = data }
			filesystem.raw_device_write(value, parent, 4)?
			return data
		}
		filesystem.raw_device_read(value, parent, 4)?
		table = unsafe { *value }
	}
	return none
}

// Visit allocated tables only. Recursion is bounded by the three on-disk
// indirect levels; each call owns one fallible buffer, released on every exit.
// The caller still owns `table` and frees it only after clearing its pointer.
fn (mut inode EXT2Inode) prune_block_table(mut filesystem EXT2Filesystem, table u32,
	depth int, first u64, kept u64) ?bool {
	entries := unsafe { &u32(memory.calloc(filesystem.block_size, 1)) }
	if entries == unsafe { nil } { errno.set(errno.enomem); return none }
	defer { memory.free(entries) }
	filesystem.raw_device_read(entries, u64(table) * filesystem.block_size, filesystem.block_size)?
	pointers := filesystem.block_size / 4
	mut span := u64(1)
	for _ in 1 .. depth { span *= pointers }
	zero := unsafe { &u32(C.vinix_stack_alloc(sizeof(u32))) }
	unsafe { *zero = 0 }
	mut empty := true
	for index := u64(0); index < pointers; index++ {
		child := unsafe { entries[index] }
		if child == 0 { continue }
		base := first + index * span
		if base + span <= kept { empty = false; continue }
		if depth > 1 && !inode.prune_block_table(mut filesystem, child, depth - 1, base, kept)? {
			empty = false
			continue
		}
		filesystem.raw_device_write(zero, u64(table) * filesystem.block_size + index * 4, 4)?
		inode.free_accounted_block(mut filesystem, child)?
	}
	return empty
}

fn (mut inode EXT2Inode) truncate_blocks(mut filesystem EXT2Filesystem, inode_index u32, kept u64) ? {
	// Earlier detached blocks stay accounted for if a later table read fails.
	// A failure of this inode write itself remains a filesystem I/O failure.
	defer { inode.write_entry(mut filesystem, inode_index) or {} }
	for index in 0 .. 12 {
		if u64(index) < kept || inode.blocks[index] == 0 { continue }
		block := inode.blocks[index]
		inode.blocks[index] = 0
		inode.write_entry(mut filesystem, inode_index) or { inode.blocks[index] = block; return none }
		inode.free_accounted_block(mut filesystem, block)?
	}
	pointers := filesystem.block_size / 4
	mut first := u64(12)
	mut span := pointers
	for depth in 1 .. 4 {
		root := 11 + depth
		table := inode.blocks[root]
		if table != 0 && first + span > kept {
			if inode.prune_block_table(mut filesystem, table, depth, first, kept)? {
				inode.blocks[root] = 0
				inode.write_entry(mut filesystem, inode_index) or { inode.blocks[root] = table; return none }
				inode.free_accounted_block(mut filesystem, table)?
			}
		}
		first += span
		span *= pointers
	}
}
