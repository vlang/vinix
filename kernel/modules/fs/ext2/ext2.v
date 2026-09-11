module ext2

import stat
import klock
import resource as resource_mod
import lib
import event
import event.eventstruct
import memory
import fs as vfs
import pagecache
import katomic
import time
import errno
import memory.mmap as mmap_mod

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

	filesystem   &EXT2Filesystem
	mapped_pages []&EXT2MappedPage
}

fn (mut this EXT2Resource) mmap(_handle voidptr, page u64, flags int) voidptr {
	if !stat.isreg(this.stat.mode) || page > u64(-1) / page_size {
		return unsafe { nil }
	}
	this.l.acquire()
	defer { this.l.release() }
	this.filesystem.l.acquire()
	defer { this.filesystem.l.release() }

	offset := page * page_size
	file_size := u64(this.stat.size)
	if offset >= file_size {
		return unsafe { nil }
	}
	if flags & mmap_mod.map_shared != 0 {
		if mut cached := this.mapped_page_locked(page) {
			cached.refs++
			return cached.physical
		}
	}

	physical := memory.pmm_alloc_fallible(1)
	if physical == unsafe { nil } {
		errno.set(errno.enomem)
		return unsafe { nil }
	}
	mut inode := EXT2Inode{}
	inode.read_entry(mut this.filesystem, u32(this.stat.ino)) or {
		memory.pmm_free(physical, 1)
		return unsafe { nil }
	}
	count := if page_size < file_size - offset { page_size } else { file_size - offset }
	inode.read(mut this.filesystem, voidptr(u64(physical) + higher_half), offset, count) or {
		memory.pmm_free(physical, 1)
		return unsafe { nil }
	}
	if flags & mmap_mod.map_shared != 0 {
		this.mapped_pages << &EXT2MappedPage{
			page: page
			physical: physical
			refs: 1
		}
	}
	return physical
}

fn (mut this EXT2Resource) read(_handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	this.l.acquire()
	defer { this.l.release() }
	this.filesystem.l.acquire()
	defer { this.filesystem.l.release() }
	mut inode := EXT2Inode{}
	inode.read_entry(mut this.filesystem, u32(this.stat.ino))?
	file_size := u64(inode.size32l) | (u64(inode.size32h) << 32)
	if loc >= file_size || count == 0 {
		return 0
	}
	actual := if count < file_size - loc { count } else { file_size - loc }
	mut done := u64(0)
	for done < actual {
		offset := loc + done
		page := offset / page_size
		in_page := offset % page_size
		chunk := if actual - done < page_size - in_page {
			actual - done
		} else {
			page_size - in_page
		}
		if cached := this.mapped_page_locked(page) {
			unsafe {
				C.memcpy(voidptr(u64(buf) + done), voidptr(u64(cached.physical) + higher_half + in_page), chunk)
			}
		} else {
			read := inode.read(mut this.filesystem, voidptr(u64(buf) + done), offset, chunk)?
			if read != i64(chunk) {
				errno.set(errno.eio)
				return none
			}
		}
		done += chunk
	}
	return i64(actual)
}

fn (mut this EXT2Resource) write(_handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	this.l.acquire()
	defer { this.l.release() }
	this.filesystem.l.acquire()
	defer { this.filesystem.l.release() }
	mut current_inode := EXT2Inode{}

	current_inode.read_entry(mut this.filesystem, u32(this.stat.ino)) or { return none }
	written := current_inode.write(mut this.filesystem, buf, u32(this.stat.ino), loc, count)?
	mut done := u64(0)
	for done < u64(written) {
		offset := loc + done
		page := offset / page_size
		in_page := offset % page_size
		chunk := if u64(written) - done < page_size - in_page {
			u64(written) - done
		} else {
			page_size - in_page
		}
		if cached := this.mapped_page_locked(page) {
			unsafe {
				C.memcpy(voidptr(u64(cached.physical) + higher_half + in_page), voidptr(u64(buf) + done), chunk)
			}
		}
		done += chunk
	}
	this.stat.size = i64(u64(current_inode.size32l) | (u64(current_inode.size32h) << 32))
	this.stat.blocks = current_inode.sector_cnt
	this.stat.mtim = time.TimeSpec{i64(current_inode.mod_time), 0}
	this.stat.ctim = time.TimeSpec{i64(current_inode.creation_time), 0}
	return written
}

