module ext2

import os

fn image_fixture(kind string, block_size int) &EXT2Filesystem {
	mut fs := fixture(u64(block_size))
	unsafe { fs.disk.free() }
	fs.disk = os.read_bytes(os.getenv('EXT_MOUNT_IMAGES') + '/' + kind + '-' + block_size.str() + '.img') or { panic(err) }
	unsafe { C.memcpy(fs.superblock, &fs.disk[1024], sizeof(EXT2Superblock)) }
	layout := volume_layout(mut fs.superblock, unsafe { &fs.disk[1024] }, u64(fs.disk.len), kind == 'ext4') or { panic('volume layout') }
	assert layout.read_only == (kind == 'ext4')
	fs.block_size = layout.block_bytes
	fs.descriptor_size = layout.descriptor_bytes
	fs.ext4 = kind == 'ext4'
	fs.bgd_cnt = (u64(fs.superblock.block_cnt - fs.superblock.sb_block) + fs.superblock.blocks_per_group - 1) / fs.superblock.blocks_per_group
	return fs
}

fn find_entry(mut fs EXT2Filesystem, name string) u32 {
	mut inode := EXT2Inode{}
	inode.read_entry(mut fs, 2) or { panic('root inode') }
	mut data := []u8{len: int(inode.size())}
	assert inode.read(mut fs, data.data, 0, u64(data.len)) or { panic('directory read') } == data.len
	defer { unsafe { data.free() } }
	mut position := 0
	for position + 8 <= data.len {
		address := unsafe { &data[position] }
		size := int(disk_u16(address, 4))
		assert size >= 8 && position + size <= data.len
		length := int(data[position + 6])
		if disk_u32(address, 0) != 0 && length == name.len {
			value := unsafe { tos(address + 8, length) }
			if value == name { return disk_u32(address, 0) }
		}
		position += size
	}
	panic('Missing ' + name)
}

fn test_linux_images_read_extents_symlinks_and_multiple_descriptor_groups() {
	for kind in ['ext2', 'ext4'] {
		for block_size in [1024, 4096] {
			mut fs := image_fixture(kind, block_size)
			mut inode := EXT2Inode{}
			inode.read_entry(mut fs, find_entry(mut fs, 'marker'))?
			mut output := [256]u8{}
			assert inode.read(mut fs, unsafe { &output[0] }, 0, 256)? == 22
			assert unsafe { tos(&output[0], 22) } == 'external Linux volume\n'
			inode.read_entry(mut fs, find_entry(mut fs, 'fragmented'))?
			if kind == 'ext4' {
				assert inode.flags & ext4_inode_extents != 0
				assert disk_u16(unsafe { &inode.blocks[0] }, 6) > 0
			}
			for i in 0 .. 9 {
				assert inode.read(mut fs, unsafe { &output[0] }, u64(i * 8192), 256)? == 256
				for byte in output {
					assert byte == u8(i + 1)
				}
				if i < 8 {
					assert inode.read(mut fs, unsafe { &output[0] }, u64(i * 8192 + 4096), 256)? == 256
					for byte in output {
						assert byte == 0
					}
				}
			}
			inode.read_entry(mut fs, find_entry(mut fs, 'short-link'))?
			assert inode.fast_symlink_target(fs.block_size)? == 'marker'
			inode.read_entry(mut fs, find_entry(mut fs, 'long-link'))?
			target := 'this/is/a/long/symlink/target/with/more/than/sixty/bytes/to/exercise/extents'
			assert inode.read(mut fs, unsafe { &output[0] }, 0, 256)? == target.len
			assert unsafe { tos(&output[0], target.len) } == target
			// The table stride matters for every group after zero, even on a small
			// volume carrying the 64bit feature with zero high block addresses.
			if fs.bgd_cnt > 1 {
				mut bgd := EXT2BlockGroupDescriptor{}
				assert bgd.read_entry(mut fs, 1) == 0
				base := if block_size == 1024 { u64(2048) } else { u64(block_size) }
				assert bgd.inode_table_block == disk_u32(fs.disk.data, base + fs.descriptor_size + 8)
				assert bgd.inode_table_block > 0
			}
			assert fs.writes == 0
			fs.close()
		}
	}
}

