// SPDX-License-Identifier: GPL-2.0-or-later
module fs

import errno
import posix_acl
import proc
import resource
import stat

fn creation_acl(parent &VFSNode, requested u32, apply_umask bool,
	mut defaults []u8, mut access []u8) ?u32 {
	mut res := unsafe { parent.resource }
	resource.get_xattr(mut res, posix_acl.default_name, mut defaults) or {
		if errno.get() != errno.enodata && errno.get() != errno.enotsup { return none }
		mask := if apply_umask { proc.current_thread().process.umask } else { u32(0) }
		return requested & ~mask
	}
	if defaults.len <= 4 || !posix_acl.valid(defaults) { errno.set(errno.eio); return none }
	for byte in defaults { access << byte }
	mode, _ := posix_acl.inherit(mut access, requested)
	return mode
}

fn apply_creation_acl(mut node VFSNode, mode u32, defaults []u8, access []u8) ? {
	// Identity inheritance may add the parent's setgid bit to a directory.
	inherited_setgid := if stat.isdir(mode) { node.resource.stat.mode & 0o2000 } else { u32(0) }
	mut res := node.resource
	res.stat.mode = mode | inherited_setgid
	if stat.isdir(mode) && defaults.len != 0 {
		resource.set_xattr(mut res, posix_acl.default_name, defaults, 0)?
	}
	if access.len != 0 { resource.set_xattr(mut res, posix_acl.access_name, access, 0)? }
	resource.persist_metadata(mut res)?
}

// Called before the new node is entered into its parent map. Failed I/O may
// leave an orphan on disk, so it must not make possibly live storage reusable.
// Ordinary nodes have never been exposed; their empty directory map can go,
// and the node itself follows the existing delayed retirement path.
fn discard_created_node(mut node VFSNode, parent &VFSNode) {
	if node.overlay != unsafe { nil } {
		mut directory := unsafe { parent }
		overlay_discard_created(mut directory, mut node)
		return
	}
	mut res := node.resource
	res.unlink(voidptr(node)) or { return }
	if stat.isdir(res.stat.mode) { node.removed = true; res.stat.nlink = 0 }
	res.unref(unsafe { nil }) or { return }
	if node.children != unsafe { nil } {
		if node.children.len != 0 { return }
		unsafe { node.children.free(); free(node.children); node.children = nil }
	}
	retire_node(mut node)
}