fn (mut this EXT2Resource) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource_mod.default_ioctl(handle, request, argp)
}

fn (mut this EXT2Resource) unref(handle voidptr) ? {
	if katomic.dec(mut &this.refcount) {
		// The VFS name owns one reference. Reaching it means the last open file
		// description closed; make ordinary buffered writes persistent.
		if this.refcount == 1 {
			this.sync(handle)?
		}
		return
	}
	if this.stat.nlink == 0 {
		this.filesystem.l.acquire()
		mut inode := EXT2Inode{}
		inode.read_entry(mut this.filesystem, u32(this.stat.ino)) or {
			this.refcount = 1
			this.filesystem.l.release()
			return none
		}
		inode.free_entry(mut this.filesystem, u32(this.stat.ino)) or {
			this.refcount = 1
			this.filesystem.l.release()
			return none
		}
		this.filesystem.flush() or {
			this.refcount = 1
			this.filesystem.l.release()
			return none
		}
		this.filesystem.l.release()
	}
	for mapped in this.mapped_pages {
		memory.pmm_free(mapped.physical, 1)
		unsafe { free(mapped) }
	}
	unsafe { this.mapped_pages.free() }
	memory.free(voidptr(this))
}

fn (mut this EXT2Resource) grow(handle voidptr, new_size u64) ? {
	this.l.acquire()
	this.filesystem.l.acquire()
	// Both failure paths below used to return with the lock still held, which
	// wedged every later access to the file.
	defer {
		this.filesystem.l.release()
		this.l.release()
	}

	mut current_inode := &EXT2Inode{}

	current_inode.read_entry(mut this.filesystem, u32(this.stat.ino)) or { return none }

	current_inode.resize(mut this.filesystem, u32(this.stat.ino), 0, new_size) or { return none }

	this.stat.size = i64(new_size)
	this.stat.blocks = current_inode.sector_cnt
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

	backing_device &vfs.VFSNode
	cache          &pagecache.Cache = unsafe { nil }
}

fn (mut this EXT2Filesystem) populate(node &vfs.VFSNode) {
	mut parent := &EXT2Inode{}
	parent.read_entry(mut this, u32(node.resource.stat.ino)) or { return }

	buffer := memory.calloc(parent.size32l, 1)
	if buffer == unsafe { nil } {
		return
	}
	defer { memory.free(buffer) }
	parent.read(mut this, buffer, 0, parent.size32l) or { return }

	for i := u32(0); i < parent.size32l;  {
		dir_entry := &EXT2DirectoryEntry(u64(buffer) + i)
		if dir_entry.entry_size < sizeof(EXT2DirectoryEntry)
			|| u32(dir_entry.entry_size) > parent.size32l - i {
			break
		}
		if dir_entry.inode_index == 0 {
			i += dir_entry.entry_size
			continue
		}

		name_buffer := memory.calloc(dir_entry.name_length + 1, 1)
		unsafe {
			C.memcpy(name_buffer, voidptr(u64(dir_entry) + sizeof(EXT2DirectoryEntry)), u64(dir_entry.name_length))
		}
		name := unsafe { tos(&u8(name_buffer), int(dir_entry.name_length)) }

		if name == '.' || name == '..' {
			memory.free(name_buffer)
			i += dir_entry.entry_size
			continue
		}

		mut inode := &EXT2Inode{}
		inode.read_entry(mut this, dir_entry.inode_index) or { return }

		mut mode := inode.permissions

		match dir_entry.dir_type {
			1 {
				mode |= stat.ifreg
			}
			2 {
				mode |= stat.ifdir
			}
			3 {
				mode |= stat.ifchr
			}
			4 {
				mode |= stat.ifblk
			}
			5 {
				mode |= stat.ififo
			}
			6 {
				mode |= stat.ifsock
			}
			7 {
				mode |= stat.iflnk
			}
			else {}
		}

		mut vfs_node := vfs.create_node(this, node, name, stat.isdir(mode))
		mut resource := &EXT2Resource{
			filesystem: unsafe { this }
			refcount: 1
		}

		resource.stat.mode = mode
		resource.stat.uid = inode.user_id
		resource.stat.gid = inode.group_id
		resource.stat.ino = dir_entry.inode_index
		resource.stat.size = u64(inode.size32l) | (u64(inode.size32h) << 32)
		resource.stat.nlink = inode.hard_link_cnt
		resource.stat.blksize = this.block_size
		resource.stat.blocks = lib.div_roundup(resource.stat.size, resource.stat.blksize)

		resource.stat.atim = time.TimeSpec{i64(inode.access_time), 0}
		resource.stat.ctim = time.TimeSpec{i64(inode.creation_time), 0}
		resource.stat.mtim = time.TimeSpec{i64(inode.mod_time), 0}
		resource.can_mmap = stat.isreg(mode)

		vfs_node.resource = resource
		if stat.islnk(mode) && inode.size32l != 0 {
			target_buffer := memory.calloc(u64(inode.size32l) + 1, 1)
			if target_buffer != unsafe { nil } {
				inode.read(mut this, target_buffer, 0, inode.size32l) or {}
				vfs_node.symlink_target = unsafe {
					tos(&u8(target_buffer), int(inode.size32l)).clone()
				}
				memory.free(target_buffer)
			}
		}

		unsafe {
			vfs_node.parent.children[name] = vfs_node
		}
		if stat.isdir(mode) && name != '.' && name != '..' {
			vfs_node.create_dotentries(node)
			this.populate(vfs_node)
		}
		i += dir_entry.entry_size
	}

	memory.free(buffer)
}

