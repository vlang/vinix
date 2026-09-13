module fs

import stat
import klock
import memory
import memory.mmap
import resource
import lib
import event.eventstruct
import katomic

@[heap]
struct TmpFSResource {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool

	storage  &u8
	capacity u64
	// Initramfs files initially point straight into the Limine module.  The
	// module remains reserved for the life of the kernel, so keeping that
	// pointer avoids allocating and copying the whole root filesystem during
	// boot.  The first operation which can modify the backing store turns it
	// into an ordinary tmpfs allocation.
	storage_owned bool
}

// materialize_locked gives a borrowed (or as-yet empty) file writable tmpfs
// storage.  The caller holds this.l.  Keep the minimum allocation at one page:
// tmpfs.mmap returns physical pages and therefore needs a page-aligned big
// allocation rather than a small slab object.
fn (mut this TmpFSResource) materialize_locked(min_capacity u64) bool {
	if this.storage_owned && min_capacity <= this.capacity {
		return true
	}

	mut new_capacity := if this.storage_owned { this.capacity } else { u64(this.stat.size) }
	if new_capacity < page_size {
		new_capacity = page_size
	}
	for min_capacity > new_capacity {
		if new_capacity > u64(-1) / 2 {
			new_capacity = min_capacity
			break
		}
		new_capacity *= 2
	}
	// malloc's large allocations occupy complete physical pages. Record that
	// usable tail as capacity too, so mapping the last partial file page does
	// not trigger a needless second allocation (and exponential growth).
	if new_capacity <= u64(-1) - (page_size - 1) {
		new_capacity = lib.align_up(new_capacity, page_size)
	}

	new_storage := memory.malloc(new_capacity)
	if new_storage == unsafe { nil } {
		return false
	}
	old_size := u64(this.stat.size)
	copy_size := if old_size < new_capacity { old_size } else { new_capacity }
	if copy_size != 0 && this.storage != unsafe { nil } {
		unsafe { C.memcpy(new_storage, this.storage, copy_size) }
	}
	if this.storage_owned {
		memory.free(this.storage)
	}

	this.storage = new_storage
	this.capacity = new_capacity
	this.storage_owned = true
	return true
}

// tmpfs_borrow_storage installs immutable backing supplied by an initramfs
// module.  Limine keeps executable-and-module memory reserved, and Vinix maps
// it in the HHDM, so the bytes remain valid after boot.  Writes, truncation and
// shared mappings transparently copy the file into owned tmpfs memory.
pub fn tmpfs_borrow_storage(mut res resource.Resource, storage voidptr, size u64) bool {
	if mut res is TmpFSResource {
		res.l.acquire()
		defer {
			res.l.release()
		}
		if res.storage_owned {
			memory.free(res.storage)
		}
		res.storage = unsafe { &u8(storage) }
		res.capacity = size
		res.storage_owned = false
		res.stat.size = size
		res.stat.blocks = lib.div_roundup(size, u64(res.stat.blksize))
		return true
	}
	return false
}

fn (mut this TmpFSResource) mmap(_handle voidptr, page u64, flags int) voidptr {
	this.l.acquire()
	defer {
		this.l.release()
	}
	if page > u64(-1) / page_size {
		return unsafe { nil }
	}
	offset := page * page_size

	if flags & mmap.map_shared != 0 {
		if offset > u64(-1) - page_size || !this.materialize_locked(offset + page_size) {
			return unsafe { nil }
		}
		unsafe {
			return voidptr(u64(&this.storage[offset]) - higher_half)
		}
	}

	copy_page := memory.pmm_alloc(1)
	file_size := u64(this.stat.size)
	if offset < file_size && this.storage != unsafe { nil } {
		copy_size := if page_size < file_size - offset { page_size } else { file_size - offset }
		unsafe {
			C.memcpy(voidptr(u64(copy_page) + higher_half), &this.storage[offset], copy_size)
		}
	}

	return copy_page
}

fn (mut this TmpFSResource) release_mapping(_handle voidptr, _page u64,
	physical voidptr, flags int) {
	if flags & mmap.map_shared == 0 {
		memory.pmm_free(physical, 1)
	}
}

fn (mut this TmpFSResource) read(_handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	this.l.acquire()
	defer {
		this.l.release()
	}

	file_size := u64(this.stat.size)
	if loc >= file_size {
		return 0
	}
	actual_count := if count > file_size - loc { file_size - loc } else { count }

	unsafe { C.memcpy(buf, &this.storage[loc], actual_count) }

	return i64(actual_count)
}

fn (mut this TmpFSResource) write(_handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	this.l.acquire()
	defer {
		this.l.release()
	}

	if count > u64(-1) - loc {
		return none
	}
	if count == 0 {
		return 0
	}
	write_end := loc + count
	if !this.storage_owned || write_end > this.capacity {
		if !this.materialize_locked(write_end) {
			return none
		}
	}

	old_size := u64(this.stat.size)
	if loc > old_size {
		// A write after a seek beyond EOF creates a zero-filled sparse hole.
		unsafe { C.memset(&this.storage[old_size], 0, loc - old_size) }
	}
	unsafe { C.memcpy(&this.storage[loc], buf, count) }

	if write_end > this.stat.size {
		this.stat.size = write_end
		this.stat.blocks = lib.div_roundup(this.stat.size, this.stat.blksize)
	}

	return i64(count)
}

