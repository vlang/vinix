// ext2.v: EXT2 driver.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module ext2

import stat
import klock
import resource
import lib
import event
import event.eventstruct
import memory
import fs

@[packed]
struct EXT2Superblock {
pub mut:
	inode_cnt          u32
	block_cnt          u32
	sb_reserved        u32
	unallocated_blocks u32
	unallocated_inodes u32
	sb_block           u32
	block_size         u32
	frag_size          u32
	blocks_per_group   u32
	frags_per_group    u32
	inodes_per_group   u32
	last_mnt_time      u32
	last_written_time  u32
	mnt_cnt            u16
	mnt_allowed        u16
	signature          u16
	fs_state           u16
	error_response     u16
	version_min        u16
	last_fsck          u32
	forced_fsck        u32
	os_id              u32
	version_maj        u32
	user_id            u16
	group_id           u16

	first_inode            u32
	inode_size             u16
	sb_bgd                 u16
	opt_features           u32
	req_features           u32
	non_supported_features u32
	uuid                   [2]u64
	volume_name            [2]u64
	last_mnt_path          [8]u64
}

@[packed]
struct EXT2BlockGroupDescriptor {
pub mut:
	block_addr_bitmap  u32
	block_addr_inode   u32
	inode_table_block  u32
	unallocated_blocks u16
	unallocated_inodes u16
	dir_cnt            u16
	reserved           [7]u16
}

@[packed]
struct EXT2Inode {
pub mut:
	permissions   u16
	user_id       u16
	size32l       u32
	access_time   u32
	creation_time u32
	mod_time      u32
	del_time      u32
	group_id      u16
	hard_link_cnt u16
	sector_cnt    u32
	flags         u32
	oss1          u32
	blocks        [15]u32
	gen_num       u32
	eab           u32
	size32h       u32
	frag_addr     u32
}

@[packed]
struct EXT2DirectoryEntry {
pub mut:
	inode_index u32
	entry_size  u16
	name_length u8
	dir_type    u8
}

struct EXT2Resource {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool

	filesystem &EXT2Filesystem
}

fn (mut this EXT2Resource) mmap(page u64, flags int) voidptr {
	return 0
}

fn (mut this EXT2Resource) read(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	mut current_inode := &EXT2Inode{}

	current_inode.read_entry(mut this.filesystem, u32(this.stat.ino)) or { return none }

	return current_inode.read(mut this.filesystem, buf, loc, count)
}

fn (mut this EXT2Resource) write(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	mut current_inode := &EXT2Inode{}

	current_inode.read_entry(mut this.filesystem, u32(this.stat.ino)) or { return none }

	return current_inode.write(mut this.filesystem, buf, u32(this.stat.ino), loc, count)
}

fn (mut this EXT2Resource) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this EXT2Resource) unref(handle voidptr) ? {
	this.refcount--
}

fn (mut this EXT2Resource) grow(handle voidptr, new_size u64) ? {
	this.l.acquire()

	mut current_inode := &EXT2Inode{}

	current_inode.read_entry(mut this.filesystem, u32(this.stat.ino)) or { return none }

	current_inode.resize(mut this.filesystem, u32(this.stat.ino), 0, new_size) or { return none }

	this.l.release()
}

struct EXT2Filesystem {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool

	dev_id u64

	superblock &EXT2Superblock
	root_inode &EXT2Inode

	block_size u64
	frag_size  u64
	bgd_cnt    u64

	backing_device &fs.VFSNode
}

