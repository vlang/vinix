// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// mknod(2)/mknodat(2): the special files a container runtime makes in the
// rootfs it is building. A device node leads to the real device of the same
// name -- Vinix names its devices rather than numbering them, so /dev/null a
// container makes is the /dev/null the kernel already has -- and a FIFO is a
// named pipe.
module fs

import errno
import katomic
import klock
import pipe
import proc
import resource
import stat
import event.eventstruct

// A device node created by mknod. It has no storage of its own: every
// operation is forwarded to the device the kernel published under the same
// name, so a container's /dev/null discards writes exactly as the host's does.
@[heap]
struct MknodDeviceResource {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool

	backing &resource.Resource = unsafe { nil }
}

// A device that decides what an open returns, as /dev/tty and /dev/ptmx do,
// must decide it for the container's node too.
fn (mut this MknodDeviceResource) open(flags int) ?&resource.Resource {
	mut backing := this.backing
	if mut backing is resource.OpenableResource {
		return backing.open(flags)
	}
	return &resource.Resource(this)
}

fn (mut this MknodDeviceResource) read(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	mut backing := this.backing
	return backing.read(handle, buf, loc, count)
}

fn (mut this MknodDeviceResource) write(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	mut backing := this.backing
	return backing.write(handle, buf, loc, count)
}

fn (mut this MknodDeviceResource) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	mut backing := this.backing
	return backing.ioctl(handle, request, argp)
}

fn (mut this MknodDeviceResource) mmap(handle voidptr, page u64, flags int) voidptr {
	mut backing := this.backing
	return backing.mmap(handle, page, flags)
}

fn (mut this MknodDeviceResource) grow(_handle voidptr, _new_size u64) ? {
	return
}

fn (mut this MknodDeviceResource) unref(_handle voidptr) ? {
	katomic.dec(mut &this.refcount)
}

fn (mut this MknodDeviceResource) link(_handle voidptr) ? {
	katomic.inc(mut &this.stat.nlink)
}

fn (mut this MknodDeviceResource) unlink(_handle voidptr) ? {
	katomic.dec(mut &this.stat.nlink)
}

// The device the kernel published under `name`, or nil.
fn device_by_name(name string) &resource.Resource {
	if unsafe { devtmpfs_root == 0 } || devtmpfs_root.children == unsafe { nil } {
		return unsafe { nil }
	}
	if name !in devtmpfs_root.children {
		return unsafe { nil }
	}
	node := unsafe { devtmpfs_root.children[name] }
	if node == unsafe { nil } {
		return unsafe { nil }
	}
	return node.resource
}

fn make_device_node(mut parent VFSNode, name string, mode u32, rdev u64) ?&VFSNode {
	backing := device_by_name(name)
	if backing == unsafe { nil } {
		// A device Vinix does not have. /dev/null stands in: writes are
		// discarded and reads give EOF, which is what an unbacked device node
		// in a container is least likely to be harmed by.
		fallback := device_by_name('null')
		if fallback == unsafe { nil } {
			errno.set(errno.enodev)
			return none
		}
		return install_device_node(mut parent, name, mode, rdev, fallback)
	}
	return install_device_node(mut parent, name, mode, rdev, backing)
}

fn install_device_node(mut parent VFSNode, name string, mode u32, rdev u64, backing &resource.Resource) ?&VFSNode {
	mut node := create_node(parent.filesystem, parent, name, false)
	mut res := &MknodDeviceResource{
		refcount: 1
		backing:  unsafe { backing }
	}
	res.stat.mode = mode
	res.stat.rdev = rdev
	res.stat.dev = resource.create_dev_id()
	res.stat.nlink = 1
	res.stat.blksize = 512
	res.can_mmap = backing.can_mmap
	res.stat.atim = realtime_clock
	res.stat.ctim = realtime_clock
	res.stat.mtim = realtime_clock
	node.resource = res
	apply_creation_identity(mut node, parent)?
	unsafe {
		parent.children[name] = node
	}
	return node
}

fn make_fifo_node(mut parent VFSNode, name string, mode u32) ?&VFSNode {
	// A named pipe has no ends open until something opens one, and blocks
	// an opener until the other side arrives; see pipe.create_fifo.
	mut new_pipe := pipe.create_fifo(mode) or {
		errno.set(errno.enomem)
		return none
	}
	mut node := create_node(parent.filesystem, parent, name, false)
	node.resource = new_pipe
	apply_creation_identity(mut node, parent)?
	unsafe {
		parent.children[name] = node
	}
	return node
}

pub fn syscall_mknodat(_ voidptr, dirfd int, _path charptr, mode u32, dev u64) (u64, u64) {
	path := user_path(_path) or { return errno.err, errno.get() }
	if path.len == 0 {
		return errno.err, errno.enoent
	}
	kind := mode & stat.ifmt
	// A device node needs the privilege to make one; a FIFO or a plain file
	// does not, exactly as on Linux.
	if (kind == stat.ifchr || kind == stat.ifblk)
		&& !proc.current_has_capability(proc.cap_mknod) {
		return errno.err, errno.eperm
	}

	parent := get_parent_dir(dirfd, path) or { return errno.err, errno.get() }
	parent_of_tgt_node, target_node, basename := path2node(parent, path)
	if unsafe { parent_of_tgt_node == 0 } {
		return errno.err, errno.enoent
	}
	if unsafe { target_node != 0 } {
		return errno.err, errno.eexist
	}
	if read_only(parent_of_tgt_node) {
		return errno.err, errno.erofs
	}
	require_access(parent_of_tgt_node, access_write | access_exec) or {
		return errno.err, errno.get()
	}

	mut dir := unsafe { parent_of_tgt_node }
	umask := proc.current_thread().process.umask
	final_mode := (mode & ~umask) & 0o7777

	vfs_lock.acquire()
	defer {
		vfs_lock.release()
	}
	match kind {
		0, stat.ifreg {
			internal_create(dir, basename, stat.ifreg | final_mode) or {
				return errno.err, errno.get()
			}
		}
		stat.ififo {
			make_fifo_node(mut dir, basename, final_mode) or { return errno.err, errno.get() }
		}
		stat.ifchr, stat.ifblk {
			make_device_node(mut dir, basename, kind | final_mode, dev) or {
				return errno.err, errno.get()
			}
		}
		stat.ifsock {
			// A filesystem socket node with no bound socket: a placeholder a
			// runtime can bind to later is not modelled, so refuse rather than
			// leave a file that cannot be connected.
			return errno.err, errno.eperm
		}
		else {
			return errno.err, errno.einval
		}
	}
	return 0, 0
}
