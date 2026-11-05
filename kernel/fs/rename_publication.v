// SPDX-License-Identifier: GPL-2.0-or-later
module fs

// A remote directory refresher must not observe a committed rename before
// its VFS maps, name and parent have been published. Only opt-in backends hold
// their private lock across this short publication interval. Callers already
// hold the VFS writer (and, for an overlay, overlay) lock; children_lock is
// acquired only for map edits, never for the backend operation.
// A failed begin releases its lock. A successful begin requires exactly one
// end, after adoption and before retirement callbacks or further backend I/O.
pub interface RenamePublication {
mut:
	rename_begin(&VFSNode, string, &VFSNode, &VFSNode, string, &VFSNode, int) ?
	rename_end()
}

struct RenamePublicationCall {
mut:
	backend RenamePublication
}

fn rename_before_publish(mut filesystem FileSystem, old_parent &VFSNode, old_name string,
	source &VFSNode, new_parent &VFSNode, new_name string, destination &VFSNode, flags int) ?bool {
	if mut filesystem is RenamePublication {
		mut call := unsafe { &RenamePublicationCall(C.vinix_stack_alloc(sizeof(RenamePublicationCall))) }
		unsafe { call.backend = RenamePublication(filesystem) }
		call.backend.rename_begin(old_parent, old_name, source, new_parent, new_name, destination, flags)?
		return true
	}
	filesystem.rename(old_parent, old_name, new_parent, new_name, flags)?
	return false
}

fn rename_after_publish(mut filesystem FileSystem, guarded bool) {
	if !guarded { return }
	if mut filesystem is RenamePublication {
		mut call := unsafe { &RenamePublicationCall(C.vinix_stack_alloc(sizeof(RenamePublicationCall))) }
		unsafe { call.backend = RenamePublication(filesystem) }
		call.backend.rename_end()
	}
}
