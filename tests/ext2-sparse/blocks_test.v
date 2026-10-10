module ext2

#flag -Dvinix_stack_alloc=__builtin_alloca
fn C.vinix_stack_alloc(bytes u64) voidptr

const ext2_feature_ro_compat_large_file = u32(2)
struct EXT2Superblock { mut: version_maj u32 = 1 non_supported_features u32 }
struct EXT2Inode {
mut:
	permissions u16 = 0x8180
	size32l u32
	size32h u32
	eab u32
	sector_cnt u32
	blocks [15]u32
	mod_time u32
	creation_time u32
}
struct TestCache { mut: fs &EXT2Filesystem = unsafe { nil } }
struct EXT2Filesystem {
mut:
	block_size u64
	superblock &EXT2Superblock = &EXT2Superblock{}
	cache TestCache
	journal voidptr
	backing_device voidptr
	disk []u8
	allocated [256]bool
	next u32 = 10
	allocations int
	alloc_fail_at int
	reads int
	read_fail_at int
	writes int
	write_fail_at int
	entries int
	entry_fail_at int
	stored EXT2Inode
	free_calls int
	feature_fail bool
	cache_fail bool
	barrier_fail bool
	order string
	last_read u64
	high_value u32
}
fn fixture(block_size u64) &EXT2Filesystem {
	mut fs := &EXT2Filesystem{ block_size: block_size, disk: []u8{len: int(block_size * 256)} }
	fs.cache.fs = fs
	fs.backing_device = fs
	return fs
}
fn (mut fs EXT2Filesystem) checkpoint_cleanup(mut _inode EXT2Inode) ? {}
fn (mut fs EXT2Filesystem) allocate_block() ?u32 {
	fs.allocations++
	if fs.allocations == fs.alloc_fail_at { return none }
	b := fs.next
	fs.next++
	assert b < 256 && !fs.allocated[b]
	fs.allocated[b] = true
	unsafe { C.memset(&fs.disk[u64(b) * fs.block_size], 0, fs.block_size) }
	return b
}
fn (mut fs EXT2Filesystem) free_block(block u32) ?int {
	assert fs.allocated[block], 'double free of block ${block}'
	fs.allocated[block] = false
	fs.free_calls++
	return 0
}
fn (mut fs EXT2Filesystem) raw_device_read(buf voidptr, location u64, count u64) ?i64 {
	fs.reads++
	fs.last_read = location
	if fs.reads == fs.read_fail_at { return none }
	if location >= u64(fs.disk.len) {
		assert count == 4
		unsafe { C.memcpy(buf, &fs.high_value, 4) }
	} else {
		assert location + count <= u64(fs.disk.len)
		unsafe { C.memcpy(buf, &fs.disk[location], count) }
	}
	return i64(count)
}
fn (mut fs EXT2Filesystem) raw_device_write(buf voidptr, location u64, count u64) ?i64 {
	fs.writes++
	if fs.writes == fs.write_fail_at { return none }
	assert location + count <= u64(fs.disk.len)
	unsafe { C.memcpy(&fs.disk[location], buf, count) }
	return i64(count)
}
fn (mut inode EXT2Inode) write_entry(mut fs EXT2Filesystem, _index u32) ?int {
	fs.entries++
	if fs.entries == fs.entry_fail_at { return none }
	if inode.size() > 0x7fffffff { assert fs.superblock.non_supported_features & 2 != 0 }
	fs.stored = *inode
	return 0
}
fn (mut fs EXT2Filesystem) write_superblock() ? {
	fs.order += 'feature '
	if fs.feature_fail { return none }
}
fn (mut cache TestCache) sync(_context voidptr, _callback fn (voidptr, voidptr, u64, u64) ?i64) ? {
	cache.fs.order += 'cache '
	if cache.fs.cache_fail { return none }
}
fn device_write(_context voidptr, _buf voidptr, _loc u64, count u64) ?i64 { return i64(count) }
fn device_flush(context voidptr) ? {
	mut fs := unsafe { &EXT2Filesystem(context) }
	fs.order += 'barrier '
	if fs.barrier_fail { return none }
}
fn ext2_now() u32 { return 123 }
fn (fs &EXT2Filesystem) live() int {
	mut result := 0
	for b in fs.allocated { if b { result++ } }
	return result
}
fn (fs &EXT2Filesystem) close() { unsafe { fs.disk.free(); free(fs.superblock); free(fs) } }