fn (mut this EXT2Filesystem) populate(node &fs.VFSNode) {
	mut parent := &EXT2Inode{}
	parent.read_entry(mut this, u32(node.resource.stat.ino)) or { return }

	buffer := &voidptr(memory.calloc(parent.size32l, 1))
	parent.read(mut this, buffer, 0, parent.size32l) or { return }

	for i := u32(0); i < parent.size32l; {
		dir_entry := &EXT2DirectoryEntry(u64(buffer) + i)

		name_buffer := memory.calloc(dir_entry.name_length + 1, 1)
		unsafe {
			C.memcpy(name_buffer, voidptr(u64(dir_entry) + sizeof(EXT2DirectoryEntry)),
				u64(dir_entry.name_length))
		}
		name := unsafe { tos(&char(name_buffer), dir_entry.name_length) }

		if dir_entry.inode_index == 0 {
			memory.free(buffer)
			return
		}

		mut inode := &EXT2Inode{}
		inode.read_entry(mut this, dir_entry.inode_index) or { return }

		mut mode := u16(0)

		match dir_entry.dir_type {
			1 { mode |= stat.ifreg }
			2 { mode |= stat.ifdir }
			3 { mode |= stat.ifchr }
			4 { mode |= stat.ifblk }
			5 { mode |= stat.ififo }
			6 { mode |= stat.ifsock }
			7 { mode |= stat.iflnk }
			else {}
		}

		mut vfs_node := fs.create_node(this, node, name, stat.isdir(mode))
		mut resource := &EXT2Resource{
			filesystem: unsafe { this }
		}

		resource.stat.mode = 0o644 | mode
		resource.stat.ino = dir_entry.inode_index
		resource.stat.size = inode.size32l | (u64(inode.size32h) >> 32)
		resource.stat.nlink = inode.hard_link_cnt
		resource.stat.blksize = this.block_size
		resource.stat.blocks = lib.div_roundup(resource.stat.size, resource.stat.blksize)

		resource.stat.atim = realtime_clock
		resource.stat.ctim = realtime_clock
		resource.stat.mtim = realtime_clock

		vfs_node.resource = resource

		unsafe {
			vfs_node.parent.children[name] = vfs_node
		}
		i += dir_entry.entry_size
	}

	memory.free(buffer)
}

fn (mut bro EXT2Filesystem) instantiate() &fs.FileSystem {
	mut this := &EXT2Filesystem{
		backing_device: bro.backing_device
		superblock: bro.superblock
		root_inode: bro.root_inode
	}

	this.block_size = 1024 << this.superblock.block_size
	this.frag_size = 1024 << this.superblock.frag_size
	this.bgd_cnt = lib.div_roundup(this.superblock.block_cnt, this.superblock.blocks_per_group)

	print('ext2: filesystem detected on device ${fs.pathname(this.backing_device)}\n')
	print('ext2: inode count: ${this.superblock.inode_cnt}\n')
	print('ext2: inodes per group: ${this.superblock.inodes_per_group:x}\n')
	print('ext2: block count: ${this.superblock.block_cnt:x}\n')
	print('ext2: blocks per group: ${this.superblock.blocks_per_group:x}\n')
	print('ext2: block size: ${this.block_size:x}\n')
	print('ext2: bgd count: ${this.bgd_cnt:x}\n')

	this.root_inode.read_entry(mut this, 2) or {
		print('ext2: unable to read root inode\n')
		return this
	}

	return this
}

fn (mut this EXT2Filesystem) symlink(parent &fs.VFSNode, dest string, target string) &fs.VFSNode {
	mut new_node := fs.create_node(this, parent, target, false)

	mut resource := &EXT2Resource{
		filesystem: unsafe { this }
	}

	resource.stat.size = u64(target.len)
	resource.stat.blocks = 0
	resource.stat.blksize = 512
	resource.stat.dev = this.dev_id
	resource.stat.ino = parent.resource.stat.ino
	resource.stat.nlink = 1

	resource.stat.atim = realtime_clock
	resource.stat.ctim = realtime_clock
	resource.stat.mtim = realtime_clock

	new_node.symlink_target = dest
	new_node.resource = resource

	return new_node
}

fn (mut this EXT2Filesystem) create(parent &fs.VFSNode, name string, mode u32) &fs.VFSNode {
	mut new_node := fs.create_node(this, parent, name, stat.isdir(mode))

	mut resource := &EXT2Resource{
		filesystem: unsafe { this }
	}

	resource.stat.size = 0
	resource.stat.blocks = 0
	resource.stat.blksize = this.block_size
	resource.stat.dev = this.dev_id
	resource.stat.mode = mode
	resource.stat.nlink = 1

	resource.stat.atim = realtime_clock
	resource.stat.ctim = realtime_clock
	resource.stat.mtim = realtime_clock

	resource.stat.ino = this.allocate_inode() or { return 0 }

	mut parent_inode := &EXT2Inode{}
	parent_inode.read_entry(mut this, u32(parent.resource.stat.ino)) or { return 0 }

	mut file_type := 0

	if stat.isreg(mode) {
		file_type = 1
	} else if stat.isdir(mode) {
		file_type = 2
	} else if stat.ischr(mode) {
		file_type = 3
	} else if stat.isblk(mode) {
		file_type = 4
	} else if stat.isifo(mode) {
		file_type = 5
	} else if stat.issock(mode) {
		file_type = 6
	} else if stat.islnk(mode) {
		file_type = 7
	}

	this.dir_create_entry(mut parent_inode, u32(parent.resource.stat.ino), u32(resource.stat.ino),
		file_type, name) or { return 0 }

	new_node.resource = resource

	return new_node
}

