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
import file

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
	mapped_reclaim_cursor int
	mapped_previous &EXT2Resource = unsafe { nil }
	mapped_next     &EXT2Resource = unsafe { nil }
	mapped_serial   u64
	mapped_registered bool
	// chattr's immutable and append-only bits, the EXT2_*_FL on-disk flags of
	// the same value; see fs/attributes.v.
	attr_bits u32
	shared_mapping_ranges u64
	// The interface box its nodes and descriptors hold, made once and freed
	// with it; a box per conversion was 384 bytes nothing freed.
	box &resource_mod.Resource = unsafe { nil }
}

fn (mut this EXT2Resource) attribute_bits() u32 {
	return katomic.load(&this.attr_bits)
}

fn (mut this EXT2Resource) set_attribute_bits(bits u32) ? {
	this.l.acquire()
	defer { this.l.release() }
	if bits & resource_mod.attributes_kept != 0 && this.shared_mapping_ranges != 0 {
		errno.set(errno.ebusy)
		return none
	}
	new_bits := bits & resource_mod.attributes_kept
	this.filesystem.l.acquire()
	defer { this.filesystem.l.release() }
	mut inode := unsafe { &EXT2Inode(C.__builtin_alloca(sizeof(EXT2Inode))) }
	unsafe { C.memset(inode, 0, sizeof(EXT2Inode)) }
	inode.read_entry(mut this.filesystem, u32(this.stat.ino))?
	inode.flags = (inode.flags & ~resource_mod.attributes_kept) | new_bits
	inode.write_entry(mut this.filesystem, u32(this.stat.ino)) or {
		// A short/error completion may already have published the new bits.
		// Keep every possible protection until a successful retry resolves it.
		katomic.store(mut &this.attr_bits, this.attr_bits | new_bits)
		return none
	}
	katomic.store(mut &this.attr_bits, new_bits)
	flush_on_return()
}

fn (mut this EXT2Resource) retain_mapping_range(_handle voidptr, _offset u64, _length u64, flags int) bool {
	if flags & mmap_mod.map_shared == 0 { return true }
	this.l.acquire()
	defer { this.l.release() }
	if this.attr_bits & resource_mod.attributes_kept != 0 {
		errno.set(errno.eperm)
		return false
	}
	this.shared_mapping_ranges++
	return true
}

fn (mut this EXT2Resource) release_mapping_range(_handle voidptr, _offset u64, _length u64, flags int) {
	if flags & mmap_mod.map_shared == 0 { return }
	this.l.acquire()
	defer { this.l.release() }
	if this.shared_mapping_ranges == 0 {
		lib.kpanic(unsafe { nil }, c'ext2: shared mapping reference underflow')
		return
	}
	this.shared_mapping_ranges--
}

fn (mut this EXT2Resource) boxed() &resource_mod.Resource {
	if this.box == unsafe { nil } {
		this.box = &resource_mod.Resource(this) @[freed]
	}
	return this.box
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
	// A mapping may legitimately reach past the end of the file: a dynamic
	// loader maps one span covering every segment of an object, and the last
	// of them ends mid-page. Those pages read as zeroes here, exactly as they
	// do on tmpfs, which is what lets a shared library be loaded at all.
	//
	// A shared mapping is refused there instead, because folding it back into
	// the inode would grow the file by whatever the mapping happened to cover.
	if offset >= file_size && flags & mmap_mod.map_shared != 0 {
		return unsafe { nil }
	}
	if offset < file_size {
		if mut cached := this.mapped_page_locked(page) {
			if flags & mmap_mod.map_shared == 0 {
				if !memory.pmm_retain(cached.physical, 1) {
					errno.set(errno.enomem)
					return unsafe { nil }
				}
			} else {
				cached.refs++
			}
			return cached.physical
		}
	}

	// A page that stays for as long as it is mapped, so the mapping process'
	// to answer for, as an anonymous one is: not from the memory the kernel
	// keeps for itself, and counted when there is none (memory/reserve.v).
	physical := memory.pmm_alloc_user(1)
	if physical == unsafe { nil } {
		errno.set(errno.enomem)
		return unsafe { nil }
	}
	mut inode := unsafe { &EXT2Inode(C.vinix_stack_alloc(sizeof(EXT2Inode))) }
	unsafe { *inode = EXT2Inode{} }
	inode.read_entry(mut this.filesystem, u32(this.stat.ino)) or {
		memory.pmm_free(physical, 1)
		return unsafe { nil }
	}
	// The allocation is already zeroed, so a page wholly past the end of the
	// file needs no read at all, and a partial one is zero-filled past it.
	mut count := u64(0)
	if offset < file_size {
		count = if page_size < file_size - offset { page_size } else { file_size - offset }
	}
	if count != 0 {
		inode.read(mut this.filesystem, voidptr(u64(physical) + higher_half), offset,
			count) or {
			memory.pmm_free(physical, 1)
			return unsafe { nil }
		}
	}
	if offset < file_size {
		is_shared := flags & mmap_mod.map_shared != 0
		if !is_shared && !memory.pmm_retain(physical, 1) {
			memory.pmm_free(physical, 1)
			errno.set(errno.enomem)
			return unsafe { nil }
		}
		this.mapped_pages.flags |= .noslices
		this.mapped_pages << &EXT2MappedPage{
			page: page
			physical: physical
			refs: if is_shared { u64(1) } else { u64(0) }
		}
		this.register_mapped_resource()
	}
	return physical
}

