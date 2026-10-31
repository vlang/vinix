// SPDX-License-Identifier: GPL-2.0-or-later
module fs

import errno

// Optional structural opt-in for registered filesystem templates whose source
// is a backend specifier, not a VFS pathname. FileSystem remains unchanged.
// instantiate() must return an instance that also implements this interface;
// dispatch calls the instance, never the template. Existing special mount paths
// (including block filesystems) retain their own contracts.
//
// source and options are borrowed for the call only: clone anything retained.
// name follows FileSystem.mount's contract: on success the root may own it;
// on failure the caller frees it. parent is borrowed. flags are the effective
// new-mount flags, including policy derived from options.
//
// On failure, set errno and release all resources acquired for the attempt,
// including the failed instance and its FileSystem box if newly allocated.
// Shared templates/instances must remain valid. The dispatcher has no generic
// filesystem destructor and cannot reclaim backend state. On success the root
// retains the backend under the existing mount lifetime rules. instantiate()
// itself owns cleanup if it returns nil; an instance lacking this interface is
// a backend contract violation, rejected with EINVAL rather than legacy mount.
pub interface MountSpecifier {
mut:
	mount_specifier(parent &VFSNode, name string, source string, flags u64, options string) ?&VFSNode
}

struct MountSpecifierCall {
mut:
	backend MountSpecifier
}

fn mount_filesystem_specifier(mut filesystem FileSystem, parent &VFSNode, name string,
	source string, flags u64, options string) ?&VFSNode {
	if filesystem is MountSpecifier {
		// Borrow the existing box through a caller-stack slot, as UnmountCheck
		// does. A promoted local interface can otherwise allocate in manualfree V.
		mut call := unsafe { &MountSpecifierCall(C.vinix_stack_alloc(sizeof(MountSpecifierCall))) }
		unsafe { call.backend = MountSpecifier(filesystem) }
		return call.backend.mount_specifier(parent, name, source, flags, options)
	}
	errno.set(errno.einval)
	return none
}
