// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module fs

import katomic
import errno
import event.eventstruct
import klock
import resource
import stat

__global (
	mqueue_filesystem &FileSystem
	mqueue_mount fn () ?&VFSNode
	mqueue_create fn (&VFSNode, string, u32, bool) ?&VFSNode
	mqueue_unlink fn (&VFSNode, &VFSNode) ?
	mqueue_lookup fn (&VFSNode, string) &VFSNode
	mqueue_snapshot fn (&VFSNode) []&VFSNode
	mqueue_last_view fn (&VFSNode)
	retired_mqueue_resource &resource.Resource
)

// The IPC module owns the namespace and queue registry. These callbacks run
// ordinary pathname operations against the same registry as mq_* syscalls.
pub fn register_mqueue_filesystem(filesystem &FileSystem, mount fn () ?&VFSNode,
	create fn (&VFSNode, string, u32, bool) ?&VFSNode, unlink fn (&VFSNode, &VFSNode) ?,
	lookup fn (&VFSNode, string) &VFSNode, snapshot fn (&VFSNode) []&VFSNode,
	last_view fn (&VFSNode)) {
	mqueue_filesystem = unsafe { filesystem }
	mqueue_mount = mount
	mqueue_create = create
	mqueue_unlink = unlink
	mqueue_lookup = lookup
	mqueue_snapshot = snapshot
	mqueue_last_view = last_view
	retired_mqueue_resource = &resource.Resource(&RetiredQueue{stat: stat.Stat{mode: stat.ifreg}})
}

pub fn hold_mqueue_view(mut node VFSNode) {
	katomic.inc(mut &node.mqueue_views)
}

pub fn mqueue_has_views(node &VFSNode) bool {
	return katomic.load(&node.mqueue_views) != 0
}

fn drop_mqueue_view(mut node VFSNode) {
	directory := is_mqueue_directory(node)
	if !directory { node_reference_releasing(voidptr(node)) }
	if !katomic.dec(mut &node.mqueue_views) && directory { mqueue_last_view(node) }
}

// Detached mounts can still be reached through descriptions, cwd or process
// root. The reaper waits for those routes outside the mount table lock.
fn retire_mqueue_view(mut entry Mount, immediate bool) {
	entry.lock.acquire()
	owned := entry.mqueue_view
	entry.mqueue_view = false
	entry.lock.release()
	if !owned { return }
	if immediate {
		mut root := entry.root
		drop_mqueue_view(mut root)
	} else {
		retire(RetiredItem{mqueue_mount: unsafe { &entry }})
	}
}

fn reap_mqueue_view(mut entry Mount) {
	if unmount_paths_in_use(entry) {
		retire(RetiredItem{mqueue_mount: unsafe { &entry }})
		return
	}
	begin_mount_unmount(mut entry) or {
		retire(RetiredItem{mqueue_mount: unsafe { &entry }})
		return
	}
	if unmount_paths_in_use(entry) {
		cancel_mount_unmount(mut entry)
		retire(RetiredItem{mqueue_mount: unsafe { &entry }})
		return
	}
	mut root := entry.root
	drop_mqueue_view(mut root)
}

fn is_mqueue_inode(node &VFSNode) bool {
	return node != unsafe { nil } && mqueue_filesystem != unsafe { nil }
		&& voidptr(node.filesystem) == voidptr(mqueue_filesystem)
}

fn is_mqueue_directory(node &VFSNode) bool {
	return is_mqueue_inode(node) && node.resource != unsafe { nil } && stat.isdir(node.resource.stat.mode)
}

pub fn mqueue_child_mounted_on(node &VFSNode) bool {
	return node != unsafe { nil } && (node.mountpoint != unsafe { nil } || node.ns_mounts > 0)
}

// The IPC registry serializes publication and removal. Path readers may
// still hold the node returned by an earlier registry lookup.
pub fn retire_mqueue_child(mut node VFSNode) {
	inotify_emit(node.parent, node.name, in_delete, 0)
	inotify_emit(node, '', in_delete_self, 0)
	inotify_forget(node)
	// The node owns its resource through grace and while a bind mount or
	// open file description still reaches it.
	node.retained_resource = true
	orphan_node(mut node, stat.ifreg)
}

// Mount history may live indefinitely. Its vnode still carries a usable
// stat field for a walk that had already selected the old mount, and the
// resource rejects operations on the retired queue.
struct RetiredQueue {
mut:
	stat stat.Stat
	refcount int
	l klock.Lock
	event eventstruct.Event
	status int
	can_mmap bool
}

fn (mut _q RetiredQueue) open(_flags int) ?&resource.Resource { errno.set(errno.enoent); return none }
fn (mut _q RetiredQueue) grow(_handle voidptr, _size u64) ? { errno.set(errno.enoent); return none }
fn (mut _q RetiredQueue) read(_handle voidptr, _buf voidptr, _loc u64, _count u64) ?i64 { errno.set(errno.enoent); return none }
fn (mut _q RetiredQueue) write(_handle voidptr, _buf voidptr, _loc u64, _count u64) ?i64 { errno.set(errno.enoent); return none }
fn (mut _q RetiredQueue) ioctl(_handle voidptr, _req u64, _arg voidptr) ?int { errno.set(errno.enoent); return none }
fn (mut _q RetiredQueue) link(_handle voidptr) ? { errno.set(errno.enoent); return none }
fn (mut _q RetiredQueue) unlink(_handle voidptr) ? { errno.set(errno.enoent); return none }
fn (mut _q RetiredQueue) unref(_handle voidptr) ? {}
fn (mut _q RetiredQueue) mmap(_handle voidptr, _page u64, _flags int) voidptr { return unsafe { nil } }
