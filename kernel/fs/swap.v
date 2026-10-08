// SPDX-License-Identifier: GPL-2.0-or-later
module fs

import errno
import pager
import proc
import resource
import security
import stat
import usercopy

fn swap_resource(path u64) ?&resource.Resource {
	process := proc.current_thread().process
	if !proc.mac_trusted() || !proc.is_initial_namespace(process.ns.user)
		|| !proc.has_capability(process, proc.cap_sys_admin) {
		errno.set(errno.eperm)
		return none
	}
	name := usercopy.copy_cstring_from_user(path, 4096)?
	defer { unsafe { name.free() } }
	node := get_node(calling_directory(), name, true)?
	mut res := node.resource
	if !stat.isblk(res.stat.mode) {
		errno.set(errno.einval)
		return none
	}
	if !resource.block_identity(mut res).valid() {
		errno.set(errno.enodev)
		return none
	}
	return res
}

pub fn syscall_swapon(_ voidptr, path u64, flags int) (u64, u64) {
	// Priority is accepted for Linux callers; the current pager has one disk.
	// Discard is deliberately unsupported: it could overwrite the header or
	// reveal old data before the activation's encrypted writes replace it.
	if flags & ~0xffff != 0 { return errno.err, errno.einval }
	mut res := swap_resource(path) or { return errno.err, errno.get() }
	identity := resource.block_identity(mut res)
	token := security.claim_swap(identity) or { return errno.err, errno.get() }
	pager.enable(mut res, identity, token) or {
		security.release_swap(token)
		return errno.err, errno.get()
	}
	return 0, 0
}

pub fn syscall_swapoff(_ voidptr, path u64) (u64, u64) {
	mut res := swap_resource(path) or { return errno.err, errno.get() }
	token := pager.disable(resource.block_identity(mut res)) or { return errno.err, errno.get() }
	security.release_swap(token)
	return 0, 0
}