fn (mut bro EXT2Filesystem) instantiate() &vfs.FileSystem {
	mut this := &EXT2Filesystem{
		backing_device: bro.backing_device
		superblock: bro.superblock
		root_inode: bro.root_inode
		cache: bro.cache
	}

	this.block_size = 1024 << this.superblock.block_size
	this.frag_size = 1024 << this.superblock.frag_size
	this.bgd_cnt = lib.div_roundup(this.superblock.block_cnt, this.superblock.blocks_per_group)

	print('ext2: filesystem detected on device ${vfs.pathname(this.backing_device)}\n')
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

fn (mut this EXT2Filesystem) symlink(parent &vfs.VFSNode, dest string, target string) &vfs.VFSNode {
	return this.create_persistent(parent, target, stat.iflnk | 0o777, dest)
}

fn (mut this EXT2Filesystem) rename(old_parent &vfs.VFSNode, old_name string,
	new_parent &vfs.VFSNode, new_name string, flags int) ? {
	this.rename_persistent(old_parent, old_name, new_parent, new_name, flags)?
}

fn (mut this EXT2Filesystem) create(parent &vfs.VFSNode, name string, mode u32) &vfs.VFSNode {
	return this.create_persistent(parent, name, mode, '')
}

fn (mut this EXT2Filesystem) link(parent &vfs.VFSNode, path string, mut old_node vfs.VFSNode) ?&vfs.VFSNode {
	return this.link_persistent(parent, path, mut old_node)
}

fn (mut this EXT2Filesystem) mount(parent &vfs.VFSNode, name string, source &vfs.VFSNode) ?&vfs.VFSNode {
	this.dev_id = resource_mod.create_dev_id()

	mut target := vfs.create_node(this, parent, name, true)

	mut resource := &EXT2Resource{
		filesystem: unsafe { this }
		refcount: 1
	}

	resource.stat.size = u64(this.root_inode.size32l) | (u64(this.root_inode.size32h) << 32)
	resource.stat.blksize = this.block_size
	resource.stat.blocks = lib.div_roundup(resource.stat.size, resource.stat.blksize)
	resource.stat.dev = this.dev_id
	resource.stat.mode = this.root_inode.permissions
	resource.stat.uid = this.root_inode.user_id
	resource.stat.gid = this.root_inode.group_id
	resource.stat.nlink = this.root_inode.hard_link_cnt
	resource.stat.ino = 2

	resource.stat.atim = time.TimeSpec{i64(this.root_inode.access_time), 0}
	resource.stat.ctim = time.TimeSpec{i64(this.root_inode.creation_time), 0}
	resource.stat.mtim = time.TimeSpec{i64(this.root_inode.mod_time), 0}

	target.filesystem = unsafe { this }
	target.resource = resource

	this.populate(target)

	return target
}

fn (mut inode EXT2Inode) read(mut filesystem EXT2Filesystem, buf voidptr, off u64, cnt u64) ?i64 {
	mut count := cnt

	if off > inode.size32l {
		return 0
	}

	if (off + count) > inode.size32l {
		count = inode.size32l - off
	}

	for headway := u64(0); headway < count;  {
		iblock := (off + headway) / filesystem.block_size

		mut size := count - headway
		offset := (off + headway) % filesystem.block_size

		if size > (filesystem.block_size - offset) {
			size = filesystem.block_size - offset
		}

		disk_block := inode.get_block(mut filesystem, u32(iblock)) or { return none }
		if disk_block == 0 {
			unsafe { C.memset(voidptr(u64(buf) + headway), 0, size) }
		} else {
			filesystem.raw_device_read(voidptr(u64(buf) + headway), disk_block * filesystem.block_size + offset, size) or { return none }
		}

		headway += size
	}

	return i64(count)
}

fn (mut inode EXT2Inode) resize(mut filesystem EXT2Filesystem, inode_index u32, start u64, cnt u64) ?int {
	sector_size := filesystem.backing_device.resource.stat.blksize
	if start > u64(0xffffffff) || cnt > u64(0xffffffff) - start {
		errno.set(errno.efbig)
		return none
	}
	new_size := start + cnt
	old_blocks := lib.div_roundup(u64(inode.size32l), filesystem.block_size)
	new_blocks := lib.div_roundup(new_size, filesystem.block_size)
	if new_blocks < old_blocks {
		for i := new_blocks; i < old_blocks; i++ {
			disk_block := inode.get_block(mut filesystem, u32(i)) or { return none }
			if disk_block != 0 {
				filesystem.free_block(disk_block)?
				inode.set_block(mut filesystem, inode_index, u32(i), 0)?
				sectors := u32(filesystem.block_size / sector_size)
				inode.sector_cnt = if inode.sector_cnt >= sectors {
					inode.sector_cnt - sectors
				} else {
					0
				}
			}
		}
		if new_size != 0 && new_size % filesystem.block_size != 0 {
			disk_block := inode.get_block(mut filesystem, u32(new_size / filesystem.block_size))?
			if disk_block != 0 {
				tail_offset := new_size % filesystem.block_size
				tail_size := filesystem.block_size - tail_offset
				zero := memory.calloc(tail_size, 1)
				if zero == unsafe { nil } {
					errno.set(errno.enomem)
					return none
				}
				filesystem.raw_device_write(zero, u64(disk_block) * filesystem.block_size + tail_offset, tail_size) or {
					memory.free(zero)
					return none
				}
				memory.free(zero)
			}
		}
	} else if new_blocks > old_blocks {
		for i := old_blocks; i < new_blocks; i++ {
			if inode.get_block(mut filesystem, u32(i)) or { u32(0) } != 0 {
				continue
			}
			disk_block := filesystem.allocate_block() or { return none }
			inode.set_block(mut filesystem, inode_index, u32(i), disk_block) or {
				filesystem.free_block(disk_block) or {}
				return none
			}
			inode.sector_cnt += u32(filesystem.block_size / sector_size)
		}
	}
	inode.size32l = u32(new_size)
	inode.size32h = 0

	inode.write_entry(mut filesystem, inode_index) or { return none }

	return 0
}

fn (mut inode EXT2Inode) write(mut filesystem EXT2Filesystem, buf voidptr, inode_index u32, off u64, cnt u64) ?i64 {
	if off > u64(0xffffffff) || cnt > u64(0xffffffff) - off {
		errno.set(errno.efbig)
		return none
	}
	end := off + cnt
	if end > u64(inode.size32l) {
		inode.resize(mut filesystem, inode_index, 0, end) or { return none }
	}

	for headway := u64(0); headway < cnt;  {
		iblock := (off + headway) / filesystem.block_size

		mut size := cnt - headway
		offset := (off + headway) % filesystem.block_size

		if size > (filesystem.block_size - offset) {
			size = filesystem.block_size - offset
		}

		disk_block := inode.get_block(mut filesystem, u32(iblock)) or { return none }

		filesystem.raw_device_write(voidptr(u64(buf) + headway), disk_block * filesystem.block_size + offset, size) or { return none }

		headway += size
	}
	inode.mod_time = ext2_now()
	inode.creation_time = inode.mod_time
	inode.write_entry(mut filesystem, inode_index)?

	return i64(cnt)
}

fn (mut inode EXT2Inode) free_entry(mut filesystem EXT2Filesystem, inode_index u32) ?int {
	for i := u64(0); i < lib.div_roundup(u64(inode.size32l), filesystem.block_size); i++ {
		block_index := inode.get_block(mut filesystem, u32(i)) or { return none }
		if block_index != 0 {
			filesystem.free_block(block_index) or { return none }
			inode.set_block(mut filesystem, inode_index, u32(i), 0) or { return none }
		}
	}
	inode.size32l = 0
	inode.size32h = 0
	inode.sector_cnt = 0
	inode.permissions = 0
	inode.hard_link_cnt = 0
	inode.write_entry(mut filesystem, inode_index)?
	filesystem.free_inode(inode_index) or { return none }

	return 0
}

fn (mut inode EXT2Inode) set_block(mut filesystem EXT2Filesystem, inode_index u32, iblock u32, disk_block u32) ?u32 {
	mut block := iblock
	blocks_per_level := u32(filesystem.block_size / 4)

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
				inode.blocks[14] = filesystem.allocate_block() or { return none }

				inode.write_entry(mut filesystem, inode_index) or { return none }
			}

			filesystem.raw_device_read(voidptr(&single_indirect_index), inode.blocks[14] * filesystem.block_size + double_indirect_index * 4, 4) or { return none }

			if single_indirect_index == 0 {
				new_block := filesystem.allocate_block() or { return none }

				filesystem.raw_device_write(voidptr(&new_block), inode.blocks[14] * filesystem.block_size + double_indirect_index * 4, 4) or { return none }

				single_indirect_index = new_block
			}

			filesystem.raw_device_read(voidptr(&indirect_block), double_indirect_index * filesystem.block_size + single_indirect_index * 4, 4) or { return none }

			if indirect_block == 0 {
				new_block := filesystem.allocate_block() or { return none }

				filesystem.raw_device_write(voidptr(&indirect_block), double_indirect_index * filesystem.block_size + single_indirect_index * 4, 4) or { return none }

				indirect_block = new_block
			}

			filesystem.raw_device_write(voidptr(&disk_block), indirect_block * filesystem.block_size + indirect_offset * 4, 4) or { return none }

			return disk_block
		}

		if inode.blocks[13] == 0 {
			inode.blocks[13] = filesystem.allocate_block() or { return none }

			inode.write_entry(mut filesystem, inode_index) or { return none }
		}

		filesystem.raw_device_read(voidptr(&indirect_block), inode.blocks[13] * filesystem.block_size + single_index * 4, 4) or { return none }

		if indirect_block == 0 {
			new_block := filesystem.allocate_block() or { return none }

			filesystem.raw_device_write(voidptr(&new_block), inode.blocks[13] * filesystem.block_size + single_index * 4, 4) or { return none }

			indirect_block = new_block
		}

		filesystem.raw_device_write(voidptr(&disk_block), indirect_block * filesystem.block_size + indirect_offset * 4, 4) or { return none }

		return disk_block
	} else {
		if inode.blocks[12] == 0 {
			inode.blocks[12] = filesystem.allocate_block() or { return none }

			inode.write_entry(mut filesystem, inode_index) or { return none }
		}

		filesystem.raw_device_write(voidptr(&disk_block), inode.blocks[12] * filesystem.block_size + block * 4, 4) or { return none }
	}

	return disk_block
}