fn (mut this EXT2Resource) read(_handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	this.l.acquire()
	defer { this.l.release() }
	this.filesystem.l.acquire()
	defer { this.filesystem.l.release() }
	mut inode := unsafe { &EXT2Inode(C.vinix_stack_alloc(sizeof(EXT2Inode))) }
	unsafe { *inode = EXT2Inode{} }
	inode.read_entry(mut this.filesystem, u32(this.stat.ino))?
	file_size := inode.size()
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
	return this.write_locked(_handle, buf, loc, count)
}

fn (mut this EXT2Resource) append_data(handle voidptr, buf voidptr, count u64, limit u64, end &u64) ?i64 {
	this.l.acquire()
	defer { this.l.release() }
	location := u64(this.stat.size)
	if count != 0 && location >= limit {
		errno.set(errno.efbig)
		return none
	}
	allowed := if count != 0 && count > limit - location { limit - location } else { count }
	written := this.write_locked(handle, buf, location, allowed)?
	unsafe { *end = location + u64(written) }
	return written
}

// Caller holds the resource lock through policy checks and data publication.
fn (mut this EXT2Resource) write_locked(_handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	append := _handle != unsafe { nil }
		&& unsafe { &file.Handle(_handle) }.flags & resource_mod.o_append != 0
	if this.attr_bits & resource_mod.attribute_immutable != 0
		|| (this.attr_bits & resource_mod.attribute_append != 0 && !append) {
		errno.set(errno.eperm)
		return none
	}
	write_at := if append { u64(this.stat.size) } else { loc }
	if count == 0 { return 0 }
	this.filesystem.l.acquire()
	defer { this.filesystem.l.release() }
	mut current_inode := unsafe { &EXT2Inode(C.vinix_stack_alloc(sizeof(EXT2Inode))) }
	unsafe { *current_inode = EXT2Inode{} }

	current_inode.read_entry(mut this.filesystem, u32(this.stat.ino)) or { return none }
	written := current_inode.write(mut this.filesystem, buf, u32(this.stat.ino), write_at, count)?
	// A writer far enough ahead of the device catches up before its call
	// returns, but not here, with EXT2's lock held.
	if this.filesystem.cache.over_dirty_limit() {
		flush_on_return()
	}
	mut done := u64(0)
	for done < u64(written) {
		offset := write_at + done
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
	this.stat.size = i64(current_inode.size())
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
		// description closed. A read-only close has written no data and must
		// not flush the entire filesystem cache: package installers close many
		// large input archives while other files still have dirty pages.
		// Compared one by one: `in` an array literal made the array on every
		// close.
		if this.refcount == 1 && handle != unsafe { nil } {
			access := unsafe { &file.Handle(handle) }.flags & resource_mod.o_accmode
			if access == resource_mod.o_wronly || access == resource_mod.o_rdwr {
				this.sync(handle)?
			}
		}
		return
	}
	if this.stat.nlink == 0 {
		this.filesystem.l.acquire()
		mut inode := unsafe { &EXT2Inode(C.vinix_stack_alloc(sizeof(EXT2Inode))) }
		unsafe { *inode = EXT2Inode{} }
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
		flush_on_return()
		this.filesystem.l.release()
	}
	for mapped in this.mapped_pages {
		memory.pmm_free(mapped.physical, 1)
		unsafe { free(mapped) }
	}
	unsafe { this.mapped_pages.free() }
	memory.free(voidptr(this.box))
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
	if this.attr_bits & resource_mod.attributes_kept != 0 {
		errno.set(errno.eperm)
		return none
	}

	mut current_inode := unsafe { &EXT2Inode(C.vinix_stack_alloc(sizeof(EXT2Inode))) }
	unsafe { *current_inode = EXT2Inode{} }

	current_inode.read_entry(mut this.filesystem, u32(this.stat.ino)) or { return none }

	old_size := current_inode.size()
	current_inode.resize(mut this.filesystem, u32(this.stat.ino), 0, new_size) or { return none }
	if new_size != old_size {
		// Truncation clears cached bytes after EOF; growth clears newly
		// exposed bytes, including old stores made while outside EOF.
		// Detached private COW copies do not live in this common cache.
		zero_start := if new_size < old_size { new_size } else { old_size }
		zero_end := if new_size < old_size { u64(-1) } else { new_size }
		for cached in this.mapped_pages {
			start := cached.page * page_size
			if start + page_size <= zero_start || start >= zero_end { continue }
			offset := if start < zero_start { zero_start - start } else { u64(0) }
			end := if start + page_size < zero_end { page_size } else { zero_end - start }
			unsafe { C.memset(voidptr(u64(cached.physical) + higher_half + offset), 0, end - offset) }
		}
	}

	this.stat.size = i64(new_size)
	this.stat.blocks = current_inode.sector_cnt
	this.stat.mtim = time.TimeSpec{i64(current_inode.mod_time), 0}
	this.stat.ctim = time.TimeSpec{i64(current_inode.creation_time), 0}
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
	// An immutable backing Resource cannot become writable through remount,
	// a second mount, or an inherited descriptor.
	read_only bool
	// The filesystem as the VFS holds it, boxed once; see as_filesystem().
	box &vfs.FileSystem = unsafe { nil }
}

