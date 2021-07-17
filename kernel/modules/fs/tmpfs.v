module fs

import stat
import klock
import memory
import resource

struct TmpFSResource {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock

	storage  &byte
	capacity u64
}

fn (mut this TmpFSResource) read(buf voidptr, loc u64, count u64) ?i64 {
	this.l.acquire()

	mut actual_count := count

	if loc + count > this.stat.size {
		actual_count = count - ((loc + count) - this.stat.size)
	}

	unsafe { C.memcpy(buf, &this.storage[loc], actual_count) }

	this.l.release()

	return i64(actual_count)
}

fn (mut this TmpFSResource) write(buf voidptr, loc u64, count u64) ?i64 {
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
	}

	this.l.release()

	return i64(count)
}

fn (mut this TmpFSResource) ioctl(request u64, argp voidptr) ?int {
	return resource.default_ioctl(request, argp)
}

struct TmpFS {
pub mut:
	dev_id u64
	inode_counter u64
}

fn (mut this TmpFS) instantiate() &FileSystem {
	new := &TmpFS{}
	return new
}

fn (mut this TmpFS) populate(node &VFSNode) {}

fn (mut this TmpFS) mount(parent &VFSNode, name string, source &VFSNode) ?&VFSNode {
	this.dev_id = resource.create_dev_id()
	return this.create(parent, name, 0o644 | stat.ifdir)
}

fn (mut this TmpFS) create(parent &VFSNode, name string, mode int) &VFSNode {
	mut new_node := create_node(this, parent, name)

	mut new_resource := &TmpFSResource(memory.malloc(sizeof(TmpFSResource)))

	if stat.isreg(mode) {
		new_resource.capacity = 4096
		new_resource.storage  = memory.malloc(new_resource.capacity)
	}

	new_resource.stat.size = 0
	new_resource.stat.blocks = 0
	new_resource.stat.blksize = 512
	new_resource.stat.dev = this.dev_id
	new_resource.stat.ino = this.inode_counter++
	new_resource.stat.mode = mode
	new_resource.stat.nlink = 1

	new_node.resource = new_resource

	return new_node
}

fn (mut this TmpFS) symlink(parent &VFSNode, dest string, target string) &VFSNode {
	mut new_node := create_node(this, parent, target)

	mut new_resource := &TmpFSResource(memory.malloc(sizeof(TmpFSResource)))

	new_resource.stat.size = u64(target.len)
	new_resource.stat.blocks = 0
	new_resource.stat.blksize = 512
	new_resource.stat.dev = this.dev_id
	new_resource.stat.ino = this.inode_counter++
	new_resource.stat.mode = stat.iflnk | 0o777
	new_resource.stat.nlink = 1

	new_node.resource = new_resource

	new_node.symlink_target = dest

	return new_node
}
