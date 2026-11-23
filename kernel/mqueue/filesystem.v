// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module mqueue

import errno
import fs as vfs
import katomic
import memory
import proc
import resource
import stat
import time

const directory_entry_size = i64(20)

struct MQueueFS {}

__global (
	// One VFS tree per IPC namespace while the namespace is live. Mount
	// records own each published root for the lifetime of the VFS.
	mq_roots map[u64]&Queue
	mq_filesystem &vfs.FileSystem
)

fn init() {
	mq_filesystem = &vfs.FileSystem(&MQueueFS{})
	vfs.register_mqueue_filesystem(mq_filesystem, mount_queue_directory, create_queue_file,
		unlink_queue_file, lookup_queue_file, snapshot_queue_directory, last_queue_directory_view)
}

fn (mut _fs MQueueFS) instantiate() &vfs.FileSystem { return mq_filesystem }
fn (mut _fs MQueueFS) populate(_node &vfs.VFSNode) {}

fn (mut _fs MQueueFS) mount(_parent &vfs.VFSNode, _name string, _source &vfs.VFSNode) ?&vfs.VFSNode {
	return mount_queue_directory()
}

fn (mut _fs MQueueFS) create(_parent &vfs.VFSNode, _name string, _mode u32) &vfs.VFSNode {
	errno.set(errno.eperm)
	return unsafe { nil }
}

fn (mut _fs MQueueFS) symlink(_parent &vfs.VFSNode, _target string, _name string) &vfs.VFSNode {
	errno.set(errno.eperm)
	return unsafe { nil }
}

fn (mut _fs MQueueFS) link(_parent &vfs.VFSNode, _name string, mut _source vfs.VFSNode) ?&vfs.VFSNode {
	errno.set(errno.eperm)
	return none
}

fn (mut _fs MQueueFS) rename(_from &vfs.VFSNode, _name string, _to &vfs.VFSNode, _target string, _flags int) ? {
	errno.set(errno.eperm)
	return none
}

fn mount_queue_directory() ?&vfs.VFSNode {
	ns, id, entered := enter_namespace()
	if !entered { errno.set(errno.eacces); return none }
	defer { leave_namespace(ns) }
	process := proc.current_thread().process
	if ns != unsafe { nil } && !proc.has_namespace_capability(process, proc.cap_sys_admin, ns.ipc_user_ns) {
		errno.set(errno.eperm)
		return none
	}
	mq_lock.acquire()
	defer { mq_lock.release() }
	if id in mq_roots {
		mut existing := unsafe { mq_roots[id].node }
		vfs.hold_mqueue_view(mut existing)
		return existing
	}
	mut root := allocate_queue()?
	mut node := vfs.create_node(mq_filesystem, unsafe { nil }, '', true)
	node.resource = root.box
	root.refcount = 1
	root.node = node
	root.ipc_ns = id
	root.linked = true
	if mq_device == 0 { mq_device = resource.create_dev_id() }
	mq_inodes++
	root.stat.dev = mq_device
	root.stat.ino = mq_inodes
	root.stat.mode = stat.ifdir | 0o1777
	root.stat.uid = if ns == unsafe { nil } { u32(0) } else { ns.ipc_fsuid }
	root.stat.gid = if ns == unsafe { nil } { u32(0) } else { ns.ipc_fsgid }
	root.stat.nlink = 2
	root.stat.blksize = i64(memory.page_size)
	root.stat.size = 2 * directory_entry_size
	root.stat.atim = now()
	root.stat.ctim = root.stat.atim
	root.stat.mtim = root.stat.atim
	node.create_dotentries(node)
	// Transfer a temporary view pin to mount publication before dropping the
	// IPC namespace reference. Another task may concurrently leave it.
	vfs.hold_mqueue_view(mut node)
	mq_roots[id] = root
	mut queue := mq_queues
	for queue != unsafe { nil } {
		if queue.linked && queue.ipc_ns == id { publish_queue_locked(mut queue, root) }
		queue = queue.all_next
	}
	return node
}

