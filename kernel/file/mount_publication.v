// SPDX-License-Identifier: GPL-2.0-or-later
module file

import lib

__global (
	mount_publication_allowed fn (&lib.MountContext) bool
)

// Installed by the VFS module initializer, before descriptors can be published.
pub fn on_mount_publication(f fn (&lib.MountContext) bool) {
	mount_publication_allowed = f
}

// The caller holds the destination's fds_lock until after slot publication.
// Unmount closes admission before trying that lock; it either observes the
// published descriptor or refuses on contention. Do not call this unlocked.
fn descriptor_mount_admitted(fd &FD) bool {
	return mount_publication_allowed == unsafe { nil }
		|| mount_publication_allowed(&fd.handle.mount)
}