fn test_layout_refuses_recovery_unsupported_features_and_invalid_geometry() {
	mut fs := image_fixture('ext4', 4096)
	defer { fs.close() }
	sb := *fs.superblock
	for bit in [u32(4), 0x10, 0x400, 0x8000, 0x10000, 0x20000, 0x80000000] {
		fs.superblock.req_features = sb.req_features | bit
		if _ := volume_layout(mut fs.superblock, unsafe { &fs.disk[1024] }, u64(fs.disk.len), true) {
			assert false
		}
	}
	unsafe { *fs.superblock = sb }
	fs.superblock.fs_state = 0
	if _ := volume_layout(mut fs.superblock, unsafe { &fs.disk[1024] }, u64(fs.disk.len), true) {
		assert false
	}
	unsafe { *fs.superblock = sb }
	fs.superblock.non_supported_features |= 0x10000
	if _ := volume_layout(mut fs.superblock, unsafe { &fs.disk[1024] }, u64(fs.disk.len), true) {
		assert false
	}
	unsafe { *fs.superblock = sb }
	fs.disk[1024 + 0x150] = 1
	if _ := volume_layout(mut fs.superblock, unsafe { &fs.disk[1024] }, u64(fs.disk.len), true) {
		assert false
	}
	fs.disk[1024 + 0x150] = 0
	if _ := volume_layout(mut fs.superblock, unsafe { &fs.disk[1024] }, u64(fs.disk.len), false) {
		assert false
	}
	for bad in [u32(0), u32(0xffffffff)] {
		unsafe { *fs.superblock = sb }
		fs.superblock.blocks_per_group = bad
		if _ := volume_layout(mut fs.superblock, unsafe { &fs.disk[1024] }, u64(fs.disk.len), true) {
			assert false
		}
	}
}

fn put16(mut words [15]u32, offset int, value u16) {
	unsafe {
		p := &u8(&words[0])
		p[offset] = u8(value)
		p[offset + 1] = u8(value >> 8)
	}
}

fn leaf_inode() EXT2Inode {
	mut inode := EXT2Inode{ flags: ext4_inode_extents }
	put16(mut inode.blocks, 0, 0xf30a)
	put16(mut inode.blocks, 2, 1)
	put16(mut inode.blocks, 4, 4)
	inode.blocks[3] = 2
	put16(mut inode.blocks, 16, 3)
	inode.blocks[5] = 10
	return inode
}

fn test_extent_holes_unwritten_maximum_length_and_corruption() {
	mut fs := fixture(4096)
	defer { fs.close() }
	fs.superblock.block_cnt = 65536
	mut inode := leaf_inode()
	assert inode.get_block(mut fs, 1)? == 0
	assert inode.get_block(mut fs, 2)? == 10
	assert inode.get_block(mut fs, 4)? == 12
	assert inode.get_block(mut fs, 5)? == 0
	put16(mut inode.blocks, 16, 0x8003)
	assert inode.get_block(mut fs, 2)? == 0
	put16(mut inode.blocks, 16, 0x8000)
	assert inode.get_block(mut fs, 2 + 32767)? == 10 + 32767
	for offset in [0, 2, 4, 6, 16, 18] {
		inode = leaf_inode()
		put16(mut inode.blocks, offset, if offset == 16 { u16(0) } else { u16(0xffff) })
		if _ := inode.get_block(mut fs, 2) {
			assert false
		}
	}
	inode = leaf_inode()
	put16(mut inode.blocks, 2, 2)
	inode.blocks[6] = 3
	put16(mut inode.blocks, 28, 1)
	inode.blocks[8] = 20
	if _ := inode.get_block(mut fs, 2) {
		assert false
	} // overlapping ranges
	// A self-referencing index is rejected by the required decreasing depth.
	inode = leaf_inode()
	put16(mut inode.blocks, 6, 1)
	inode.blocks[3] = 0
	inode.blocks[4] = 10
	inode.blocks[5] = 0
	unsafe { C.memcpy(&fs.disk[10 * 4096], &inode.blocks[0], 60) }
	if _ := inode.get_block(mut fs, 2) {
		assert false
	}
	fs.read_fail_at = fs.reads + 1
	if _ := inode.get_block(mut fs, 2) {
		assert false
	}
}
