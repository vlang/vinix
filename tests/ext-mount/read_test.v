module ext2

fn store16(data &u8, offset int, value u16) {
	unsafe { data[offset] = u8(value); data[offset + 1] = u8(value >> 8) }
}

fn store32(data &u8, offset int, value u32) {
	store16(data, offset, u16(value))
	store16(data, offset + 2, u16(value >> 16))
}

fn test_inode_layout_refuses_extensions_instead_of_truncating() {
	mut raw := [256]u8{}
	p := unsafe { &raw[0] }
	store16(p, 0, 0x81a4)
	store16(p, 26, 1)
	store16(p, 128, 32)
	ext4_inode_layout(p, 256, 0x40)?
	for flag in [u32(4), 0x200, 0x800, 0x40000, 0x100000, 0x200000, 0x10000000, 0x40000000] {
		store32(p, 32, flag)
		if _ := ext4_inode_layout(p, 256, 0x40) { assert false }
	}
	store32(p, 32, 0)
	for offset in [116, 118, 120, 122] {
		store16(p, offset, 1)
		if _ := ext4_inode_layout(p, 256, 0x40) { assert false }
		store16(p, offset, 0)
	}
	store16(p, 128, 132)
	if _ := ext4_inode_layout(p, 256, 0x40) { assert false }
	store16(p, 128, 32)
	store32(p, 136, 1)
	if _ := ext4_inode_layout(p, 256, 0x40) { assert false }
	store32(p, 136, 4000) // nanoseconds, no extended epoch
	ext4_inode_layout(p, 256, 0x40)?
	store32(p, 136, 0)
	for field in 0 .. 3 {
		store16(p, 128, u16(8 + field * 4))
		store32(p, 132 + field * 4, 1)
		if _ := ext4_inode_layout(p, 256, 0x40) { assert false }
		store32(p, 132 + field * 4, 0)
		ext4_inode_layout(p, 256, 0x40)?
	}
	store16(p, 128, 32)
	store32(p, 32, ext4_inode_extents)
	if _ := ext4_inode_layout(p, 256, 0) { assert false }
	if _ := ext4_inode_layout(p, 127, 0x40) { assert false }
}

fn test_directory_records_are_block_bounded_and_names_are_valid() {
	mut raw := [32]u8{}
	p := unsafe { &raw[0] }
	store32(p, 0, 12)
	store16(p, 4, 12)
	raw[6] = 3
	raw[7] = 1
	raw[8] = `a`; raw[9] = `b`; raw[10] = `c`
	entry := read_directory_entry(p, 32, true)?
	assert entry.inode == 12 && entry.name_bytes == 3 && entry.bytes == 12
	for length in [u16(0), 4, 9, 36] {
		store16(p, 4, length)
		if _ := read_directory_entry(p, 32, true) { assert false }
	}
	store16(p, 4, 12)
	if _ := read_directory_entry(p, 8, true) { assert false }
	raw[6] = 5
	if _ := read_directory_entry(p, 32, true) { assert false }
	raw[6] = 3
	for c in [u8(0), `/`] {
		raw[9] = c
		if _ := read_directory_entry(p, 32, true) { assert false }
	}
	raw[9] = `b`
	if _ := read_directory_entry(p, 32, false) { assert false }
	raw[7] = 0
	read_directory_entry(p, 32, false)?
	// A metadata_csum tail has inode zero and type 0xde. Do not parse a name.
	store32(p, 0, 0)
	raw[6] = 0; raw[7] = 0xde
	read_directory_entry(p, 12, true)?
}

fn extent_header(data &u8, count u16, depth u16) {
	store16(data, 0, 0xf30a)
	store16(data, 2, count)
	store16(data, 4, 4)
	store16(data, 6, depth)
}

fn test_indexed_extents_depth_two_and_parent_ranges() {
	mut fs := fixture(4096)
	defer { fs.close() }
	fs.superblock.block_cnt = 256
	mut inode := EXT2Inode{flags: ext4_inode_extents}
	p := unsafe { &u8(&inode.blocks[0]) }
	extent_header(p, 2, 2)
	store32(p, 12, 0); store32(p, 16, 10); store32(p, 20, 0)
	store32(p, 24, 100); store32(p, 28, 11); store32(p, 32, 0)
	middle := unsafe { &fs.disk[10 * 4096] }
	extent_header(middle, 1, 1)
	store32(middle, 12, 0); store32(middle, 16, 12)
	leaf := unsafe { &fs.disk[12 * 4096] }
	extent_header(leaf, 1, 0)
	store32(leaf, 12, 2); store16(leaf, 16, 3); store32(leaf, 20, 20)
	assert inode.get_block(mut fs, 1)? == 0
	assert inode.get_block(mut fs, 2)? == 20
	assert inode.get_block(mut fs, 4)? == 22
	store16(leaf, 16, 0x8003)
	assert inode.get_block(mut fs, 2)? == 0
	// A child's extent cannot cross the next key in its ancestor.
	store32(leaf, 12, 99); store16(leaf, 16, 3)
	if _ := inode.get_block(mut fs, 99) { assert false }
	store32(leaf, 12, 2); store16(leaf, 16, 3)
	store16(leaf, 6, 1)
	if _ := inode.get_block(mut fs, 2) { assert false }
	assert fs.writes == 0
}