fn (mut this EXT2Filesystem) mount(parent &fs.VFSNode, name string, source &fs.VFSNode) ?&fs.VFSNode {
	this.dev_id = resource.create_dev_id()

	mut target := fs.create_node(this, parent, name, true)

	mut resource := &EXT2Resource{
		filesystem: unsafe { this }
	}

	resource.stat.size = this.root_inode.size32l | (u64(this.root_inode.size32h) >> 32)
	resource.stat.blksize = this.block_size
	resource.stat.blocks = lib.div_roundup(resource.stat.size, resource.stat.blksize)
	resource.stat.dev = this.dev_id
	resource.stat.mode = 0o644 | stat.ifdir
	resource.stat.nlink = this.root_inode.hard_link_cnt
	resource.stat.ino = 2

	resource.stat.atim = realtime_clock
	resource.stat.ctim = realtime_clock
	resource.stat.mtim = realtime_clock

	target.filesystem = unsafe { this }
	target.resource = resource

	this.populate(target)

	return target
}

fn (mut fs EXT2Filesystem) dir_create_entry(mut parent EXT2Inode, parent_inode_index u32, new_inode u32, dir_type u8, name string) ?int {
	buffer := &voidptr(memory.calloc(parent.size32l, 1))
	parent.read(mut fs, buffer, 0, parent.size32l) or { return none }

	mut found := false

	for i := u32(0); i < parent.size32l; {
		mut dir_entry := &EXT2DirectoryEntry(u64(buffer) + i)

		if found == true {
			dir_entry.inode_index = new_inode
			dir_entry.dir_type = dir_type
			dir_entry.name_length = name.len
			dir_entry.entry_size = u16(parent.size32l - i)

			unsafe {
				C.memcpy(voidptr(u64(dir_entry) + sizeof(EXT2DirectoryEntry)), name.str,
					name.len)
			}

			parent.write(mut fs, buffer, parent_inode_index, 0, parent.size32l) or { return none }

			return 0
		}

		expected_size := lib.align_up(sizeof(EXT2DirectoryEntry) + dir_entry.name_length,
			4)
		if dir_entry.entry_size != expected_size {
			dir_entry.entry_size = u16(expected_size)
			i += u32(expected_size)

			found = true

			continue
		}

		i += dir_entry.entry_size
	}

	memory.free(buffer)

	return none
}

fn (mut inode EXT2Inode) read(mut fs &EXT2Filesystem, buf voidptr, off u64, cnt u64) ?i64 {
	mut count := cnt

	if off > inode.size32l {
		return 0
	}

	if (off + count) > inode.size32l {
		count = inode.size32l - off
	}

	for headway := u64(0); headway < count; {
		iblock := (off + headway) / fs.block_size

		mut size := count - headway
		offset := (off + headway) % fs.block_size

		if size > (fs.block_size - offset) {
			size = fs.block_size - offset
		}

		disk_block := inode.get_block(mut fs, u32(iblock)) or { return none }

		fs.raw_device_read(voidptr(u64(buf) + headway), disk_block * fs.block_size + offset,
			size) or { return none }

		headway += size
	}

	return i64(count)
}

fn (mut inode EXT2Inode) resize(mut fs &EXT2Filesystem, inode_index u32, start u64, cnt u64) ?int {
	sector_size := fs.backing_device.resource.stat.blksize

	if (start + cnt) < (inode.sector_cnt * sector_size) {
		return 0
	}

	iblock_start := lib.div_roundup(inode.sector_cnt * sector_size, fs.block_size)
	iblock_end := lib.div_roundup(start + cnt, fs.block_size)

	if inode.size32l < (start + cnt) {
		inode.size32l = u32(start + cnt)
	}

	for i := iblock_start; i < iblock_end; i++ {
		disk_block := fs.allocate_block() or { return none }

		inode.sector_cnt = u32(fs.block_size / sector_size)

		inode.set_block(mut fs, inode_index, u32(i), disk_block) or { return none }
	}

	inode.write_entry(mut fs, inode_index) or { return none }

	return 0
}

