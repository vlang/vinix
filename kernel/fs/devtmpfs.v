@[has_globals]
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
struct DevTmpFSResource {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool

	storage  &u8
	capacity u64
	// The interface box its nodes and descriptors hold, freed with it; see
	// TmpFSResource.box.
	box &resource.Resource = unsafe { nil }
}

fn (mut this DevTmpFSResource) boxed() &resource.Resource {
	if this.box == unsafe { nil } {
		this.box = &resource.Resource(this) @[freed]
	}
	return this.box
}

fn (mut this DevTmpFSResource) mmap(_handle voidptr, page u64, flags int) voidptr {
	this.l.acquire()
	defer {
		this.l.release()
	}

	if flags & mmap.map_shared != 0 {
		unsafe {
			return voidptr(memory.kernel_virt2phys(u64(&this.storage[page * page_size])))
		}
	}

	copy_page := memory.pmm_alloc(1)

	unsafe {
		C.memcpy(voidptr(u64(copy_page) + higher_half), &this.storage[page * page_size], page_size)
	}

	return copy_page
}

fn (mut this DevTmpFSResource) release_mapping(_handle voidptr, _page u64,
	physical voidptr, flags int) {
	if flags & mmap.map_shared == 0 {
		memory.pmm_free(physical, 1)
	}
}

fn (mut this DevTmpFSResource) read(_handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	this.l.acquire()

	mut actual_count := count
	if loc + count > this.stat.size {
		actual_count = u64(count - ((loc + count) - this.stat.size))
	}

	unsafe { C.memcpy(buf, &this.storage[loc], actual_count) }

	this.l.release()

	return i64(actual_count)
}

fn (mut this DevTmpFSResource) write(_handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	this.l.acquire()

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

	unsafe { C.memcpy(&this.storage[loc], buf, count) }

	if loc + count > this.stat.size {
		this.stat.size = loc + count
		this.stat.blocks = lib.div_roundup(this.stat.size, this.stat.blksize)
	}

	this.l.release()

	return i64(count)
}

