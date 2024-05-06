// devtmpfs.v: devtmpfs managing.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module fs

import stat
import klock
import memory
import memory.mmap
import resource
import lib
import event.eventstruct
import katomic

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
}

fn (mut this DevTmpFSResource) mmap(page u64, flags int) voidptr {
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

fn (mut this DevTmpFSResource) read(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	this.l.acquire()

	mut actual_count := count
	if loc + count > this.stat.size {
		actual_count = u64(count - ((loc + count) - this.stat.size))
	}

	unsafe { C.memcpy(buf, &this.storage[loc], actual_count) }

	this.l.release()

	return i64(actual_count)
}

fn (mut this DevTmpFSResource) write(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
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

fn (mut this DevTmpFSResource) unref(handle voidptr) ? {
	katomic.dec(this.refcount)
}

fn (mut this DevTmpFSResource) link(handle voidptr) ? {
	katomic.inc(this.stat.nlink)
}

fn (mut this DevTmpFSResource) unlink(handle voidptr) ? {
	katomic.dec(this.stat.nlink)
}

fn (mut this DevTmpFSResource) grow(handle voidptr, new_size u64) ? {
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

struct DevTmpFS {}

__global (
	devtmpfs_dev_id        u64
	devtmpfs_inode_counter u64
	devtmpfs_root          &VFSNode
)

fn (this DevTmpFS) instantiate() &FileSystem {
	new := &DevTmpFS{}
	return new
}

fn (this DevTmpFS) populate(node &VFSNode) {}

fn (mut this DevTmpFS) mount(parent &VFSNode, name string, source &VFSNode) ?&VFSNode {
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
	mut new_node := create_node(this, parent, name, stat.isdir(mode))

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

	new_node.resource = new_resource

	return new_node
}

fn (mut this DevTmpFS) link(parent &VFSNode, path string, old_node &VFSNode) ?&VFSNode {
	mut new_node := create_node(this, parent, path, false)

	katomic.inc(old_node.resource.refcount)

	new_node.resource = old_node.resource
	new_node.children = old_node.children

	return new_node
}

fn (mut this DevTmpFS) symlink(parent &VFSNode, dest string, target string) &VFSNode {
	mut new_node := create_node(this, parent, target, false)

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

	new_node.resource = new_resource

	new_node.symlink_target = dest

	return new_node
}

pub fn devtmpfs_add_device(device &resource.Resource, name string) {
	mut new_node := create_node(unsafe { filesystems['devtmpfs'] }, devtmpfs_root, name, false)

	new_node.resource = unsafe { device }
	new_node.resource.stat.dev = devtmpfs_dev_id
	new_node.resource.stat.ino = devtmpfs_inode_counter++
	new_node.resource.stat.nlink = 1

	new_node.resource.stat.atim = realtime_clock
	new_node.resource.stat.ctim = realtime_clock
	new_node.resource.stat.mtim = realtime_clock

	unsafe {
		devtmpfs_root.children[name] = new_node
	}
}
