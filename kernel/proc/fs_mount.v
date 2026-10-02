// SPDX-License-Identifier: GPL-2.0-or-later
module proc

// Mount identities accompany filesystem nodes: a bind mount can name the
// same node with different permissions. fs owns these permanent identities.
pub fn root_mount_of(process &Process) voidptr {
	if process == unsafe { nil } { return unsafe { nil } }
	own := thread_fs_of(process)
	if own != unsafe { nil } { return own.root_mount }
	return process.root_mount
}

pub fn current_mount_of(process &Process) voidptr {
	if process == unsafe { nil } { return unsafe { nil } }
	own := thread_fs_of(process)
	if own != unsafe { nil } { return own.current_mount }
	return process.current_mount
}

pub fn set_root_mount(mut process Process, mount voidptr) {
	mut own := thread_fs_of(process)
	if own != unsafe { nil } { own.root_mount = mount; return }
	process.root_mount = mount
}

pub fn set_current_mount(mut process Process, mount voidptr) {
	mut own := thread_fs_of(process)
	if own != unsafe { nil } { own.current_mount = mount; return }
	process.current_mount = mount
}
