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
}

fn (mut this TmpFSResource) mmap(_handle voidptr, page u64, flags int) voidptr {
	this.l.acquire()
	defer {
		this.l.release()
	}

	if flags & mmap.map_shared != 0 {
		unsafe {
			return voidptr(u64(&this.storage[page * page_size]) - higher_half)
		}
	}

	copy_page := memory.pmm_alloc(1)

	unsafe {
		C.memcpy(voidptr(u64(copy_page) + higher_half), &this.storage[page * page_size],
			page_size)
	}

	return copy_page
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

	if loc + count > this.capacity {
		mut new_capacity := this.capacity

		for loc + count > new_capacity {
			new_capacity *= 2
		}

		new_storage := memory.realloc(this.storage, new_capacity)

		if new_storage == 0 {
			return none
		}

		this.storage = new_storage
		this.capacity = new_capacity
	}

	old_size := u64(this.stat.size)
	if loc > old_size {
		// A write after a seek beyond EOF creates a zero-filled sparse hole.
		unsafe { C.memset(&this.storage[old_size], 0, loc - old_size) }
	}
	unsafe { C.memcpy(&this.storage[loc], buf, count) }

	if loc + count > this.stat.size {
		this.stat.size = loc + count
		this.stat.blocks = lib.div_roundup(this.stat.size, this.stat.blksize)
	}

	return i64(count)
}

fn (mut this TmpFSResource) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this TmpFSResource) unref(_handle voidptr) ? {
	katomic.dec(mut &this.refcount)

	if this.refcount != 0 {
		return
	}

	if stat.isreg(this.stat.mode) {
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

	mut new_capacity := this.capacity
	if new_capacity == 0 {
		// Only regular files are given a buffer at creation; a directory or a
		// symlink starts at zero capacity. Doubling zero never reaches
		// new_size, so growing one of those spun here forever and took the
		// kernel with it.
		new_capacity = 4096
	}
	for new_size > new_capacity {
		new_capacity *= 2
	}

	new_storage := memory.realloc(this.storage, new_capacity)

	if new_storage == 0 {
		return none
	}

	this.storage = new_storage
	this.capacity = new_capacity

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
	return this.create(parent, name, 0o644 | stat.ifdir)
}

fn (mut this TmpFS) create(parent &VFSNode, name string, mode u32) &VFSNode {
	mut new_node := create_node(this, parent, name, stat.isdir(mode))

	mut new_resource := &TmpFSResource{
		storage:  unsafe { nil }
		refcount: 1
	}

	if stat.isreg(mode) {
		new_resource.capacity = 4096
		new_resource.storage = memory.malloc(new_resource.capacity)
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

	new_node.resource = old_node.resource
	new_node.children = old_node.children

	return new_node
}

fn (mut this TmpFS) rename(_old_parent &VFSNode, _old_name string,
	_new_parent &VFSNode, _new_name string, _flags int) ? {}

fn (mut this TmpFS) symlink(parent &VFSNode, dest string, target string) &VFSNode {
	mut new_node := create_node(this, parent, target, false)

	mut new_resource := &TmpFSResource{
		storage:  unsafe { nil }
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
		storage:  unsafe { nil }
		refcount: 1
	}

	new_resource.capacity = 4096
	new_resource.storage = memory.malloc(new_resource.capacity)
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
