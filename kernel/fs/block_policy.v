// SPDX-License-Identifier: GPL-2.0-or-later
module fs

import resource
import security

// The filesystem capability supplies the actual backing extent. A mount's
// source string does not necessarily select that extent (EXT2 templates
// already carry their backing resource), and a device pathname may be aliased.
pub interface BlockBackedFilesystem {
	block_identity() resource.BlockIdentity
}

struct BlockFilesystemCall {
mut:
	backend BlockBackedFilesystem
}

fn begin_filesystem_block_mount(mut filesystem FileSystem) ?int {
	if filesystem is BlockBackedFilesystem {
		mut call := unsafe { &BlockFilesystemCall(C.vinix_stack_alloc(sizeof(BlockFilesystemCall))) }
		unsafe { call.backend = BlockBackedFilesystem(filesystem) }
		identity := call.backend.block_identity()
		// An unsupported backing capability carries no physical identity.
		// Its userspace block writes fail closed at level 1, so mounting it
		// preserves that protection without inventing an rdev-based alias.
		if identity.disk_id == 0 && identity.start == 0 && identity.length == 0 { return -1 }
		return security.begin_block_mount(identity)
	}
	return -1
}