fn (mut this DevTmpFSResource) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this DevTmpFSResource) filesystem_stat() resource.FileSystemStat {
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

fn (mut this DevTmpFSResource) unref(_handle voidptr) ? {
	katomic.dec(mut &this.refcount)

	if this.refcount != 0 {
		return
	}

	if stat.isreg(this.stat.mode) {
		memory.free(this.storage)
	}

	unsafe {
		free(voidptr(this.box))
		free(this)
	}
}

fn (mut this DevTmpFSResource) link(_handle voidptr) ? {
	katomic.inc(mut &this.stat.nlink)
}

fn (mut this DevTmpFSResource) unlink(_handle voidptr) ? {
	katomic.dec(mut &this.stat.nlink)
}

fn (mut this DevTmpFSResource) grow(_handle voidptr, new_size u64) ? {
	this.l.acquire()
	defer {
		this.l.release()
	}

	mut new_capacity := this.capacity
	for new_size > new_capacity {
		new_capacity *= 2
	}

	new_storage := memory.realloc(this.storage, new_capacity)

	if new_storage == 0 {
		return none
	}

	this.storage = new_storage
	this.capacity = new_capacity

	this.stat.size = new_size
	this.stat.blocks = lib.div_roundup(new_size, u64(this.stat.blksize))
}

struct DevTmpFS {
mut:
	// See TmpFS.as_filesystem().
	box &FileSystem = unsafe { nil }
}

fn (mut this DevTmpFS) as_filesystem() &FileSystem {
	if this.box == unsafe { nil } {
		this.box = &FileSystem(this)
	}
	return this.box
}

__global (
	devtmpfs_dev_id        u64
	devtmpfs_inode_counter u64
	devtmpfs_root          &VFSNode
)

fn (this DevTmpFS) instantiate() &FileSystem {
	mut new := &DevTmpFS{}
	return new.as_filesystem()
}

fn (this DevTmpFS) populate(_node &VFSNode) {}

fn (mut this DevTmpFS) mount(parent &VFSNode, name string, _source &VFSNode) ?&VFSNode {
	if devtmpfs_dev_id == 0 {
		devtmpfs_dev_id = resource.create_dev_id()
	}
	if unsafe { devtmpfs_root == 0 } {
		// XXX this will break if devtmpfs is mounted more than once
		devtmpfs_root = this.create(parent, name, 0o644 | stat.ifdir)
	}
	return devtmpfs_root
}

// TODO	should it be maybe `mut parent`? doesn't `create_node` mutate `parent` in `unsafe`(passing it to `mut` field)?
fn (mut this DevTmpFS) create(parent &VFSNode, name string, mode u32) &VFSNode {
	mut new_node := create_node(this.as_filesystem(), parent, name, stat.isdir(mode))

	mut new_resource := &DevTmpFSResource{
		storage: unsafe { nil }
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
	new_resource.stat.dev = devtmpfs_dev_id
	new_resource.stat.ino = devtmpfs_inode_counter++
	new_resource.stat.mode = mode
	new_resource.stat.nlink = 1

	new_resource.stat.atim = realtime_clock
	new_resource.stat.ctim = realtime_clock
	new_resource.stat.mtim = realtime_clock

	new_node.resource = new_resource.boxed()

	return new_node
}

fn (mut this DevTmpFS) link(parent &VFSNode, path string, mut old_node VFSNode) ?&VFSNode {
	mut new_node := create_node(this.as_filesystem(), parent, path, false)

	katomic.inc(mut &old_node.resource.refcount)
	katomic.inc(mut &old_node.resource.stat.nlink)

	new_node.resource = old_node.resource
	new_node.children = old_node.children

	return new_node
}

fn (mut this DevTmpFS) rename(_old_parent &VFSNode, _old_name string,
	_new_parent &VFSNode, _new_name string, _flags int) ? {}

fn (mut this DevTmpFS) symlink(parent &VFSNode, dest string, target string) &VFSNode {
	mut new_node := create_node(this.as_filesystem(), parent, target, false)

	mut new_resource := &DevTmpFSResource{
		storage: unsafe { nil }
		refcount: 1
	}

	new_resource.stat.size = u64(target.len)
	new_resource.stat.blocks = 0
	new_resource.stat.blksize = 512
	new_resource.stat.dev = devtmpfs_dev_id
	new_resource.stat.ino = devtmpfs_inode_counter++
	new_resource.stat.mode = stat.iflnk | 0o777
	new_resource.stat.nlink = 1

	new_resource.stat.atim = realtime_clock
	new_resource.stat.ctim = realtime_clock
	new_resource.stat.mtim = realtime_clock

	new_node.resource = new_resource.boxed()

	// A copy of its own, as every filesystem keeps: symlinkat(2) frees the
	// text it was given.
	new_node.symlink_target = dest.clone()

	return new_node
}

fn ensure_devtmpfs_dir(parent &VFSNode, name string) &VFSNode {
	if name in parent.children {
		return unsafe { parent.children[name] or { panic('devtmpfs: missing child ${name}') } }
	}

	// `name` may point into a longer path; the node keeps a copy.
	mut new_node := create_node(unsafe { filesystems['devtmpfs'] }, parent, name.clone(), true)
	mut new_resource := &DevTmpFSResource{
		storage: unsafe { nil }
		refcount: 1
	}

	new_resource.stat.size = 0
	new_resource.stat.blocks = 0
	new_resource.stat.blksize = 512
	new_resource.stat.dev = devtmpfs_dev_id
	new_resource.stat.ino = devtmpfs_inode_counter++
	new_resource.stat.mode = stat.ifdir | 0o755
	new_resource.stat.nlink = 1
	new_resource.stat.atim = realtime_clock
	new_resource.stat.ctim = realtime_clock
	new_resource.stat.mtim = realtime_clock

	new_node.resource = new_resource.boxed()
	new_node.create_dotentries(parent)
	mut p := unsafe { parent }
	unsafe {
		p.children[name] = new_node
	}
	return new_node
}

pub fn devtmpfs_add_device(device &resource.Resource, name string) {
	vfs_lock.acquire()
	defer {
		vfs_lock.release()
	}

	mut parent := devtmpfs_root
	mut leaf := name

	if name.contains('/') {
		// Every pty's pts/N comes and goes through here. The components are
		// views into `name`, where split() made copies nothing freed, and the
		// node is given a copy of its own name.
		mut last := ''
		mut start := 0
		for end := 0; end <= name.len; end++ {
			if end < name.len && name[end] != `/` {
				continue
			}
			if end > start {
				if last.len > 0 {
					parent = ensure_devtmpfs_dir(parent, last)
				}
				last = unsafe { tos(name.str + start, end - start) }
			}
			start = end + 1
		}
		if last.len == 0 {
			return
		}
		leaf = last.clone()
	}

	if leaf.len == 0 {
		return
	}

	mut new_node := create_node(unsafe { filesystems['devtmpfs'] }, parent, leaf, false)

	new_node.resource = unsafe { device }
	new_node.resource.stat.dev = devtmpfs_dev_id
	new_node.resource.stat.ino = devtmpfs_inode_counter++
	new_node.resource.stat.nlink = 1
	new_node.resource.stat.atim = realtime_clock
	new_node.resource.stat.ctim = realtime_clock
	new_node.resource.stat.mtim = realtime_clock

	unsafe {
		parent.children[leaf] = new_node
	}
}

// Remove a dynamically-created device node. The resource held one reference
// on behalf of the node; open file descriptions keep their own references and
// can therefore drain normally after the pathname disappears.
//
// The node itself goes the way an unlinked file's does (see removed.v), once
// the last description that leads to it has: they count themselves in it, and
// a shell whose terminal window closed first still had its /dev/pts/N open.
// Freed here at once, it was then written to as each of those closed -- the
// last one's close is what removes a pty's node -- and the kernel heap
// reported a 192-byte object written after it was freed.
pub fn devtmpfs_remove_device(name string) bool {
	mut node := detach_device_node(name) or { return false }
	node.orphan = true
	if katomic.load(&node.handles) == 0 {
		retire_node(mut node)
	}
	return true
}

// Take a device node out of devtmpfs, and its name's reference to its
// resource; the node, for the caller to retire.
fn detach_device_node(name string) ?&VFSNode {
	vfs_lock.acquire()
	defer {
		vfs_lock.release()
	}

	mut parent := devtmpfs_root
	mut leaf := name
	if name.contains('/') {
		// Views into `name`, as in devtmpfs_add_device().
		mut last := ''
		mut start := 0
		for end := 0; end <= name.len; end++ {
			if end < name.len && name[end] != `/` {
				continue
			}
			if end > start {
				if last.len > 0 {
					if parent.children == unsafe { nil } || last !in parent.children {
						return none
					}
					parent = unsafe { parent.children[last] }
				}
				last = unsafe { tos(name.str + start, end - start) }
			}
			start = end + 1
		}
		if last.len == 0 {
			return none
		}
		leaf = last
	}

	if parent == unsafe { nil } || parent.children == unsafe { nil } || leaf !in parent.children {
		return none
	}
	mut node := unsafe { parent.children[leaf] }
	parent.children.delete(leaf)
	node.resource.stat.nlink = 0
	mut removed_resource := node.resource
	removed_resource.unref(unsafe { nil }) or {}
	return node
}

pub fn devtmpfs_get_root() &VFSNode {
	return devtmpfs_root
}