fn last_queue_directory_view(node &vfs.VFSNode) {
	root := unsafe { &Queue(node.resource) }
	mq_lock.acquire()
	mut dead := &Queue(unsafe { nil })
	if !root.linked && root.ipc_ns in mq_roots && !vfs.mqueue_has_views(node) {
		dead = unname_namespace_locked(root.ipc_ns)
	}
	mq_lock.release()
	free_unnamed_queues(dead)
}

fn dir_entry_changed(mut root Queue, delta i64, stamp time.TimeSpec) {
	root.stat.size += delta
	root.stat.ctim = stamp
	root.stat.mtim = stamp
}

fn publish_queue_locked(mut queue Queue, _root &Queue) {
	mut root := unsafe { _root }
	name := unsafe { tos(&queue.name[0], queue.name_len).clone() }
	mut node := vfs.create_node(mq_filesystem, root.node, name, false)
	queue.node = node
	node.resource = queue.box
	katomic.inc(mut &queue.refcount)
	dir_entry_changed(mut root, directory_entry_size, now())
	vfs.inotify_emit(root.node, name, vfs.in_create, 0)
}

fn lookup_queue_file(parent &vfs.VFSNode, name string) &vfs.VFSNode {
	root := unsafe { &Queue(parent.resource) }
	mq_lock.acquire()
	defer { mq_lock.release() }
	queue := find_locked(root.ipc_ns, name)
	return if queue == unsafe { nil } { unsafe { nil } } else { queue.node }
}

fn snapshot_queue_directory(parent &vfs.VFSNode) []&vfs.VFSNode {
	root := unsafe { &Queue(parent.resource) }
	mq_lock.acquire()
	defer { mq_lock.release() }
	// Directory size is the count of visible names, including the two dots.
	mut nodes := []&vfs.VFSNode{cap: int(root.stat.size / directory_entry_size)}
	unsafe {
		nodes << parent.children['.']
		nodes << parent.children['..']
	}
	mut queue := mq_queues
	for queue != unsafe { nil } {
		if queue.linked && queue.ipc_ns == root.ipc_ns { nodes << queue.node }
		queue = queue.all_next
	}
	return nodes
}

fn create_queue_file(parent &vfs.VFSNode, name string, mode u32, apply_umask bool) ?&vfs.VFSNode {
	if !stat.isreg(mode) { errno.set(errno.eperm); return none }
	if name.len > name_max { errno.set(errno.enametoolong); return none }
	mut spare := allocate_queue()?
	root := unsafe { &Queue(parent.resource) }
	process := proc.current_thread().process
	final_mode := if apply_umask { mode & ~process.umask } else { mode }
	account := quota_owner(process)
	mq_lock.acquire()
	code := if !root.linked { u64(errno.eacces) } else if find_locked(root.ipc_ns, name) != unsafe { nil } {
		u64(errno.eexist)
	} else {
		create_locked(mut spare, process, account, root.ipc_ns, name, final_mode, unsafe { nil })
	}
	node := spare.node
	mq_lock.release()
	if code != 0 {
		free_queue(mut spare)
		errno.set(code)
		return none
	}
	return node
}

fn unlink_queue_file(parent &vfs.VFSNode, node &vfs.VFSNode) ? {
	res := node.resource
	if voidptr(node.parent) != voidptr(parent) || res !is Queue { errno.set(errno.enoent); return none }
	mut queue := unsafe { &Queue(res) }
	mq_lock.acquire()
	defer { mq_lock.release() }
	// mq_unlink may have raced the pathname walk. Compare the original
	// queue, so this operation cannot unlink a replacement of the same name.
	if !queue.linked || voidptr(queue.node) != voidptr(node) { errno.set(errno.enoent); return none }
	if vfs.mqueue_child_mounted_on(node) { errno.set(errno.ebusy); return none }
	unname_locked(mut queue)
}

fn (mut _queue Queue) filesystem_stat() resource.FileSystemStat {
	return resource.FileSystemStat{
		@type: 0x19800202
		bsize: memory.page_size
		frsize: memory.page_size
		namelen: name_max
	}
}