fn (mut this TmpFSResource) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this TmpFSResource) filesystem_stat() resource.FileSystemStat {
	return resource.FileSystemStat{
		@type: 0x01021994
		bsize: page_size
		blocks: memory.total_bytes() / page_size
		bfree: memory.free_bytes() / page_size
		bavail: memory.free_bytes() / page_size
		files: u64(-1)
		ffree: u64(-1)
		namelen: 255
		frsize: page_size
	}
}

fn (mut this TmpFSResource) unref(_handle voidptr) ? {
	katomic.dec(mut &this.refcount)

	if this.refcount != 0 {
		return
	}

	if stat.isreg(this.stat.mode) && this.storage_owned {
		memory.free(this.storage)
	}

	unsafe { free(this) }
}

fn (mut this TmpFSResource) link(_handle voidptr) ? {
	katomic.inc(mut &this.stat.nlink)
}

fn (mut this TmpFSResource) unlink(_handle voidptr) ? {
	katomic.dec(mut &this.stat.nlink)
}

fn (mut this TmpFSResource) grow(_handle voidptr, new_size u64) ? {
	this.l.acquire()
	defer {
		this.l.release()
	}

	old_size := u64(this.stat.size)
	if new_size <= old_size {
		// Borrowed storage can stay borrowed when truncated. If the file grows
		// again, materialisation copies only the still-visible prefix and its
		// zero-filled allocation supplies the truncated tail correctly.
		this.stat.size = new_size
		this.stat.blocks = lib.div_roundup(new_size, u64(this.stat.blksize))
		return
	}

	if !this.materialize_locked(new_size) {
		return none
	}

	// Anything past the old end of the file has to read back as zero, whether
	// it got there by seeking past the end and writing or by ftruncate. realloc
	// makes no such promise about the memory it hands back.
	if new_size > old_size {
		unsafe {
			C.memset(voidptr(u64(this.storage) + old_size), 0, new_size - old_size)
		}
	}

	this.stat.size = new_size
	this.stat.blocks = lib.div_roundup(new_size, u64(this.stat.blksize))
}

struct TmpFS {
pub mut:
	dev_id        u64
	inode_counter u64
}

fn (this TmpFS) instantiate() &FileSystem {
	new := &TmpFS{}
	return new
}

fn (this TmpFS) populate(_node &VFSNode) {}

fn (mut this TmpFS) mount(parent &VFSNode, name string, _source &VFSNode) ?&VFSNode {
	this.dev_id = resource.create_dev_id()
	return this.create(parent, name, 0o755 | stat.ifdir)
}

fn (mut this TmpFS) create(parent &VFSNode, name string, mode u32) &VFSNode {
	mut new_node := create_node(this, parent, name, stat.isdir(mode))

	mut new_resource := &TmpFSResource{
		storage: unsafe { nil }
		refcount: 1
	}

	if stat.isreg(mode) {
		new_resource.can_mmap = true
	}

	new_resource.stat.size = 0
	new_resource.stat.blocks = 0
	new_resource.stat.blksize = 512
	new_resource.stat.dev = this.dev_id
	new_resource.stat.ino = this.inode_counter++
	new_resource.stat.mode = mode
	new_resource.stat.nlink = 1

	new_resource.stat.atim = realtime_clock
	new_resource.stat.ctim = realtime_clock
	new_resource.stat.mtim = realtime_clock

	new_node.resource = new_resource

	return new_node
}

fn (mut this TmpFS) link(parent &VFSNode, path string, mut old_node VFSNode) ?&VFSNode {
	mut new_node := create_node(this, parent, path, false)

	katomic.inc(mut &old_node.resource.refcount)
	katomic.inc(mut &old_node.resource.stat.nlink)

	new_node.resource = old_node.resource
	new_node.children = old_node.children

	return new_node
}

fn (mut this TmpFS) rename(_old_parent &VFSNode, _old_name string,
	_new_parent &VFSNode, _new_name string, _flags int) ? {}

fn (mut this TmpFS) symlink(parent &VFSNode, dest string, target string) &VFSNode {
	mut new_node := create_node(this, parent, target, false)

	mut new_resource := &TmpFSResource{
		storage: unsafe { nil }
		refcount: 1
	}

	// A symlink's size is the length of the path it holds, not of its own name.
	new_resource.stat.size = i64(dest.len)
	new_resource.stat.blocks = 0
	new_resource.stat.blksize = 512
	new_resource.stat.dev = this.dev_id
	new_resource.stat.ino = this.inode_counter++
	new_resource.stat.mode = stat.iflnk | 0o777
	new_resource.stat.nlink = 1

	new_resource.stat.atim = realtime_clock
	new_resource.stat.ctim = realtime_clock
	new_resource.stat.mtim = realtime_clock

	new_node.resource = new_resource

	new_node.symlink_target = dest

	return new_node
}

// A tmpfs file with no name and no place in the directory tree, for
// memfd_create(2). It behaves like any other tmpfs file — it can be written,
// truncated and mapped — and goes away with its last descriptor.
pub fn create_anonymous(mode u32) &resource.Resource {
	mut new_resource := &TmpFSResource{
		storage: unsafe { nil }
		refcount: 1
	}

	new_resource.can_mmap = true

	new_resource.stat.size = 0
	new_resource.stat.blocks = 0
	new_resource.stat.blksize = 512
	new_resource.stat.dev = resource.create_dev_id()
	new_resource.stat.ino = 1
	new_resource.stat.mode = stat.ifreg | mode
	new_resource.stat.nlink = 1

	new_resource.stat.atim = realtime_clock
	new_resource.stat.ctim = realtime_clock
	new_resource.stat.mtim = realtime_clock

	return new_resource
}