fn (mut inode EXT2Inode) get_block(mut filesystem EXT2Filesystem, iblock u32) ?u32 {
	mut disk_block_index := u32(0)
	mut block := iblock
	blocks_per_level := u32(filesystem.block_size / 4)

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

			filesystem.raw_device_read(voidptr(&single_indirect_index), inode.blocks[14] * filesystem.block_size + double_indirect_index * 4, 4) or { return none }

			filesystem.raw_device_read(voidptr(&indirect_block), double_indirect_index * filesystem.block_size + single_indirect_index * 4, 4) or { return none }

			filesystem.raw_device_read(voidptr(&disk_block_index), indirect_block * filesystem.block_size + indirect_offset * 4, 4) or { return none }

			return disk_block_index
		}

		filesystem.raw_device_read(voidptr(&indirect_block), inode.blocks[13] * filesystem.block_size + single_index * 4, 4) or { return none }

		filesystem.raw_device_read(voidptr(&disk_block_index), indirect_block * filesystem.block_size + indirect_offset * 4, 4) or { return none }

		return disk_block_index
	}

	filesystem.raw_device_read(voidptr(&disk_block_index), inode.blocks[12] * filesystem.block_size + block * 4, 4) or { return none }

	return disk_block_index
}

fn (mut filesystem EXT2Filesystem) allocate_block() ?u32 {
	mut bgd := &EXT2BlockGroupDescriptor{}

	for i := u32(0); i < filesystem.bgd_cnt; i++ {
		bgd.read_entry(mut filesystem, i)

		block_index := bgd.allocate_block(mut filesystem, i) or { continue }

		absolute := u32(block_index + i * filesystem.superblock.blocks_per_group + filesystem.superblock.sb_block)
		zero := memory.calloc(filesystem.block_size, 1)
		if zero == unsafe { nil } {
			filesystem.free_block(absolute) or {}
			errno.set(errno.enomem)
			return none
		}
		filesystem.raw_device_write(zero, u64(absolute) * filesystem.block_size, filesystem.block_size) or {
			memory.free(zero)
			filesystem.free_block(absolute) or {}
			return none
		}
		memory.free(zero)
		return absolute
	}

	return none
}

