// SPDX-License-Identifier: GPL-2.0-or-later
module fs

import errno

// A backing filesystem can commit a rename and its source whiteout together.
// The whiteout is a real, privately staged inode on that same filesystem.
// Backends change disk entries only; overlay publishes the VFS maps afterwards.
pub interface OverlayStorage {
mut:
	rename_whiteout(old_parent &VFSNode, old_name string, new_parent &VFSNode,
		new_name string, whiteout &VFSNode) ?
}

fn overlay_persistent_storage(mut filesystem FileSystem) bool {
	return filesystem is OverlayStorage
}

fn overlay_storage_rename(mut filesystem FileSystem, old_parent &VFSNode,
	old_name string, source &VFSNode, new_parent &VFSNode, new_name string,
	destination &VFSNode, whiteout &VFSNode) ?bool {
	if whiteout != unsafe { nil } && voidptr(whiteout.parent) != voidptr(old_parent) {
		if mut filesystem is OverlayStorage {
			mut backend := OverlayStorage(filesystem)
			mut stack := unsafe { &backend }
			stack.rename_whiteout(old_parent, old_name, new_parent, new_name, whiteout)?
			return false
		}
		errno.set(errno.enotsup)
		return none
	}
	return rename_before_publish(mut filesystem, old_parent, old_name, source,
		new_parent, new_name, destination, 0)
}