fn test_size_high_word_is_regular_only_and_sparse_growth_is_bounded() {
	mut fs := fixture(4096)
	defer { fs.close() }
	mut inode := EXT2Inode{}
	size := u64(3) << 40
	assert inode.resize(mut fs, 1, 0, size)? == 0
	assert inode.size() == size && inode.size32h == 768
	assert fs.order == 'feature cache barrier '
	assert fs.live() == 0 && fs.reads == 0 && fs.writes == 0 && inode.sector_cnt == 0
	inode.permissions = 0x4000
	assert inode.size() == u64(inode.size32l)
	if _ := inode.resize(mut fs, 1, 0, u64(1) << 32) { assert false }
	assert fs.live() == 0
}

fn test_inline_symlink_with_xattr_block_reads_inline_bytes() {
	for block_size in [u64(1024), 4096] {
		mut fs := fixture(block_size)
		mut inode := EXT2Inode{
			permissions: 0xa1ff
			size32l: 5
			eab: 42
			sector_cnt: u32(block_size / 512)
		}
		target := [u8(`/`), `l`, `i`, `n`, `k`]!
		unsafe { C.memcpy(&inode.blocks[0], &target[0], target.len) }
		mut output := [8]u8{init: 0xff}
		assert inode.read(mut fs, unsafe { &output[0] }, 2, u64(output.len))? == 3
		assert output[0] == `i` && output[1] == `n` && output[2] == `k`
		assert output[3] == 0xff && fs.reads == 0 && fs.live() == 0
		fs.close()
	}
}

fn test_large_file_feature_failure_and_capacity_leave_inode_unchanged() {
	for failure in 0 .. 3 {
		mut fs := fixture(4096)
		mut inode := EXT2Inode{}
		fs.feature_fail = failure == 0
		fs.cache_fail = failure == 1
		fs.barrier_fail = failure == 2
		if _ := inode.resize(mut fs, 1, 0, u64(1) << 32) { assert false }
		assert inode.size() == 0 && fs.superblock.non_supported_features == 0 && fs.entries == 0
		fs.feature_fail = false; fs.cache_fail = false; fs.barrier_fail = false
		assert inode.resize(mut fs, 1, 0, u64(1) << 32)? == 0
		if _ := inode.resize(mut fs, 1, 0, fs.file_capacity() + 1) { assert false }
		if _ := inode.resize(mut fs, 1, u64(-1), 2) { assert false }
		assert inode.size() == u64(1) << 32
		fs.close()
	}
}

fn test_sparse_paths_holes_high_offsets_and_all_indirect_cleanup() {
	for block_size in [u64(1024), 4096] {
		mut fs := fixture(block_size)
		mut inode := EXT2Inode{}
		p := block_size / 4
		positions := [u64(11), 12, 12 + p - 1, 12 + p, 12 + p + p*p - 1,
			12 + p + p*p, 12 + p + p*p + p*p + 2*p + 3]
		bytes := [u8(0x71), 0x92, 0x53]!
		for position in positions {
			assert inode.write(mut fs, unsafe { &bytes[0] }, 1, position * block_size + 17, 3)? == 3
			mut observed := [32]u8{}
			assert inode.read(mut fs, unsafe { &observed[0] }, position * block_size, 20)? == 20
			for i in 0 .. 17 { assert observed[i] == 0 }
			assert observed[17] == 0x71 && observed[18] == 0x92 && observed[19] == 0x53
		}
		assert inode.sector_cnt == u32(fs.live()) * u32(block_size / 512)
		mut hole := [32]u8{init: 0xff}
		assert inode.read(mut fs, unsafe { &hole[0] }, block_size * 3, 32)? == 32
		for byte in hole { assert byte == 0 }
		fs.reads = 0
		assert inode.resize(mut fs, 1, 0, (12 + p) * block_size + 20)? == 0
		assert fs.reads < 30
		assert inode.blocks[14] == 0
		assert inode.get_block(mut fs, u32(12 + p))? != 0
		fs.reads = 0
		assert inode.resize(mut fs, 1, 0, 0)? == 0
		assert fs.reads < 15 && fs.live() == 0 && inode.sector_cnt == 0
		for block in inode.blocks { assert block == 0 }
		fs.close()
	}
}