fn test_ext4_superblock_features_device_size_and_descriptor_bounds() {
	mut raw := [1024]u8{}
	p := unsafe { &raw[0] }
	store16(p, 0xfe, 64)
	mut sb := EXT2Superblock{
		inode_cnt: 128
		block_cnt: 1024
		block_size: 2
		blocks_per_group: 1024
		inodes_per_group: 128
		inode_size: 256
		version_maj: 1
		fs_state: 1
		req_features: 0x2 | 0x40 | 0x80 | 0x200
		non_supported_features: 0x1 | 0x2 | 0x8 | 0x20 | 0x40 | 0x400
	}
	assert volume_layout(mut sb, p, 4 * 1024 * 1024, true)?.descriptor_bytes == 64
	saved := sb
	for flag in [u32(4), 0x10, 0x100, 0x400, 0x8000, 0x10000, 0x20000, 0x80000000] {
		sb = saved; sb.req_features |= flag
		if _ := volume_layout(mut sb, p, 4 * 1024 * 1024, true) { assert false }
	}
	for flag in [u32(0x200), 0x8000, 0x10000] {
		sb = saved; sb.non_supported_features |= flag
		if _ := volume_layout(mut sb, p, 4 * 1024 * 1024, true) { assert false }
	}
	sb = saved
	if _ := volume_layout(mut sb, p, 4096, true) { assert false }
	sb.fs_state = 0
	if _ := volume_layout(mut sb, p, 4 * 1024 * 1024, true) { assert false }
	sb = saved
	store32(p, 0xe8, 2)
	if _ := volume_layout(mut sb, p, 4 * 1024 * 1024, true) { assert false }
	store32(p, 0xe8, 0)
	for bytes in [u16(32), 128, 0xffff] {
		store16(p, 0xfe, bytes)
		if _ := volume_layout(mut sb, p, 4 * 1024 * 1024, true) { assert false }
	}
	store16(p, 0xfe, 64)
	store32(p, 0x150, 1)
	if _ := volume_layout(mut sb, p, 4 * 1024 * 1024, true) { assert false }
	store32(p, 0x150, 0)
	sb.req_features &= ~u32(0x80)
	assert volume_layout(mut sb, p, 4 * 1024 * 1024, true)?.descriptor_bytes == 32
}

fn test_production_inode_reads_both_descriptor_strides_and_rejects_high_fields() {
	for stride in [u64(32), 64] {
		mut fs := fixture(4096)
		fs.ext4 = true
		fs.descriptor_size = stride
		fs.bgd_cnt = 2
		fs.superblock.inode_cnt = 32
		fs.superblock.block_cnt = 256
		fs.superblock.inodes_per_group = 16
		fs.superblock.inode_size = 256
		fs.superblock.req_features = 0x40
		for group in 0 .. 2 {
			store32(unsafe { &fs.disk[4096] }, int(u64(group) * stride + 8), u32(4 + group * 4))
			data := unsafe { &fs.disk[(4 + group * 4) * 4096] }
			store16(data, 0, 0x81a4)
			store16(data, 26, 1)
			store16(data, 128, 32)
			store32(data, 4, u32(42 + group))
			mut inode := EXT2Inode{}
			inode.read_entry(mut fs, u32(group * 16 + 1))?
			assert inode.size() == u64(42 + group)
			store16(data, 120, 1)
			if _ := inode.read_entry(mut fs, u32(group * 16 + 1)) { assert false }
			store16(data, 120, 0)
		}
		mut inode := EXT2Inode{}
		if _ := inode.read_entry(mut fs, 0) { assert false }
		if stride == 64 {
			store32(unsafe { &fs.disk[4096] }, 40, 1) // inode table high word
			if _ := inode.read_entry(mut fs, 1) { assert false }
		}
		assert fs.writes == 0
		fs.close()
	}
}
