// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module fs

import stat

__global (
	mqueue_filesystem &FileSystem
	mqueue_mount fn () ?&VFSNode
	mqueue_create fn (&VFSNode, string, u32, bool) ?&VFSNode
	mqueue_unlink fn (&VFSNode, &VFSNode) ?
	mqueue_lookup fn (&VFSNode, string) &VFSNode
	mqueue_snapshot fn (&VFSNode) []&VFSNode
)

// The IPC module owns the namespace and queue registry. These callbacks run
// ordinary pathname operations against the same registry as mq_* syscalls.
pub fn register_mqueue_filesystem(filesystem &FileSystem, mount fn () ?&VFSNode,
	create fn (&VFSNode, string, u32, bool) ?&VFSNode, unlink fn (&VFSNode, &VFSNode) ?,
	lookup fn (&VFSNode, string) &VFSNode, snapshot fn (&VFSNode) []&VFSNode) {
	mqueue_filesystem = unsafe { filesystem }
	mqueue_mount = mount
	mqueue_create = create
	mqueue_unlink = unlink
	mqueue_lookup = lookup
	mqueue_snapshot = snapshot
}

fn is_mqueue_directory(node &VFSNode) bool {
	return mqueue_filesystem != unsafe { nil } && voidptr(node.filesystem) == voidptr(mqueue_filesystem)
		&& node.resource != unsafe { nil } && stat.isdir(node.resource.stat.mode)
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
