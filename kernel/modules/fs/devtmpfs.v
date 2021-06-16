module fs

import stat
import klock
import memory
import resource

struct DevTmpFSResource {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock

	storage  &byte
	capacity u64
}

fn (mut this DevTmpFSResource) read(buf voidptr, loc u64, count u64) i64 {
	this.l.acquire()

	mut actual_count := u64(count)
	if loc + count > this.stat.size {
		actual_count = count - ((loc + count) - this.stat.size)
	}

	unsafe { C.memcpy(buf, &this.storage[loc], actual_count) }

	this.l.release()

	return i64(count)
}

fn (mut this DevTmpFSResource) write(buf voidptr, loc u64, count u64) i64 {
	this.l.acquire()

	if loc + count > this.capacity {
		mut new_capacity := this.capacity

		for loc + count > new_capacity {
			new_capacity *= 2
		}

		new_storage := memory.realloc(this.storage, new_capacity)

		if new_storage == 0 {
			return -1
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

struct DevTmpFS {}

__global (
	devtmpfs_dev_id u64
	devtmpfs_inode_counter u64
	devtmpfs_root &VFSNode
)

fn (mut this DevTmpFS) populate(node &VFSNode) {}

fn (mut this DevTmpFS) mount(source &VFSNode) &VFSNode {
	if devtmpfs_dev_id == 0 {
		devtmpfs_dev_id = resource.create_dev_id()
	}
	if devtmpfs_root == 0 {
		devtmpfs_root = this.create(&VFSNode(0), '', 0644 | stat.ifdir)
	}
	return devtmpfs_root
}

fn (mut this DevTmpFS) create(parent &VFSNode, name string, mode int) &VFSNode {
	mut new_node := create_node(this)

	mut new_resource := &DevTmpFSResource(memory.malloc(sizeof(DevTmpFSResource)))

	if stat.isreg(mode) {
		new_resource.capacity = 4096
		new_resource.storage  = memory.malloc(new_resource.capacity)
	}

	new_resource.stat.size = 0
	new_resource.stat.blocks = 0
	new_resource.stat.blksize = 512
	new_resource.stat.dev = devtmpfs_dev_id
	new_resource.stat.ino = devtmpfs_inode_counter++
	new_resource.stat.mode = mode
	new_resource.stat.nlink = 1

	new_node.resource = new_resource

	return new_node
}

pub fn devtmpfs_add_device(device &resource.Resource, name string) {
	mut new_node := create_node(&(filesystems['devtmpfs']))

	new_node.resource = unsafe { device }
	new_node.resource.stat.dev = devtmpfs_dev_id
	new_node.resource.stat.ino = devtmpfs_inode_counter++
	new_node.resource.stat.nlink = 1

	devtmpfs_root.children[name] = new_node
}