fn (mut inode EXT2Inode) write(mut fs &EXT2Filesystem, buf voidptr, inode_index u32, off u64, cnt u64) ?i64 {
	inode.resize(mut fs, inode_index, off, cnt) or { return none }

	for headway := u64(0); headway < cnt; {
		iblock := (off + headway) / fs.block_size

		mut size := cnt - headway
		offset := (off + headway) % fs.block_size

		if size > (fs.block_size - offset) {
			size = fs.block_size - offset
		}

		disk_block := inode.get_block(mut fs, u32(iblock)) or { return none }

		fs.raw_device_write(voidptr(u64(buf) + headway), disk_block * fs.block_size + offset,
			size) or { return none }

		headway += size
	}

	return i64(cnt)
}

fn (mut inode EXT2Inode) free_entry(mut fs &EXT2Filesystem, inode_index u32) ?int {
	for i := u64(0); i < lib.div_roundup(inode.sector_cnt * fs.backing_device.resource.stat.blksize,
		fs.block_size); i++ {
		block_index := inode.get_block(mut fs, u32(i)) or { return none }

		fs.free_block(block_index) or { return none }

		inode.set_block(mut fs, inode_index, u32(i), 0) or { return none }
	}

	fs.free_inode(inode_index) or { return none }

	return 0
}

fn (mut inode EXT2Inode) set_block(mut fs &EXT2Filesystem, inode_index u32, iblock u32, disk_block u32) ?u32 {
	mut block := iblock
	blocks_per_level := u32(fs.block_size / 4)

	if block < 12 {
		inode.blocks[block] = disk_block
		return disk_block
	}

	block -= 12

	if block >= blocks_per_level {
		block -= blocks_per_level

		single_index := block / blocks_per_level
		mut indirect_offset := block % blocks_per_level
		mut indirect_block := u32(0)

		if single_index >= blocks_per_level {
			block -= blocks_per_level * blocks_per_level

			double_indirect_index := block / blocks_per_level
			indirect_offset = block % blocks_per_level
			mut single_indirect_index := u32(0)

			if inode.blocks[14] == 0 {
				inode.blocks[14] = fs.allocate_block() or { return none }

				inode.write_entry(mut fs, inode_index) or { return none }
			}

			fs.raw_device_read(voidptr(&single_indirect_index), inode.blocks[14] * fs.block_size +
				double_indirect_index * 4, 4) or { return none }

			if single_indirect_index == 0 {
				new_block := fs.allocate_block() or { return none }

				fs.raw_device_write(voidptr(&new_block), inode.blocks[14] * fs.block_size +
					double_indirect_index * 4, 4) or { return none }

				single_indirect_index = new_block
			}

			fs.raw_device_read(voidptr(&indirect_block), double_indirect_index * fs.block_size +
				single_indirect_index * 4, 4) or { return none }

			if indirect_block == 0 {
				new_block := fs.allocate_block() or { return none }

				fs.raw_device_write(voidptr(&indirect_block),
					double_indirect_index * fs.block_size + single_indirect_index * 4,
					4) or { return none }

				indirect_block = new_block
			}

			fs.raw_device_write(voidptr(&disk_block), indirect_block * fs.block_size +
				indirect_offset * 4, 4) or { return none }

			return disk_block
		}

		if inode.blocks[13] == 0 {
			inode.blocks[13] = fs.allocate_block() or { return none }

			inode.write_entry(mut fs, inode_index) or { return none }
		}

		fs.raw_device_read(voidptr(&indirect_block), inode.blocks[13] * fs.block_size +
			single_index * 4, 4) or { return none }

		if indirect_block == 0 {
			new_block := fs.allocate_block() or { return none }

			fs.raw_device_write(voidptr(&new_block), inode.blocks[13] * fs.block_size +
				single_index * 4, 4) or { return none }

			indirect_block = new_block
		}

		fs.raw_device_write(voidptr(&disk_block), indirect_block * fs.block_size +
			indirect_offset * 4, 4) or { return none }

		return disk_block
	} else {
		if inode.blocks[12] == 0 {
			inode.blocks[12] = fs.allocate_block() or { return none }

			inode.write_entry(mut fs, inode_index) or { return none }
		}

		fs.raw_device_write(voidptr(&disk_block), inode.blocks[12] * fs.block_size + block * 4,
			4) or { return none }
	}

	return disk_block
}