fn (mut filesystem EXT2Filesystem) allocate_inode() ?u64 {
	mut bgd := &EXT2BlockGroupDescriptor{}

	for i := u32(0); i < filesystem.bgd_cnt; i++ {
		bgd.read_entry(mut filesystem, i)

		inode_index := bgd.allocate_inode(mut filesystem, i) or { continue }

		return inode_index + i * filesystem.superblock.inodes_per_group + 1
	}

	return none
}

fn (mut filesystem EXT2Filesystem) free_block(block u32) ?int {
	if block < filesystem.superblock.sb_block {
		errno.set(errno.eio)
		return none
	}
	relative := block - filesystem.superblock.sb_block
	bgd_index := relative / filesystem.superblock.blocks_per_group
	bitmap_index := relative % filesystem.superblock.blocks_per_group
	bitmap := memory.calloc(filesystem.block_size, 1)

	mut bgd := &EXT2BlockGroupDescriptor{}
	bgd.read_entry(mut filesystem, bgd_index)

	filesystem.raw_device_read(bitmap, bgd.block_addr_bitmap * filesystem.block_size, filesystem.block_size) or {
		print('ext2: unable to read bgd bitmap\n')
		return none
	}

	if lib.bittest(bitmap, bitmap_index) == false {
		memory.free(bitmap)
		return 0
	}

	lib.bitreset(bitmap, bitmap_index)

	filesystem.raw_device_write(bitmap, bgd.block_addr_bitmap * filesystem.block_size, filesystem.block_size) or {
		print('ext2: unable to write bgd bitmap\n')
		return none
	}

	bgd.unallocated_blocks++
	bgd.write_entry(mut filesystem, bgd_index)
	filesystem.superblock.unallocated_blocks++
	filesystem.write_superblock()?

	memory.free(bitmap)

	return 0
}