// as_filesystem is the filesystem as nodes hold it. Passing `this` to
// create_node() boxed it again for every node made.
fn (mut this EXT2Filesystem) as_filesystem() &vfs.FileSystem {
	if this.box == unsafe { nil } {
		this.box = &vfs.FileSystem(this)
	}
	return this.box
}

fn (mut this EXT2Filesystem) populate(node &vfs.VFSNode) {
	this.populate_checked(node) or {}
}

fn (mut this EXT2Filesystem) populate_checked(node &vfs.VFSNode) ? {
	mut parent := unsafe { &EXT2Inode(C.vinix_stack_alloc(sizeof(EXT2Inode))) }
	unsafe { *parent = EXT2Inode{} }
	parent.read_entry(mut this, u32(node.resource.stat.ino))?

	buffer := memory.calloc(parent.size32l, 1)
	if buffer == unsafe { nil } {
		errno.set(errno.enomem)
		return none
	}
	defer { memory.free(buffer) }
	parent.read(mut this, buffer, 0, parent.size32l)?
	// One reusable inode slot bounds directory-population stack usage.
	mut inode := unsafe { &EXT2Inode(C.vinix_stack_alloc(sizeof(EXT2Inode))) }

	for i := u32(0); i < parent.size32l;  {
		if parent.size32l - i < sizeof(EXT2DirectoryEntry) {
			errno.set(errno.eio)
			return none
		}
		dir_entry := &EXT2DirectoryEntry(u64(buffer) + i)
		if dir_entry.entry_size < sizeof(EXT2DirectoryEntry)
			|| u32(dir_entry.entry_size) > parent.size32l - i
			|| u32(dir_entry.name_length) > u32(dir_entry.entry_size) - u32(sizeof(EXT2DirectoryEntry)) {
			errno.set(errno.eio)
			return none
		}
		if dir_entry.inode_index == 0 {
			i += dir_entry.entry_size
			continue
		}

		name_buffer := memory.calloc(dir_entry.name_length + 1, 1)
		if name_buffer == unsafe { nil } {
			errno.set(errno.enomem)
			return none
		}
		unsafe {
			C.memcpy(name_buffer, voidptr(u64(dir_entry) + sizeof(EXT2DirectoryEntry)), u64(dir_entry.name_length))
		}
		name := unsafe { tos(&u8(name_buffer), int(dir_entry.name_length)) }

		if name == '.' || name == '..' {
			memory.free(name_buffer)
			i += dir_entry.entry_size
			continue
		}

		unsafe { *inode = EXT2Inode{} }
		inode.read_entry(mut this, dir_entry.inode_index) or {
			memory.free(name_buffer)
			return none
		}

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

		mut vfs_node := vfs.create_node(this.as_filesystem(), node, name, stat.isdir(mode))
		vfs_node.read_only = this.read_only
		mut resource := &EXT2Resource{
			filesystem: unsafe { this }
			refcount: 1
		}

		resource.stat.mode = mode
		resource.stat.uid = inode.user_id
		resource.stat.gid = inode.group_id
		resource.stat.ino = dir_entry.inode_index
		resource.stat.size = inode.size()
		resource.stat.nlink = inode.hard_link_cnt
		resource.stat.blksize = this.block_size
		resource.stat.blocks = inode.sector_cnt

		resource.stat.atim = time.TimeSpec{i64(inode.access_time), 0}
		resource.stat.ctim = time.TimeSpec{i64(inode.creation_time), 0}
		resource.stat.mtim = time.TimeSpec{i64(inode.mod_time), 0}
		resource.can_mmap = stat.isreg(mode)

		vfs_node.resource = resource.boxed()
		if stat.islnk(mode) && inode.size32l != 0 {
			if target := inode.fast_symlink_target(this.block_size) {
				vfs_node.symlink_target = target
			} else {
				target_buffer := memory.calloc(u64(inode.size32l) + 1, 1)
				if target_buffer == unsafe { nil } {
					errno.set(errno.enomem)
					return none
				}
				inode.read(mut this, target_buffer, 0, inode.size32l) or {
					memory.free(target_buffer)
					return none
				}
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
			this.populate_checked(vfs_node)?
		}
		i += dir_entry.entry_size
	}

}

fn (this &EXT2Filesystem) block_identity() resource_mod.BlockIdentity {
	mut device := this.backing_device.resource
	return resource_mod.block_identity(mut device)
}

fn (mut bro EXT2Filesystem) instantiate() &vfs.FileSystem {
	mut this := &EXT2Filesystem{
		backing_device: bro.backing_device
		superblock: bro.superblock
		root_inode: bro.root_inode
		cache: bro.cache
		read_only: bro.read_only
	}

	this.block_size = 1024 << this.superblock.block_size
	this.frag_size = 1024 << this.superblock.frag_size
	this.bgd_cnt = lib.div_roundup(this.superblock.block_cnt, this.superblock.blocks_per_group)

	device := vfs.pathname(this.backing_device)
	C.kprintf(c'ext2: filesystem detected on device %.*s\n', i32(device.len), device.str)
	unsafe { device.free() }
	C.kprintf(c'ext2: inode count: %llu\n', u64(this.superblock.inode_cnt))
	C.kprintf(c'ext2: inodes per group: %llx\n', u64(this.superblock.inodes_per_group))
	C.kprintf(c'ext2: block count: %llx\n', u64(this.superblock.block_cnt))
	C.kprintf(c'ext2: blocks per group: %llx\n', u64(this.superblock.blocks_per_group))
	C.kprintf(c'ext2: block size: %llx\n', u64(this.block_size))
	C.kprintf(c'ext2: bgd count: %llx\n', u64(this.bgd_cnt))

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
	if this.read_only && source != unsafe { nil }
		&& (source.resource == unsafe { nil }
			|| voidptr(source.resource) != voidptr(this.backing_device.resource)) {
		errno.set(errno.enodev)
		return none
	}
	this.dev_id = resource_mod.create_dev_id()

	mut target := vfs.create_node(this.as_filesystem(), parent, name, true)
	target.read_only = this.read_only

	mut resource := &EXT2Resource{
		filesystem: unsafe { this }
		refcount: 1
	}

	resource.stat.size = this.root_inode.size()
	resource.stat.blksize = this.block_size
	resource.stat.blocks = this.root_inode.sector_cnt
	resource.stat.dev = this.dev_id
	resource.stat.mode = this.root_inode.permissions
	resource.stat.uid = this.root_inode.user_id
	resource.stat.gid = this.root_inode.group_id
	resource.stat.nlink = this.root_inode.hard_link_cnt
	resource.stat.ino = 2

	resource.stat.atim = time.TimeSpec{i64(this.root_inode.access_time), 0}
	resource.stat.ctim = time.TimeSpec{i64(this.root_inode.creation_time), 0}
	resource.stat.mtim = time.TimeSpec{i64(this.root_inode.mod_time), 0}

	target.filesystem = this.as_filesystem()
	target.resource = resource.boxed()

	this.populate_checked(target)?

	return target
}

// The block array is 15 u32s, and a symlink whose target fits in those 60
// bytes keeps it there instead of allocating a block -- a "fast symlink", which
// is what mke2fs and every other ext2 tool writes. Reading one as block
// pointers yields whatever the target's characters happen to address, so a
// volume prepared on the host has to be recognised rather than followed.
//
// Read the inline form used by ext2 tools and by this driver's symlink writer.
fn (inode &EXT2Inode) fast_symlink_target(block_size u64) ?string {
	attribute_sectors := if inode.eab != 0 { u32(block_size / 512) } else { u32(0) }
	if inode.sector_cnt != attribute_sectors || inode.size32l == 0
		|| inode.size32l > u32(sizeof(inode.blocks)) {
		return none
	}
	return unsafe { tos(&u8(&inode.blocks[0]), int(inode.size32l)).clone() }
}

fn (mut inode EXT2Inode) read(mut filesystem EXT2Filesystem, buf voidptr, off u64, cnt u64) ?i64 {
	file_size := inode.size()
	if off >= file_size || cnt == 0 { return 0 }
	count := if cnt < file_size - off { cnt } else { file_size - off }
	attribute_sectors := if inode.eab != 0 { u32(filesystem.block_size / 512) } else { u32(0) }
	if stat.islnk(u32(inode.permissions)) && inode.sector_cnt == attribute_sectors
		&& inode.size32l <= u32(sizeof(inode.blocks)) {
		unsafe { C.memcpy(buf, voidptr(u64(&inode.blocks[0]) + off), count) }
		return i64(count)
	}
	for headway := u64(0); headway < count; {
		logical := (off + headway) / filesystem.block_size
		if logical >= u64(0x100000000) { errno.set(errno.efbig); return none }
		offset := (off + headway) % filesystem.block_size
		amount := if count - headway < filesystem.block_size - offset {
			count - headway
		} else { filesystem.block_size - offset }
		block := inode.get_block(mut filesystem, u32(logical))?
		if block == 0 {
			unsafe { C.memset(voidptr(u64(buf) + headway), 0, amount) }
		} else {
			filesystem.raw_device_read(voidptr(u64(buf) + headway), u64(block) * filesystem.block_size + offset, amount)?
		}
		headway += amount
	}
	return i64(count)
}

fn (mut inode EXT2Inode) prepare_size(mut filesystem EXT2Filesystem, size u64) ? {
	maximum := if stat.isreg(u32(inode.permissions)) { filesystem.file_capacity() } else { u64(0xffffffff) }
	if size > maximum { errno.set(errno.efbig); return none }
	if stat.isreg(u32(inode.permissions)) && size > 0x7fffffff {
		// Dynamic-revision inodes assign i_dir_acl to the size high word.
		if filesystem.superblock.version_maj == 0 { errno.set(errno.efbig); return none }
		filesystem.enable_large_files()?
	}
}

fn (mut inode EXT2Inode) set_size(size u64) {
	inode.size32l = u32(size)
	if stat.isreg(u32(inode.permissions)) { inode.size32h = u32(size >> 32) }
}

// Clear the retained block's bytes past a logical EOF. This also prevents
// a failed extending write from exposing its uncommitted suffix on later growth.
fn (mut inode EXT2Inode) zero_tail(mut filesystem EXT2Filesystem, size u64) ? {
	if size == 0 || size % filesystem.block_size == 0 { return }
	block := inode.get_block(mut filesystem, u32(size / filesystem.block_size))?
	if block == 0 { return }
	offset := size % filesystem.block_size
	amount := filesystem.block_size - offset
	zero := memory.calloc(amount, 1)
	if zero == unsafe { nil } { errno.set(errno.enomem); return none }
	defer { memory.free(zero) }
	filesystem.raw_device_write(zero, u64(block) * filesystem.block_size + offset, amount)?
}

fn (mut inode EXT2Inode) resize(mut filesystem EXT2Filesystem, inode_index u32, start u64, count u64) ?int {
	if count > u64(-1) - start { errno.set(errno.efbig); return none }
	new_size := start + count
	inode.prepare_size(mut filesystem, new_size)?
	old_size := inode.size()
	if new_size < old_size {
		inode.zero_tail(mut filesystem, new_size)?
		inode.truncate_blocks(mut filesystem, inode_index, lib.div_roundup(new_size, filesystem.block_size))?
	} else if new_size > old_size {
		inode.zero_tail(mut filesystem, old_size)?
	}
	// Growth reserves size only. Holes acquire physical blocks on the first write.
	inode.set_size(new_size)
	inode.mod_time = ext2_now()
	inode.creation_time = inode.mod_time
	inode.write_entry(mut filesystem, inode_index)?
	return 0
}

// A new data block remains detached until both its data and pointer tables
// have been copied successfully into the filesystem cache.
fn (mut inode EXT2Inode) write_file_block(mut filesystem EXT2Filesystem, buf voidptr,
	inode_index u32, logical u32, offset u64, amount u64) ? {
	mut block := inode.get_block(mut filesystem, logical)?
	fresh := block == 0
	if fresh { block = inode.allocate_accounted_block(mut filesystem)? }
	filesystem.raw_device_write(buf, u64(block) * filesystem.block_size + offset, amount) or {
		if fresh { inode.free_accounted_block(mut filesystem, block) or {} }
		return none
	}
	if fresh {
		inode.set_block(mut filesystem, inode_index, logical, block) or {
			// set_block has no failing operation after publication. Single-
			// page pointer/inode copies fail before mutation, so this data
			// block and any detached metadata remain safe to return.
			inode.free_accounted_block(mut filesystem, block) or {}
			return none
		}
	}
}

fn (mut inode EXT2Inode) write(mut filesystem EXT2Filesystem, buf voidptr, inode_index u32, off u64, count u64) ?i64 {
	if count == 0 { return 0 }
	if count > u64(-1) - off { errno.set(errno.efbig); return none }
	inode.prepare_size(mut filesystem, off + count)?
	if off > inode.size() { inode.zero_tail(mut filesystem, inode.size())? }
	mut headway := u64(0)
	for headway < count {
		logical := u32((off + headway) / filesystem.block_size)
		offset := (off + headway) % filesystem.block_size
		amount := if count - headway < filesystem.block_size - offset {
			count - headway
		} else { filesystem.block_size - offset }
		inode.write_file_block(mut filesystem, voidptr(u64(buf) + headway), inode_index,
			logical, offset, amount) or {
			// Keep counters for any already-published tables. The failed
			// chunk contributes no size or returned bytes.
			inode.write_entry(mut filesystem, inode_index) or {}
			if headway != 0 { return i64(headway) }
			return none
		}
		old_size := inode.size()
		end := off + headway + amount
		if end > old_size { inode.set_size(end) }
		inode.mod_time = ext2_now()
		inode.creation_time = inode.mod_time
		inode.write_entry(mut filesystem, inode_index) or {
			// Inode writes fit one cache page (validated at mount), so a
			// failed cache acquisition has published no new inode bytes.
			inode.set_size(old_size)
			if end > old_size {
				// Return any rejected extending data to holes. Otherwise a
				// later ftruncate growth could expose this unreported suffix.
				// Permanent cleanup I/O failures still require FS recovery.
				inode.zero_tail(mut filesystem, old_size) or {}
				inode.truncate_blocks(mut filesystem, inode_index,
					lib.div_roundup(old_size, filesystem.block_size)) or {}
			}
			inode.write_entry(mut filesystem, inode_index) or {}
			// Bytes already within EOF are visible even if their timestamp
			// update failed. Report them so the Resource's mapped cache gets
			// the same completed prefix as the backing cache.
			if off + headway < old_size {
				visible := if amount < old_size - off - headway { amount } else { old_size - off - headway }
				return i64(headway + visible)
			}
			if headway != 0 { return i64(headway) }
			return none
		}
		headway += amount
	}
	return i64(headway)
}

fn (mut inode EXT2Inode) free_entry(mut filesystem EXT2Filesystem, inode_index u32) ?int {
	// A short symlink stores its target directly in the fifteen block-pointer
	// fields. Interpreting those bytes as block numbers while unlinking or
	// replacing the symlink corrupts the allocation bitmap (and made apk fail
	// as soon as it replaced one of Alpine's compatibility links).
	// Linux's test: no blocks but an extended-attribute one. Taking that
	// block for data read a target's bytes as block numbers, and freed them.
	attribute_sectors := if inode.eab != 0 { u32(filesystem.block_size / 512) } else { u32(0) }
	is_fast_symlink := stat.islnk(u32(inode.permissions))
		&& inode.sector_cnt == attribute_sectors && inode.size32l != 0
		&& inode.size32l <= u32(sizeof(inode.blocks))
	if !is_fast_symlink {
		inode.truncate_blocks(mut filesystem, inode_index, 0)?
	}
	if stat.isdir(u32(inode.permissions)) {
		filesystem.count_directory(inode_index, false)
	}
	inode.delete_ea(mut filesystem, inode_index)?
	inode.size32l = 0
	inode.size32h = 0
	inode.sector_cnt = 0
	inode.permissions = 0
	inode.hard_link_cnt = 0
	inode.write_entry(mut filesystem, inode_index)?
	filesystem.free_inode(inode_index) or { return none }

	return 0
}

fn (mut filesystem EXT2Filesystem) allocate_block() ?u32 {
	mut bgd := unsafe { &EXT2BlockGroupDescriptor(C.vinix_stack_alloc(sizeof(EXT2BlockGroupDescriptor))) }
	unsafe { *bgd = EXT2BlockGroupDescriptor{} }

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
	mut bgd := unsafe { &EXT2BlockGroupDescriptor(C.vinix_stack_alloc(sizeof(EXT2BlockGroupDescriptor))) }
	unsafe { *bgd = EXT2BlockGroupDescriptor{} }

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
	bitmap := memory.calloc(filesystem.block_size, 1) @[freed]
	if bitmap == unsafe { nil } { errno.set(errno.enomem); return none }
	defer { memory.free(bitmap) }

	mut bgd := unsafe { &EXT2BlockGroupDescriptor(C.vinix_stack_alloc(sizeof(EXT2BlockGroupDescriptor))) }
	unsafe { *bgd = EXT2BlockGroupDescriptor{} }
	bgd.read_entry(mut filesystem, bgd_index)

	filesystem.raw_device_read(bitmap, bgd.block_addr_bitmap * filesystem.block_size, filesystem.block_size) or {
		print('ext2: unable to read bgd bitmap\n')
		return none
	}

	if lib.bittest(bitmap, bitmap_index) == false {
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


	return 0
}

// Each group counts the directories among its inodes. Nothing here reads the
// count, but e2fsck checks it and Linux places new directories by it.
fn (mut filesystem EXT2Filesystem) count_directory(inode_index u32, added bool) {
	bgd_index := (inode_index - 1) / filesystem.superblock.inodes_per_group
	mut bgd := unsafe { &EXT2BlockGroupDescriptor(C.vinix_stack_alloc(sizeof(EXT2BlockGroupDescriptor))) }
	unsafe { *bgd = EXT2BlockGroupDescriptor{} }
	bgd.read_entry(mut filesystem, bgd_index)
	if added {
		bgd.dir_cnt++
	} else if bgd.dir_cnt > 0 {
		bgd.dir_cnt--
	}
	bgd.write_entry(mut filesystem, bgd_index)
}

fn (mut filesystem EXT2Filesystem) free_inode(inode u32) ?int {
	if inode == 0 {
		errno.set(errno.eio)
		return none
	}
	bgd_index := (inode - 1) / filesystem.superblock.inodes_per_group
	bitmap_index := (inode - 1) % filesystem.superblock.inodes_per_group
	bitmap := memory.calloc(filesystem.block_size, 1) @[freed]
	if bitmap == unsafe { nil } { errno.set(errno.enomem); return none }
	defer { memory.free(bitmap) }

	mut bgd := unsafe { &EXT2BlockGroupDescriptor(C.vinix_stack_alloc(sizeof(EXT2BlockGroupDescriptor))) }
	unsafe { *bgd = EXT2BlockGroupDescriptor{} }
	bgd.read_entry(mut filesystem, bgd_index)

	filesystem.raw_device_read(bitmap, bgd.block_addr_inode * filesystem.block_size, filesystem.block_size) or {
		print('ext2: unable to read inode bitmap\n')
		return none
	}

	if lib.bittest(bitmap, bitmap_index) == false {
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


	return 0
}

fn (mut bgd EXT2BlockGroupDescriptor) read_entry(mut filesystem EXT2Filesystem, bgd_index u32) int {
	mut bgd_offset := u64(0)

	if filesystem.block_size >= 2048 {
		bgd_offset = filesystem.block_size
	} else {
		bgd_offset = filesystem.block_size * 2
	}

	filesystem.raw_device_read(voidptr(unsafe { &bgd }), bgd_offset + sizeof(EXT2BlockGroupDescriptor) * bgd_index, sizeof(EXT2BlockGroupDescriptor)) or {
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

	filesystem.raw_device_write(voidptr(unsafe { &bgd }), bgd_offset + sizeof(EXT2BlockGroupDescriptor) * bgd_index, sizeof(EXT2BlockGroupDescriptor)) or {
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

	mut bgd := unsafe { &EXT2BlockGroupDescriptor(C.__builtin_alloca(sizeof(EXT2BlockGroupDescriptor))) }
	unsafe { *bgd = EXT2BlockGroupDescriptor{} }
	if bgd.read_entry(mut filesystem, bgd_index) < 0 {
		errno.set(errno.eio)
		return none
	}

	filesystem.raw_device_read(unsafe { voidptr(&inode) }, bgd.inode_table_block * filesystem.block_size + filesystem.superblock.inode_size * inode_table_index, sizeof(EXT2Inode)) or {
		print('ext2: unable to read inode entry\n')
		return none
	}

	return 0
}

fn (mut inode EXT2Inode) write_entry(mut filesystem EXT2Filesystem, inode_index u32) ?int {
	inode_table_index := (inode_index - 1) % filesystem.superblock.inodes_per_group
	bgd_index := (inode_index - 1) / filesystem.superblock.inodes_per_group

	mut bgd := unsafe { &EXT2BlockGroupDescriptor(C.__builtin_alloca(sizeof(EXT2BlockGroupDescriptor))) }
	unsafe { *bgd = EXT2BlockGroupDescriptor{} }
	if bgd.read_entry(mut filesystem, bgd_index) < 0 {
		errno.set(errno.eio)
		return none
	}

	filesystem.raw_device_write(unsafe { voidptr(&inode) }, bgd.inode_table_block * filesystem.block_size + filesystem.superblock.inode_size * inode_table_index, sizeof(EXT2Inode)) or {
		print('ext2: unable to read inode entry\n')
		return none
	}

	return 0
}

// Build a root node for an already-detected filesystem without attaching it to
// the tree. A caller that means to make the volume the system root has to
// inspect what is on it first, and publish it only if it is a system.
pub fn ext2_root(mut filesystem EXT2Filesystem) ?&vfs.VFSNode {
	mut instance := filesystem.instantiate()
	mut root := instance.mount(unsafe { nil }, '', unsafe { nil })?
	// A root's parent is itself, so `..` at the top of the tree stays inside it.
	root.create_dotentries(root)
	return root
}

pub fn ext2_init(backing_device &vfs.VFSNode) (&EXT2Filesystem, bool) {
	sector_size := u64(backing_device.resource.stat.blksize)
	if sector_size == 0 || sector_size > pagecache.page_bytes
		|| pagecache.page_bytes % sector_size != 0 || backing_device.resource.stat.size < 2048
		|| u64(backing_device.resource.stat.size) % sector_size != 0 {
		return 0, false
	}
	reserve_bounce()
	mut backend := backing_device.resource
	mut new_filesystem := &EXT2Filesystem{
		backing_device: unsafe { backing_device }
		superblock: &EXT2Superblock{}
		root_inode: &EXT2Inode{}
		cache: pagecache.new_cache(u64(backing_device.resource.stat.size))
		read_only: resource_mod.backend_is_read_only(mut backend)
	}

	// The EXT2 superblock is at byte 1024, regardless of device sector size.
	new_filesystem.raw_device_read(new_filesystem.superblock, 1024, sizeof(EXT2Superblock)) or {
		new_filesystem.cache.release(voidptr(backing_device), device_write) or {}
		return 0, false
	}

	if new_filesystem.superblock.signature != 0xef53 {
		new_filesystem.cache.release(voidptr(backing_device), device_write) or {}
		return 0, false
	}
	// Pointer entries, inode headers and a data block must fit one software
	// cache page. A failed cache acquisition then cannot expose a half inode
	// or half pointer while the caller rolls back detached allocations.
	if new_filesystem.superblock.block_size > 2 {
		new_filesystem.cache.release(voidptr(backing_device), device_write) or {}
		return 0, false
	}
	block_bytes := u64(1024) << new_filesystem.superblock.block_size
	if new_filesystem.superblock.version_maj == 0 { new_filesystem.superblock.inode_size = 128 }
	inode_bytes := u64(new_filesystem.superblock.inode_size)
	if inode_bytes < sizeof(EXT2Inode) || inode_bytes > block_bytes
		|| inode_bytes & (inode_bytes - 1) != 0 {
		new_filesystem.cache.release(voidptr(backing_device), device_write) or {}
		return 0, false
	}
	if !register_mapped_writeback()
		|| !pagecache.register_cache(new_filesystem.cache, voidptr(backing_device), device_write, device_flush) {
		new_filesystem.cache.release(voidptr(backing_device), device_write) or {}
		return 0, false
	}

	return new_filesystem, true
}