fn (mut inode EXT2Inode) get_block(mut fs &EXT2Filesystem, iblock u32) ?u32 {
	mut disk_block_index := u32(0)
	mut block := iblock
	blocks_per_level := u32(fs.block_size / 4)

	if block < 12 {
		disk_block_index = inode.blocks[iblock]
		return disk_block_index
	}

	block -= 12

	if block >= blocks_per_level {
		block -= blocks_per_level

		single_index := block / blocks_per_level
		mut indirect_offset := block % blocks_per_level
		indirect_block := u32(0)

		if single_index >= blocks_per_level {
			block -= blocks_per_level * blocks_per_level

			double_indirect_index := block / blocks_per_level
			indirect_offset = block % blocks_per_level
			single_indirect_index := u32(0)

			fs.raw_device_read(voidptr(&single_indirect_index), inode.blocks[14] * fs.block_size +
				double_indirect_index * 4, 4) or { return none }

			fs.raw_device_read(voidptr(&indirect_block), double_indirect_index * fs.block_size +
				single_indirect_index * 4, 4) or { return none }

			fs.raw_device_read(voidptr(&disk_block_index), indirect_block * fs.block_size +
				indirect_offset * 4, 4) or { return none }

			return disk_block_index
		}

		fs.raw_device_read(voidptr(&indirect_block), inode.blocks[13] * fs.block_size +
			single_index * 4, 4) or { return none }

		fs.raw_device_read(voidptr(&disk_block_index), indirect_block * fs.block_size +
			indirect_offset * 4, 4) or { return none }

		return disk_block_index
	}

	fs.raw_device_read(voidptr(&disk_block_index), inode.blocks[12] * fs.block_size + block * 4,
		4) or { return none }

	return disk_block_index
}

fn (mut fs EXT2Filesystem) allocate_block() ?u32 {
	mut bgd := &EXT2BlockGroupDescriptor{}

	for i := u32(0); i < fs.bgd_cnt; i++ {
		bgd.read_entry(mut fs, i)

		block_index := bgd.allocate_block(mut fs, i) or { continue }

		return u32(block_index + i * fs.superblock.blocks_per_group)
	}

	return none
}

fn (mut fs EXT2Filesystem) allocate_inode() ?u64 {
	mut bgd := &EXT2BlockGroupDescriptor{}

	for i := u32(0); i < fs.bgd_cnt; i++ {
		bgd.read_entry(mut fs, i)

		inode_index := bgd.allocate_inode(mut fs, i) or { continue }

		return inode_index + i * fs.superblock.blocks_per_group
	}

	return none
}

fn (mut fs EXT2Filesystem) free_block(block u32) ?int {
	bgd_index := block / fs.superblock.blocks_per_group
	bitmap_index := block - bgd_index * fs.superblock.blocks_per_group
	bitmap := memory.calloc(lib.div_roundup(fs.block_size, u64(8)), 1)

	mut bgd := &EXT2BlockGroupDescriptor{}
	bgd.read_entry(mut fs, bgd_index)

	fs.raw_device_read(bitmap, bgd.block_addr_bitmap * fs.block_size, fs.block_size) or {
		print('ext2: unable to read bgd bitmap\n')
		return none
	}

	if lib.bittest(bitmap, bitmap_index) == false {
		memory.free(bitmap)
		return 0
	}

	lib.bitreset(bitmap, bitmap_index)

	fs.raw_device_write(bitmap, bgd.block_addr_bitmap * fs.block_size, fs.block_size) or {
		print('ext2: unable to write bgd bitmap\n')
		return none
	}

	bgd.unallocated_blocks++
	bgd.write_entry(mut fs, bgd_index)

	memory.free(bitmap)

	return 0
}