fn (mut filesystem EXT2Filesystem) free_inode(inode u32) ?int {
	if inode == 0 {
		errno.set(errno.eio)
		return none
	}
	bgd_index := (inode - 1) / filesystem.superblock.inodes_per_group
	bitmap_index := (inode - 1) % filesystem.superblock.inodes_per_group
	bitmap := memory.calloc(filesystem.block_size, 1)

	mut bgd := &EXT2BlockGroupDescriptor{}
	bgd.read_entry(mut filesystem, bgd_index)

	filesystem.raw_device_read(bitmap, bgd.block_addr_inode * filesystem.block_size, filesystem.block_size) or {
		print('ext2: unable to read inode bitmap\n')
		return none
	}

	if lib.bittest(bitmap, bitmap_index) == false {
		memory.free(bitmap)
		return 0
	}

	lib.bitreset(bitmap, bitmap_index)

	filesystem.raw_device_write(bitmap, bgd.block_addr_inode * filesystem.block_size, filesystem.block_size) or {
		print('ext2: unable to write inode bitmap\n')
		return none
	}

	bgd.unallocated_inodes++
	bgd.write_entry(mut filesystem, bgd_index)
	filesystem.superblock.unallocated_inodes++
	filesystem.write_superblock()?

	memory.free(bitmap)

	return 0
}