fn test_shrink_inside_block_clears_suffix_and_zero_write_does_not_grow() {
	mut fs := fixture(4096)
	defer { fs.close() }
	mut inode := EXT2Inode{}
	bytes := [64]u8{init: 0xcc}
	assert inode.write(mut fs, unsafe { &bytes[0] }, 1, 0, 64)? == 64
	assert inode.resize(mut fs, 1, 0, 17)? == 0
	assert inode.resize(mut fs, 1, 0, 64)? == 0
	mut observed := [64]u8{}
	assert inode.read(mut fs, unsafe { &observed[0] }, 0, 64)? == 64
	for i in 0 .. 64 { assert observed[i] == if i < 17 { u8(0xcc) } else { u8(0) } }
	assert inode.write(mut fs, unsafe { &bytes[0] }, 1, u64(-1), 0)? == 0
	assert inode.size() == 64 && fs.live() == 1
}

fn test_detached_allocation_and_write_failures_roll_back_all_blocks() {
	for failure in 1 .. 5 {
		mut fs := fixture(4096)
		fs.alloc_fail_at = failure
		mut inode := EXT2Inode{}
		byte := u8(0xd4)
		if _ := inode.write(mut fs, unsafe { &byte }, 1, u64(12 + 1024 + 1024*1024) * 4096, 1) { assert false }
		assert fs.live() == 0 && inode.sector_cnt == 0 && inode.blocks[14] == 0 && inode.size() == 0
		fs.close()
	}
	for failure in 1 .. 5 {
		mut fs := fixture(4096)
		fs.write_fail_at = failure
		mut inode := EXT2Inode{}
		byte := u8(0xd4)
		if _ := inode.write(mut fs, unsafe { &byte }, 1, u64(12 + 1024 + 1024*1024) * 4096, 1) { assert false }
		assert fs.live() == 0 && inode.sector_cnt == 0 && inode.blocks[14] == 0 && inode.size() == 0
		fs.close()
	}
	mut fs := fixture(4096)
	defer { fs.close() }
	fs.entry_fail_at = 1
	mut inode := EXT2Inode{}
	byte := u8(1)
	if _ := inode.write(mut fs, unsafe { &byte }, 1, u64(12 + 1024 + 1024*1024) * 4096, 1) { assert false }
	assert fs.live() == 0 && inode.sector_cnt == 0 && inode.blocks[14] == 0
}

fn test_failed_truncate_read_and_pointer_write_preserve_owned_storage_for_retry() {
	for fail_read in [true, false] {
		mut fs := fixture(4096)
		mut inode := EXT2Inode{}
		byte := u8(0x31)
		offset := u64(12 + 1024 + 1024*1024) * 4096
		assert inode.write(mut fs, unsafe { &byte }, 1, offset, 1)? == 1
		live := fs.live()
		if fail_read { fs.read_fail_at = fs.reads + 1 } else { fs.write_fail_at = fs.writes + 1 }
		if _ := inode.resize(mut fs, 1, 0, 0) { assert false }
		assert fs.live() == live && inode.sector_cnt == u32(live * 8) && inode.size() == offset + 1
		fs.read_fail_at = 0; fs.write_fail_at = 0
		assert inode.resize(mut fs, 1, 0, 0)? == 0
		assert fs.live() == 0 && inode.sector_cnt == 0
		fs.close()
	}
}

fn test_missing_children_of_existing_table_roll_back_without_dangling_pointers() {
	for failure in 1 .. 6 {
		mut fs := fixture(4096)
		mut inode := EXT2Inode{}
		byte := u8(0x61)
		first := u64(12 + 1024 + 1024*1024) * 4096
		second := first + u64(1024*1024) * 4096
		assert inode.write(mut fs, unsafe { &byte }, 1, first, 1)? == 1
		live, sectors, size := fs.live(), inode.sector_cnt, inode.size()
		fs.write_fail_at = fs.writes + failure
		if _ := inode.write(mut fs, unsafe { &byte }, 1, second, 1) { assert false }
		assert fs.live() == live && inode.sector_cnt == sectors && inode.size() == size
		assert inode.get_block(mut fs, u32(second / 4096))? == 0
		mut observed := u8(0)
		assert inode.read(mut fs, unsafe { &observed }, first, 1)? == 1 && observed == byte
		assert inode.resize(mut fs, 1, 0, 0)? == 0
		assert fs.live() == 0
		fs.close()
	}
}

