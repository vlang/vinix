// SPDX-License-Identifier: GPL-2.0-or-later
module fs

import errno
import kbudget
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

// Backing overlay publication can fail after identity/ACL setup. Roll back the
// private staged inode while keeping the old whiteout and merged name hidden.
fn commit_created_node(mut node VFSNode, parent &VFSNode) ? {
	overlay_commit_created(node) or {
		failure := errno.get()
		discard_created_node(mut node, parent)
		errno.set(failure)
		return none
	}
	settle_creation_charge(mut node)
}

// A node on a disk caches what the disk holds, which the disk's size already
// bounds, and it stays cached for as long as the file exists. Kept charged to
// its creator, every file a user had ever written counted against the kernel
// memory that user's processes need: installing a few applications as root
// filled the account, and from then on no process or thread could start. The
// reservation still admits the creation; nodes whose memory is the file itself
// -- tmpfs, devtmpfs, cgroups, device wrappers -- keep theirs until removed.
fn settle_creation_charge(mut node VFSNode) {
	if node.resource == unsafe { nil } || node.overlay != unsafe { nil } {
		return
	}
	res := unsafe { *node.resource }
	if res is TmpFSResource || res is DevTmpFSResource || res is CGroupResource
		|| res is MknodDeviceResource || res is SysFSResource || res is ProcFSResource
		|| res is NsFSResource {
		return
	}
	kbudget.release(node.kernel_charge)
	node.kernel_charge = kbudget.Charge{}
}