fn (mut bgd EXT2BlockGroupDescriptor) read_entry(mut filesystem EXT2Filesystem, bgd_index u32) int {
	mut bgd_offset := u64(0)

	if filesystem.block_size >= 2048 {
		bgd_offset = filesystem.block_size
	} else {
		bgd_offset = filesystem.block_size * 2
	}

	filesystem.raw_device_read(voidptr(&bgd), bgd_offset + sizeof(EXT2BlockGroupDescriptor) * bgd_index, sizeof(EXT2BlockGroupDescriptor)) or {
		print('ext2: unable to read bgd entry\n')
		return -1
	}

	return 0
}

fn (mut bgd EXT2BlockGroupDescriptor) write_entry(mut filesystem EXT2Filesystem, bgd_index u32) int {
	mut bgd_offset := u64(0)

	if filesystem.block_size >= 2048 {
		bgd_offset = filesystem.block_size
	} else {
		bgd_offset = filesystem.block_size * 2
	}

	filesystem.raw_device_write(voidptr(&bgd), bgd_offset + sizeof(EXT2BlockGroupDescriptor) * bgd_index, sizeof(EXT2BlockGroupDescriptor)) or {
		print('ext2: unable to read bgd entry\n')
		return -1
	}

	return 0
}

fn (mut bgd EXT2BlockGroupDescriptor) allocate_block(mut filesystem EXT2Filesystem, bgd_index u32) ?u64 {
	if bgd.unallocated_blocks == 0 {
		return none
	}

	bitmap := memory.calloc(filesystem.block_size, 1)

	filesystem.raw_device_read(bitmap, bgd.block_addr_bitmap * filesystem.block_size, filesystem.block_size) or {
		print('ext2: unable to read bgd bitmap\n')
		return none
	}

	mut group_blocks := u64(filesystem.superblock.blocks_per_group)
	group_start := u64(filesystem.superblock.sb_block) + u64(bgd_index) * group_blocks
	if group_start + group_blocks > filesystem.superblock.block_cnt {
		group_blocks = u64(filesystem.superblock.block_cnt) - group_start
	}
	for i := u64(0); i < group_blocks; i++ {
		if lib.bittest(bitmap, i) == false {
			lib.bitset(bitmap, i)

			filesystem.raw_device_write(bitmap, bgd.block_addr_bitmap * filesystem.block_size, filesystem.block_size) or {
				print('ext2: unable to write bgd bitmap\n')
				return none
			}

			bgd.unallocated_blocks--
			bgd.write_entry(mut filesystem, bgd_index)
			filesystem.superblock.unallocated_blocks--
			filesystem.write_superblock()?

			memory.free(bitmap)

			return i
		}
	}

	memory.free(bitmap)

	return none
}

