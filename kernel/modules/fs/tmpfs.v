// tmpfs.v: tmpfs implementation.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module fs

import stat
import klock
import memory
import memory.mmap
import resource
import lib
import event
import event.eventstruct
import katomic

struct TmpFSResource {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool

	storage  &byte
	capacity u64
}

fn (mut this TmpFSResource) mmap(page u64, flags int) voidptr {
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

fn (mut this TmpFSResource) read(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	this.l.acquire()

	mut actual_count := count

	if loc + count > this.stat.size {
		actual_count = count - ((loc + count) - this.stat.size)
	}

	unsafe { C.memcpy(buf, &this.storage[loc], actual_count) }

	this.l.release()

	return i64(actual_count)
}

fn (mut this TmpFSResource) write(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
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

fn (mut this TmpFSResource) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this TmpFSResource) unref(handle voidptr) ? {
	katomic.dec(this.refcount)

	if this.refcount == 0 && stat.isreg(this.stat.mode) {
		memory.free(this.storage)
		unsafe { free(this) }
	}
}

fn (mut this TmpFSResource) link(handle voidptr) ? {
	katomic.inc(this.stat.nlink)
}

fn (mut this TmpFSResource) unlink(handle voidptr) ? {
	katomic.dec(this.stat.nlink)
}

fn (mut this TmpFSResource) grow(handle voidptr, new_size u64) ? {
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
		return error('')
	}

	this.storage = new_storage
	this.capacity = new_capacity

	this.stat.size = new_size
	this.stat.blocks = lib.div_roundup(new_size, this.stat.blksize)
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

fn (this TmpFS) populate(node &VFSNode) {}

fn (mut this TmpFS) mount(parent &VFSNode, name string, source &VFSNode) ?&VFSNode {
	this.dev_id = resource.create_dev_id()
	return this.create(parent, name, 0o644 | stat.ifdir)
}

fn (mut this TmpFS) create(parent &VFSNode, name string, mode int) &VFSNode {
	mut new_node := create_node(this, parent, name, stat.isdir(mode))

	mut new_resource := &TmpFSResource{
		storage: 0
		refcount: 1
	}

	if stat.isreg(mode) {
		new_resource.capacity = 4096
		new_resource.storage = memory.malloc(new_resource.capacity)
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

	new_resource.can_mmap = true

	new_node.resource = new_resource

	return new_node
}

fn (mut this TmpFS) link(parent &VFSNode, path string, old_node &VFSNode) ?&VFSNode {
	mut new_node := create_node(this, parent, path, false)

	katomic.inc(old_node.resource.refcount)

	new_node.resource = old_node.resource
	new_node.children = old_node.children

	return new_node
}

fn (mut this TmpFS) symlink(parent &VFSNode, dest string, target string) &VFSNode {
	mut new_node := create_node(this, parent, target, false)

	mut new_resource := &TmpFSResource{
		storage: 0
		refcount: 1
	}

	new_resource.stat.size = u64(target.len)
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