fn test_failed_root_detach_retains_empty_table_until_retry() {
	mut fs := fixture(4096)
	defer { fs.close() }
	mut inode := EXT2Inode{}
	byte := u8(0x21)
	assert inode.write(mut fs, unsafe { &byte }, 1, 12*4096, 1)? == 1
	fs.entry_fail_at = fs.entries + 1
	if _ := inode.resize(mut fs, 1, 0, 0) { assert false }
	assert inode.blocks[12] != 0 && fs.allocated[inode.blocks[12]]
	assert fs.live() == 1 && inode.sector_cnt == 8
	assert fs.stored.sector_cnt == 8
	assert inode.resize(mut fs, 1, 0, 0)? == 0
	assert fs.live() == 0 && inode.sector_cnt == 0
}

fn test_missing_table_does_not_read_block_zero_and_physical_offsets_are_64_bit() {
	mut fs := fixture(4096)
	defer { fs.close() }
	mut inode := EXT2Inode{}
	assert inode.get_block(mut fs, 12)? == 0
	assert inode.get_block(mut fs, 12 + 1024)? == 0
	assert inode.get_block(mut fs, 12 + 1024 + 1024*1024)? == 0
	assert fs.reads == 0
	inode.blocks[12] = 0xfffffff1
	fs.high_value = 37
	assert inode.get_block(mut fs, 15)? == 37
	assert fs.last_read == u64(0xfffffff1) * 4096 + 12
	inode.sector_cnt = 0xfffffff8
	if _ := inode.allocate_accounted_block(mut fs) { assert false }
	assert fs.live() == 0
}

fn test_partial_write_commits_prefix_size_and_counters() {
	for fail_inode in [false, true] {
		mut fs := fixture(1024)
		defer { fs.close() }
		mut inode := EXT2Inode{}
		bytes := [2048]u8{init: 0xa7}
		// First data page + three triple-indirect tables, then a second page.
		if fail_inode { fs.entry_fail_at = 3 } else { fs.alloc_fail_at = 5 }
		assert inode.write(mut fs, unsafe { &bytes[0] }, 1, (u64(1) << 32), 2048)? == 1024
		assert inode.size() == (u64(1) << 32) + 1024
		assert fs.stored.size() == inode.size()
		assert fs.stored.sector_cnt == inode.sector_cnt
		assert fs.live() == 4 && inode.sector_cnt == 8
		assert inode.resize(mut fs, 1, 0, (u64(1) << 32) + 2048)? == 0
		mut suffix := [1024]u8{init: 0xff}
		assert inode.read(mut fs, unsafe { &suffix[0] }, (u64(1) << 32) + 1024, 1024)? == 1024
		for byte in suffix { assert byte == 0 }
		mut observed := [1024]u8{}
		assert inode.read(mut fs, unsafe { &observed[0] }, u64(1) << 32, 1024)? == 1024
		for byte in observed { assert byte == 0xa7 }
		assert inode.resize(mut fs, 1, 0, 0)? == 0
		assert fs.live() == 0 && inode.sector_cnt == 0
	}
}

fn test_failed_extending_inode_write_reports_visible_prefix_and_growth_zeros_hidden_tail() {
	mut fs := fixture(4096)
	defer { fs.close() }
	mut inode := EXT2Inode{}
	original := [64]u8{init: 0xcc}
	replacement := [64]u8{init: 0xa7}
	assert inode.write(mut fs, unsafe { &original[0] }, 1, 0, 64)? == 64
	fs.entry_fail_at = fs.entries + 1
	assert inode.write(mut fs, unsafe { &replacement[0] }, 1, 17, 64)? == 47
	assert inode.size() == 64 && fs.stored.size() == 64
	assert inode.resize(mut fs, 1, 0, 128)? == 0
	mut observed := [128]u8{}
	assert inode.read(mut fs, unsafe { &observed[0] }, 0, 128)? == 128
	for i in 0 .. 128 { assert observed[i] == if i < 17 { u8(0xcc) } else if i < 64 { u8(0xa7) } else { u8(0) } }
}