fn (mut bgd EXT2BlockGroupDescriptor) allocate_inode(mut filesystem EXT2Filesystem, bgd_index u32) ?u64 {
	if bgd.unallocated_inodes == 0 {
		return none
	}

	bitmap := memory.calloc(filesystem.block_size, 1)

	filesystem.raw_device_read(bitmap, bgd.block_addr_inode * filesystem.block_size, filesystem.block_size) or {
		print('ext2: unable to read inode bitmap\n')
		return none
	}

	mut group_inodes := u64(filesystem.superblock.inodes_per_group)
	group_start := u64(bgd_index) * group_inodes
	if group_start + group_inodes > filesystem.superblock.inode_cnt {
		group_inodes = u64(filesystem.superblock.inode_cnt) - group_start
	}
	for i := u64(0); i < group_inodes; i++ {
		if lib.bittest(bitmap, i) == false {
			lib.bitset(bitmap, i)

			filesystem.raw_device_write(bitmap, bgd.block_addr_inode * filesystem.block_size, filesystem.block_size) or {
				print('ext2: unable to write inode bitmap\n')
				return none
			}

			bgd.unallocated_inodes--
			bgd.write_entry(mut filesystem, bgd_index)
			filesystem.superblock.unallocated_inodes--
			filesystem.write_superblock()?

			memory.free(bitmap)

			return i
		}
	}

	memory.free(bitmap)

	return none
}

fn (mut filesystem EXT2Filesystem) write_superblock() ? {
	filesystem.raw_device_write(filesystem.superblock, 1024, sizeof(EXT2Superblock))?
}

fn (mut inode EXT2Inode) read_entry(mut filesystem EXT2Filesystem, inode_index u32) ?int {
	inode_table_index := (inode_index - 1) % filesystem.superblock.inodes_per_group
	bgd_index := (inode_index - 1) / filesystem.superblock.inodes_per_group

	mut bgd := &EXT2BlockGroupDescriptor{}
	bgd.read_entry(mut filesystem, bgd_index)

	filesystem.raw_device_read(voidptr(&inode), bgd.inode_table_block * filesystem.block_size + filesystem.superblock.inode_size * inode_table_index, sizeof(EXT2Inode)) or {
		print('ext2: unable to read inode entry\n')
		return none
	}

	return 0
}

fn (mut inode EXT2Inode) write_entry(mut filesystem EXT2Filesystem, inode_index u32) ?int {
	inode_table_index := (inode_index - 1) % filesystem.superblock.inodes_per_group
	bgd_index := (inode_index - 1) / filesystem.superblock.inodes_per_group

	mut bgd := &EXT2BlockGroupDescriptor{}
	bgd.read_entry(mut filesystem, bgd_index)

	filesystem.raw_device_write(voidptr(&inode), bgd.inode_table_block * filesystem.block_size + filesystem.superblock.inode_size * inode_table_index, sizeof(EXT2Inode)) or {
		print('ext2: unable to read inode entry\n')
		return none
	}

	return 0
}

pub fn ext2_init(backing_device &vfs.VFSNode) (&EXT2Filesystem, bool) {
	sector_size := u64(backing_device.resource.stat.blksize)
	if sector_size == 0 || sector_size > pagecache.page_bytes
		|| pagecache.page_bytes % sector_size != 0 || backing_device.resource.stat.size < 2048
		|| u64(backing_device.resource.stat.size) % sector_size != 0 {
		return 0, false
	}
	mut new_filesystem := &EXT2Filesystem{
		backing_device: unsafe { backing_device }
		superblock: &EXT2Superblock{}
		root_inode: &EXT2Inode{}
		cache: &pagecache.Cache{}
	}

	// The EXT2 superblock is at byte 1024, regardless of device sector size.
	new_filesystem.raw_device_read(new_filesystem.superblock, 1024, sizeof(EXT2Superblock)) or {
		new_filesystem.cache.release(voidptr(backing_device.resource), device_write) or {}
		return 0, false
	}

	if new_filesystem.superblock.signature != 0xef53 {
		new_filesystem.cache.release(voidptr(backing_device.resource), device_write) or {}
		return 0, false
	}
	if !pagecache.register_cache(new_filesystem.cache) {
		new_filesystem.cache.release(voidptr(backing_device.resource), device_write) or {}
		return 0, false
	}

	return new_filesystem, true
}