fn (mut fs EXT2Filesystem) free_inode(inode u32) ?int {
	bgd_index := inode / fs.superblock.inodes_per_group
	bitmap_index := inode - bgd_index * fs.superblock.inodes_per_group
	bitmap := memory.calloc(lib.div_roundup(fs.block_size, u64(8)), 1)

	mut bgd := &EXT2BlockGroupDescriptor{}
	bgd.read_entry(mut fs, bgd_index)

	fs.raw_device_read(bitmap, bgd.block_addr_inode * fs.block_size, fs.block_size) or {
		print('ext2: unable to read inode bitmap\n')
		return none
	}

	if lib.bittest(bitmap, bitmap_index) == false {
		memory.free(bitmap)
		return 0
	}

	lib.bitreset(bitmap, bitmap_index)

	fs.raw_device_write(bitmap, bgd.block_addr_inode * fs.block_size, fs.block_size) or {
		print('ext2: unable to write inode bitmap\n')
		return none
	}

	bgd.unallocated_inodes++
	bgd.write_entry(mut fs, bgd_index)

	memory.free(bitmap)

	return 0
}

fn (mut bgd EXT2BlockGroupDescriptor) read_entry(mut fs &EXT2Filesystem, bgd_index u32) int {
	mut bgd_offset := u64(0)

	if fs.block_size >= 2048 {
		bgd_offset = fs.block_size
	} else {
		bgd_offset = fs.block_size * 2
	}

	fs.raw_device_read(voidptr(&bgd), bgd_offset + sizeof(EXT2BlockGroupDescriptor) * bgd_index,
		sizeof(EXT2BlockGroupDescriptor)) or {
		print('ext2: unable to read bgd entry\n')
		return -1
	}

	return 0
}

fn (mut bgd EXT2BlockGroupDescriptor) write_entry(mut fs &EXT2Filesystem, bgd_index u32) int {
	mut bgd_offset := u64(0)

	if fs.block_size >= 2048 {
		bgd_offset = fs.block_size
	} else {
		bgd_offset = fs.block_size * 2
	}

	fs.raw_device_write(voidptr(&bgd), bgd_offset + sizeof(EXT2BlockGroupDescriptor) * bgd_index,
		sizeof(EXT2BlockGroupDescriptor)) or {
		print('ext2: unable to read bgd entry\n')
		return -1
	}

	return 0
}

fn (mut bgd EXT2BlockGroupDescriptor) allocate_block(mut fs &EXT2Filesystem, bgd_index u32) ?u64 {
	if bgd.unallocated_blocks == 0 {
		return none
	}

	bitmap := memory.calloc(lib.div_roundup(fs.block_size, u64(8)), 1)

	fs.raw_device_read(bitmap, bgd.block_addr_bitmap * fs.block_size, fs.block_size) or {
		print('ext2: unable to read bgd bitmap\n')
		return none
	}

	for i := u64(0); i < fs.block_size; i++ {
		if lib.bittest(bitmap, i) == false {
			lib.bitset(bitmap, i)

			fs.raw_device_write(bitmap, bgd.block_addr_bitmap * fs.block_size, fs.block_size) or {
				print('ext2: unable to write bgd bitmap\n')
				return none
			}

			bgd.unallocated_blocks--
			bgd.write_entry(mut fs, bgd_index)

			memory.free(bitmap)

			return i
		}
	}

	memory.free(bitmap)

	return -1
}

fn (mut bgd EXT2BlockGroupDescriptor) allocate_inode(mut fs &EXT2Filesystem, bgd_index u32) ?u64 {
	if bgd.unallocated_blocks == 0 {
		return none
	}

	bitmap := memory.calloc(lib.div_roundup(fs.block_size, u64(8)), 1)

	fs.raw_device_read(bitmap, bgd.block_addr_inode * fs.block_size, fs.block_size) or {
		print('ext2: unable to read inode bitmap\n')
		return none
	}

	for i := u64(0); i < fs.block_size; i++ {
		if lib.bittest(bitmap, i) == false {
			lib.bitset(bitmap, i)

			fs.raw_device_write(bitmap, bgd.block_addr_inode * fs.block_size, fs.block_size) or {
				print('ext2: unable to write inode bitmap\n')
				return none
			}

			bgd.unallocated_inodes--
			bgd.write_entry(mut fs, bgd_index)

			memory.free(bitmap)

			return i
		}
	}

	memory.free(bitmap)

	return -1
}

