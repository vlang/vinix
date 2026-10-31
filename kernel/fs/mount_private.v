// SPDX-License-Identifier: GPL-2.0-or-later
module fs

import krandom

// Credential-bearing backends opt out of retaining raw mount options. This is
// separate from MountSpecifier: existing backends keep their display contract.
interface PrivateMountOptions {
	mount_options_private() bool
}

fn public_mount_options(root &VFSNode, options string) string {
	// Bind is an internal routing marker, not caller-supplied authentication.
	if options == 'bind' || root == unsafe { nil } || root.filesystem == unsafe { nil } {
		return options
	}
	backend := root.filesystem
	if backend is PrivateMountOptions {
		if backend.mount_options_private() {
			return ''
		}
	}
	return options
}

fn erase_mount_scratch(data voidptr, length usize) {
	if length > 0 { krandom.explicit_bzero(data, length) }
}

fn free_mount_options(options string) {
	erase_mount_scratch(options.str, usize(options.len))
	unsafe { options.free() }
}