fn (mut inode EXT2Inode) read_entry(mut fs &EXT2Filesystem, inode_index u32) ?int {
	inode_table_index := (inode_index - 1) % fs.superblock.inodes_per_group
	bgd_index := (inode_index - 1) / fs.superblock.inodes_per_group

	mut bgd := &EXT2BlockGroupDescriptor{}
	bgd.read_entry(mut fs, bgd_index)

	fs.raw_device_read(voidptr(&inode), bgd.inode_table_block * fs.block_size +
		fs.superblock.inode_size * inode_table_index, sizeof(EXT2Inode)) or {
		print('ext2: unable to read inode entry\n')
		return none
	}

	return 0
}

fn (mut inode EXT2Inode) write_entry(mut fs &EXT2Filesystem, inode_index u32) ?int {
	inode_table_index := (inode_index - 1) % fs.superblock.inodes_per_group
	bgd_index := (inode_index - 1) / fs.superblock.inodes_per_group

	mut bgd := &EXT2BlockGroupDescriptor{}
	bgd.read_entry(mut fs, bgd_index)

	fs.raw_device_write(voidptr(&inode), bgd.inode_table_block * fs.block_size +
		fs.superblock.inode_size * inode_table_index, sizeof(EXT2Inode)) or {
		print('ext2: unable to read inode entry\n')
		return none
	}

	return 0
}

fn (mut fs EXT2Filesystem) raw_device_read(buf voidptr, loc u64, count u64) ?i64 {
	lba_size := fs.backing_device.resource.stat.blksize

	mut alignment := u64(0)
	if (loc & (lba_size - 1)) + count > lba_size {
		alignment = 0
	}

	lba_start := u64(loc / lba_size)
	lba_cnt := u64(lib.div_roundup(count, lba_size) + alignment)

	buffer := voidptr(u64(memory.pmm_alloc(lib.div_roundup(lba_cnt * lba_size, page_size))) +
		higher_half)

	fs.backing_device.resource.read(0, buffer, lba_start * lba_size, lba_cnt * lba_size) or {
		print('ext2: unable to read from device\n')
		return none
	}

	lba_offset := loc % lba_size

	unsafe { C.memcpy(buf, voidptr(u64(buffer) + lba_offset), count) }

	memory.pmm_free(voidptr(u64(buffer) - higher_half), lib.div_roundup(lba_cnt * lba_size,
		page_size))

	return i64(count)
}

fn (mut fs EXT2Filesystem) raw_device_write(buf voidptr, loc u64, count u64) ?i64 {
	lba_size := fs.backing_device.resource.stat.blksize

	mut alignment := u64(0)
	if (loc & (lba_size - 1)) + count > lba_size {
		alignment = 0
	}

	lba_start := u64(loc / lba_size)
	lba_cnt := u64(lib.div_roundup(count, lba_size) + alignment)

	buffer := voidptr(u64(memory.pmm_alloc(lib.div_roundup(lba_cnt * lba_size, page_size))) +
		higher_half)

	fs.backing_device.resource.read(0, buffer, lba_start * lba_size, lba_cnt * lba_size) or {
		print('ext2: unable to write from device\n')
		return none
	}

	lba_offset := loc % lba_size

	unsafe { C.memcpy(voidptr(u64(buffer) + lba_offset), buf, count) }

	fs.backing_device.resource.write(0, buffer, lba_start * lba_size, lba_cnt * lba_size) or {
		print('ext2: unable to read from device\n')
		return none
	}

	memory.pmm_free(voidptr(u64(buffer) - higher_half), lib.div_roundup(lba_cnt * lba_size,
		page_size))

	return i64(count)
}

pub fn ext2_init(backing_device &fs.VFSNode) (&EXT2Filesystem, bool) {
	mut new_filesystem := &EXT2Filesystem{
		backing_device: unsafe { backing_device }
		superblock: &EXT2Superblock{}
		root_inode: &EXT2Inode{}
	}

	new_filesystem.raw_device_read(new_filesystem.superblock, backing_device.resource.stat.blksize * 2,
		sizeof(EXT2Superblock)) or { return 0, false }

	if new_filesystem.superblock.signature != 0xef53 {
		return 0, false
	}

	return new_filesystem, true
}
